-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The array language in ops, each primitive in its meaning: a new array is
||| `idr.array.tabulate` into a fresh destination, a fold along the last
||| axis `idr.array.fold_last`, a scan `idr.array.scan_last`, each a region
||| from indices (and an accumulator) to an element; a transpose of words is
||| upstream's `linalg.transpose`, of counted elements a tabulation reading
||| at the swapped coordinates; a join of words is two slices inserted into
||| a fresh destination, of counted elements a tabulation reading the one
||| array or the other; a read is `tensor.extract`, a write
||| `tensor.insert`, and a slice and a reshape the `tensor` ops of each.
||| An array of counted elements is written whole by the op that makes it,
||| which reads none of it. Nothing here decides that an iteration's order is
||| free: the MLIR side does, once it knows what a region does. A coordinate
||| is an `index` at its access, unguarded, since its type bounds it by an
||| extent; an extent enters `index` at an allocation, guarded. An array of
||| records is a tensor of the record's data type, like any other.
module IdrisMLIR.Emit.Tensors

import IdrisMLIR.Dialect.Arith as Arith
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.Linalg as Linalg
import IdrisMLIR.Dialect.SCF as SCF
import IdrisMLIR.Dialect.Tensor as Tensor
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Operations
import IdrisMLIR.Emit.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.Fin
import Data.List
import Data.Maybe
import Data.SortedMap
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Sizes and coordinates
------------------------------------------------------------------------------

||| `arith.constant n : index`.
indexConst : Loc -> Integer -> E Value
indexConst l n = mlirValue l IndexType (Arith.constantOp (IntegerAttr n IndexType))

||| Size arithmetic on `index`, which no size overflows: a sum of two sizes
||| of arrays that exist is below 2^63.
noWrap : Maybe MlirAttr
noWrap = Just (Arith.arith (IntegerOverflowFlagsAttr [Nsw, Nuw]))

||| A natural as a coordinate: exact, unguarded, since its type bounds it
||| by an extent.
export
coordinate : Index -> Loc -> Val -> E Value
coordinate ix l n = do
  w <- mlirValue l (IntegerType 64) (Idr.bigToIntOp (operand ix !(coerce ix l Many n)))
  mlirValue l IndexType (Arith.indexCastuiOp w)

||| A coordinate as a natural, the variable `binder` bound to it.
natural : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Value -> E Val
natural ix l i = do
  w <- mlirValue l (IntegerType 64) (Arith.indexCastuiOp i)
  r <- mlirValueAt (madeAt binder l Many) (gradedType ix Many made (NatT IOpaque)) (Idr.bigSmallOp w)
  pure (val r.name (NatT IOpaque) Many made)

||| A natural as the extent of an array to be made: past every allocation
||| either target can make, it is the allocation's failure.
extent : Index -> Loc -> Val -> E Value
extent ix l n = mlirValue l IndexType (Idr.natToExtentOp (operand ix !(coerce ix l Many n)))

||| A value as a plain operand: a linear one is used here.
plainOperand : Index -> Loc -> Val -> E Value
plainOperand ix l v = operand ix <$> coerce ix l Many v

||| The element of an array's type; any other type is its own.
elementOf : Ty -> Ty
elementOf (TensorT _ e) = e
elementOf t = t

||| What a cell of dimensions `ds` of element `e` is: the element itself
||| when it has none.
shaped : List Dim -> Ty -> Ty
shaped [] e = e
shaped ds e = TensorT ds e

||| Dimensions, each with its axis, outermost first.
withAxes : Vect r Dim -> Vect r (Nat, Dim)
withAxes = go 0
  where
    go : Nat -> Vect k Dim -> Vect k (Nat, Dim)
    go j [] = []
    go j (d :: ds) = (j, d) :: go (S j) ds

