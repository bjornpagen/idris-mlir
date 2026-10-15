## C20 Frontend recognition and request chains

Producer: U14. Every declaration below is in `compiler/src/IdrisMLIR/`
and is written by U14 alone. Authority: 0004 §2.5, §4 stage 1, D18,
D19, D29, D40, D43; 0012 feature 2 and D4; 0009 §4.10; 0003 §2, §3,
§4.1, §4.3, D2, D4, D13, D14, D25, D37, D39. Line numbers are the tree
at `a3e61f3a`.

### 1. Core types (`Types.idr`, module `IdrisMLIR.Types`)

`Types.idr` imports `IdrisMLIR.MLIR` today (for `Op`); `Dim` is C22's,
declared there once and used here:

```idris
-- C22, IdrisMLIR.MLIR:
public export
data Dim = Static Nat | Dynamic
```

`Ty` (today `Types.idr:98-113`) becomes:

```idris
||| How an array is held: a value of the array language, a tensor, or an
||| array a world orders, a memref.
public export
data ArrayKind = ValueArray | OrderedArray

mutual
  public export
  data Ty = IntT IntTy | CharT | DoubleT | StrT | BigT | NatT | WorldT
          | DataT DataId
          | FunT Binder Ty
          | LazyT Ty
          | ||| A value of the array language (`Array s a`, `LArray s a`): a
            ||| ranked tensor of its element, one dimension per axis of the
            ||| form of `s`, outermost first; an axis is `Static n` where the
            ||| shape's normal form at the instance is the literal `n`, and
            ||| `Dynamic` otherwise. An array of arrays is one tensor, the
            ||| element's dimensions after the shape's.
            TensorT (List Dim) Ty
          | ||| An array a world orders: `ArrayData a` and `Buffer` (one
            ||| dynamic dimension), an IORef's `Mut a` (none). Read and
            ||| written through the world.
            MemRefT (List Dim) Ty
          | ||| An array of either kind whose element is a record: one array
            ||| per field, in field order (0003 D44, §10 below).
            ColumnsT ArrayKind (List Dim) DataId

  public export
  record Binder where
    constructor MkBinder
    quantity : Quantity
    type : Ty
```

`Rank`, `dimensions` and `ArrayT` are deleted.

Invariants (the frontend makes no other value; emission may treat a
violation as `internal`):
- the element of a `TensorT` is never a `TensorT` or a `MemRefT`;
- the element of a `MemRefT` is never a `TensorT`; its dimensions are
  `[Dynamic]` or `[]`;
- every `TensorT` and `ColumnsT` reachable from a `FunT`'s binder or
  result, or from a `LazyT`'s value, through `FunT` and `LazyT`, has
  only `Dynamic` dimensions (one closure type for every extent);
- `Eq Ty` compares dimensions exactly;
- a `ColumnsT k ds r` names a record `r`: a data instance of one
  constructor with two fields or more that does not contain itself
  (neither registered while it was being registered nor while a field of
  it was), every field of which an array of kind `k` can hold as its
  element: for `ValueArray` no field is a `MemRefT` or an ordered
  `ColumnsT`; for `OrderedArray` no field is a `TensorT`, `MemRefT` or
  `ColumnsT`. The frontend decides it once, in `coreType`, for every
  array of either kind whose element is such a record; any other element
  is one array of the element (`TensorT ds (DataT r)`, `MemRefT ds (DataT
  r)`), so one Idris type has one Core type.

New exports:

