-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The array language in upstream ops, each primitive in its sequential
||| meaning: a new array is `tensor.empty` and a nest of `scf.for` that
||| inserts each element, a fold an `scf.for` carrying its accumulator, a
||| read `tensor.extract`, a write `tensor.insert`, a slice, a join, a
||| reshape and a pad the `tensor` ops of each. Nothing here decides that a
||| loop's order is free: the MLIR side does, once the optimizer has shown
||| what a body does. A coordinate is an `index` at its access, unguarded,
||| since its type bounds it by an extent; an extent enters `index` at an
||| allocation, guarded.
module IdrisMLIR.Emit.Tensors

import IdrisMLIR.Dialect.Arith as Arith
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.SCF as SCF
import IdrisMLIR.Dialect.Tensor as Tensor
import IdrisMLIR.Dialect.UB as UB
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

||| A value as plain operands: one, or one per column.
plainOperands : Index -> Loc -> Val -> E (List Value)
plainOperands ix l v = operandsOf ix !(coerce ix l Many v)

||| The first column of an array of records, whose leading dimensions are
||| the array's; an array itself.
firstColumn : Val -> Val
firstColumn (MkVal _ _ _ (Columns (c :: _))) = firstColumn c
firstColumn v = v

||| The dimensions of an array value: a tensor's, or an array of records'.
dimsOf : Val -> E (List Dim)
dimsOf v = case v.type of
  TensorT ds _ => pure ds
  ColumnsT ValueArray ds _ => pure ds
  t => internal ("an array operation on a value of type " ++ show t)

||| The one value that holds an array's leading dimensions: itself, or its
||| first column.
dimSource : Index -> Loc -> Val -> E Value
dimSource ix l v = plainOperand ix l (firstColumn v)

||| A value of type `t` made of its columns, given in field order.
columnsVal : Ty -> List Val -> E Val
columnsVal t ps = (\key => MkVal key t Many (Columns ps)) <$> fresh

||| The columns of an array of records' type.
columnTys : Index -> Ty -> E (List Ty)
columnTys ix (ColumnsT k ds r) = columnsOf ix k ds r
columnTys ix t = internal ("the columns of a value of type " ++ show t)

||| The parts of a value held in columns.
partsOf : Val -> E (List Val)
partsOf (MkVal _ _ _ (Columns ps)) = pure ps
partsOf v = internal ("the columns of a value of type " ++ show v.type ++ " held whole")

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

||| A list of mixed entries: the operands of its dynamic ones, and the static
||| list, `kDynamic` where an operand gives the entry.
mixed : List (Either Value Integer) -> (List Value, MlirAttr)
mixed es = (mapMaybe (either Just (const Nothing)) es,
            DenseI64ArrayAttr (map (either (const dynamicExtent) id) es))

------------------------------------------------------------------------------
-- Casts
------------------------------------------------------------------------------

||| `v` where a slot of type `slot` takes it: a tensor whose type differs
||| from the slot's only in which dimensions are static is cast to it; any
||| other tensor that differs is the frontend's error. Other values are as
||| they are. An array of records is fit column by column.
export covering
fit : Index -> Loc -> Maybe Ty -> Val -> E Val
fit ix l (Just (ColumnsT k ds r)) v = case v.type of
  ColumnsT k' es r' =>
    if ds == es then pure v
    else if k == k' && r == r' && length ds == length es then do
      ts <- columnsOf ix k ds r
      columnsVal (ColumnsT k ds r) !(traverse (\(t, c) => fit ix l (Just t) c) (zip ts !(partsOf v)))
    else internal ("an array of type " ++ show v.type ++ " where " ++ show (ColumnsT k ds r) ++ " is expected")
  _ => pure v
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

------------------------------------------------------------------------------
-- Loops
------------------------------------------------------------------------------