||| What a vector holds before a position, at it, and after it: an
||| operation's own axis of its array, with the dimensions around it.
around : Fin r -> Vect r a -> (List a, a, List a)
around FZ (x :: xs) = ([], x, toList xs)
around (FS i) (x :: xs) = let (before, here, after) = around i xs in (x :: before, here, after)

||| What a vector holds before a position, at it and at the one after it,
||| and after both: a transpose's axis and the one it swaps it with.
aroundPair : Fin r -> Vect (S r) a -> (List a, a, a, List a)
aroundPair FZ (x :: y :: xs) = ([], x, y, toList xs)
aroundPair (FS i) (x :: xs) = let (before, p, q, after) = aroundPair i xs in (x :: before, p, q, after)

||| The size of an array's dimension at its axis: its size where the type
||| fixes it, else `tensor.dim`.
sizeAt : Loc -> Value -> (Nat, Dim) -> E (Either Value Integer)
sizeAt l x (j, Static n) = pure (Right (cast n))
sizeAt l x (j, Dynamic) = Left <$> mlirValue l IndexType (Tensor.dimOp x !(indexConst l (cast j)))

||| A size as a value.
sizeValue : Loc -> Either Value Integer -> E Value
sizeValue l (Left v) = pure v
sizeValue l (Right n) = indexConst l n

||| The dimensions sizes give a tensor: static where they are.
dimsOfSizes : List (Either Value Integer) -> List Dim
dimsOfSizes = map (either (const Dynamic) (Static . cast))

||| A list of mixed entries: the operands of its dynamic ones, and the static
||| list, `kDynamic` where an operand gives the entry.
mixed : List (Either Value Integer) -> (List Value, List Integer)
mixed es = (mapMaybe (either Just (const Nothing)) es, map (either (const dynamicExtent) id) es)

||| The size of a result's dimension: its static size where the result's
||| type fixes it, else what `otherwise` makes.
resultSize : Dim -> E (Either Value Integer) -> E (Either Value Integer)
resultSize (Static n) otherwise = pure (Right (cast n))
resultSize Dynamic otherwise = otherwise

------------------------------------------------------------------------------
-- Casts
------------------------------------------------------------------------------

||| How a value fits a slot: as it is; cast to the slot's type, a tensor
||| whose type differs from the slot's only in which dimensions are static;
||| reindexed to it (`idr.data.reindex`), a value of the slot's family at
||| index terms the scope's refinements make equal to the slot's, one known
||| to be a constructor the slot's type does not name, or a natural linked
||| to another term than the slot's; or not at all, the
||| frontend's error. Any other value is of the slot's type, but for the
||| extents of the tensors in it, which a closure's type holds dynamic. A
||| value of one family where its slot takes another is one type translated
||| as two, and a match on the slot's would take the constructors the value
||| was built with as never built.
data Fitting = AsIs | CastTo Ty | Reindex Ty | Mismatch String Ty

