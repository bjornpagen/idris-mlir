-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The array language in ops, each primitive in its meaning: a new array is
||| `idr.tabulate` (in a world's order `idr.tabulate_io`), a fold along the
||| last axis `idr.fold_last`, a scan `idr.scan_last`, each a region from
||| indices (and an accumulator) to an element, and a transpose
||| `idr.transpose`; a read is `tensor.extract`, a write `tensor.insert`,
||| and a slice, a join, a reshape and a pad the `tensor` ops of each. Nothing here decides that an iteration's order is
||| free: the MLIR side does, once it knows what a region does. A coordinate
||| is an `index` at its access, unguarded, since its type bounds it by an
||| extent; an extent enters `index` at an allocation, guarded. An array of
||| records is a tensor of the record's data type, like any other.
module IdrisMLIR.Emit.Tensors

import IdrisMLIR.Dialect.Arith as Arith
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.Tensor as Tensor
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Operations
import IdrisMLIR.Emit.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.Maybe
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
noWrap = Just (Arith (IntegerOverflowFlagsAttr [Nsw, Nuw]))

||| A natural as a coordinate: exact, unguarded, since its type bounds it
||| by an extent.
export
coordinate : Index -> Loc -> Val -> E Value
coordinate ix l n = do
  w <- mlirValue l (IntegerType 64) (Idr.bigToIntOp !(operand ix !(coerce ix l Many n)))
  mlirValue l IndexType (Arith.indexCastuiOp w)

||| A coordinate as a natural.
natural : Loc -> Value -> E Val
natural l i = do
  w <- mlirValue l (IntegerType 64) (Arith.indexCastuiOp i)
  r <- mlirValue l (Idr NatType) (Idr.bigSmallOp w)
  pure (val r.name NatT Many)

||| A natural as the extent of an array to be made: past every allocation
||| either target can make, it is the allocation's failure.
extent : Index -> Loc -> Val -> E Value
extent ix l n = mlirValue l IndexType (Idr.natToExtentOp !(operand ix !(coerce ix l Many n)))

||| A value as a plain operand: a linear one is used here.
plainOperand : Index -> Loc -> Val -> E Value
plainOperand ix l v = operand ix !(coerce ix l Many v)

||| The dimensions of an array value.
dimsOf : Val -> E (List Dim)
dimsOf v = case v.type of
  TensorT ds _ => pure ds
  t => internal ("an array operation on a value of type " ++ show t)

||| The element of an array's type; any other type is its own.
elementOf : Ty -> Ty
elementOf (TensorT _ e) = e
elementOf t = t

||| What a cell of dimensions `ds` of element `e` is: the element itself
||| when it has none.
shaped : List Dim -> Ty -> Ty
shaped [] e = e
shaped ds e = TensorT ds e

||| Dimension `j` of a tensor: its size where the type fixes it, else
||| `tensor.dim`.
dimEntry : Loc -> Value -> List Dim -> Nat -> E (Either Value Integer)
dimEntry l x ds j = case getAt j ds of
  Just (Static n) => pure (Right (cast n))
  Just Dynamic => Left <$> mlirValue l IndexType (Tensor.dimOp x !(indexConst l (cast j)))
  Nothing => internal ("dimension " ++ show j ++ " of an array of rank " ++ show (length ds))

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

||| The axes of a list, by position.
axes : List a -> List Nat
axes xs = take (length xs) [0 .. length xs]

------------------------------------------------------------------------------
-- Casts
------------------------------------------------------------------------------

||| `v` where a slot of type `slot` takes it: a tensor whose type differs
||| from the slot's only in which dimensions are static is cast to it; any
||| other tensor that differs is the frontend's error. Other values are as
||| they are.
export
fit : Index -> Loc -> Maybe Ty -> Val -> E Val
fit ix l (Just (TensorT ds e)) v = case v.type of
  TensorT es e' =>
    if ds == es then pure v
    else if length ds == length es && e == e' then do
      t <- mlirType ix (TensorT ds e)
      r <- mlirValue l t (Tensor.castOp !(plainOperand ix l v))
      pure (val r.name (TensorT ds e) Many)
    else internal ("an array of type " ++ show v.type ++ " where " ++ show (TensorT ds e) ++ " is expected")
  _ => pure v
fit ix l _ v = pure v

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

||| Fresh `index` values, one per axis: the coordinates a region binds.
indices : (k : Nat) -> E (Vect k Value)
indices k = traverse (\_ => (\n => MkValue n IndexType) <$> fresh) (replicate k ())

||| The sizes of the leading dimensions `ds` that are dynamic, from the
||| extents given, each guarded as an allocation's: a static one is the
||| type's.
dynamicExtents : Index -> Loc -> List Dim -> List Val -> E (List Value)
dynamicExtents ix l ds es = traverse (extent ix l . snd) (filter (\(d, _) => d == Dynamic) (zip ds es))

------------------------------------------------------------------------------
-- Reads and writes
------------------------------------------------------------------------------

||| The cell of `x` at the coordinates `cs`, `index` values: the element
||| when they address every axis (`tensor.extract`), else the slice of the
||| remaining axes, of unit size along the addressed ones and rank-reduced,
||| at the type its sizes give, then at `rt`.
readAt : Index -> Loc -> Ty -> Val -> List Value -> E Val
readAt ix l rt x cs = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  let n = length cs
  case drop n ds of
    [] => value ix l rt (Tensor.extractOp xv cs)
    cell => do
      sizes <- traverse (dimEntry l xv ds) (drop n (axes ds))
      let (offsets, staticOffsets) = mixed (map Left cs ++ map (const (Right 0)) cell)
          (sizeOps, staticSizes) = mixed (map (const (Right 1)) cs ++ sizes)
          (_, staticStrides) = mixed (map (const (Right 1)) ds)
      s <- value ix l (TensorT (dimsOfSizes sizes) (elementOf x.type))
             (Tensor.extractSliceOp xv offsets sizeOps [] staticOffsets staticSizes staticStrides)
      fit ix l (Just rt) s

||| The cell of `x` at `coords`, naturals.
read : Index -> Loc -> Ty -> Val -> List Val -> E Val
read ix l rt x coords = readAt ix l rt x !(traverse (coordinate ix l) coords)

||| `x` with `v` at `coords`: `tensor.insert` of an element, or
||| `tensor.insert_slice` of a cell, the cell first at the type of the
||| slice it fills; the result at `rt`.
write : Index -> Loc -> Ty -> Val -> Val -> List Val -> E Val
write ix l rt x v coords = do
  xv <- plainOperand ix l x
  cs <- traverse (coordinate ix l) coords
  ds <- dimsOf x
  let n = length cs
  r <- case drop n ds of
    [] => value ix l x.type (Tensor.insertOp !(plainOperand ix l v) xv cs)
    cell => do
      vv <- given ix l (TensorT cell (elementOf x.type)) v
      sizes <- traverse (dimEntry l vv cell) (axes cell)
      let (offsets, staticOffsets) = mixed (map Left cs ++ map (const (Right 0)) cell)
          (sizeOps, staticSizes) = mixed (map (const (Right 1)) cs ++ sizes)
          (_, staticStrides) = mixed (map (const (Right 1)) ds)
      value ix l x.type (Tensor.insertSliceOp vv xv offsets sizeOps [] staticOffsets staticSizes staticStrides)
  fit ix l (Just rt) r

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
sliced : Index -> Loc -> Ty -> Value -> Ty -> List (Either Value Integer) -> List (Either Value Integer)
      -> E Val
sliced ix l rt xv e offsets sizes = do
  let (os, so) = mixed offsets
      (ss, sz) = mixed sizes
      (_, st) = mixed (map (const (Right 1)) sizes)
  s <- value ix l (TensorT (dimsOfSizes sizes) e) (Tensor.extractSliceOp xv os ss [] so sz st)
  fit ix l (Just rt) s

||| The size of axis `i` of a result of dimensions `rds`: its static size,
||| else what `otherwise` gives.
resultSize : List Dim -> Nat -> E (Either Value Integer) -> E (Either Value Integer)
resultSize rds i otherwise = case getAt i rds of
  Just (Static n) => pure (Right (cast n))
  _ => otherwise

||| An operation of the array language on its operands.
export
tensorOp : Index -> Loc -> TensorOp -> Ty -> List Val -> E Val
tensorOp ix l (Extent j) rt [x] = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  natural l !(sizeValue l !(dimEntry l xv ds j))
tensorOp ix l Extract rt (x :: coords) = read ix l rt x coords
tensorOp ix l Insert rt (x :: v :: coords) = write ix l rt x v coords
tensorOp ix l (Take a) rt [k, x] = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  kv <- coordinate ix l k
  sizes <- traverse (\i => if i == a then resultSize (tensorDims rt) i (pure (Left kv))
                           else dimEntry l xv ds i) (axes ds)
  sliced ix l rt xv (elementOf x.type) (map (const (Right 0)) ds) sizes
tensorOp ix l (Drop a) rt [k, x] = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  kv <- coordinate ix l k
  sizes <- traverse (\i => if i == a
                              then resultSize (tensorDims rt) i $ do
                                whole <- sizeValue l !(dimEntry l xv ds i)
                                Left <$> mlirValue l IndexType (Arith.subiOp {overflowFlags = noWrap} whole kv)
                              else dimEntry l xv ds i) (axes ds)
  sliced ix l rt xv (elementOf x.type) (map (\i => if i == a then Left kv else Right 0) (axes ds)) sizes
tensorOp ix l (Concat a) rt [x, y] = do
  xv <- plainOperand ix l x
  yv <- plainOperand ix l y
  xds <- dimsOf x
  yds <- dimsOf y
  let rds = tensorDims rt
  sizes <- traverse (\i => resultSize rds i $
                             if i == a
                               then do
                                 m <- sizeValue l !(dimEntry l xv xds i)
                                 n <- sizeValue l !(dimEntry l yv yds i)
                                 Left <$> mlirValue l IndexType (Arith.addiOp {overflowFlags = noWrap} m n)
                               else dimEntry l xv xds i) (axes rds)
  let joined = TensorT (dimsOfSizes sizes) (elementOf rt)
  empty <- value ix l joined (Tensor.emptyOp (fst (mixed sizes)))
  ev <- operand ix empty
  xsizes <- traverse (dimEntry l xv xds) (axes xds)
  ysizes <- traverse (dimEntry l yv yds) (axes yds)
  shift <- dimEntry l xv xds a
  let (xo, xso) = mixed (map (const (Right 0)) rds)
      (xs, xss) = mixed xsizes
      (yo, yso) = mixed (map (\i => if i == a then shift else Right 0) (axes rds))
      (ys, yss) = mixed ysizes
      (_, strides) = mixed (map (const (Right 1)) rds)
  first <- mlirValue l ev.type (Tensor.insertSliceOp xv ev xo xs [] xso xss strides)
  r <- value ix l joined (Tensor.insertSliceOp yv first yo ys [] yso yss strides)
  fit ix l (Just rt) r
tensorOp ix l (Transpose a) rt [x] = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  let perm = map (\i => if i == a then S a else if i == S a then a else i) (axes ds)
      swapped = TensorT (map (\i => fromMaybe Dynamic (getAt i ds)) perm) (elementOf x.type)
  r <- value ix l swapped (Idr.transposeOp xv (map cast perm))
  fit ix l (Just rt) r
tensorOp ix l Reshape rt (x :: extents) = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  let rds = tensorDims rt
      t = length extents
      cellRank = minus (length rds) t
      r = minus (length ds) cellRank
      cell = drop r ds
      e = elementOf x.type
      leading = take r ds
      n = if all isStatic leading then Static (product (map staticOf leading)) else Dynamic
  flatTy <- mlirType ix (TensorT (n :: cell) e)
  cellSizes <- traverse (dimEntry l xv ds) (take cellRank [r .. length ds])
  flat <- case r of
    S Z => pure xv
    Z => do
      let (outs, static) = mixed (Right 1 :: cellSizes)
      mlirValue l flatTy (Tensor.expandShapeOp xv (map ArrayAttr (unitGroups cellRank)) outs static)
    _ => mlirValue l flatTy (Tensor.collapseShapeOp xv (groups r cellRank))
  rt' <- mlirType ix rt
  case t of
    S Z => do
      res <- if TensorT (n :: cell) e == rt then pure flat else mlirValue l rt' (Tensor.castOp flat)
      pure (val res.name rt Many)
    Z => do
      unitTy <- mlirType ix (TensorT (Static 1 :: cell) e)
      unit <- if n == Static 1 then pure flat else mlirValue l unitTy (Tensor.castOp flat)
      res <- mlirValue l rt' (Tensor.collapseShapeOp unit (map ArrayAttr (unitGroups cellRank)))
      pure (val res.name rt Many)
    _ => do
      sizes <- traverse (\(i, d) => case d of
                           Static k => pure (Right (cast k))
                           Dynamic => case getAt i extents of
                             Just ext => Left <$> coordinate ix l ext
                             Nothing => dimEntry l xv ds (r + minus i t))
                        (zip (axes rds) rds)
      let (outs, static) = mixed sizes
      res <- mlirValue l rt' (Tensor.expandShapeOp flat (groups t cellRank) outs static)
      pure (val res.name rt Many)
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
tensorOp ix l (Pad a) rt [lo, hi, v, x] = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  -- The padded length, guarded as an extent: the total of three sizes is
  -- converted whole, its parts then coordinates.
  len <- natural l !(sizeValue l !(dimEntry l xv ds a))
  front <- value ix l NatT (Idr.bigAddOp !(plainOperand ix l lo) !(operand ix len))
  whole <- value ix l NatT (Idr.bigAddOp !(operand ix front) !(plainOperand ix l hi))
  _ <- extent ix l whole
  low <- coordinate ix l lo
  high <- coordinate ix l hi
  let (lows, staticLow) = mixed (map (\i => if i == a then Left low else Right 0) (axes ds))
      (highs, staticHigh) = mixed (map (\i => if i == a then Left high else Right 0) (axes ds))
      padded = TensorT (map (\(i, d) => if i == a then Dynamic else d) (zip (axes ds) ds)) (elementOf x.type)
  pt <- mlirType ix padded
  -- The region gives the value at each index of the padding: the cell's
  -- element at the cell's axes.
  ivs <- traverse (\_ => (\n => MkValue n IndexType) <$> fresh) ds
  (yielded, ops) <- collect $ case v.type of
    TensorT _ el => do
      vv <- plainOperand ix l v
      mlirValue l !(mlirType ix el) (Tensor.extractOp vv (drop (S a) ivs))
    _ => plainOperand ix l v
  let body = MkRegion (map (\i => MkArgument i (At l)) ivs)
                      (ops ++ [MkStatement Nothing (Tensor.yieldOp yielded) (At l)])
  r <- mlirValue l pt (Tensor.padOp xv lows highs staticLow staticHigh body)
  fit ix l (Just rt) (val r.name padded Many)
tensorOp ix l op rt vs =
  internal ("the array operation " ++ show op ++ " on " ++ show (length vs) ++ " operands")

------------------------------------------------------------------------------
-- New arrays and reductions
------------------------------------------------------------------------------

||| A new array of `rt` of the extents given, each element or cell what
||| `body` gives at the coordinates: `idr.tabulate` of the extents `rt`
||| leaves dynamic, its region binding the coordinates. A cell's own
||| dimensions are `rt`'s, those it leaves dynamic the cells' own, which
||| every cell shares.
export
tabulate : {k : Nat} -> Index -> Loc -> Ty -> Vect k Val -> (Vect k Val -> E (Maybe Val)) -> E (Maybe Val)
tabulate ix l rt extents body = do
  let ds = tensorDims rt
      cell = shaped (drop k ds) (elementOf rt)
  sizes <- dynamicExtents ix l (take k ds) (toList extents)
  ivs <- indices k
  r <- region l (toList ivs) $ do
    Just v <- body !(traverse (natural l) ivs)
      | Nothing => pure Nothing
    pure (Just [!(given ix l cell v)])
  Just <$> value ix l rt (\t => Idr.tabulateOp sizes r [t])

||| A reduction of `x` along the axis after the frame of `z`, from `z`'s
||| accumulators, left to right in index order: `idr.fold_last` keeping the
||| last accumulators, `idr.scan_last` every one. The frame is the axes `z`
||| has beyond an accumulator's; the region binds the frame's indices, the
||| index along the axis and the accumulator, reads `x`'s element there and
||| gives the next accumulator. An accumulator of no frame and no axis of
||| its own is held, for the op, in an array of none.
export
reduce : Index -> Loc -> Reduction -> (acc, elem, result : Ty) -> Val -> Val -> (Val -> Val -> E (Maybe Val))
      -> E (Maybe Val)
reduce ix l r acc elem rt z x body = do
  let frame = minus (length (tensorDims z.type)) (length (tensorDims acc))
  xv <- plainOperand ix l x
  xds <- dimsOf x
  len <- sizeValue l !(dimEntry l xv xds frame)
  init <- case z.type of
    TensorT _ _ => case r of
      FoldLast => given ix l rt z
      ScanLast => plainOperand ix l z
    t => mlirValue l (RankedTensorType [] !(mlirType ix t)) (Tensor.fromElementsOp [!(plainOperand ix l z)])
  ivs <- indices (S frame)
  (a, av) <- freshVal ix acc Many
  reg <- region l (toList ivs ++ [av]) $ do
    Just a' <- body a !(readAt ix l elem x (toList ivs))
      | Nothing => pure Nothing
    pure (Just [!(given ix l acc a')])
  case (r, rt) of
    (FoldLast, TensorT _ _) => Just <$> value ix l rt (\t => Idr.foldLastOp [init] len reg [t])
    (FoldLast, _) => do
      held <- mlirValue l init.type (\t => Idr.foldLastOp [init] len reg [t])
      Just <$> value ix l rt (Tensor.extractOp held [])
    (ScanLast, _) => Just <$> value ix l rt (\t => Idr.scanLastOp [init] len reg [t])

||| A new array of `rt` of the extents given, made in the world's order:
||| `idr.tabulate_io`, its region given the coordinates and the world before
||| each element and giving the element and the world after it, which it
||| takes from the body's `IORes` (`step`) by a match of its one
||| constructor. Its value is the `IORes` (`done`) of the array and the last
||| world.
export
tabulateIO : {k : Nat} -> Index -> Loc -> Ty -> Vect k Val -> Val -> (Vect k Val -> Val -> E (Maybe Val))
          -> (step, done : DataId) -> E (Maybe Val)
tabulateIO ix l rt extents world body step done = do
  let ds = tensorDims rt
      cell = shaped (drop k ds) (elementOf rt)
  stepCon <- only ix step
  [elemField, _] <- pure stepCon.fields
    | _ => internal (show step ++ " does not hold a value and a world")
  sizes <- dynamicExtents ix l (take k ds) (toList extents)
  ivs <- indices k
  (w0, wv) <- freshVal ix WorldT Many
  r <- region l (toList ivs ++ [wv]) $ do
    Just res <- body !(traverse (natural l) ivs) w0
      | Nothing => pure Nothing
    (e, w1) <- taken stepCon (typeOf elemField) res
    pure (Just [!(given ix l cell e), w1])
  t <- mlirType ix rt
  wt <- mlirType ix WorldT
  [arr, w] <- resultNames l (Idr.tabulateIoOp sizes !(operand ix world) r [t] wt)
    | _ => internal "a tabulation in the world's order giving more than its array and world"
  Just <$> ioResult ix l done (val arr rt Many) (val w WorldT Many)
  where
    -- The element and the world of an `IORes`, held plainly: a match of
    -- its one constructor, whose case yields its fields.
    taken : Con -> Ty -> Val -> E (Val, Value)
    taken c et res = do
      et' <- mlirType ix et
      wt <- mlirType ix WorldT
      x <- fresh
      w1 <- fresh
      let arm = MkRegion [MkArgument (MkValue x et') (At l), MkArgument (MkValue w1 wt) (At l)]
                         [MkStatement Nothing (Idr.yieldOp [MkValue x et', MkValue w1 wt]) (At l)]
      [e, w2] <- resultNames l (Idr.matchOp !(operand ix res) [c.tag] [arm] [et', wt])
        | _ => internal "a match on an IORes giving more than a value and a world"
      pure (val e et Many, MkValue w2 wt)

------------------------------------------------------------------------------
-- Ties
------------------------------------------------------------------------------

||| What a tie states of one dimension: the size of another array's
||| dimension (`Extent`), exact, or a natural from elsewhere, an extent.
public export
data Stated = OfArray Val | OfNatural Val

||| The array, its dynamic dimensions stated equal to the sizes given
||| (`idr.tie_shape`), the others read from it; itself when nothing is
||| stated of a dynamic dimension.
export
tie : Index -> Loc -> Val -> List (Maybe Stated) -> E Val
tie ix l v stated = do
  sizes <- traverse (traverse size) stated
  ds <- dimsOf v
  let given = sizes ++ replicate (minus (length ds) (length sizes)) Nothing
      dynamic = filter (\(_, d, _) => d == Dynamic) (zip3 (axes ds) ds given)
  if all (\(_, _, g) => isNothing g) dynamic then pure v else do
    xv <- plainOperand ix l v
    dims <- traverse (\(j, _, g) => case g of
                        Just d => pure d
                        Nothing => sizeValue l !(dimEntry l xv ds j)) dynamic
    r <- mlirValue l xv.type (Idr.tieShapeOp xv dims)
    pure (val r.name v.type Many)
  where
    size : Stated -> E Value
    size (OfArray n) = coordinate ix l n
    size (OfNatural n) = extent ix l n