||| An `scf.for` from 0 to `bound` by 1 carrying `inits`, its body given the
||| induction variable and the values carried. A body that never returns
||| ends in its crash and yields `ub.poison` of each carried type, since an
||| `scf.for` block ends in `scf.yield`. The loop's values are the carried
||| ones after it.
covering
forLoop : Index -> Loc -> Value -> List Val -> (Value -> List Val -> E (Maybe (List Val))) -> E (List Val)
forLoop ix l bound inits body = do
  zero <- indexConst l 0
  one <- indexConst l 1
  initOps <- concat <$> traverse (plainOperands ix l) inits
  iv <- (\n => MkValue n IndexType) <$> fresh
  bound' <- traverse (\v => freshVal ix v.type Many) inits
  let carried = map fst bound'
      args = concatMap (\(_, vs) => map (\o => MkArgument o (At l)) vs) bound'
  (next, ops) <- collect (body iv carried)
  ending <- case next of
    Just vs => do
      outs <- traverse (\(c, v) => do
                          v' <- fit ix l (Just c.type) v
                          plainOperands ix l v') (zip carried vs)
      pure [MkStatement Nothing (SCF.yieldOp (concat outs)) (At l)]
    Nothing => do
      poisons <- traverse (\o => mlirValue l o.type UB.poisonOp) initOps
      pure [MkStatement Nothing (SCF.yieldOp poisons) (At l)]
  let kept = case next of
               Just _ => ops
               Nothing => dropUnreachable ops
  names <- resultNames l (SCF.forOp zero bound one initOps
                            (MkRegion (MkArgument iv (At l) :: args) (kept ++ ending))
                            (map (.type) initOps))
  results names inits
  where
    results : List String -> List Val -> E (List Val)
    results ns [] = pure []
    results ns (v :: vs) = do
      (r, rest) <- fromNames ix v.type Many ns
      (r ::) <$> results rest vs
    dropUnreachable : List Statement -> List Statement
    dropUnreachable ss = case reverse ss of
      (s :: rest) => if s.op.name == UB.unreachableOp.name then reverse rest else ss
      [] => []

------------------------------------------------------------------------------
-- Reads and writes
------------------------------------------------------------------------------

||| The axes of a list, by position.
axes : List a -> List Nat
axes xs = take (length xs) [0 .. length xs]

mutual
  ||| The cell of `x` at `coords`: the element when the result is not a
  ||| tensor (`tensor.extract`), else the slice of the remaining axes, of
  ||| unit size along the addressed ones and rank-reduced. An array of
  ||| records gathers: each column read, the record built of its fields, or
  ||| the columns of the cell when the cell is an array of records.
  covering
  read : Index -> Loc -> Ty -> Val -> List Val -> E Val
  read ix l rt (MkVal n xt u (Columns ps)) coords = case rt of
    DataT r => do
      c <- only ix r
      con ix l c !(readAll (map typeOf c.fields) ps)
    ColumnsT _ _ _ => columnsVal rt !(readAll !(columnTys ix rt) ps)
    t => internal ("a read of an array of records giving " ++ show t)
    where
      readAll : List Ty -> List Val -> E (List Val)
      readAll (t :: ts) (p :: rest) = (::) <$> read ix l t p coords <*> readAll ts rest
      readAll _ _ = pure []
  read ix l rt x coords = do
    xv <- plainOperand ix l x
    cs <- traverse (coordinate ix l) coords
    t <- mlirType ix rt
    case rt of
      TensorT cell _ => do
        ds <- dimsOf x
        let n = length cs
        sizes <- traverse (dimEntry l xv ds) (drop n (axes ds))
        let (offsets, staticOffsets) = mixed (map Left cs ++ map (const (Right 0)) cell)
            (sizeOps, staticSizes) = mixed (map (const (Right 1)) cs ++ sizes)
            (_, staticStrides) = mixed (map (const (Right 1)) ds)
        r <- mlirValue l t (Tensor.extractSliceOp xv offsets sizeOps [] staticOffsets staticSizes staticStrides)
        pure (val r.name rt Many)
      _ => do
        r <- mlirValue l t (Tensor.extractOp xv cs)
        pure (val r.name rt Many)

mutual
  ||| `x` with `v` at `coords`: `tensor.insert` of an element, or
  ||| `tensor.insert_slice` of a cell. An array of records scatters: a
  ||| record taken apart, each field written into its column, or each
  ||| column of a cell of records into the array's.
  covering
  write : Index -> Loc -> Ty -> Val -> Val -> List Val -> E Val
  write ix l rt (MkVal n xt u (Columns ps)) v coords = do
    vs <- case v.parts of
      Columns qs => pure qs
      _ => fieldsOf ix l v
    columnsVal rt !(writeAll !(columnTys ix rt) ps vs)
    where
      writeAll : List Ty -> List Val -> List Val -> E (List Val)
      writeAll (t :: ts) (p :: rest) (f :: fs) = (::) <$> write ix l t p f coords <*> writeAll ts rest fs
      writeAll _ _ _ = pure []
  write ix l rt x v coords = do
    xv <- plainOperand ix l x
    vv <- plainOperand ix l v
    cs <- traverse (coordinate ix l) coords
    t <- mlirType ix rt
    case v.type of
      TensorT cell _ => do
        sizes <- traverse (dimEntry l vv cell) (axes cell)
        ds <- dimsOf x
        let (offsets, staticOffsets) = mixed (map Left cs ++ map (const (Right 0)) cell)
            (sizeOps, staticSizes) = mixed (map (const (Right 1)) cs ++ sizes)
            (_, staticStrides) = mixed (map (const (Right 1)) ds)
        r <- mlirValue l t (Tensor.insertSliceOp vv xv offsets sizeOps [] staticOffsets staticSizes staticStrides)
        pure (val r.name rt Many)
      _ => do
        r <- mlirValue l t (Tensor.insertOp vv xv cs)
        pure (val r.name rt Many)

------------------------------------------------------------------------------
-- The operations
------------------------------------------------------------------------------

||| The reassociation of a reshape: the leading `n` axes as one group, then
||| each later axis alone.
groups : Nat -> Nat -> MlirAttr
groups n rest =
  ArrayAttr (group (take n [0 .. n]) :: map (\i => group [i]) (take rest [n .. n + rest]))
  where
    group : List Nat -> MlirAttr
    group is = ArrayAttr (map (\i => IntegerAttr (cast i) (IntegerType 64)) is)

||| A slice of `x` of rank `rank` at the offsets and sizes given, strides 1.
sliced : Index -> Loc -> Ty -> Value -> List (Either Value Integer) -> List (Either Value Integer) -> Nat
      -> E Val
sliced ix l rt xv offsets sizes rank = do
  t <- mlirType ix rt
  let (os, so) = mixed offsets
      (ss, sz) = mixed sizes
      (_, st) = mixed (replicate rank (Right 1))
  r <- mlirValue l t (Tensor.extractSliceOp xv os ss [] so sz st)
  pure (val r.name rt Many)

||| An array of records whose every column is what `f` makes of the
||| array's, at the column's type in `rt`.
covering
perColumn : Index -> Ty -> (Ty -> Val -> E Val) -> List Val -> E Val
perColumn ix rt f ps = do
  ts <- columnTys ix rt
  columnsVal rt !(traverse (\(t, p) => f t p) (zip ts ps))

||| An operation of the array language on its operands. On an array of
||| records it acts on every column alike: an extent is the first
||| column's; a slice, a join and a reshape act on each column, a pad pads
||| each column with its field of the cell. It recurses through columns,
||| which hold no column of their own record, so it is covering.
export covering
tensorOp : Index -> Loc -> TensorOp -> Ty -> List Val -> E Val
tensorOp ix l (Extent j) rt [MkVal _ _ _ (Columns (c :: _))] = tensorOp ix l (Extent j) rt [c]
tensorOp ix l (Take a) rt [k, MkVal _ _ _ (Columns ps)] =
  perColumn ix rt (\t, p => tensorOp ix l (Take a) t [k, p]) ps
tensorOp ix l (Drop a) rt [k, MkVal _ _ _ (Columns ps)] =
  perColumn ix rt (\t, p => tensorOp ix l (Drop a) t [k, p]) ps
tensorOp ix l (Concat a) rt [MkVal _ _ _ (Columns ps), y] = do
  qs <- partsOf y
  ts <- columnTys ix rt
  columnsVal rt !(traverse (\(t, p, q) => tensorOp ix l (Concat a) t [p, q]) (zip3 ts ps qs))
tensorOp ix l Reshape rt (MkVal _ _ _ (Columns ps) :: extents) =
  perColumn ix rt (\t, p => tensorOp ix l Reshape t (p :: extents)) ps
tensorOp ix l (Pad a) rt [lo, hi, v, MkVal _ _ _ (Columns ps)] = do
  fs <- case v.parts of
    Columns qs => pure qs
    _ => fieldsOf ix l v
  ts <- columnTys ix rt
  columnsVal rt !(traverse (\(t, p, f) => tensorOp ix l (Pad a) t [lo, hi, f, p]) (zip3 ts ps fs))
tensorOp ix l (Extent j) rt [x] = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  size <- sizeValue l !(dimEntry l xv ds j)
  natural l size
tensorOp ix l Extract rt (x :: coords) = read ix l rt x coords
tensorOp ix l Insert rt (x :: v :: coords) = write ix l rt x v coords
tensorOp ix l (Take a) rt [k, x] = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  rds <- maybe (internal "a take whose result is not an array") pure (Just (tensorDims rt))
  kv <- coordinate ix l k
  sizes <- traverse (\i => if i == a
                              then case getAt i rds of
                                     Just (Static n) => pure (Right (cast n))
                                     _ => pure (Left kv)
                              else dimEntry l xv ds i) (axes ds)
  sliced ix l rt xv (map (const (Right 0)) ds) sizes (length ds)
tensorOp ix l (Drop a) rt [k, x] = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  kv <- coordinate ix l k
  sizes <- traverse (\i => if i == a
                              then case getAt i (tensorDims rt) of
                                     Just (Static n) => pure (Right (cast n))
                                     _ => do
                                       whole <- sizeValue l !(dimEntry l xv ds i)
                                       Left <$> mlirValue l IndexType (Arith.subiOp {overflowFlags = noWrap} whole kv)
                              else dimEntry l xv ds i) (axes ds)
  sliced ix l rt xv (map (\i => if i == a then Left kv else Right 0) (axes ds)) sizes (length ds)
tensorOp ix l (Concat a) rt [x, y] = do
  xv <- plainOperand ix l x
  yv <- plainOperand ix l y
  xds <- dimsOf x
  yds <- dimsOf y
  let rds = tensorDims rt
  sizes <- traverse (\i => case getAt i rds of
                             Just (Static n) => pure (Right (cast n))
                             _ => if i == a
                                    then do
                                      m <- sizeValue l !(dimEntry l xv xds i)
                                      n <- sizeValue l !(dimEntry l yv yds i)
                                      Left <$> mlirValue l IndexType (Arith.addiOp {overflowFlags = noWrap} m n)
                                    else dimEntry l xv xds i) (axes rds)
  t <- mlirType ix rt
  empty <- mlirValue l t (Tensor.emptyOp (fst (mixed sizes)))
  xsizes <- traverse (dimEntry l xv xds) (axes xds)
  ysizes <- traverse (dimEntry l yv yds) (axes yds)
  shift <- dimEntry l xv xds a
  let unit = map (const (Right 1)) rds
      (xo, xso) = mixed (map (const (Right 0)) rds)
      (xs, xss) = mixed xsizes
      (yo, yso) = mixed (map (\i => if i == a then shift else Right 0) (axes rds))
      (ys, yss) = mixed ysizes
      (_, strides) = mixed unit
  first <- mlirValue l t (Tensor.insertSliceOp xv empty xo xs [] xso xss strides)
  r <- mlirValue l t (Tensor.insertSliceOp yv first yo ys [] yso yss strides)
  pure (val r.name rt Many)
tensorOp ix l Reshape rt (x :: extents) = do
  xv <- plainOperand ix l x
  ds <- dimsOf x
  let rds = tensorDims rt
      t = length extents
      cellRank = minus (length rds) t
      r = minus (length ds) cellRank
      cell = drop r ds
      e = case x.type of
            TensorT _ el => el
            other => other
      leading = take r ds
      n = if all isStatic leading then Static (product (map staticOf leading)) else Dynamic
  flatTy <- mlirType ix (TensorT (n :: cell) e)
  cellSizes <- traverse (dimEntry l xv ds) (take cellRank [r .. length ds])
  flat <- case r of
    S Z => pure xv
    Z => do
      let (outs, static) = mixed (Right 1 :: cellSizes)
      mlirValue l flatTy (Tensor.expandShapeOp xv (map ArrayAttr (unitGroups cellRank)) outs static)
    _ => mlirValue l flatTy (Tensor.collapseShapeOp xv (groupsList r cellRank))
  rt' <- mlirType ix rt
  case t of
    S Z => do
      r <- if TensorT (n :: cell) e == rt then pure flat else mlirValue l rt' (Tensor.castOp flat)
      pure (val r.name rt Many)
    Z => do
      unitTy <- mlirType ix (TensorT (Static 1 :: cell) e)
      unit <- if n == Static 1 then pure flat else mlirValue l unitTy (Tensor.castOp flat)
      r <- mlirValue l rt' (Tensor.collapseShapeOp unit (map ArrayAttr (unitGroups cellRank)))
      pure (val r.name rt Many)
    _ => do
      sizes <- traverse (\(i, d) => case d of
                           Static k => pure (Right (cast k))
                           Dynamic => case getAt i extents of
                             Just ext => Left <$> coordinate ix l ext
                             Nothing => dimEntry l xv ds (r + minus i t))
                        (zip (axes rds) rds)
      let (outs, static) = mixed sizes
      res <- mlirValue l rt' (Tensor.expandShapeOp flat (groupsList t cellRank) outs static)
      pure (val res.name rt Many)
  where
    isStatic : Dim -> Bool
    isStatic (Static _) = True
    isStatic Dynamic = False
    staticOf : Dim -> Nat
    staticOf (Static k) = k
    staticOf Dynamic = 0
    groupsList : Nat -> Nat -> List MlirAttr
    groupsList n rest = case groups n rest of
      ArrayAttr gs => gs
      _ => []
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
  len <- tensorOp ix l (Extent a) NatT [x]
  front <- value ix l NatT (Idr.bigAddOp !(plainOperand ix l lo) !(operand ix len))
  whole <- value ix l NatT (Idr.bigAddOp !(operand ix front) !(plainOperand ix l hi))
  _ <- extent ix l whole
  low <- coordinate ix l lo
  high <- coordinate ix l hi
  let (lows, staticLow) = mixed (map (\i => if i == a then Left low else Right 0) (axes ds))
      (highs, staticHigh) = mixed (map (\i => if i == a then Left high else Right 0) (axes ds))
      padded = TensorT (map (\(i, d) => if i == a then Dynamic else d) (zip (axes ds) ds))
                       (case x.type of
                          TensorT _ el => el
                          other => other)
  pt <- mlirType ix padded
  -- The region gives the value at each index of the padding: the cell's
  -- element at the cell's axes.
  ivs <- traverse (\_ => (\n => MkValue n IndexType) <$> fresh) ds
  (yielded, ops) <- collect $ case v.type of
    TensorT cell _ => do
      vv <- plainOperand ix l v
      e <- mlirType ix (case v.type of
                          TensorT _ el => el
                          other => other)
      mlirValue l e (Tensor.extractOp vv (drop (S a) ivs))
    _ => plainOperand ix l v
  let region = MkRegion (map (\i => MkArgument i (At l)) ivs)
                        (ops ++ [MkStatement Nothing (Tensor.yieldOp yielded) (At l)])
  r <- mlirValue l pt (Tensor.padOp xv lows highs staticLow staticHigh region)
  fit ix l (Just rt) (val r.name padded Many)
tensorOp ix l op rt vs =
  internal ("the array operation " ++ show op ++ " on " ++ show (length vs) ++ " operands")

------------------------------------------------------------------------------
-- New arrays and reductions
------------------------------------------------------------------------------

||| A new array of type `t` whose leading dimensions have the sizes given:
||| `tensor.empty`, or one per column of an array of records. A dimension
||| after them must be static: nothing gives its size before the first
||| cell is made.
covering
emptyOf : Index -> Loc -> Ty -> List (Either Value Integer) -> E Val
emptyOf ix l t@(ColumnsT k ds r) sizes = do
  cols <- columnsOf ix k ds r
  columnsVal t !(traverse (\c => emptyOf ix l c sizes) cols)
emptyOf ix l t sizes = do
  let rest = drop (length sizes) (tensorDims t)
  unless (all (/= Dynamic) rest) $
    internal ("a new array of " ++ show t ++ " whose cells' size no extent gives")
  ty <- mlirType ix t
  e <- mlirValue l ty (Tensor.emptyOp (fst (mixed sizes)))
  pure (val e.name t Many)

||| A new array of `rt` of the extents given, each element or cell what
||| `body` gives at the coordinates: `tensor.empty` and a nest of loops,
||| one per extent, the innermost inserting the body's value. A cell whose
||| size its type leaves dynamic has no size before the first one is made.
export covering
tabulate : {k : Nat} -> Index -> Loc -> Ty -> Vect k Val -> (Vect k Val -> E (Maybe Val)) -> E (Maybe Val)
tabulate ix l rt extents body = do
  let ds = tensorDims rt
  sizes <- traverse (\(d, e) => case d of
                       Static n => pure (Right (cast n))
                       Dynamic => Left <$> extent ix l e) (zip (take k ds) (toList extents))
  empty <- emptyOf ix l rt sizes
  bounds <- traverse (sizeValue l) sizes
  result <- nest bounds [] empty
  pure (Just result)
  where
    covering
    nest : List Value -> List Value -> Val -> E Val
    nest [] ivs dest = case toVect k (reverse ivs) of
      Nothing => internal "a tabulation with fewer coordinates than extents"
      Just is => do
        coords <- traverse (natural l) is
        Just v <- body coords
          | Nothing => pure dest
        written <- write ix l rt dest v (toList coords)
        pure written
    nest (b :: bs) ivs dest = do
      [out] <- forLoop ix l b [dest] (\iv, carried => case carried of
                 [d] => Just . (:: []) <$> nest bs (iv :: ivs) d
                 _ => internal "a loop of a tabulation carrying more than the array")
        | _ => internal "a loop of a tabulation giving more than the array"
      pure out

||| A reduction of `x` along the axis after the frame of `z`, from `z`'s
||| accumulators, left to right in index order: an `scf.for` over that axis
||| carrying the accumulator, inside a nest over the frame carrying the
||| array of accumulators; a scan carries the array of every accumulator
||| too, into which each is written.
export covering
reduce : Index -> Loc -> Reduction -> (acc, elem, result : Ty) -> Val -> Val -> (Val -> Val -> E (Maybe Val))
      -> E (Maybe Val)
reduce ix l r acc elem rt z x body = do
  let frame = minus (length (tensorDims z.type)) (length (tensorDims acc))
  xv <- dimSource ix l x
  xds <- dimsOf x
  length' <- sizeValue l !(dimEntry l xv xds frame)
  frameBounds <- traverse (\i => sizeValue l !(dimEntry l xv xds i)) (take frame [0 .. frame])
  case r of
    FoldLast => Just <$> foldFrame frameBounds [] (!(fit ix l (Just rt) z)) length'
    ScanLast => do
      sizes <- traverse (\i => dimEntry l xv xds i) (take (S frame) [0 .. S frame])
      cellSizes <- the (E (List (Either Value Integer))) $ case z.type of
        TensorT zds _ => do
          zv <- plainOperand ix l z
          traverse (dimEntry l zv zds) (drop frame (axes zds))
        ColumnsT ValueArray zds _ => do
          zv <- dimSource ix l z
          traverse (dimEntry l zv zds) (drop frame (axes zds))
        _ => pure []
      dest <- emptyOf ix l rt (sizes ++ cellSizes)
      Just <$> scanFrame frameBounds [] dest length'
  where
    -- The accumulator at the frame's coordinates, folded along the axis.
    fold : List Value -> Val -> Value -> E Val
    fold frameIvs a0 len = do
      [out] <- forLoop ix l len [a0] (\iv, carried => case carried of
                 [a] => do
                   coords <- traverse (natural l) (reverse frameIvs ++ [iv])
                   e <- read ix l elem x coords
                   map (map (:: [])) (body a e)
                 _ => internal "a fold carrying more than its accumulator")
        | _ => internal "a fold giving more than its accumulator"
      pure out
    foldFrame : List Value -> List Value -> Val -> Value -> E Val
    foldFrame [] [] zs len = fold [] zs len
    foldFrame [] ivs dests len = do
      coords <- traverse (natural l) (reverse ivs)
      a0 <- read ix l acc dests coords
      a <- fold ivs a0 len
      write ix l rt dests a coords
    foldFrame (b :: bs) ivs dests len = do
      [out] <- forLoop ix l b [dests] (\iv, carried => case carried of
                 [d] => Just . (:: []) <$> foldFrame bs (iv :: ivs) d len
                 _ => internal "a frame loop carrying more than its array")
        | _ => internal "a frame loop giving more than its array"
      pure out
    -- The scan along the axis at the frame's coordinates: each accumulator
    -- written at its index.
    scan : List Value -> Val -> Val -> Value -> E Val
    scan frameIvs a0 dest len = do
      [_, out] <- forLoop ix l len [a0, dest] (\iv, carried => case carried of
                    [a, d] => do
                      coords <- traverse (natural l) (reverse frameIvs ++ [iv])
                      e <- read ix l elem x coords
                      Just a' <- body a e
                        | Nothing => pure Nothing
                      a'' <- fit ix l (Just acc) a'
                      d' <- write ix l rt d a'' coords
                      pure (Just [a'', d'])
                    _ => internal "a scan carrying more than its accumulator and array")
        | _ => internal "a scan giving more than its accumulator and array"
      pure out
    scanFrame : List Value -> List Value -> Val -> Value -> E Val
    scanFrame [] [] dest len = scan [] z dest len
    scanFrame [] ivs dest len = do
      coords <- traverse (natural l) (reverse ivs)
      a0 <- read ix l acc z coords
      scan ivs a0 dest len
    scanFrame (b :: bs) ivs dest len = do
      [out] <- forLoop ix l b [dest] (\iv, carried => case carried of
                 [d] => Just . (:: []) <$> scanFrame bs (iv :: ivs) d len
                 _ => internal "a frame loop carrying more than its array")
        | _ => internal "a frame loop giving more than its array"
      pure out

||| A new array of `rt` of the extents given, made in the world's order:
||| the loops of `tabulate`, each carrying the world too, the body given the
||| coordinates and the world before it and giving the `IORes` (`step`) of
||| the element and the world after it, which a match takes apart. Its value
||| is the `IORes` (`done`) of the array and the last world.
export covering
tabulateIO : {k : Nat} -> Index -> Loc -> Ty -> Vect k Val -> Val -> (Vect k Val -> Val -> E (Maybe Val))
          -> (step, done : DataId) -> E (Maybe Val)
tabulateIO ix l rt extents world body step done = do
  let ds = tensorDims rt
  stepCon <- only ix step
  [elemField, worldField] <- pure stepCon.fields
    | _ => internal (show step ++ " does not hold a value and a world")
  sizes <- traverse (\(d, e) => case d of
                       Static n => pure (Right (cast n))
                       Dynamic => Left <$> extent ix l e) (zip (take k ds) (toList extents))
  empty <- emptyOf ix l rt sizes
  bounds <- traverse (sizeValue l) sizes
  [arr, w] <- nest stepCon elemField worldField bounds [] [empty, world]
    | _ => internal "a tabulation in the world's order giving more than its array and world"
  Just <$> ioResult ix l done arr w
  where
    covering
    nest : Con -> Binder -> Binder -> List Value -> List Value -> List Val -> E (List Val)
    nest c ef wf [] ivs [dest, w0] = case toVect k (reverse ivs) of
      Nothing => internal "a tabulation with fewer coordinates than extents"
      Just is => do
        coords <- traverse (natural l) is
        Just res <- body coords w0
          | Nothing => pure [dest, w0]
        et <- binderType ix ef
        wt <- binderType ix wf
        x <- fresh
        w1 <- fresh
        let region = MkRegion [MkArgument (MkValue x et) (At l), MkArgument (MkValue w1 wt) (At l)]
                              [MkStatement Nothing (Idr.yieldOp [MkValue x et, MkValue w1 wt]) (At l)]
        [e, w2] <- resultNames l (Idr.matchOp !(operand ix res)
                                    [SymbolRefAttr (MkSymbolRef c.id.name [])] [region] [et, wt])
          | _ => internal "a match on an IORes giving more than a value and a world"
        written <- write ix l rt dest (val e (typeOf ef) Many) (toList coords)
        pure [written, val w2 WorldT Many]
    nest c ef wf [] ivs carried = internal "a tabulation in the world's order carrying more than its array and world"
    nest c ef wf (b :: bs) ivs carried =
      forLoop ix l b carried (\iv, inner => Just <$> nest c ef wf bs (iv :: ivs) inner)

------------------------------------------------------------------------------
-- Ties
------------------------------------------------------------------------------

||| What a tie states of one dimension: the size of another array's
||| dimension (`Extent`), exact, or a natural from elsewhere, an extent.
public export
data Stated = OfArray Val | OfNatural Val

||| The array, its dynamic dimensions stated equal to the sizes given
||| (`idr.tie_shape`), the others read from it; itself when nothing is
||| stated of a dynamic dimension. Of an array of records, every column is
||| tied, its leading dimensions to the same sizes.
export covering
tie : Index -> Loc -> Val -> List (Maybe Stated) -> E Val
tie ix l x stated = tieWith x !(traverse (traverse size) stated)
  where
    size : Stated -> E Value
    size (OfArray n) = coordinate ix l n
    size (OfNatural n) = extent ix l n
    covering
    tieWith : Val -> List (Maybe Value) -> E Val
    tieWith (MkVal _ t _ (Columns ps)) sizes = columnsVal t !(traverse (\p => tieWith p sizes) ps)
    tieWith v sizes = do
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