fitting : Maybe Ty -> Ty -> Refinement -> Fitting
fitting (Just (TensorT ds e)) (TensorT es e') _ =
  if ds == es then AsIs
  else if length ds == length es && e == e' then CastTo (TensorT ds e)
  else Mismatch "an array" (TensorT ds e)
fitting (Just (TensorT _ _)) _ _ = AsIs
fitting (Just slot@(DataT f ts)) (DataT g us) r =
  if f /= g then Mismatch "a value" slot
  else case r of
    AnyConstructor => if ts == us then AsIs else Reindex slot
    OneOf _ => Reindex slot
fitting (Just slot@(NatT t)) (NatT u) _ = if t == u then AsIs else Reindex slot
fitting (Just slot) t _ = if dynamicDims t == dynamicDims slot then AsIs else Mismatch "a value" slot
fitting Nothing _ _ = AsIs

||| `v` where a slot of type `slot` takes it, as `fitting` fits it, the
||| variable `binder` bound to a cast it is given.
export
fit : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Maybe Ty -> Val -> E Val
fit ix l slot v = case fitting slot v.type v.refinement of
  AsIs => pure v
  CastTo t => do
    r <- mlirValueAt (madeAt binder l Many) (mlirType ix t) (Tensor.castOp !(plainOperand ix l v))
    pure (val r.name t Many made)
  Reindex t => do
    let v' = { type := t, refinement := AnyConstructor } v
    r <- mlirValueAt (madeAt binder l v.uses) (valueType ix v') (Idr.dataReindexOp (operand ix v) [])
    pure ({ name := r.name } v')
  -- Kept: the core term holds the type each slot takes, and each form the
  -- type of the value it gives (`Term.termType`), but no proof that the two
  -- agree but for the extents and index terms a cast or a reindex fixes. A
  -- term is not indexed by its type: a `let` of a value the translation
  -- binds (`OfValue`), a field of a value taken apart and a value a
  -- settled term computes are typed by what makes them, not by a binder of
  -- the scope, so what makes a value and what holds it are two readings
  -- of one Idris type.
  Mismatch what expected =>
    internal (what ++ " of type " ++ show v.type ++ " where " ++ show expected ++ " is expected")

||| An op that makes a value of type `made`, where a slot of type `slot`
||| takes it (`fit`), the variable `binder` bound to what the slot takes:
||| the op's value, or the cast of it.
export
fitted : {default Nothing binder : Maybe Binding} -> {default Nothing stands : Maybe Shown} -> Index -> Loc -> Maybe Ty -> Ty -> (MlirType -> Op) -> E Val
fitted ix l slot made build = case fitting slot made AnyConstructor of
  AsIs => value {binder} {stands} ix l made build
  _ => fit {binder} ix l slot !(value {stands} ix l made build)

||| What a region gives where its op takes it: the value at the slot's
||| type, plain.
given : Index -> Loc -> Ty -> Val -> E Value
given ix l slot v = plainOperand ix l !(fit ix l (Just slot) v)

------------------------------------------------------------------------------
-- Regions
------------------------------------------------------------------------------

||| The region of an array op: its block's arguments, the ops its body
||| appends, and, when the body returns, `idr.array.yield` of what it
||| gives. A body that never returns has ended in `ub.unreachable`, which is
||| then the region's terminator.
region : Loc -> List Value -> E (Maybe (List Value)) -> E MLIR.Region
region l args body = do
  (yielded, ops) <- collect body
  pure (MkRegion (map (\a => MkArgument a (At l)) args)
                 (ops ++ maybe [] (\vs => [MkStatement Nothing (Idr.arrayYieldOp vs) (At l)]) yielded))

||| A fresh `index` value: the coordinate a region binds along one axis.
freshIndex : E Value
freshIndex = (\n => MkValue (Bound n 0) IndexType) <$> fresh

||| Fresh `index` values, one per axis: the coordinates a region binds.
indices : (k : Nat) -> E (Vect k Value)
indices k = traverse (\_ => freshIndex) (replicate k ())

||| The sizes of the leading dimensions `ds` that are dynamic, from the
||| extents given, each guarded as an allocation's: a static one is the
||| type's.
dynamicExtents : Index -> Loc -> List Dim -> List Val -> E (List Value)
dynamicExtents ix l ds es = traverse (extent ix l . snd) (filter (\(d, _) => d == Dynamic) (zip ds es))

------------------------------------------------------------------------------
-- Reads and writes
------------------------------------------------------------------------------

||| The cell of `x`, of type `a`, at the coordinates `cs`, `index` values:
||| the element when they address every axis (`tensor.extract`), else the
||| slice of the remaining axes, of unit size along the addressed ones and
||| rank-reduced, at the type its sizes give, then at `rt`; the variable
||| `binder` bound to it.
readAt : Index -> Loc -> Maybe Binding -> Ty -> ArrayType r -> Val -> List Value -> E Val
readAt ix l binder rt a x cs = do
  xv <- plainOperand ix l x
  let n = length cs
  case drop n (toList (withAxes a.dims)) of
    [] => value {binder} ix l rt (Tensor.extractOp xv cs)
    cell => do
      sizes <- traverse (sizeAt l xv) cell
      let (offsets, staticOffsets) = mixed (map Left cs ++ map (const (Right 0)) cell)
          (sizeOps, staticSizes) = mixed (map (const (Right 1)) cs ++ sizes)
          (_, staticStrides) = mixed (map (const (Right 1)) (toList a.dims))
      fitted {binder} ix l (Just rt) (TensorT (dimsOfSizes sizes) a.element)
             (Tensor.extractSliceOp xv offsets sizeOps [] staticOffsets staticSizes staticStrides)

||| The cell of `x`, of type `a`, at `coords`, naturals.
read : Index -> Loc -> Maybe Binding -> Ty -> ArrayType r -> Val -> List Val -> E Val
read ix l binder rt a x coords = readAt ix l binder rt a x !(traverse (coordinate ix l) coords)

||| `x`, of type `a`, with `v` at `coords`: `tensor.insert` of an element,
||| or `tensor.insert_slice` of a cell, the cell first at the type of the
||| slice it fills; the result at `rt`.
write : Index -> Loc -> Maybe Binding -> Ty -> ArrayType r -> Val -> Val -> List Val -> E Val
write ix l binder rt a x v coords = do
  xv <- plainOperand ix l x
  cs <- traverse (coordinate ix l) coords
  let n = length cs
      ds = toList a.dims
  case drop n ds of
    [] => fitted {binder} ix l (Just rt) x.type (Tensor.insertOp !(plainOperand ix l v) xv cs)
    cell => do
      vv <- given ix l (TensorT cell a.element) v
      sizes <- traverse (sizeAt l vv) (toList (withAxes (Data.Vect.fromList cell)))
      let (offsets, staticOffsets) = mixed (map Left cs ++ map (const (Right 0)) cell)
          (sizeOps, staticSizes) = mixed (map (const (Right 1)) cs ++ sizes)
          (_, staticStrides) = mixed (map (const (Right 1)) ds)
      fitted {binder} ix l (Just rt) x.type
             (Tensor.insertSliceOp vv xv offsets sizeOps [] staticOffsets staticSizes staticStrides)

------------------------------------------------------------------------------
-- The operations
------------------------------------------------------------------------------

||| The reassociation of a reshape: the leading `n` axes as one group, then
||| each later axis alone.
groups : Nat -> Nat -> List MlirAttr
groups n rest = group (take n [0 .. n]) :: map (\i => group [i]) (take rest [n .. n + rest])
  where
    group : List Nat -> MlirAttr
    group is = ArrayAttr (map (\i => IntegerAttr (cast i) (IntegerType 64)) is)

||| A slice of `xv`, of element `e`, at the offsets and sizes given, strides
||| 1, at the type its sizes give, then at `rt`.
sliced : Index -> Loc -> Maybe Binding -> Ty -> Value -> Ty -> List (Either Value Integer)
      -> List (Either Value Integer) -> E Val
sliced ix l binder rt xv e offsets sizes = do
  let (os, so) = mixed offsets
      (ss, sz) = mixed sizes
      (_, st) = mixed (map (const (Right 1)) sizes)
  fitted {binder} ix l (Just rt) (TensorT (dimsOfSizes sizes) e) (Tensor.extractSliceOp xv os ss [] so sz st)

||| An operation of the array language on its operands, giving a value of
||| the type it holds of its result, the variable `binder` bound to it. Each
||| array it takes is of the type the operation holds of it, which every
||| dimension and axis is read from.
export
tensorOp : Index -> Loc -> Maybe Binding -> TensorOp Val -> E Val
tensorOp ix l binder (Extent a j x) = do
  xv <- plainOperand ix l x
  natural {binder} ix l !(sizeValue l !(sizeAt l xv (finToNat j, Data.Vect.index j a.dims)))
tensorOp ix l binder (Extract a rt x coords) = read ix l binder rt a x coords
tensorOp ix l binder (Insert a rt x v coords) = write ix l binder rt a x v coords
tensorOp ix l binder (Take a ra j k x) = do
  xv <- plainOperand ix l x
  kv <- coordinate ix l k
  let (before, _, after) = around j (withAxes a.dims)
  pre <- traverse (sizeAt l xv) before
  mid <- resultSize (Data.Vect.index j ra.dims) (pure (Left kv))
  post <- traverse (sizeAt l xv) after
  sliced ix l binder (arrayTy ra) xv a.element (map (const (Right 0)) (toList a.dims)) (pre ++ mid :: post)
tensorOp ix l binder (Drop a ra j k x) = do
  xv <- plainOperand ix l x
  kv <- coordinate ix l k
  let (before, own, after) = around j (withAxes a.dims)
  pre <- traverse (sizeAt l xv) before
  mid <- resultSize (Data.Vect.index j ra.dims) $ do
    whole <- sizeValue l !(sizeAt l xv own)
    Left <$> mlirValue l IndexType (Arith.subiOp {overflowFlags = noWrap} whole kv)
  post <- traverse (sizeAt l xv) after
  sliced ix l binder (arrayTy ra) xv a.element
         (map (const (Right 0)) before ++ Left kv :: map (const (Right 0)) after) (pre ++ mid :: post)
tensorOp ix l binder (Concat xa ya ra axis x y) = do
  xv <- plainOperand ix l x
  yv <- plainOperand ix l y
  let rt = arrayTy ra
      rds = toList ra.dims
      -- The result's dimensions, each with the first array's at its axis,
      -- and the second array's own.
      (before, (xown, rown), after) = around axis (Data.Vect.zip (withAxes xa.dims) ra.dims)
      yown = Data.Vect.index axis (withAxes ya.dims)
  pre <- traverse (\(xd, rd) => resultSize rd (sizeAt l xv xd)) before
  mid <- resultSize rown $ do
    m <- sizeValue l !(sizeAt l xv xown)
    n <- sizeValue l !(sizeAt l yv yown)
    Left <$> mlirValue l IndexType (Arith.addiOp {overflowFlags = noWrap} m n)
  post <- traverse (\(xd, rd) => resultSize rd (sizeAt l xv xd)) after
  let sizes = pre ++ mid :: post
      el = ra.element
      joined = TensorT (dimsOfSizes sizes) el
  case reaches ix el of
    -- Words are joined slice by slice into a fresh destination.
    WordsOnly => do
      empty <- value ix l joined (Tensor.emptyOp (fst (mixed sizes)))
      let ev = operand ix empty
      xsizes <- traverse (sizeAt l xv) (toList (withAxes xa.dims))
      ysizes <- traverse (sizeAt l yv) (toList (withAxes ya.dims))
      shift <- sizeAt l xv xown
      let (xo, xso) = mixed (map (const (Right 0)) rds)
          (xs, xss) = mixed xsizes
          (yo, yso) = mixed (map (const (Right 0)) before ++ shift :: map (const (Right 0)) after)
          (ys, yss) = mixed ysizes
          (_, strides) = mixed (map (const (Right 1)) rds)
      first <- mlirValue l ev.type (Tensor.insertSliceOp xv ev xo xs [] xso xss strides)
      fitted {binder} ix l (Just rt) joined (Tensor.insertSliceOp yv first yo ys [] yso yss strides)
    -- Elements that hold references are written whole by the one op that
    -- makes the array, which reads neither: a tabulation whose element at
    -- a coordinate below the first array's extent along the axis is the
    -- first's there, and any other the second's, the coordinate less that
    -- extent.
    HoldsReferences => do
      m <- sizeValue l !(sizeAt l xv xown)
      -- The result's coordinates, split at the axis as its dimensions
      -- are, so the coordinate along the axis is at hand.
      lead <- indices (length before)
      iv <- freshIndex
      trail <- indices (length after)
      let cs = toList lead ++ iv :: toList trail
      reg <- region l cs $ do
        below <- mlirValue l (IntegerType 1) (Arith.cmpiOp CmpIPredicate.Ult iv m)
        -- Each arm reads in its own region, and only there. The choice is
        -- a condition, upstream's `scf.if`: no Idris value is matched.
        (fromX, xops) <- collect $ do
          e <- readAt ix l Nothing el xa x cs
          given ix l el e
        (fromY, yops) <- collect $ do
          j <- mlirValue l IndexType (Arith.subiOp {overflowFlags = noWrap} iv m)
          e <- readAt ix l Nothing el ya y (toList lead ++ j :: toList trail)
          given ix l el e
        r <- mlirValue l (mlirType ix el) (\t => SCF.ifOp below
               (MkRegion [] (xops ++ [MkStatement Nothing (SCF.yieldOp [fromX]) (At l)]))
               (MkRegion [] (yops ++ [MkStatement Nothing (SCF.yieldOp [fromY]) (At l)])) [t])
        pure (Just [r])
      dest <- mlirValue l (mlirType ix joined) (Tensor.emptyOp (fst (mixed sizes)))
      fitted {binder} ix l (Just rt) joined (\t => Idr.arrayTabulateOp dest reg [t])
-- A transpose of words is upstream's `linalg.transpose` into a fresh
-- destination, its permutation given once; of elements that hold
-- references it is a tabulation reading at the swapped coordinates, since
-- no linalg body holds a reference while counting runs.
tensorOp ix l binder (Transpose a rt axis x) = do
  xv <- plainOperand ix l x
  let (before, (_, da), (_, db), rest) = aroundPair axis (withAxes a.dims)
      ax = finToNat axis
      perm = map fst before ++ S ax :: ax :: map fst rest
      swappedDims = map snd before ++ db :: da :: map snd rest
      swapped = TensorT swappedDims a.element
  sizes <- traverse (sizeAt l xv) (zip perm swappedDims)
  case reaches ix a.element of
    WordsOnly => do
      dest <- mlirValue l (mlirType ix swapped) (Tensor.emptyOp (fst (mixed sizes)))
      fitted {binder} ix l (Just rt) swapped (\t => Linalg.transposeOp xv dest (map cast perm) [t])
    HoldsReferences => do
      -- The result's coordinates, split at the two axes the transpose
      -- swaps; `x` is read at them swapped back.
      lead <- indices (length before)
      ia <- freshIndex
      ib <- freshIndex
      trail <- indices (length rest)
      reg <- region l (toList lead ++ ia :: ib :: toList trail) $ do
        e <- readAt ix l Nothing a.element a x (toList lead ++ ib :: ia :: toList trail)
        pure (Just [!(given ix l a.element e)])
      dest <- mlirValue l (mlirType ix swapped) (Tensor.emptyOp (fst (mixed sizes)))
      fitted {binder} ix l (Just rt) swapped (\t => Idr.arrayTabulateOp dest reg [t])
tensorOp ix l binder (Reshape a rt x extents) = do
  xv <- plainOperand ix l x
  let ds = toList a.dims
      rds = tensorDims rt
      t = length extents
      cellRank = minus (length rds) t
      r = minus (length ds) cellRank
      cell = drop r ds
      e = a.element
      leading = take r ds
      n = if all isStatic leading then Static (product (map staticOf leading)) else Dynamic
      flatTy = mlirType ix (TensorT (n :: cell) e)
      -- The flattened array is the result when the result has one leading
      -- axis of its type.
      flatAt = if t == 1 && TensorT (n :: cell) e == rt then madeAt binder l Many else At l
  cellSizes <- traverse (sizeAt l xv) (drop r (toList (withAxes a.dims)))
  flat <- case r of
    S Z => pure xv
    Z => do
      let (outs, static) = mixed (Right 1 :: cellSizes)
      mlirValueAt flatAt flatTy (Tensor.expandShapeOp xv (map ArrayAttr (unitGroups cellRank)) outs static)
    _ => mlirValueAt flatAt flatTy (Tensor.collapseShapeOp xv (groups r cellRank))
  let rt' = mlirType ix rt
      at = madeAt binder l Many
  case t of
    S Z => do
      res <- if TensorT (n :: cell) e == rt then pure flat else mlirValueAt at rt' (Tensor.castOp flat)
      pure (val res.name rt Many made)
    Z => do
      let unitTy = mlirType ix (TensorT (Static 1 :: cell) e)
      unit <- if n == Static 1 then pure flat else mlirValue l unitTy (Tensor.castOp flat)
      res <- mlirValueAt at rt' (Tensor.collapseShapeOp unit (map ArrayAttr (unitGroups cellRank)))
      pure (val res.name rt Many made)
    _ => do
      let (lead, cellDims) = splitAt t rds
      leadSizes <- traverse (\(d, ext) => resultSize d (Left <$> coordinate ix l ext)) (zip lead extents)
      restSizes <- traverse (\(d, xd) => resultSize d (sizeAt l xv xd)) (zip cellDims (drop r (toList (withAxes a.dims))))
      let (outs, static) = mixed (leadSizes ++ restSizes)
      res <- mlirValueAt at rt' (Tensor.expandShapeOp flat (groups t cellRank) outs static)
      pure (val res.name rt Many made)
  where
    isStatic : Dim -> Bool
    isStatic (Static _) = True
    isStatic Dynamic = False
    staticOf : Dim -> Nat
    staticOf (Static k) = k
    staticOf Dynamic = 0
    -- From rank `c` to the unit axis and `c` more, or back: the unit axis
    -- joins the first cell axis; with no cell, no group.
    unitGroups : Nat -> List (List MlirAttr)
    unitGroups Z = []
    unitGroups (S c) =
      map (\i => IntegerAttr (cast i) (IntegerType 64)) [0, 1]
        :: map (\i => [IntegerAttr (cast i) (IntegerType 64)]) (take c [2 .. S c])

------------------------------------------------------------------------------
-- New arrays and reductions
------------------------------------------------------------------------------

||| A new array of `rt` of the extents given, each element or cell what
||| `body` gives at the coordinates: `idr.array.tabulate` of the extents `rt`
||| leaves dynamic, its region binding the coordinates. A cell's own
||| dimensions are `rt`'s, those it leaves dynamic the cells' own, which
||| every cell shares. The variable `binder` is bound to it.
export
tabulate : {k : Nat} -> Index -> Loc -> Maybe Binding -> Ty -> Vect k Val -> (Vect k Val -> E (Maybe Val))
        -> E (Maybe Val)
tabulate ix l binder rt extents body = do
  let ds = tensorDims rt
      cell = shaped (drop k ds) (elementOf rt)
  sizes <- dynamicExtents ix l (take k ds) (toList extents)
  ivs <- indices k
  r <- region l (toList ivs) $ do
    Just v <- body !(traverse (natural ix l) ivs)
      | Nothing => pure Nothing
    pure (Just [!(given ix l cell v)])
  -- The tabulation writes a fresh destination, never one an element was
  -- read from.
  dest <- mlirValue l (mlirType ix rt) (Tensor.emptyOp sizes)
  Just <$> value {binder} ix l rt (\t => Idr.arrayTabulateOp dest r [t])

||| A reduction of `x`, of type `xa`, along `axis`, the one after the frame
||| of `z`, from `z`'s accumulators, left to right in index order:
||| `idr.array.fold_last` keeping the last accumulators,
||| `idr.array.scan_last` every one. The frame is the axes `z` has beyond
||| an accumulator's, as many as the axes before `axis`; the region binds
||| the frame's indices, the index along the axis and the accumulator,
||| reads `x`'s element there and gives the next accumulator. An
||| accumulator of no frame and no axis of its own is held, for the op, in
||| an array of none. The variable `binder` is bound to the result.
export
reduce : Index -> Loc -> Maybe Binding -> Reduction -> (acc, elem, result : Ty) -> (xa : ArrayType k) -> (axis : Fin k)
      -> Val -> Val -> (Val -> Val -> E (Maybe Val)) -> E (Maybe Val)
reduce ix l binder r acc elem rt xa axis z x body = do
  let frame = finToNat axis
  xv <- plainOperand ix l x
  len <- sizeValue l !(sizeAt l xv (frame, Data.Vect.index axis xa.dims))
  init <- case z.type of
    TensorT _ _ => case r of
      FoldLast => given ix l rt z
      ScanLast => plainOperand ix l z
    -- An accumulator held in an array of none: of words, the array of its
    -- one element; of one that holds references, a tabulation of no axis
    -- giving it, so that the array is written whole by the op that makes it.
    t => case reaches ix t of
      WordsOnly => mlirValue l (RankedTensorType [] (mlirType ix t)) (Tensor.fromElementsOp [!(plainOperand ix l z)])
      HoldsReferences => do
        reg <- region l [] (Just . (:: []) <$> given ix l t z)
        dest <- mlirValue l (RankedTensorType [] (mlirType ix t)) (Tensor.emptyOp [])
        mlirValue l (RankedTensorType [] (mlirType ix t)) (\r => Idr.arrayTabulateOp dest reg [r])
  ivs <- indices (S frame)
  (a, av) <- freshVal ix acc Many
  reg <- region l (toList ivs ++ [av]) $ do
    Just a' <- body a !(readAt ix l Nothing elem xa x (toList ivs))
      | Nothing => pure Nothing
    pure (Just [!(given ix l acc a')])
  case (r, rt) of
    (FoldLast, TensorT _ _) => Just <$> value {binder} ix l rt (\t => Idr.arrayFoldLastOp [init] len reg [t])
    (FoldLast, _) => do
      held <- mlirValue l init.type (\t => Idr.arrayFoldLastOp [init] len reg [t])
      Just <$> value {binder} ix l rt (Tensor.extractOp held [])
    (ScanLast, _) => Just <$> value {binder} ix l rt (\t => Idr.arrayScanLastOp [init] len reg [t])

------------------------------------------------------------------------------
-- Ties
------------------------------------------------------------------------------

||| The array `v`, of type `tied`, the dynamic dimensions that type gives
||| it stated equal to the sizes given (`idr.array.tie_shape`): the extent
||| of another array's axis, exact, or a natural, converted as an extent;
||| the other dynamic dimensions read from it. Itself when nothing is
||| stated of a dynamic dimension. The variable `binder` is bound to it.
export
tie : Index -> Loc -> Maybe Binding -> (tied : Ty) -> Val -> List (Nat, Stated Val) -> E Val
tie ix l binder tied v stated = do
  sizes <- SortedMap.fromList <$> traverse (\(a, s) => (a,) <$> size s) stated
  let ds = tensorDims tied
      dynamic = filter (\(_, d) => d == Dynamic) (toList (withAxes (Data.Vect.fromList ds)))
  if all (\(j, _) => isNothing (lookup j sizes)) dynamic then pure v else do
    xv <- plainOperand ix l v
    dims <- traverse (\(j, d) => case lookup j sizes of
                        Just s => pure s
                        Nothing => sizeValue l !(sizeAt l xv (j, d))) dynamic
    r <- mlirValueAt (madeAt binder l Many) xv.type (Idr.arrayTieShapeOp xv dims)
    pure (val r.name v.type Many made)
  where
    size : Stated Val -> E Value
    size (SameAs n) = coordinate ix l n
    size (Natural n) = extent ix l n
