-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the arrays declare: the generating set and its yield, a step's
||| movements on buffers, mutable memory and its accesses, the read that
||| gives a value array back, the opening of a field's buffer as an array,
||| the copy that first writes a buffer allocated for it, the extent of an
||| array to be made and the tie of its dimensions;
||| the memory space of mutable memory; the two interfaces the generating
||| set and the update share; the two hand predicates their operands are
||| checked by; the skeleton rules on two accesses of one element of
||| mutable memory: a read and a write its update, a read of a write the
||| value written, a write overwritten unread gone; and what each function
||| of the array library that the compiler writes as array operations
||| means, as a composition of those operations over its arguments.
module IdrisMLIR.Spec.Arrays.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Arrays.Generating
import IdrisMLIR.Spec.Arrays.Memory

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The upstream ops arrays admit
------------------------------------------------------------------------------

-- A list names an upstream op the frontend writes, which its record gives
-- a builder with its guards; one code of ours makes or reads (a pass's
-- allocations, copies, accesses and loops below); or one whose class a
-- table of ours names (its laws, its range, its fold, a word op's). What
-- upstream's bufferization models make of a concat or a pad is none of
-- these: `memref.subview` of the buffer they fill (as of each slice),
-- `affine.apply` for a padded size and `linalg.map` for the padding. No
-- code of ours makes, models or reads one, and upstream's memref, affine
-- and linalg lowerings take each, so no list names them.

||| An upstream op whose record's name carries its dialect, its own alias.
admitNamed : Dialect -> Ident -> Legal -> Writer -> Admitted
admitNamed d r legal writer = MkAdmitted d r r legal writer [] [] Nothing UpstreamFold

||| An upstream op whose record's name does not carry its dialect: its
||| alias does.
admitAliased : Dialect -> Ident -> Ident -> Legal -> Writer -> Admitted
admitAliased d r alias legal writer = MkAdmitted d r alias legal writer [] [] Nothing UpstreamFold

||| The tensor ops the frontend writes on arrays as values, which passes
||| also write (columns, structured loops, bufferization's preparation):
||| until bufferization makes them buffers.
tensorAdmitted : List Admitted
tensorAdmitted = map (\r : Ident => admitNamed Tensor r (between Higher First) FrontendWrites)
  [ "Tensor_CastOp", "Tensor_DimOp", "Tensor_EmptyOp", "Tensor_ExtractOp"
  , "Tensor_ExtractSliceOp", "Tensor_FromElementsOp", "Tensor_InsertOp"
  , "Tensor_InsertSliceOp", "Tensor_ExpandShapeOp", "Tensor_CollapseShapeOp" ]

||| The joins the frontend writes on arrays of words: `++` as upstream's
||| `tensor.concat`, and `pad` and `grow` as its `tensor.pad`, with the
||| yield that ends the pad's region and gives the padding value, which
||| enters with the pad since the frontend builds that region. Until
||| bufferization: upstream's models of both, attached with the rest of the
||| tensor dialect's, make each a fresh buffer, the concat's filled by a
||| copy of each array into its place, the pad's by its region over the
||| whole buffer and then a copy of the array into its place.
tensorJoinsAdmitted : List Admitted
tensorJoinsAdmitted = map (\r : Ident => admitNamed Tensor r (between Higher First) FrontendWrites)
  [ "Tensor_ConcatOp", "Tensor_PadOp", "Tensor_YieldOp" ]

||| The crossings between a buffer and an array value, until
||| bufferization, which removes them: the buffer a constructor's field
||| takes, which the frontend writes; and the fresh array bufferization's
||| preparation makes. A buffer a cell holds is opened as an array by an op
||| of ours that takes the value holding it (`array.open`, and the take
||| before bufferization, `count.take_open`), never by upstream's
||| `to_tensor`.
bufferizationAdmitted : List Admitted
bufferizationAdmitted =
  [ admitNamed Bufferization "Bufferization_ToBufferOp" (between Higher First) FrontendWrites
  , admitNamed Bufferization "Bufferization_AllocTensorOp" (between First First) PassesOnly ]

||| A buffer's size, which the frontend reads, and the buffers bufferization
||| allocates, copies, reads and writes, until the lowering.
memrefAdmitted : List Admitted
memrefAdmitted =
  [ admitNamed MemRef "MemRef_DimOp" (between Higher Owned) FrontendWrites
  , admitNamed MemRef "MemRef_AllocOp" (between First Owned) PassesOnly
  , admitAliased MemRef "CopyOp" "MemRef_CopyOp" (between First Owned) PassesOnly
  , admitAliased MemRef "LoadOp" "MemRef_LoadOp" (between First Owned) PassesOnly
  , admitNamed MemRef "MemRef_StoreOp" (between First Owned) PassesOnly ]

||| The transpose the frontend writes, and the parallel ops structured loops
||| make of word ops, on tensors and then on buffers, until the lowering.
||| The yield ends the body of each: the transpose's body too, which the
||| frontend builds, so it enters with the transpose.
linalgAdmitted : List Admitted
linalgAdmitted =
  [ admitAliased Linalg "TransposeOp" "Linalg_TransposeOp" (between Higher Owned) FrontendWrites
  , admitAliased Linalg "GenericOp" "Linalg_GenericOp" (between First Owned) PassesOnly
  , admitNamed Linalg "Linalg_IndexOp" (between First Owned) PassesOnly
  , admitNamed Linalg "Linalg_YieldOp" (between Higher Owned) FrontendWrites ]

||| The loops arrays' passes make and read: `scf.for`, which structured
||| loops writes and the ordered loops after narrowing write again, until
||| the lowering; `scf.while` and its condition, which narrowing reads and
||| versions where the program's own loops stand once counted.
scfAdmitted : List Admitted
scfAdmitted =
  [ admitAliased SCF "ForOp" "SCF_ForOp" (between First Owned) PassesOnly
  , admitAliased SCF "WhileOp" "SCF_WhileOp" (between Owned Owned) PassesOnly
  , admitAliased SCF "ConditionOp" "SCF_ConditionOp" (between Owned Owned) PassesOnly ]

------------------------------------------------------------------------------
-- What the array library's functions mean
------------------------------------------------------------------------------

-- A function of the array library whose calls the compiler writes as array
-- operations, instead of compiling a body, means a composition of the
-- operations below over its runtime arguments, each operation upstream's op
-- admitted above, an op of this area, or the few ops it is made of. The
-- registry's row for the function names its meaning here, so the library's
-- names stay in the registry and no composition is written twice: a call
-- takes each argument apart once, where the call gives it, computes the
-- composition, and builds what the function's type gives. A function that
-- only retypes its array (the cells of an array of arrays are its trailing
-- axes) is the identity on it, no composition, and has no meaning here.

||| How a function a call gives is applied, which the operation that
||| applies it fixes.
public export
data AppliedAt
  = ||| To each position of a new array, giving what goes there.
    EachPosition
  | ||| To each position of a new array, giving an action of the world whose
    ||| result goes there: the actions run once each, in row-major order and
    ||| in the world's order, and none runs when the array is empty.
    EachPositionInWorld
  | ||| To the accumulator and the element at each step of a fold along the
    ||| last axis, giving the next accumulator.
    EachStep
  | ||| Once, to a fresh linear array, giving an unrestricted value.
    OnceToLinearArray

||| What a runtime argument of a function of the array library is, by what
||| a call takes apart of it, once, where it gives it.
public export
data Takes
  = ||| A value array, as it is.
    TakesArray
  | ||| A natural, as it is: a number of positions along an axis.
    TakesNatural
  | ||| A shape at run time: its naturals, one per axis, outermost first.
    TakesExtents
  | ||| A position in a shape: its coordinates, one per axis, each below its
    ||| extent by its type, so none is checked.
    TakesPosition
  | ||| An element, or a cell of the trailing axes, as it is.
    TakesElement
  | ||| A function, applied as the operation that takes it says.
    TakesFunction AppliedAt
  | ||| A linear array: its cell opened, the array it holds. It is used
    ||| once, so it is opened once, where the call gives it, and every
    ||| operation after reads the array.
    TakesLinearArray

||| What a composition computes, and what a function of the array library
||| gives.
public export
data Computed
  = ||| A value array: a ranked tensor of its shape's axes, then its
    ||| element's.
    AnArray
  | ||| A natural.
    ANatural
  | ||| A shape: one natural per axis, outermost first.
    SomeExtents
  | ||| A position: one coordinate per axis, outermost first.
    SomeCoordinates
  | ||| An element, or a cell of the trailing axes.
    AnElement
  | ||| A function, applied as said.
    AFunction AppliedAt
  | ||| A linear array: a cell holding an array.
    ALinearArray
  | ||| What a continuation returns, as it returns it.
    AnUnrestricted
  | ||| An action of the world whose result is what is said.
    InWorld Computed
  | ||| What is said, read off an array, and a linear array holding the
    ||| array given back as a new value, so that what writes it next comes
    ||| after the read by data.
    GivenBack Computed

||| What a runtime argument is once it is taken apart.
public export
takenAs : Takes -> Computed
takenAs TakesArray = AnArray
takenAs TakesNatural = ANatural
takenAs TakesExtents = SomeExtents
takenAs TakesPosition = SomeCoordinates
takenAs TakesElement = AnElement
takenAs (TakesFunction how) = AFunction how
takenAs TakesLinearArray = AnArray

-- A side of a padding, defined after the compositions, which it is made of
-- and which take it.
public export
data Side : Vect n Takes -> Type

||| A composition of the array operations over a call's runtime arguments,
||| `ts` saying what each is taken as, by what it computes: no operation is
||| given an operand of another kind. The shape's last axis is the last
||| axis of an array's shape, before its element's axes.
public export
data Composed : Vect n Takes -> Computed -> Type where
  ||| The call's runtime argument at a position, as it is taken apart.
  Nth : (j : Fin n) -> Composed ts (takenAs (index j ts))
  ||| The extents of an array's shape, one per axis of the shape and none of
  ||| its element's, outermost first: upstream's `tensor.dim` of each axis
  ||| its type leaves dynamic, the type's extent of every other.
  ExtentsOf : Composed ts AnArray -> Composed ts SomeExtents
  ||| One run of extents and then another: a frame's, then its cells'.
  ExtentsThen : Composed ts SomeExtents -> Composed ts SomeExtents -> Composed ts SomeExtents
  ||| The extents with the last replaced by the natural.
  WithLastExtent : Composed ts SomeExtents -> Composed ts ANatural -> Composed ts SomeExtents
  ||| The element at the coordinates, upstream's `tensor.extract`; or, where
  ||| the element is a cell with axes of its own, the cell there, a
  ||| `tensor.extract_slice` of unit size along the coordinates' axes,
  ||| rank-reduced.
  ElementAt : Composed ts AnArray -> Composed ts SomeCoordinates -> Composed ts AnElement
  ||| The array with the element at the coordinates replaced by the one
  ||| given, upstream's `tensor.insert`; or, where the element is a cell, the
  ||| cell there, a `tensor.insert_slice`.
  Replaced : Composed ts AnArray -> Composed ts SomeCoordinates -> Composed ts AnElement ->
             Composed ts AnArray
  ||| As many of the first positions of the shape's last axis as the
  ||| natural: upstream's `tensor.extract_slice` from offset 0.
  FirstOf : Composed ts ANatural -> Composed ts AnArray -> Composed ts AnArray
  ||| The positions of the shape's last axis after the first ones, as many
  ||| as the natural: a `tensor.extract_slice` from that offset, its length
  ||| the axis's extent less the natural (`arith.subi`).
  AfterFirst : Composed ts ANatural -> Composed ts AnArray -> Composed ts AnArray
  ||| The two arrays one after the other along the shape's last axis. Of
  ||| words, upstream's `tensor.concat` along that axis, its dimension the
  ||| shape's rank less one, which the type fixes; the type makes every
  ||| other axis the same in both, as the op asks. Of elements that hold
  ||| references, the array is an `idr.array.tabulate` of a fresh
  ||| destination that reads the one array or the other as the coordinate
  ||| along the axis is below the first's extent or not (`arith.cmpi`,
  ||| `scf.if`): the one op that makes it writes every slot and reads none,
  ||| so each element's reference is placed once, where counting places it.
  Concatenated : Composed ts AnArray -> Composed ts AnArray -> Composed ts AnArray
  ||| The array between copies of the element along the shape's last axis,
  ||| as many before it and after it as each side says, every other axis
  ||| the array's. Of words, upstream's `tensor.pad`, that axis padded low
  ||| by the one side and high by the other, a flush side by a static zero,
  ||| and every other axis by none; its region yields the element, or,
  ||| where the element is a cell with axes of its own, the cell's element
  ||| at the region's coordinates along those axes, which no side pads. Of
  ||| elements that hold references, `byCopies`.
  Padded : (before, after : Side ts) -> Composed ts AnElement -> Composed ts AnArray ->
           Composed ts AnArray
  ||| The shape's last two axes swapped. Of words, upstream's
  ||| `linalg.transpose` into a `tensor.empty`, its permutation stated once;
  ||| of elements that hold references, an `idr.array.tabulate` that reads
  ||| at the swapped coordinates, since no linalg body holds a reference
  ||| while counting runs.
  Transposed : Composed ts AnArray -> Composed ts AnArray
  ||| The same elements in the same row-major order at the extents given,
  ||| then the axes of the result's element as they were: upstream's
  ||| `tensor.collapse_shape` of every axis before those into one, then
  ||| `tensor.expand_shape` to the extents, with a `tensor.cast` where two
  ||| types differ only in what they leave dynamic.
  Reshaped : Composed ts SomeExtents -> Composed ts AnArray -> Composed ts AnArray
  ||| A new array of the extents, what goes at each position the function at
  ||| that position: `idr.array.tabulate` of a `tensor.empty`.
  Tabulated : Composed ts SomeExtents -> Composed ts (AFunction EachPosition) -> Composed ts AnArray
  ||| A new array of the extents, each cell a copy of the element, the
  ||| cell's extents read off it: `idr.array.tabulate` of a `tensor.empty`,
  ||| every slot written once, with a reference of its own.
  Copies : Composed ts SomeExtents -> Composed ts AnElement -> Composed ts AnArray
  ||| For each position of the first array's frame, the left fold along the
  ||| second's last axis from the accumulator the first holds there:
  ||| `idr.array.fold_last`, the first array its destination.
  FoldedLast : Composed ts (AFunction EachStep) -> Composed ts AnArray -> Composed ts AnArray ->
               Composed ts AnArray
  ||| The fold with every accumulator kept: `idr.array.scan_last` into a
  ||| `tensor.empty`.
  ScannedLast : Composed ts (AFunction EachStep) -> Composed ts AnArray -> Composed ts AnArray ->
                Composed ts AnArray
  ||| A new array of the extents, what goes at each position the result of
  ||| the action at that position: `idr.array.tabulate` of a `tensor.empty`
  ||| whose region runs the action, so the region states the actions' order
  ||| and the op keeps it.
  TabulatedInWorld : Composed ts SomeExtents -> Composed ts (AFunction EachPositionInWorld) ->
                     Composed ts (InWorld AnArray)
  ||| The element at the coordinates, and the array given back:
  ||| `idr.array.read`.
  ReadGivingBack : Composed ts AnArray -> Composed ts SomeCoordinates -> Composed ts (GivenBack AnElement)
  ||| The extents of the array's shape, each read giving the array back:
  ||| `idr.array.extent` of each axis.
  ExtentsGivingBack : Composed ts AnArray -> Composed ts (GivenBack SomeExtents)
  ||| A linear array holding the array: its cell, built around it, which
  ||| no op of arrays makes.
  Held : Composed ts AnArray -> Composed ts ALinearArray
  ||| The continuation given the linear array.
  Continued : Composed ts (AFunction OnceToLinearArray) -> Composed ts ALinearArray ->
              Composed ts AnUnrestricted

||| One side of an array along the shape's last axis, as a padding leaves
||| it: flush with the array, which is known when the composition is
||| written; or as many copies of the element as a natural says, which may
||| be none at run time.
public export
data Side : Vect n Takes -> Type where
  ||| No copies on this side: upstream's static padding of zero, and no
  ||| array of copies joined.
  Flush : Side ts
  ||| As many copies as the natural.
  SideOf : Composed ts ANatural -> Side ts

||| As many copies of the element along the shape's last axis as the
||| natural, the other axes the array's: what is joined to an array to pad
||| or grow it where its elements hold references, so that every slot of
||| the result is written once.
public export
copiesAlongLast : (count : Composed ts ANatural) -> (element : Composed ts AnElement) ->
                  (like : Composed ts AnArray) -> Composed ts AnArray
copiesAlongLast count element like = Copies (WithLastExtent (ExtentsOf like) count) element

||| The copies a side puts beside an array where its elements hold
||| references: none where the side is flush, else one array of as many
||| copies as it says.
public export
copiesBeside : Side ts -> (element : Composed ts AnElement) -> (like : Composed ts AnArray) ->
               List (Composed ts AnArray)
copiesBeside Flush _ _ = []
copiesBeside (SideOf count) element like = [copiesAlongLast count element like]

||| The padding of an array whose elements hold references: the copies
||| before it, the array and the copies after it, joined left to right,
||| each copy its own, so that tabulations alone write every slot of the
||| result once.
public export
byCopies : (before, after : Side ts) -> (element : Composed ts AnElement) ->
           (array : Composed ts AnArray) -> Composed ts AnArray
byCopies before after element array =
  foldl1 Concatenated
    (lappend (copiesBeside before element array) (array ::: copiesBeside after element array))

||| A function of the array library by what it means: what each of its
||| runtime arguments is taken as, in the order its type takes them, and
||| the composition its calls are. Its arity is how many runtime arguments
||| its definition's type must give.
public export
record ArrayMeaning where
  constructor MkArrayMeaning
  {arity : Nat}
  takes : Vect arity Takes
  {gives : Computed}
  composition : Composed takes gives

||| The extents of an array's shape. Upstream's `tensor.dim` covers it, one
||| per axis.
public export
extentsOfArray : ArrayMeaning
extentsOfArray = MkArrayMeaning [TakesArray] (ExtentsOf (Nth 0))

||| A new array of the extents, the function at each position.
||| `idr.array.tabulate` covers it.
public export
tabulation : ArrayMeaning
tabulation = MkArrayMeaning [TakesExtents, TakesFunction EachPosition] (Tabulated (Nth 0) (Nth 1))

||| The element or cell of an array at a position. Upstream's
||| `tensor.extract` covers it, and `tensor.extract_slice` for a cell.
public export
elementAtPosition : ArrayMeaning
elementAtPosition = MkArrayMeaning [TakesArray, TakesPosition] (ElementAt (Nth 0) (Nth 1))

||| A new array equal to the array but the element given at the position.
||| Upstream's `tensor.insert` covers it, and `tensor.insert_slice` for a
||| cell.
public export
replacedAtPosition : ArrayMeaning
replacedAtPosition =
  MkArrayMeaning [TakesArray, TakesPosition, TakesElement] (Replaced (Nth 0) (Nth 1) (Nth 2))

||| For each position of the frame, the left fold along the last axis.
||| `idr.array.fold_last` covers it.
public export
foldAlongLast : ArrayMeaning
foldAlongLast =
  MkArrayMeaning [TakesFunction EachStep, TakesArray, TakesArray] (FoldedLast (Nth 0) (Nth 1) (Nth 2))

||| For each position of the frame, every accumulator of the left fold
||| along the last axis. `idr.array.scan_last` covers it.
public export
scanAlongLast : ArrayMeaning
scanAlongLast =
  MkArrayMeaning [TakesFunction EachStep, TakesArray, TakesArray] (ScannedLast (Nth 0) (Nth 1) (Nth 2))

||| The same elements at other extents of the same count. No one op covers
||| it: upstream's `tensor.collapse_shape`, then `tensor.expand_shape`.
public export
reshaping : ArrayMeaning
reshaping = MkArrayMeaning [TakesExtents, TakesArray] (Reshaped (Nth 0) (Nth 1))

||| An array of cells put back together as one array, at the frame's
||| extents and then the cells' extents given, not read off a cell: an
||| empty frame has no cell to read them from, yet the array still has its
||| shape. No one op covers it: the reshaping to the frame's `tensor.dim`
||| and then the given extents.
public export
merging : ArrayMeaning
merging =
  MkArrayMeaning [TakesExtents, TakesArray] (Reshaped (ExtentsThen (ExtentsOf (Nth 1)) (Nth 0)) (Nth 1))

||| The shape's last two axes swapped. Upstream's `linalg.transpose` covers
||| it where the elements are words, and `idr.array.tabulate` where they
||| hold references.
public export
transposition : ArrayMeaning
transposition = MkArrayMeaning [TakesArray] (Transposed (Nth 0))

||| The first positions of the last axis. Upstream's `tensor.extract_slice`
||| covers it.
public export
firstPositions : ArrayMeaning
firstPositions = MkArrayMeaning [TakesNatural, TakesArray] (FirstOf (Nth 0) (Nth 1))

||| The positions of the last axis after the first ones. Upstream's
||| `tensor.extract_slice` covers it, its length an `arith.subi`.
public export
positionsAfterFirst : ArrayMeaning
positionsAfterFirst = MkArrayMeaning [TakesNatural, TakesArray] (AfterFirst (Nth 0) (Nth 1))

||| Two arrays one after the other along the last axis. Upstream's
||| `tensor.concat` covers it where the elements are words, and
||| `idr.array.tabulate` where they hold references.
public export
concatenation : ArrayMeaning
concatenation = MkArrayMeaning [TakesArray, TakesArray] (Concatenated (Nth 0) (Nth 1))

||| Copies of an element before and after an array along its last axis, as
||| many as each natural says. Upstream's `tensor.pad` covers it where the
||| elements are words; where they hold references, the array between two
||| arrays of copies, each copy its own.
public export
padding : ArrayMeaning
padding =
  MkArrayMeaning [TakesNatural, TakesNatural, TakesElement, TakesArray]
    (Padded (SideOf (Nth 0)) (SideOf (Nth 1)) (Nth 2) (Nth 3))

||| A fresh linear array of the extents, each element a copy of the one
||| given, given to the continuation. `idr.array.tabulate` covers the array.
public export
freshLinearArray : ArrayMeaning
freshLinearArray =
  MkArrayMeaning [TakesExtents, TakesElement, TakesFunction OnceToLinearArray]
    (Continued (Nth 2) (Held (Copies (Nth 0) (Nth 1))))

||| The element of a linear array at a position, and the linear array
||| given back. `idr.array.read` covers it.
public export
linearRead : ArrayMeaning
linearRead = MkArrayMeaning [TakesLinearArray, TakesPosition] (ReadGivingBack (Nth 0) (Nth 1))

||| A linear array with the element given at the position. Upstream's
||| `tensor.insert` covers it, and `tensor.insert_slice` for a cell, which
||| bufferization writes in place, since nothing reads the old array.
public export
linearWrite : ArrayMeaning
linearWrite =
  MkArrayMeaning [TakesLinearArray, TakesPosition, TakesElement] (Held (Replaced (Nth 0) (Nth 1) (Nth 2)))

||| A fresh linear array with an array's elements, given to the
||| continuation; the array is unchanged. No op: the continuation is given
||| the array itself in a linear array, and whether writing it needs a copy
||| first is bufferization's to decide, which sees what reads the array
||| after.
public export
thawing : ArrayMeaning
thawing = MkArrayMeaning [TakesArray, TakesFunction OnceToLinearArray] (Continued (Nth 1) (Held (Nth 0)))

||| The extents of a linear array, and the linear array given back.
||| `idr.array.extent` covers it, one per axis.
public export
linearExtents : ArrayMeaning
linearExtents = MkArrayMeaning [TakesLinearArray] (ExtentsGivingBack (Nth 0))

||| A fresh linear array longer on its last axis by the natural, the old
||| elements at their positions and a copy of the element given in each new
||| slot. Upstream's `tensor.pad` covers it where the elements are words,
||| flush before the array, its bufferization allocating the fresh array;
||| where they hold references, the array then an array of copies.
public export
growth : ArrayMeaning
growth =
  MkArrayMeaning [TakesNatural, TakesElement, TakesLinearArray]
    (Held (Padded Flush (SideOf (Nth 0)) (Nth 1) (Nth 2)))

||| A new array of the extents, the result of the action at each position,
||| the actions run in the world's order. `idr.array.tabulate` covers it,
||| its region the action.
public export
tabulationInWorld : ArrayMeaning
tabulationInWorld =
  MkArrayMeaning [TakesExtents, TakesFunction EachPositionInWorld] (TabulatedInWorld (Nth 0) (Nth 1))

public export
declarations : Declarations
declarations = MkDeclarations
  { ops = generatingOps ++ memoryOps
  , types = []
  , attributes = [SomeAttr mutableAttr]
  , enums = []
  , interfaces = generatingInterfacesDeclared
  , traits = []
  , directives = []
  , predicates = [valueBuffer, mutableArray]
  , resources = []
  , helpers = []
  , admitted = tensorAdmitted ++ tensorJoinsAdmitted ++ bufferizationAdmitted ++ memrefAdmitted
                 ++ linalgAdmitted ++ scfAdmitted
  , rewrites = []
  , skeleton = memorySkeleton
  , headers = []
  }