```idris
||| The dimensions a type contributes to a tensor that holds it: a
||| tensor's own, a value array of records' own, none for anything else.
public export
tensorDims : Ty -> List Dim

||| A type as a closure's binder or result, or a suspension's value,
||| holds it: every tensor dimension in it made dynamic.
export
dynamicDims : Ty -> Ty

||| An operation of the array language on tensors (`Term.Tensor`).
public export
data TensorOp
  = ||| [x]: the extent of axis k of x, a natural.
    Extent Nat
  | ||| (x :: coords): the element of x at the coordinates (naturals, one
    ||| per leading axis), or the cell there when the result is a tensor.
    Extract
  | ||| (x :: v :: coords): x with v, an element or a cell, at the
    ||| coordinates.
    Insert
  | ||| [k, x]: the first k (a natural) along axis a of x.
    Take Nat
  | ||| [k, x]: all but the first k along axis a of x.
    Drop Nat
  | ||| [x, y]: x then y along axis a.
    Concat Nat
  | ||| (x :: extents): x's elements in row-major order at the result's
    ||| shape, its extents given outermost first (naturals); the result's
    ||| dimensions after them are the cell's.
    Reshape
  | ||| [lo, hi, v, x]: x along axis a with lo copies of the cell v
    ||| before and hi after.
    Pad Nat

||| How a reduction along an axis keeps its accumulators (`Term.Reduce`).
public export
data Reduction = FoldLast | ScanLast

||| The part a constructor plays that a pass needs and cannot read off its
||| shape: the list's nil and cons, which the string builders take apart.
public export
data Role = ListNil | ListCons

||| A promise a library type makes of its values, checked on every
||| program: its cells are rebuilt in place and held exclusive.
public export
data Promise = InPlace
```

Each has `Eq` and `Show` (`extent<k>`, `extract`, `insert`, `take<a>`,
`drop<a>`, `concat<a>`, `reshape`, `pad<a>`; `fold_last`,
`scan_last`; `list_nil`, `list_cons`; `in_place`).

`Prim` (`Types.idr:247-270`): `IndexBelow` is deleted; `ArrayLength Ty`
stays, a world-ordered array's length, with `primArgs (ArrayLength e) =
[MemRefT [Dynamic] e]`.

`tyText`: `TensorT ds a` prints `Tensor [<d0, d1] (a)` with `?` for a
dynamic axis; `MemRefT [] a` prints `Mut (a)`; `MemRefT [_] a` prints
`Array (a)`, as world-ordered arrays print today; `ColumnsT k ds r`
prints `Columns value [<d0] (r)` or `Columns ordered [<] (r)`.

The refusal rule is C04's generated enum: every importer of the
hand-written `IdrisMLIR.Rule` imports `IdrisMLIR.Syntax.Idr` instead.

### 2. Full Core (`Term.idr`, module `IdrisMLIR.Term`)

Deleted: `Region`, `RegionF`, `regionName` and their cases
(`Term.idr:124-130, 163, 217, 251, 276, 418-421, 458-460`).

Added to `Term n`, with the same cases in `TermF`, `rename`, `hmap`,
`para` and the printer:

```idris
    ||| An operation of the array language on its operands, giving a value
    ||| of `result`.
    Tensor : Loc -> TensorOp -> (result : Ty) -> List (Term n) -> Term n
    ||| A new array of `result` (a `TensorT`) of the extents given
    ||| (naturals, one per axis of the shape tabulated, outermost first),
    ||| each element or cell the body's value; the body binds the
    ||| coordinates, coordinate j (outermost first) being `Bound j`, a
    ||| natural.
    Tabulate : {k : Nat} -> Loc -> (result : Ty) -> Vect k (Term n) -> Term (Under k n) -> Term n
    ||| A reduction of `x` along its axis after the frame of `z`, from
    ||| `z`'s accumulators, left to right in index order; the body binds
    ||| the accumulator (`Bound 0`) and the element or cell (`Bound 1`).
    ||| `FoldLast` gives the last accumulators (`z`'s type), `ScanLast`
    ||| every one, along that axis.
    Reduce : Loc -> Reduction -> (acc, elem, result : Ty) -> (z, x : Term n) -> Term (Under 2 n) -> Term n
    ||| The array, its dynamic dimensions stated equal to the naturals
    ||| given: one entry per dimension of its type, outermost first,
    ||| `Nothing` where nothing is stated. Static dimensions always have
    ||| `Nothing`.
    Tie : Loc -> Term n -> List (Maybe (Term n)) -> Term n
    ||| A new array of `result` (a `TensorT`) of the extents given, made
    ||| in the world's order: the body binds the coordinates (`Bound 0` to
    ||| `Bound (k - 1)`, outermost first) and the world before it (`Bound
    ||| k`), and gives the `IORes` (instance `step`) of the element and the
    ||| world after it, once per index in row-major order, never when the
    ||| array is empty. Its value is the `IORes` (instance `done`) of the
    ||| array and the last world; `world` is the first.
    TabulateIO : {k : Nat} -> Loc -> (result : Ty) -> Vect k (Term n) -> (world : Term n)
              -> Term (Under (S k) n) -> (step, done : DataId) -> Term n
```

Renaming under binders: `Tabulate` by `liftRen {k}`, `Reduce`'s body by
`liftRen {k = 2}`, `TabulateIO`'s body by `liftRen {k = S k}`, `Tie`
renames its array and each `Just`.

Printer (the Core dump): `tensor.<op><result>(args)`,
`tabulate<result>(extents)/<k> => body`, `fold_last<acc, elem,
result>(z, x)/2 => body` (or `scan_last`), `tie(x; d0, _, d2)`,
`io.tabulate<result>(extents; w)/<k+1> => body`.

What each term means, for emission (U15):
- A term's `result`, `acc` and `elem` types are the normal forms at the
  instance. Axis `a` of `Take`, `Drop`, `Concat` and `Pad` is the last
  axis of the shape, counted from 0 (the cell's axes follow it). The
  number of coordinates of `Extract` and `Insert` is the number of
  leading axes addressed; the cell's rank is the result's (`Extract`) or
  `v`'s (`Insert`) `tensorDims`. `Reshape`'s source rank is `x`'s rank
  less the cell's, the cell's rank being the result's less the number of
  extents. `Reduce`'s frame rank is `z`'s rank less `acc`'s.
- Coordinates and extents are naturals (`NatT`) in Core. Their
  conversion to `index` (unguarded for a coordinate, guarded for an
  extent at allocation, 0003 D4) is emission's.
- A `Tabulate`, `TabulateIO` or the fill of `withArray` never has a cell
  (the result's dimensions after the tabulated axes, and the dimensions
  of each array field of a record element) with a `Dynamic` dimension:
  a tabulation is given the extents of its axes, and its cells' extents
  only by their types. The frontend refuses such a program with
  `unsupported (type)`: "an array of cells whose extents no type fixes:
  <type>". Emission may treat one as an internal error.
- The frontend writes no cast. Wherever a value meets a slot whose type
  differs from the value's only in which dimensions are static (a call's
  operand and its callee's parameter, a constructor's field, a function
  result, a match's join, a closure's parameter, capture or result, a
  `Tie`), emission writes `tensor.cast` to the slot's type (0003 D39 is
  the call's case).
- Quantity is the binder's: an `LArray` bound at quantity 1 is a
  `TensorT` in a binder of quantity `One`, held as `!idr.lin<tensor<…>>`
  by emission's `heldType` and entered and used by its `coerce`, as
  every linear value is.

`Con` (`Term.idr:310-318`) gains, after `loc`:

```idris
  ||| The part the registry says this constructor plays, if any.
  role : Maybe Role
```

`Data` (`Term.idr:331-338`) gains, after `repr`:

```idris
  ||| The promise the registry says the type's values keep, if any.
  promise : Maybe Promise
```

Emission writes both into the identified type's body (C01, C22).
`Repr`, `TFn`, `Source`, `Names`, `showBody` and `showSource` keep their
shapes. `TFn.loc` of the root and the location of every binder the
frontend makes for itself (the root's world, the exit's world) is
`Loc.noLoc`, whose origin is `Generated`.

`keyText` (`Term.idr:364-372`) is the symbol:

```idris
export
keyText : InstanceKey -> String
keyText k = printed ++ suffix k.print
  where
    printed : String
    printed = case k.arguments of
      [] => k.origin
      as => fastConcat [k.origin, "[", joinBy ", " as, "]"]
    suffix : KeyPrint -> String
    suffix Whole = ""
    suffix (Lossy h) = ";" ++ hex16 h
```

### 3. Identities (`Ids.idr`, module `IdrisMLIR.Ids`)

```idris
||| What a key's print keeps of the instance's identity: all of it, or not
||| all, with the low 64 bits of the identity's hash (C21).
public export
data KeyPrint = Whole | Lossy Bits64

public export
record InstanceKey where
  constructor MkInstanceKey
  origin : String
  arguments : List String
  print : KeyPrint
```

`FnId` and `DataId` keep their shapes; their `name` is the instance's
symbol, `keyText` of its key, interned once by `Translate/Keys.idr`. So
emission's symbol of a function is `f.name` and of a data instance
`d.name`, and needs no repeat counter. The root's is
`$idris-mlir.root`, key `MkInstanceKey "$idris-mlir.root" [] Whole`.
C21's hash functions live in this module too.

The print and its loss (`Translate/Keys.idr`, `renderKey`): as today's
`render` (`Keys.idr:264-306`), returning also whether the print dropped
part of the identity. Loss is reported for: an `Erased` of reason
`Impossible` or `Dotted`; a `Meta` with arguments; a reference to a `DN`;
a case or with block's name; a lambda or a let (binder type and
quantity unprinted); a binder printed through (`PVar`, `PLet`, `PVTy`);
a `DefImplicit` binder; an integer constant (`I`, `I8` to `I64`, `B8`
to `B64`, `BI`); a `TDelay`; an as-pattern. `Erased` of reason
`Placeholder` and every other construct lose nothing. The identity text
(`identityText : Name -> List (Maybe ClosedTerm) -> String`) is a
prefix-free structural encoding of the definition's full name and each
argument, by Idris's `eqTerm` classes: tagged constructors, strings
length-prefixed, variables by de Bruijn index, binders by kind,
quantity and `PiInfo`, `Erased` by reason, constants by constructor and
value, names by their raw structure (`Show @{Raw}`), no `FC`, no binder
name. A key with loss gets `Lossy (xxh3_128 (utf8 identityText)).low`.

### 4. The registry (`Registry/*.idr`, `Registry.idr`)

`Registry/Libraries.idr`: `Purpose` is `Trusted | Admitted |
ReportAtCaller`; the break-last column, its cells and its doc go;
`moduleOrigin (Installed "mlir-array") _ = Library InHouse`, beside
`mlir-linear`.

`Registry/Entry.idr`, `Hook` (today `Entry.idr:213-305`):
- deleted: `ArrayType Rank (Maybe Ty)`, `ArraySize`, `ArrayLoop IdrRegionPrim`;
- `PrimCall Prim`'s doc drops the index check;
- added:

```idris
  | ||| An external type that is an array a world orders, of the
    ||| dimensions given, of the element its type argument names
    ||| (`Nothing`) or of the one given (`Buffer`'s byte).
    ||| Handler: `Frontend.Translate.Types.coreType`.
    OrderedArrayType (List Dim) (Maybe Ty)
  | ||| A type of the array language that is a value, `Array s a` or
    ||| `LArray s a`: a tensor (`TensorT`). Opaque: no constructor of it
    ||| is matched or applied. Handler: `Frontend.Translate.Types.coreType`.
    ArrayValueType
  | ||| A function of the array language whose calls are the operation
    ||| its `ArrayPrim` names, in their sequential meaning; its body is
    ||| not translated. Handler: `Frontend.Translate.Terms.application`.
    Generating ArrayPrim
  | ||| A constructor that plays a role a pass needs (`Con.role`).
    ||| Handler: `Frontend.Translate.Types.dataInstance`.
    Plays Role
  | ||| A data type whose values keep a promise every program is checked
    ||| against (`Data.promise`). Handler:
    ||| `Frontend.Translate.Types.dataInstance`.
    Promises Promise
```

with `kind`: `OrderedArrayType`, `ArrayValueType`, `Generating`, `Plays`
are `Faster`; `Promises` is `Stricter`.

```idris
||| A function of the array language's generating set, or of `LArray`'s
||| operations, by what its calls are.
public export
data ArrayPrim
  = AShape | ATabulate | AIndex | AUpdate | AFoldLast | AScanLast
  | AReshape | ATake | ADrop | AConcat | APad
  | AWithArray | ARead | AWrite | AThaw | ALShape | AGrow | ATabulateIO
```

`Registry/Primitives.idr`: `ArrayData` is `OrderedArrayType [Dynamic]
Nothing`, `Mut` is `OrderedArrayType [] Nothing`, `Buffer` is
`OrderedArrayType [Dynamic] (Just byte)`; the two entries keyed by the
in-house linear array library's Scheme specs are deleted; every other
entry stays.

`Registry/Recognized.idr`: the index-space entries go; `recognized`
adds the entries below, with `shapeType = Head (Def (MkQName ["Prelude",
"Basics"] "SnocList")) [nat]`. The frontend asks the registry, which
compares:

```idris
-- Registry.idr
export
isShapeType : Shape -> Bool
isShapeType = conforms shapeType
```

The entries (key, expected shape, hook). `M0` binders are the
implicits, written `I` below; `arr` is `Head (Def Array.Core.Array)
[_, _]`, and `larr`, `ext`, `idx`, `cell`, `fin` likewise for
`Array.Core.LArray`, `Array.Core.Extents.Extents`,
`Array.Core.Index.Index`, `Array.Core.Cell.Cell` and `Data.Fin.Fin`;
every implicit's own type and every type argument is `Hole`, so
validation checks arity, quantities and heads, which the handlers depend
on. The names, signatures and implicit counts are C19's (§2.2, §2.3,
"each implicit is quantity 0").

| key | shape | hook |
| --- | --- | --- |
| `Array.Core.Array` | `(0 _ : shapeType) -> Type -> Type` | `ArrayValueType` |
| `Array.Core.LArray` | `(0 _ : shapeType) -> Type -> Type` | `ArrayValueType` |
| `Array.Core.shape` | `I I -> arr -> ext` | `Generating AShape` |
| `Array.Core.tabulate` | `I I -> ext -> (idx -> _) -> arr` | `Generating ATabulate` |
| `Array.Core.!!` | `I I -> arr -> idx -> _` | `Generating AIndex` |
| `Array.Core.update` | `I I -> arr -> idx -> _ -> arr` | `Generating AUpdate` |
| `Array.Core.foldLast` | `I I I I -> (_ -> _ -> _) -> arr -> arr -> arr` | `Generating AFoldLast` |
| `Array.Core.scanLast` | `I I I I -> (_ -> _ -> _) -> arr -> arr -> arr` | `Generating AScanLast` |
| `Array.Core.nest` | `I I I -> cell -> arr -> arr` | `IdentityOnLastArgument` |
| `Array.Core.merge` | `I I I -> ext -> arr -> arr` | `IdentityOnLastArgument` |
| `Array.Core.reshape` | `I I I -> ext -> (0 _ : _) -> arr -> arr` | `Generating AReshape` |
| `Array.Core.take` | `I I I -> Nat -> (0 _ : _) -> arr -> arr` | `Generating ATake` |
| `Array.Core.drop` | `I I I -> Nat -> (0 _ : _) -> arr -> arr` | `Generating ADrop` |
| `Array.Core.++` | `I I I I -> arr -> arr -> arr` | `Generating AConcat` |
| `Array.Core.pad` | `I I I -> Nat -> Nat -> _ -> arr -> arr` | `Generating APad` |
| `Array.Core.withArray` | `I I I -> ext -> _ -> ((1 _ : larr) -> _) -> _` | `Generating AWithArray` |
| `Array.Core.read` | `I I -> (1 _ : larr) -> idx -> _` | `Generating ARead` |
| `Array.Core.write` | `I I -> (1 _ : larr) -> idx -> _ -> larr` | `Generating AWrite` |
| `Array.Core.freeze` | `I I -> (1 _ : larr) -> _` | `IdentityOnLastArgument` |
| `Array.Core.thaw` | `I I I -> arr -> ((1 _ : larr) -> _) -> _` | `Generating AThaw` |
| `Array.Core.lshape` | `I I -> (1 _ : larr) -> _` | `Generating ALShape` |
| `Array.Core.grow` | `I I I -> Nat -> _ -> (1 _ : larr) -> larr` | `Generating AGrow` |
| `Array.Core.tabulateIO` | `I I -> ext -> (idx -> _) -> _` | `Generating ATabulateIO` |
| `Data.Fin.natToFinLT` | `Nat -> I -> I -> fin` | `IdentityOnLastArgument` |
| `Prelude.Basics.Nil` | `I -> List _` | `Plays ListNil` |
| `Prelude.Basics.::` | `I -> _ -> List _ -> List _` | `Plays ListCons` |
| `Linear.List.LList` | `Type -> Type` | `Promises InPlace` |
| `Linear.Nat.LNat` | `Type` | `Promises InPlace` |

`IdentityOnLastArgument` means the identity on the call's last runtime
argument, wherever it stands among the proofs and types
(`natToFinLT`'s precedes two erased ones; `nest`'s cell form and
`merge`'s extents before it are not read); C19's `checkIndex` costs one
comparison by it.

`Registry.idr`: the test hook that broke an entry is deleted;
`validate` takes no argument.

### 5. What the frontend makes of a generating call

The table is the frontend's; emission reads only the terms. Each
runtime argument is bound by one `Let` at its binder's quantity, left to
right, before use, so evaluation order is the call's and no argument is
duplicated. A call below its arity is eta-expanded first (§7). `rt` is
the call's result type at the instance. A rank is read from types,
never from the order of the implicits: `rank t = length (tensorDims t)`.
Extents (`Extents s`) and coordinates (`Index s`) are library data taken
apart and built by tag: tag 0 is the empty one (`Lin`), tag 1 the snoc
(`:<`) of the rest and a natural, the order C19 §2.1 declares them in. A
`Fin` coordinate is a natural (`Fin` is `Nat`-like). `Res`
(`Builtin.Res`) and `!*` (`Linear.Notation`) are ordinary data: `!* b`
has one constructor and one field, so its value is the field's.

| hook | runtime arguments | Core |
| --- | --- | --- |
| `AShape` | `[x]` | the `Extents` value of `Tensor (Extent j) NatT [x]` for each axis j of the shape, whose rank is `rank x - rank a`, `a` the call's one type argument |
| `ATabulate` | `[e, f]` | `e` taken apart into its extents; `Tabulate rt extents (App f index)`, `index` the `Index` value of the coordinates `Bound j`; the rank is `rank rt - rank b`, `b` the result type of `f` |
| `AIndex` | `[x, i]` | `i` taken apart; `Tensor Extract rt (x :: coords)` |
| `AUpdate`, `AWrite` | `[x, i, v]` | `i` taken apart; `Tensor Insert rt (x :: v :: coords)` |
| `AFoldLast`, `AScanLast` | `[g, z, x]` | `Reduce FoldLast` or `ScanLast`, `acc` and `elem` the two binder types of `g`, body `App (App g (Bound 0)) (Bound 1)` |
| `AReshape` | `[e, x]` | `e` taken apart; `Tensor Reshape rt (x :: extents)` |
| `ATake`, `ADrop` | `[k, x]` | `Tensor (Take a) rt [k, x]` or `Drop a`, `a = rank x - 1 - rank c`, `c` the call's one type argument |
| `AConcat` | `[x, y]` | `Tensor (Concat a) rt [x, y]`, `a` as for take |
| `APad` | `[lo, hi, v, x]` | `Tensor (Pad a) rt [lo, hi, v, x]`, `a = rank x - 1 - rank (type of v)` |
| `AWithArray` | `[e, v, k]` | `e` taken apart; `App k (Tabulate t extents v')`, `t` the binder type of `k`, `v'` the fill weakened past the coordinates |
| `ARead` | `[l, i]` | `i` taken apart; the result's one constructor applied to `Tensor Extract el (l :: coords)` and `l`, `el` the call's one type argument |
| `AThaw` | `[x, k]` | `App k x` |
| `ALShape` | `[l]` | the result's one constructor applied to the `Extents` value of `Tensor (Extent j) NatT [l]` and `l`; the rank is `rank l - rank a`, `a` the call's one type argument |
| `AGrow` | `[k, v, l]` | `Tensor (Pad a) rt [0, k, v, l]`, `a = rank l - 1 - rank (type of v)` |
| `ATabulateIO` | `[e, act]` | `e` taken apart; `Lam "world" w (TabulateIO t extents (Var w) (App (App act index) (Bound k)) step done)`, `t` the array type, `step` the `IORes` instance `act` gives, `done` the call's |

`nest`, `merge` and `freeze` are the identity on their array.
Matching or applying a constructor of `Array` or `LArray` is
`unsupported (hook)`: "the array type <name> is opaque".

### 6. Shapes, forms and ties (`Frontend/Translate/Shapes.idr`, new)

- A shape's spine is read from its normal form: `[<]` and `:<` of
  `SnocList` (the entries pin the shape type). No spine is
  `unsupported (polymorphism)`: "a shape whose rank no analysis fixes:
  <shape>".
- An extent is `Static n` when its normal form is a `Nat`-like chain of
  successors ending at zero or a non-negative integer literal, and
  `Dynamic` otherwise (erased does not mean constant).
- A shape's form is its spine with every extent `Erased Placeholder`.
- `PKind` (`Translate/State.idr:48-52`) gains `FormParam ClosedTerm`: an
  erased, non-type-like parameter whose type conforms to `shapeType`
  and which the rest of the callee's type mentions inside the shape of a
  value array; its value is the argument's form, and it keys the
  instance (`staticOf`). Any other erased parameter is `ErasedParam` as
  today.
- Entry ties: in each instance, for every runtime parameter of
  quantity many whose type is a value array (`TensorT`, or `ColumnsT
  ValueArray`, whose columns share its dimensions), each dynamic
  dimension whose
  extent in the definition's type is a size variable (a form
  parameter's extent, an erased `Nat`, or a runtime `Nat` parameter) is
  grouped by that variable. A runtime `Nat` parameter is its group's
  source; otherwise the first dimension met, in parameter then axis
  order, is the source and is not tied. The body is wrapped, in
  parameter order, in `Let "tied" Many (Tie p dims)` for each parameter
  with a tied dimension, the dims being `Var` of the runtime size or
  `Tensor (Extent j) NatT [source parameter]`.
- Result ties: a call whose callee's result type has a dynamic
  dimension whose extent is a size variable that one of the call's
  runtime arguments determines is `Tie (Call …) dims` after its
  arguments are bound.
- Static extents need no tie and get `Nothing`.

### 7. Hooks below their arity

Every hooked call applied to fewer arguments than its runtime
parameters goes through `finish` (`Translate/Terms.idr:658-676`), which
eta-expands it into one closure per missing runtime parameter whose body
is the saturated call; the identity hook is no exception any more (0002
D18). A missing type or implementation argument stays
`unsupported (static argument)`.

### 8. Request chains (`Frontend/Translate/Instances.idr`)

- `request` keeps its signature
  (`request : FC -> String -> Name -> List PKind -> Core FnId`).
- `Request` (`State.idr:84-90`) gains `key : InstanceKey`.
- The size of a static value: `size Nothing = 0`; for a term, 1 plus
  the sizes of its parts (an application's head and arguments, a
  binder's type, value and scope); an integer literal is 1 plus its
  magnitude, a string literal 1 plus its length; every other leaf is 1.
- A new instance of definition `d` (by `nameKey`) with static vector `v`
  is refused when an instance of `d` on its request chain (`TS.current`,
  then each `parent`) has vector `u` with `size v_i >= size u_i` at
  every position and `size v_i > size u_i` at one.
- The refusal, at the requesting call:

```
<owner>: unsupported (polymorphism): polymorphic recursion: <d> requests itself with its argument <x> larger, which its recursion builds deeper at each call (<keyText new> after <keyText earlier>), so that each instance would need another
```

  `<d>` is the definition's printed full name, `<x>` the name the
  definition's type gives the parameter at the first growing position.
- `checkComponent` computes the loop verdicts (`TS.loops`, the
  `terminating` fact) and refuses nothing.

### 9. Acceptance changes (for U18)

- `tests/reject/polymorphism-growing-shape`: still refused at line 19,
  the message still contains "which its recursion builds deeper at each
  call".
- `tests/reject/polymorphism-nested`: refused by the rule at the
  recursive call, line 8 (the header's `line 6` becomes `line 8`).
- A recursion that passes a changed type or implementation within a
  finite set now compiles; none is in the corpus (0012's table: "none
  for the bounded case").
- No program refused for more than 4,096 instances of one definition
  is known; none changes.
- The frontend has no option that breaks a registry entry: the
  registry tests give validation a refused input (D43).
- New refusals, of array programs only (no such program exists before
  this wave): a tabulation whose cells have an extent no type fixes
  (`unsupported (type)`, §2); and a value array whose shape no instance
  fixes (`unsupported (polymorphism)`, "a shape whose rank no analysis
  fixes"), which includes a data type that takes a whole shape as a
  parameter and holds an array of it, since a data instance is keyed by
  its type parameters and a shape is an index.

### 10. Arrays of records, as emission writes them (0003 D44)

The frontend holds an array of records as one Core value of type
`ColumnsT k ds r` and every term on it as on any array; emission (U15)
writes it one-to-N:

- **The values.** A `ColumnsT k ds r` is one MLIR value per field of
  `r`'s one constructor, in field order, each a column: for
  `ValueArray`, a field of type `TensorT es e` gives `tensor<(ds ++ es)
  x e>`, a field of type `ColumnsT ValueArray es r'` gives the columns of
  `ColumnsT ValueArray (ds ++ es) r'` (flattened depth first), and any
  other field type `t` gives `tensor<ds x t>`; for `OrderedArray`, every
  field type `t` gives `memref<ds x t>`. A value of quantity one is each
  column held at quantity one. A function parameter, a function result, a
  block or region argument, a constructor field, a capture and an
  operand of this type are its columns, in that order, wherever the type
  appears (a signature lists them in place of the one type).
- **Reads gather, writes scatter.** `Tensor Extract (DataT r) (x ::
  coords)` on columns is one `tensor.extract` per column at the
  coordinates, then the record built of them (`idr.con` of `r`'s
  constructor, fields at their quantities); `Tensor Insert` of a record
  `v` takes `v` apart (its fields) and inserts each field into its
  column. `Tensor (Extent k)` is the extent of the first column.
  `Take`, `Drop`, `Concat`, `Reshape` and `Pad` act on every column
  alike (`Pad`'s cell `v`, a record, taken apart, each field padding its
  column). `Tie` ties every column's dimension `k` to the same natural.
- **Loops.** `Tabulate` whose result is columns carries one destination
  per column through its loop and inserts each field of the body's
  record into its column; `Reduce` over columns `x` reads its element by
  gathering; `ScanLast` whose accumulator is a record writes it by
  scattering; `TabulateIO` likewise.
- **Arrays a world orders.** `Effect ArrayNew/ArrayGet/ArraySet [DataT
  r] …` on `ColumnsT OrderedArray`: a new array is one new memref per
  column, each filled with its field of the fill; a get is one load per
  column and the record built; a set takes the record apart and stores
  each field. Every access keeps its guard, checked once on the first
  column (one length).
- `Data.promise` and `Con.role` are unaffected: they are facts of `r`'s
  declaration, which emission still writes.

### 11. Other interfaces

- `Frontend/Translate/Errors.idr`: `reject : FC -> String -> Rule ->
  String -> Core a`, `Rule` from `IdrisMLIR.Syntax.Idr` (C04), the
  message `<owner>: unsupported (<phrase>): <what>`, `show rule` being
  C04's phrase.
- `Frontend/Program.idr`: `program : (mainFile : ModuleIdent) ->
  (timing : Maybe String) -> (corePath, mlirPath : String) -> Core (List
  Error)`; it writes the module through C22's entry point.
- `Frontend/Driver.idr`: the synopsis is `[--timing FILE] --core FILE -o
  FILE SOURCE`, with no other compile option.
- `compiler/idris-mlir.ipkg` lists, at integration: every module of
  `compiler/src/IdrisMLIR` this lane keeps; `IdrisMLIR.Frontend.Translate.Shapes`;
  not the deleted profiling module; not `IdrisMLIR.Rule` (C04 generates
  `Rule` into `IdrisMLIR.Syntax.Idr`); C22's `IdrisMLIR.MLIR.Bytecode`,
  `IdrisMLIR.Emit.Lifted`, `IdrisMLIR.Emit.Tensors`, and the generated
  `IdrisMLIR.Syntax.Tensor`, `IdrisMLIR.Syntax.SCF`,
  `IdrisMLIR.Dialect.Tensor`, `IdrisMLIR.Dialect.SCF`. A module a
  sibling adds is listed by U14 from that sibling's contract.

### Consumers

U15 (§1 to §3, §5, the ipkg), U13 (§4's entries against its
signatures), U18 (§8's message, §9, §4's validation), U08 (the promise,
which emission writes), U17 (the Core dump's new terms in fixtures that
read it).
