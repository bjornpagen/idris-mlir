# Representations first: the refactor, memory, and arrays

Research note. Nothing here was built or run. It reads the compiler at
`802cdbe` and the sources in section 3, and it decides. Where a question is
the user's to answer, section 10 says so. Everything else is a decision.

Sources are marked in three ways:

- **source**: the implementation was read, at the commit given in section 3;
- **local**: the paper is stored under `docs/research/papers/`;
- **literature**: cited from the paper, not re-read for this note.

## 1. Where we are, and where it stops

The compiler has one representation strategy. `Simplify` is a two-level
evaluator (Kovács, *local* `kovacs-2022-staged`):

- every value is either a runtime scalar atom or a static value whose
  *shape* is known at compile time;
- functions are specialized per shape;
- data with a known shape is flattened into scalars (`LOW-DATA-1`).

That is why the benchmarks beat MLton: nothing is left to box, allocate,
tag-test or call indirectly.

It stops at one case: **a value whose shape is decided at runtime has no
representation.** Every rejection we hit is that case:

| Program | Why the shape is dynamic | Today |
| --- | --- | --- |
| `line <- getLine` | the bytes come from input | no primitive |
| `words line`, `unpack s`, `filter p xs` | a list's length depends on runtime data | `PROF-DATA-3` |
| `if b then (+ 1) else (* 2)` stored in data | which closure it is depends on runtime data | `PROF-HEAP-1` |
| a string built in a loop | its length depends on runtime data | `PROF-HEAP-3` |
| an array of runtime length | its length depends on runtime data | no primitive |
| n-body over `Vect 3 Double` | the shape is fixed, but it crosses a runtime join (the loop's result) | `PROF-DATA-3` |

The last row is different: the shape *is* static, and only a way to carry a
static value through runtime control flow is missing. The other rows need
memory.

The code that decides all this is a stack of local rules (section 2). This
note replaces it with **five data structures**. The algorithms fall out of
them.

## 2. The code today

`Simplify` (953 lines), `Simplify/Gen` (306) and `Simplify/Value` (357)
make one decision at every call: unfold, specialize, defer, or evaluate to
a constant. Each rule below was added to fix one program:

- **Three recursion bounds** in `unfoldOnce`:
  - 1 by default;
  - 64 for string join points and static `IORes` results;
  - 10000 for `Integer` results, recursive-data results, and known
    recursive constructors among the arguments.
- **A separate fuel of 20000** for compile-time evaluation (`ELIM-G-16`).
- **Four forcing helpers**, each with its own cap: `known`, `knownData`,
  `force` (1000) and `once` (64).
- **Two literal specializations**: `ELIM-G-17` (retry with literal keys) and
  `ELIM-G-18` (call patterns, at most 4 per function).
- **Growth backstops**: `PROF-HEAP-4`'s embedding check, at most 256
  specializations per function, and a key size of at most 4096.
- **Predicates on result types** (`chooses`, `staticRun`, `value`,
  `== BigT`) and on arguments (`recursiveArg`, `interesting`, `joinIn`).
- **Matcher special cases**:
  - two extra `matchCon` paths for deferred calls;
  - one for "one constructor whose alternative returns a static value";
  - string join points (`SCase`), a form only strings get.
- **Three predicates** in `Translate` for "is this argument compile-time":
  `isAuto`, the `dictionary` flag, `interfaceType`.
- **Hand-written traversals** in `Value`: about 150 lines of `rank`, `cmp`,
  `couple`, `pairs`, `children` and `size`, plus a separate `SStr` type.
- **A C++ pass**, `TailLoops.cc`, that rebuilds loops out of self tail calls
  that `Simplify` had just produced from Idris recursion.

Every one of these answers one of four questions, case by case:

1. Must this call run now?
2. Will running it terminate?
3. What does a static value become when it meets runtime control flow?
4. How is a value laid out, and when is its memory free?

## 3. What the sources do

Read for this note:

- **Lean 4** at `e21c2cf`: `src/Lean/Compiler/LCNF`, `IR`,
  `include/lean/lean.h`, and `Init/Data/{Array,ByteArray}`.
- **Futhark** at `22ab4b5`: `IR/Mem`, `IR/Mem/LMAD`, `IR/Syntax/Core`,
  `Internalise`, `Optimise/DoubleBuffer`, `Optimise/ArrayShortCircuiting`,
  and the C backend.
- **Koka** at `a0e403d`: file list only (`Core/CTail`, `Core/CheckFBIP`,
  `Backend/C/ParcReuse`). Content is from the literature.
- **MLton** at `aa2fd1a`: the headers of `deep-flatten`, `useless`, and
  `packed-representation`.
- **Kovács**, `AndrasKovacs/staged` at `9c4e201`: the ICFP 2024 paper
  source.
- **Idris 2**, pinned `third_party/Idris2`: `TTImp/ProcessData.idr`,
  `Core/CompileExpr.idr`, `Compiler/Opts/Constructor.idr`, `libs/base`,
  `libs/contrib` and `libs/linear`.

### Lean 4 (source)

- **One IR for every phase.** LCNF's `Code (pu : Purity)` covers the whole
  pipeline from pure code to reference counts. Phase-specific constructors
  carry an erased proof: `inc … (h : pu = .impure)`, `proj … (h : pu = .pure)`.
  One type, one traversal library, and ill-phased code cannot be built.
- **Join points are syntax.** `Code` has `jp` (declare) and `jmp` (jump),
  and `cases` is a terminator. `findJoinPoints`, `reduceJpArity` and
  `extendJoinPointContext` work on them directly.
- **Specialization is decided per parameter, once.** `SpecParamInfo` is
  `fixedInst | fixedHO | fixedNeutral | user | other`. It is computed from
  each parameter's type and from a *fixed-parameter* analysis: is the
  parameter passed unchanged in recursive calls (`FixedParams.lean`, an
  abstract interpretation with values `top | erased | val i`)?
  Specializing only on fixed parameters terminates by construction. Only
  `user` parameters can loop, and Lean stops those with a stack-depth error.
- **Result shapes use a lattice with type-recursion widening.**
  `ElimDeadBranches` has the domain `bot | top | ctor i vs | choice vs`.
  `truncate` widens to `top` when a constructor of an inductive type
  appears inside that same type, or when depth reaches 8.
- **Small results travel in registers.** `IRType` has `struct` and `union`
  "to return small values (e.g., `Option`, `Prod`, `Except`) on the stack".
  They are used exactly once per path.
- **Representation is computed once per type** (`ToImpureType.lean`):
  - all-nullary types become `uint8/16/32`;
  - types whose constructors all have fields become `object`;
  - mixed types become `tobject`, a tagged pointer or an object;
  - trivial structures become their field;
  - `UInt*`, `Float` and `USize` are built in.
- **Arrays are copy-on-write with reference counts.**
  - `lean_array_uset` calls `lean_ensure_exclusive_array`, which copies
    unless the count is 1.
  - `Array.set` and `ByteArray.set` take a proof `i < a.size`, so there is
    no bounds check. The exclusivity check remains.
  - `Array α` boxes its elements, which is why `ByteArray` and `FloatArray`
    exist separately.
- **The silent copy is a known problem.** Lean recently added
  `Array.markLinear` and `ByteArray.markLinear`: a header bit
  (`LEAN_LINEAR_MARK_MASK`) under which a non-linear use panics instead of
  copying, if `LEAN_ABORT_ON_NONLINEAR` is set. It is a runtime debugging
  aid for exactly the performance cliff that static uniqueness rules out.

### Futhark (source, and `henriksen-2017-futhark` local)

- **Uniqueness, not linearity.**
  - `Diet = Observe | Consume` is a monoid under `max`.
  - In-place update is `Update Safety VName Slice SubExp`.
  - Aliases are tracked (`IR/Aliases.hs`), and consuming a value forbids
    later uses of it and of its aliases.
- **Every array carries its memory.**
  - `MemInfo` says what a binding is: a primitive, a memory block, or an
    array. An array is `MemArray … (ArrayIn mem lmad)`: a block plus an
    index function.
  - Returns are either `ReturnsInBlock mem lmad` (in a block the caller
    already has) or `ReturnsNewBlock` (a fresh block).
  - The memory plan is part of the IR, not a side table.
- **Layout is an index function.** An `LMAD` is an offset plus a
  stride and shape per dimension. Slices, transposes and reshapes change
  the LMAD, not the data. This is exactly MLIR's strided `memref` layout.
- **Allocations are hoisted and double-buffered.**
  - The simplifier hoists an allocation out of a loop only if its block is
    dead at the end of the loop.
  - `DoubleBuffer` rewrites loops that allocate a fresh block every
    iteration into pointer swapping between two blocks.
  - Array short-circuiting builds results directly in their destination.
- **Blocks are reference counted.** The C backend's
  `struct memblock { int *references; … }` with `memblock_unref` is how it
  frees arrays whose lifetime is not static.
- **Representation is type-directed flattening.**
  - Records flatten into their components.
  - An array of records is a record of arrays: `internaliseTypeM` maps the
    array constructor over the element's leaves (struct of arrays).
  - Sums are a tag plus payload slots, and `internaliseConstructors` reuses
    a slot of the same primitive type across constructors. This is
    `LOW-DATA-1`'s slot sharing, found independently.
- **Defunctionalization's `StaticVal` is our `SVal`.** It is
  `Dynamic | LambdaSV | RecordSV | SumSV | DynamicFun | …`. Futhark's type
  rules forbid functions in arrays, in branch results and in loop
  parameters, so every function's static value is known (Hovgaard,
  Henriksen and Elsman, *literature*). We reach the same point by
  specialization, and reject where Futhark's type checker would.

### Kovács, closure-free two-level type theory (source, ICFP 2024)

- The object language splits types into **value types** (`VTy`: algebraic
  data whose fields are value types) and **computation types** (`CTy`:
  functions from value types). Functions "cannot be passed as arguments
  or stored in data constructors". That is what makes object programs run
  without closures.
- **Joining control flow.** When a branching action is followed by more
  code, inlining the continuation into each branch duplicates code, and
  let-binding the branching action materializes a runtime `Just` or
  `Nothing` plus a case. The fix is **one join point per summand**, with
  the constructor fused away. It works whenever the result is "isomorphic
  to a meta-level finite sum of value types", developed as sums of
  products: `USOP = List (List VTy)`.

That is the whole answer to question 3. A static value crossing runtime
control flow is a finite sum of products of runtime atoms, and it crosses
as one join point per summand. CPR is the one-summand case; case-of-case
is the inlined case.

### Koka (literature, source file names)

- **Perceus** (Reinking et al., PLDI 2021): precise reference counting with
  reuse of cells that die as a same-sized constructor is built.
- **FP²** (Lorenzen, Leijen and Swierstra, ICFP 2023): `fip` functions,
  checked in `Core/CheckFBIP.hs`, run in constant space by reusing their
  unique inputs.
- **Tail recursion modulo context** (Leijen and Lorenzen, POPL 2023,
  `Core/CTail.hs`): `map` and `filter` become loops that build their result
  forward through a hole.
- All of it assumes reference counts to find uniqueness at runtime.

### MLton (source headers)

- `DeepFlatten` and `RefFlatten` flatten tuples into the objects and
  arrays that hold them.
- `Useless` removes components nobody reads.
- `PackedRepresentation` packs tags and small fields into words.
- The whole program is monomorphic, and representation is chosen per type.

### Idris 2 itself (source)

- **Idris already classifies every data type's shape.** `calcConInfo` in
  `TTImp/ProcessData.idr` flags constructors as `NIL/CONS`,
  `NOTHING/JUST`, `ENUM n`, `RECORD`, `UNIT` or `ZERO/SUCC`. It counts
  relevant arguments only, so `Fin` is flagged `ZERO/SUCC` exactly like
  `Nat`. The flags are in the definition context we already read.
- `Compiler/Opts/Constructor.idr` uses `ZERO/SUCC` to replace nat-like
  data with `Integer` arithmetic (the "Nat hack").
- **Arrays**:
  - `Data.IOArray.Prims` declares three backend primitives:
    `%extern prim__newArray : forall a . Int -> a -> PrimIO (ArrayData a)`,
    `prim__arrayGet` and `prim__arraySet`. They are unchecked:
    "behaviour is undefined otherwise".
  - `Data.IOArray` wraps them with bounds checks. It stores
    `ArrayData (Maybe elem)`.
  - `contrib`'s `Data.Linear.Array` is a linear interface over `IOArray`,
    through `unsafePerformIO`. `newArray size k` returns whatever `k`
    returns, unrestricted, so linearity does not give uniqueness there
    (Marshall, Vollmer and Orchard, *local*).
- **Strings**: the primitives `StrLength`, `StrHead`, `StrTail`,
  `StrIndex`, `StrCons`, `StrAppend`, `StrReverse` and `StrSubstr`, plus
  `fastPack`, `fastUnpack`, `fastConcat`, and `getLine = primIO prim__getStr`.

### What we take, and what we don't

| From | We take | We don't |
| --- | --- | --- |
| Lean | one phase-indexed IR; join points as syntax; per-parameter specialization info with fixedness; lattice with type-recursion widening; `struct`/`union` returns; representation computed once per type | reference counts, `isShared`, reset/reuse, boxing of polymorphic elements |
| Futhark | memory as part of the IR (returns in a given block or a new one); double buffering; struct-of-arrays; slot sharing; `StaticVal` restrictions as our rejections | source-level uniqueness types (not Idris); refcounted blocks |
| Kovács | value/computation split (no runtime closures); SOP join points | a separate staging language (Idris quantities and our shapes decide stages) |
| Koka | TRMC for list-building loops; reuse of dead cells | reference counts |
| MLton | whole-program representation choice; useless-field removal | the heap and the GC |
| Idris | `ConInfo` flags; the array and string primitives; `base`/`contrib`/`linear` unchanged | `Integer` for nat-like data |

The common thread: **every system that is fast chooses representation from
types, once, and keeps memory decisions in the IR.** The systems that need
a runtime (Lean, Koka, Futhark's blocks) need it only for lifetimes they
cannot see statically. We see the whole program, and we choose to reject
what we cannot see.

## 4. The five data structures

| # | Structure | Answers | Replaces |
| --- | --- | --- | --- |
| 1 | `SValF r a`, the static value functor, with `zipMatch` | equality, order, embedding, generalization, joins | `Value.idr`'s hand-written traversals, `SStr`, `SCase` |
| 2 | `ParamInfo`, per function parameter | must this call run now? | `isAuto`, `dictionary`, `interfaceType`, `recursiveArg`, `interesting`, `chooses`, `staticRun` |
| 3 | `Code p`, phase-indexed, with join points | what does a static value become at a runtime join? where are loops? | `OCase` as an op, `joinIn`, the `IORes` special case, `TailLoops.cc` |
| 4 | `Rep`, the runtime representation of a type | how is a value laid out? | ad hoc `VTy` cases, the implicit "recursive means compile-time" rule |
| 5 | `Prov` on `Code Mem` binders, and regions at recursive join points | when is memory free? | nothing today (no memory) |

Two algorithms remain, both generic over these structures:

- **one well-quasi-order**, homeomorphic embedding over `SValF` trees. It
  stops unfolding (the whistle) and widens result-shape fixpoints;
- **one generalization**, the most specific generalization by `zipMatch`,
  used for specialization keys, and its dual (least upper bound with
  choice) for join shapes.

### 4.1 Static values: `SValF r a`

```idris
data SValF : (r : Type) -> (a : Type) -> Type where
  Dyn  : a -> SValF r a                             -- a runtime atom
  Lit  : Lit -> SValF r a                           -- literals, Integer included
  Con  : ConId -> List r -> SValF r a               -- a known constructor
  Lam  : Label -> List r -> SValF r a               -- a closure: code label + captured values
  Call : FnId -> List r -> List (Elim r) -> SValF r a   -- a deferred call
  Sum  : List (ConId, List r) -> SValF r a          -- one of these shapes (join results only)

SVal : Type -> Type
SVal a = Fix (\r => SValF r a)
```

- `SBig` becomes a `Lit`. `SDelay` and `SCall` become one `Call`.
- `SString` becomes `Con` over the string pieces (literal, runtime,
  character, shown number, append), defined as ordinary static data (R2).
  Output fusion (`ELIM-G-7`) and `nonEmpty`/`headOf` (`ELIM-G-15`) are then
  folds.
- `Functor`, `Foldable` and `Traversable` in `a` give `atoms`, `refill` and
  `shape`. `cata` gives `size` and `children`.
- `zipMatch : SValF r a -> SValF r b -> Maybe (SValF (r, r) (a, b))` is the
  one generic operation (Sheard, "Generic unification via two-level
  types", ICFP 2001, *literature*; the `unification-fd` library). Equal
  heads zip; different heads fail.

Everything else is derived:

| Operation | Definition |
| --- | --- |
| `==`, `compare` | `zipMatch`, then the children |
| embedding `x ⊴ y` | *couple*: `zipMatch x y` succeeds and the children embed; *dive*: `x` embeds in a child of `y`; leaves compare by the literal wqo |
| `msg x y` (keys) | `zipMatch` where it succeeds; `Dyn` (a fresh atom) where it fails |
| `x ⊔ y` (join shapes) | `zipMatch` where it succeeds; `Sum` of both where heads differ; `Dyn` where a leaf differs |

The literal wqo is equality for characters and booleans, `|a| ≤ |b|` for
integers, and subsequence (Higman) for literal strings. With finitely many
functions and constructors, Kruskal's theorem makes `⊴` a well-quasi-order.

### 4.2 Driving: `ParamInfo`, one whistle, one generalization (R3)

**Parameter classes.** Each function parameter gets one `ParamInfo`,
computed once in the frontend from its type, its quantity, and a
fixed-parameter analysis like Lean's:

```idris
data ParamInfo
  = Erased   -- quantity 0: never passed, never part of a key
  | Static   -- a type-like or interface type, or a function type passed
             -- unchanged in recursive calls: always specialized
  | Value    -- anything else: part of the key only when its shape is static
```

- `Static` parameters are fixed by definition, so specializing on them
  cannot grow keys. This is Lean's rule, and it covers dictionaries,
  `map f`, `foldl f` and monad transformer stacks without the whistle.
- `Value` parameters go through the whistle.
- This deletes `isAuto`, the `dictionary` flag, `interfaceType`,
  `isImplementation`, `recursiveArg` and `interesting`. `VarInfo`'s
  `TypeValue` and `Static` become one constructor (both hold closed
  terms).

**Drive.** A call is unfolded when:

- a `Static` argument is present;
- a `Value` argument's shape is not `Dyn`;
- its result type after the applied eliminations is a static type;
- or it is an Idris case block, a `with` block, or a library `%inline`.

A call with only `Dyn` values and a runtime result type is residualized as
a call of the function's generic instance.

**Whistle.** The configuration of a call is its function plus the `SVal`s
of its non-erased arguments, literals included. The driver keeps the
configurations on the current unfolding path. If an ancestor with the same
function embeds (`⊴`) in the current configuration, the whistle blows.

**Generalize upward.** When the whistle blows, take `msg ancestor current`.
Roll back to the ancestor (`Gen` already supports rollback), residualize a
specialization keyed by the generalization, and memoize it (folding).

- Upward, not downward: downward peels one iteration of every loop that
  starts from a literal, which costs code size for nothing.
- `ack 3 n` still yields `ack[3]`, `ack[2]`, `ack[1]`, because each
  recursive call repeats its own first argument, so no ancestor embeds.
- `go 0 n → go 1 n` generalizes to `go(_, _)`.

**Budget.** One global unfolding budget per residual function bounds
compile time. When it runs out, the whistle is treated as having blown. It
is not a termination argument; `⊴` is.

What R3 deletes:

| Today | Under R3 |
| --- | --- |
| bounds 1, 64 and 10000; `staticRun`; `chooses`; `unfolding` counts | the whistle |
| `ELIM-G-16`, `known`, `knownData`, `evaluate`, `abandon`, `attempt` | a constant call drives to a literal; a path that does not finish generalizes |
| `force`, `once`, the `Call` cases in `matchCon` | driving a deferred call is driving |
| `ELIM-G-17`, `ELIM-G-18`, the budget of 4 | `msg` keeps equal literals |
| `PROF-HEAP-4` growth check, 256 per function, key size 4096 | a generalization that has no runtime representation (section 4.4) |
| `interesting`, `constants`, `callPattern`, `matchedParams` | the drive rule |

### 4.3 Residual code: `Code p` with join points (R4)

```idris
data Phase = Pure | Mem

data Code : Phase -> Type where
  Let    : Loc -> List Binder -> Op -> Code p -> Code p      -- multi-result
  Join   : Loc -> JoinId -> List Binder -> (body : Code p) -> (rest : Code p) -> Code p
  Jump   : Loc -> JoinId -> List Atom -> Code p
  Case   : Loc -> Atom -> List (Alt p) -> Maybe (Code p) -> Code p
  Ret    : Loc -> List Atom -> Code p
  Absurd : Loc -> Code p
  Mark   : Loc -> VarId -> Code Mem -> Code Mem                 -- region mark
  Release: Loc -> VarId -> Code Mem -> Code Mem                 -- release to a mark
```

Five changes from today's `Code`:

1. **`Case` is a terminator**, not an op bound to a variable. What followed
   a case becomes a join point. This is Lean's `cases`, and it is what
   Maurer, Downen, Ariola and Peyton Jones (PLDI 2017, *literature*) show
   to be the right core.
2. **Join points are declared and jumped to.** A join point's body may
   jump to itself: **a loop is a recursive join point.** A self tail call
   in a residual function becomes a jump to the join point wrapping the
   function body. `TailLoops.cc` is deleted, and `Emit` produces loops
   directly.
3. **`Let` and `Ret` are multi-valued.** A function returns a list of
   atoms, which is Lean's `struct` return, and MLIR's multiple results.
4. **Phases, Lean-style.** `Code Pure` is `Simplify`'s output. `Code Mem`
   adds `Mark`, `Release`, and a provenance on each binder (section 4.5).
   One type and one set of traversals covers both.
5. **Join points lower to MLIR blocks with arguments** (`cf.br`,
   `cf.cond_br`, `cf.switch`). SSA blocks are join points, which is
   Kelsey's CPS/SSA correspondence (1995, *literature*). `scf.if`,
   `scf.index_switch` and `scf.while` leave `Emit`, and LLVM sees the same
   control-flow graph.

**Static values across runtime control flow.** A residual `Case` whose
alternatives produce static values `s₁ … sₙ`:

1. Compute `S = s₁ ⊔ … ⊔ sₙ`.
2. `S` is a sum of products of `Dyn` leaves, the SOP of Kovács.
3. Declare one join point per summand of `S`. Its parameters are that
   summand's atoms, and its body is the continuation, driven with the
   static value rebuilt from those parameters.
4. Each alternative jumps to its summand's join point with its atoms.
   Nothing is materialized: no tag, no constructor, no case on the result.
5. With one summand this is CPR (Baker-Finch, Glynn and Peyton Jones, JFP
   2004, *literature*). If the continuation is small, the driver may inline
   it instead of declaring the join point, which is case-of-case, bounded
   by the whistle.

**Residual functions with static results** use the same SOP. The result is
the least fixpoint of `⊔` over the function's alternatives: start from the
non-recursive alternatives, and iterate.

- **Widening is the whistle.** If an iterate embeds its predecessor and is
  strictly larger, generalize. The growing positions become `Dyn`. That is
  Lean's type-recursion widening, derived from the same `⊴` instead of a
  depth constant.
- A function returning an n-summand SOP returns a tag plus the union of the
  summands' atoms, with slots shared by type as in `LOW-DATA-1`. The caller
  switches on the tag straight into its join points. This is Lean's
  `union` return.
- The n-body `Vect 3 Double` loop result is a one-summand SOP of three
  doubles: a function returning three `f64`s.

This deletes `SCase`, string join points (`ELIM-G-14`), `joinIn`,
`needsJoin`, `reifiable`, the single-constructor `IORes` case, and the
n-body rejection. It is the missing piece of the overnight CPR attempt,
which looped because it guessed the result shape instead of computing the
fixpoint.

### 4.4 Runtime representation: `Rep`

A generalization that yields `Dyn` for a value that is not a scalar needs a
runtime layout. `Rep` is computed once per runtime type, like Lean's
`impureTypeExt` and Futhark's internalisation:

```idris
data Rep
  = Scalar Scalar               -- i8 … i64, f64; Char is i32
  | Str                         -- (pointer, length)
  | Sop (List (List Rep))       -- non-recursive data, and join shapes
  | Box DataId                  -- recursive data: a pointer to a region cell (M2)
  | Arr Rep                     -- ArrayData: struct of arrays over the element
  | None                        -- erased, world, unit
```

`rep` is one algebra over the type, driven by the flags Idris computed:

| Idris type (flag) | `Rep` |
| --- | --- |
| `Int`, `Bits*`, `Int*`, `Double`, `Char` | `Scalar` |
| `String` | `Str` |
| `ZERO/SUCC` (nat-like: `Nat`, `Fin`, …) | `Scalar i64`. Arithmetic is checked: overflow crashes with a message (a new rule in 03). `Nat`'s `%builtin Natural` operations map to i64 operations. |
| `UNIT`, erased, `%World` | `None` |
| `ENUM n` | `Sop` of `n` empty products: a tag only |
| `RECORD` | `Sop [[fields]]`: no tag |
| `NOTHING/JUST` whose payload is a `Box` or `Arr` | the payload's pointer, with null as `Nothing` |
| other non-recursive data | `Sop`, with the `LOW-DATA-1` slot sharing |
| recursive data | `Box` (M2; `PROF-DATA-3` until then) |
| `ArrayData a` | `Arr (rep a)` |
| a function type | never a runtime `Rep` |

Two properties make this the whole story:

- **Arrays distribute over products and sums** (Futhark):
  - `Arr (Sop [[a, b]])` is two arrays;
  - `Arr (Sop [[], [Int]])`, the `Maybe Int` inside `IOArray`, is a byte
    array of tags and an `i64` array;
  - `Arr (Scalar f64)` is a plain `double*`.
  - Whole-program monomorphism gives us unboxed element arrays for every
    element type. Lean needs `FloatArray` and `ByteArray` because it
    cannot.
- **Functions are never runtime values** (Kovács's `CTy`):
  - a closure that must exist at runtime (a `Lam` generalized to `Dyn`) is
    defunctionalized into a `Sop` over the lambda labels that reach that
    point, each summand holding the captured atoms (Reynolds; Danvy and
    Nielsen, *local*);
  - applying it is a `Case` on the label;
  - closures are data, so there is no second mechanism.

`Emit` passes `Sop` shapes to the `idr` dialect as `idr.data` declarations.
Synthesized join shapes get generated names, deduplicated structurally. The
byte layout stays in C++ (`LOW-DATA-1`); the choice of representation moves
to Idris, where the types are.

### 4.5 Memory: regions at recursive join points

**The region stack** (GNAT's secondary stack; OCaml's local allocations with
`exclave_`, Lorenzen et al. ICFP 2024, *literature*; Tofte and Talpin's
regions restricted to loop nesting, *literature*):

- A static `.bss` arena of 1 GiB and a bump pointer. The kernel commits
  pages lazily, so untouched space costs nothing. A compiler flag
  `--region-size` changes the size.
- Overflow is a crash with a message, like a stack overflow.
- No new symbols: `TEST-HEAP-1` stays `write`, `read`, `_exit` and libm.
- A callee may allocate and return the memory to its caller.
- Memory is freed only by releasing to a mark, which is LIFO.

**Regions are recursive join points.** In `Code Mem`:

- a recursive join point marks on entry;
- before each jump back to itself, it releases to that mark if every
  carried `Box`, `Str` or `Arr` argument is `Old`.

Nothing else releases. Functions never release on return, so returning
dynamic data costs nothing.

**Provenance** is a two-point lattice, `Prov = Old | New`, on every pointer
binder in `Code Mem`. It is Futhark's `ReturnsInBlock` vs `ReturnsNewBlock`,
relative to the innermost mark:

- **Old**:
  - the join point's parameters and literals;
  - fields and views of `Old` values;
  - the result of an in-place array write to an `Old` array, whose
    identity does not change.
- **New**:
  - allocations since the mark;
  - results of calls whose result `Rep` contains a pointer (callers see
    callees' allocations as new);
  - an array that a `New` pointer was stored into.

It is one forward dataflow over `Code Mem`, and it is exact without alias
analysis because `Simplify` has removed every closure and every unknown
call.

**When a loop carries `New` data:**

- **Total loop** (`CFn.terminating`): no release. Its allocations belong to
  the enclosing region, and termination bounds them. `reverse`, `foldl`
  with a list accumulator, and `words` work this way.
- **Partial loop** (a REPL's `main`): in M1 this is `PROF-REG-1`, a
  rejection. M3 lifts it with two rewrites:
  - **double buffering** (Futhark's `DoubleBuffer`): when the carried
    value is an array or string whose size is loop-invariant, allocate two
    buffers before the loop and swap them;
  - **move-down**: copy the carried `New` values to the mark, then release.
    The copy is a per-`Rep` function the compiler generates, and it costs
    the size of the carried data, with no copy when the data is already at
    the top of the region.
  - What remains rejected is a partial loop whose carried data grows
    without bound: an unbounded history, which needs a heap.

### 4.6 Arrays, strings and effects: what Idris already defines

We implement Idris's backend primitives, the ones every backend (Chez,
RefC, JavaScript) implements. We add no library, no pragma and no API; the
profile adds no meaning (`01-goals`, non-goals).

**The primitives, as `idr` ops:**

| Primitive | Op | Lowering |
| --- | --- | --- |
| `prim__newArray n x` | `idr.array.new` | bump-allocate `n` elements of `Arr (rep a)` in the region, then fill |
| `prim__arrayGet a i` | `idr.array.get` | bounds trap, then a load per component |
| `prim__arraySet a i x` | `idr.array.set` | bounds trap, then a store per component |
| `prim__getStr` (`getLine`) | `idr.io.get_line` | read into the region; return `(pointer, length)` |
| `StrLength … StrSubstr`, `fastPack`, `fastUnpack`, `fastConcat` | `idr.str.*` | on `Str` in the region |

- The primitives are unchecked in Idris ("behaviour is undefined
  otherwise"). We emit a trapping bounds check, so an out-of-bounds access
  crashes and never miscompiles. `IOArray`'s own check dominates it, and
  LLVM removes the duplicate.
- The ops carry C++ `MemoryEffects` on an array resource, so MLIR and LLVM
  never reorder a load across a store of the same array.

**Effects: one world.**

- Every effectful op consumes and produces the world (`CORE-INV-9`).
- `unsafeCreateWorld` takes the *current* program world at its evaluation
  point, and `unsafeDestroyWorld` puts it back. So an `unsafePerformIO` in
  library code is sequenced in strict, left-to-right evaluation order.
- A function is **effectful** if it reaches an IO primitive or
  `unsafeCreateWorld`. This is one fact computed over the call graph
  (section 4.7).
- Calls to effectful functions are never deferred, duplicated, dropped or
  evaluated at compile time. Their residual instances take and return the
  world.

That is enough for the libraries as they are:

- **`Data.IOArray`**: plain `IO` code, sequenced by the world.
- **`contrib`'s `Data.Linear.Array`**:
  - `LinArray` operations are `unsafePerformIO` over `IOArray`, so they are
    effectful and run in evaluation order.
  - The compiler never needs uniqueness for soundness. If a program
    aliases a `LinArray` (possible through `newArray n id`), our output
    matches the Chez backend's, because both perform the same mutations in
    the same order.
  - Linearity is the user's proof that the interface is observationally
    pure. `AGENTS.md`'s rule holds: a linear binder does not imply unique
    ownership, and we never assume it does.
- **`Data.IOArray.Prims`**, used directly: `ArrayData Int` is a plain
  `i64*` with no `Maybe`. That is the fastest form, and it is ordinary
  Idris.
- **Length-indexed arrays** are the user's code: a record over `IOArray`
  with `Fin n` indices. `Fin` is `Scalar i64` by `ZERO/SUCC`. `IOArray`'s
  `maxSize` is a flattened record field, the same SSA value the program
  passed to `newArray`, so in a loop bounded by that value LLVM removes the
  check.
- **In-place update costs one store** and never copies. That is Lean's
  `Array.set` without the exclusivity check, the reference count, or the
  silent copy that `markLinear` exists to catch.
- **Aliasing**: two arrays from different `prim__newArray` sites never
  alias, which the region allocator guarantees. `Emit` puts them in
  distinct alias scopes, so LLVM vectorizes without runtime alias checks.

**Costs, stated plainly:**

- `IOArray a` reads a tag byte and branches on every read, because Idris
  stores `Maybe a`. `Data.IOArray.Prims` has neither.
- `contrib`'s `write` returns a `Bool` from its bounds check. It flattens
  into a register, and is dead if unused.

**Strings** are `Str`, a pointer and a length into the region. Compile-time
strings stay static rope data (R2) and never reach memory. `Vect` stays a
list: `Sop` when its shape is static, `Box` at M2 when it is not. Indexed
vectors do not imply contiguous storage, and we do not pretend they do.

### 4.7 Facts: one algebra over the call graph

`needsV1`, `needsV2` and `needsV3` become one algebra returning a record of
facts per function, computed once and joined over the call graph:

```idris
record Facts where
  features    : SortedSet Feature   -- the contract version is the maximum
  effectful   : Bool                -- reaches IO or unsafeCreateWorld
  allocates   : Bool                -- may return New pointers
  terminating : Bool                -- Idris's totality flag
```

Collapsing the rules to match:

- `ELIM-G-10` to `ELIM-G-18` collapse into three:
  - **drive**: 10, 11, 12, 13 and 16;
  - **whistle and generalization**: 17, 18, and `PROF-HEAP-4`'s check;
  - **join**: 14.
- `ELIM-G-15` becomes two string algebras.

## 5. What changes in the code

| Module | Change |
| --- | --- |
| `Simplify/Value` | `SValF`, `zipMatch`, the derived operations; `SStr` deleted |
| `Simplify/Gen` | the driving path with configurations, rollback, memo by generalized key; `St` from 16 fields to about 9 |
| `Simplify` | the drive rule and the join rule; the bounds, fuel, forcing helpers and matcher special cases deleted |
| `Code` | `Code p` with join points, case as terminator, multi-valued `Let`/`Ret`; `Facts` |
| new `Rep` | `rep` and its cache |
| new `Memory` | `Code Pure → Code Mem`: provenance, marks, releases, `PROF-REG-1` |
| `Emit` | join points to `cf` blocks; SOP returns as multiple results; array, string and region ops |
| `Frontend/Translate` | split into `Frontend/Data`, `Frontend/Instances`, `Frontend/Terms`, `Frontend/Trees`; `ParamInfo`; `ConInfo` flags read into `Rep` |
| `foreign/idr` | `TailLoops.cc` deleted; `idr.array.*`, `idr.str.*`, `idr.io.get_line`, `idr.region.{mark,release,alloc}`, with `MemoryEffects`; the region arena in `Runtime.mlir.inc` |

Size estimates, to check against the diff:

- `Simplify`: from about 950 to about 600 lines;
- `Value`: about 150 lines fewer;
- `Rep` and `Memory`: about 350 lines together;
- `TailLoops.cc`: gone.

## 6. Order of work

The refactor (R1 to R6) comes first and changes no behaviour. Each step is
one commit: the same fixtures pass, and the benchmark table is unchanged or
better.

1. **R1**: `SValF`, `zipMatch`, `⊴`, `msg`, `⊔`.
2. **R2**: strings as static data.
3. **R3**: `ParamInfo` and driving (drive, whistle, upward generalization,
   budget). Measure code size and benchmark times before and after.
4. **R4**: `Code p` with join points. First only the move of case to a
   terminator, with loops as recursive join points and `cf` lowering
   (delete `TailLoops.cc`). Then SOP joins with the fixpoint. This is where
   n-body over `Vect` compiles.
5. **R5**: the frontend split.
6. **R6**: `Facts` and the rule collapse.

Then the milestones, each a profile version:

- **M1 (v4): scalars, strings and arrays at runtime.**
  - `Rep`, with `ZERO/SUCC` as checked i64;
  - the region stack, and regions at recursive join points;
  - provenance, and `PROF-REG-1`;
  - runtime strings and `getLine`;
  - the three array primitives, over elements whose `Rep` has no pointer
    (`PROF-ARR-1`);
  - the `effectful` fact, with `Data.IOArray` and `contrib`'s
    `Data.Linear.Array` admitted.
- **M2 (v5): dynamic data.**
  - `Box` for recursive data;
  - defunctionalized closures;
  - `words`, `lines`, `unpack`, `pack`;
  - TRMC for loops that build lists (Koka);
  - arrays of pointer elements, with a stored `New` pointer making the
    array `New`.
- **M3 (v6): loops that carry dynamic state.**
  - double buffering and move-down, which lift most of `PROF-REG-1`;
  - reuse of a `Box` cell that dies as a same-`Rep` cell is built
    (Perceus/FP² reuse). Uniqueness is proved on `Code Mem` from `Code.uses`
    on freshly allocated values, not from reference counts.
- **M4: frames.** Allocations that do not escape a function go to
  `memref.alloca` in its frame, as `promote-buffers-to-stack` does.

## 7. What compiles

**After the refactor, with no memory yet:**

- everything that compiles today;
- n-body and other loops over `Vect n` with a static `n`;
- functions returning tuples or records built in branches;
- monad transformer stacks over state and `Maybe`, with SOP joins instead
  of runtime `Just`/`Nothing`.

**After M1:**

- **line-oriented programs.** A command loop parses each line by
  scanning bytes into a non-recursive `data Cmd = Fib Int | NBody Int |
  Quit | Bad`, runs the benchmark, prints, and loops in constant memory;
- **array programs with runtime sizes**:
  - a sieve;
  - histograms;
  - edit distance and LCS on two input lines, with one flat table or two
    swapped rows;
  - in-place quicksort, heapsort and Fisher–Yates;
  - matrix multiply with runtime dimensions;
  - n-body with a runtime body count, as struct-of-arrays automatically;
  - each written with `IOArray` in `IO`, with `contrib`'s `LinArray` in
    pure code, or with `ArrayData` directly;
- **a table carried across commands** in the command loop. The array is
  allocated before the loop and updated in place, so it stays `Old`.

**After M2:** the CLI of the previous note, with `words`, and any
`List`/tree code whose loops are total or carry only `Old` data.

**After M3:** REPLs whose carried state is bounded (a buffer, a
fixed-size table, a current value) even when rebuilt each iteration.

## 8. What does not compile, and why that is acceptable

| Program | Rule | Why | Path |
| --- | --- | --- | --- |
| runtime `Integer` | `PROF-TYPE-4` | needs bignums in memory | not planned; `Int`/`Bits64` or `Nat` as checked i64 cover the benchmarks |
| pointer elements in arrays (M1) | `PROF-ARR-1` | the element could be newer than the array | M2 |
| runtime lists, trees, closures in data (M1) | `PROF-DATA-3`, `PROF-HEAP-1` | need `Box` | M2 |
| a partial loop carrying new data (M1, M2) | `PROF-REG-1` | memory could grow without bound | M3 lifts the bounded cases |
| a partial loop whose carried data grows without bound | `PROF-REG-1` | that is the one program shape that needs a heap | not planned |
| `IORef`, and `IOArray` holding pointers into newer regions | `PROF-REG-1`/`PROF-ARR-1` | a mutable cell can make old data point at new data | scalars and old data only |
| `Data.Linear.Array` aliasing through `newArray n id` | none | compiles, with the same mutations Chez performs | nothing to do |

Every rejection names a rule and has a rewrite: pre-size, double-buffer by
hand, flatten nested arrays into one, keep carried state bounded. Every
accepted program runs with no reference counts, no GC and no runtime, and
an array write costs one store.

## 9. Contract changes (need approval, `AG-NEVER-1`)

- **02, profile.**
  - Admit `Data.IOArray`, `Data.IOArray.Prims` and `contrib`'s
    `Data.Linear.Array` as library modules.
  - Lift `PROF-ESC-1` for exactly the three `prim__array*` externs and
    `prim__getStr`.
  - Admit `unsafePerformIO` in library modules (`PROF-IO-3` still bans it
    in user modules).
  - Add `PROF-ARR-1` and `PROF-REG-1`.
- **03, semantics.**
  - Nat-like types are checked i64.
  - Region semantics.
  - The one-world rule for `unsafeCreateWorld`.
  - Strict left-to-right order of effects in pure code.
- **08, dialect.**
  - `idr.array.*`, `idr.str.*`, `idr.io.get_line`, `idr.region.*`, and
    their memory effects.
  - Multiple results for SOP returns.
- **10, lowering.**
  - `Rep` to `LOW-DATA-1` layout, struct of arrays, nullable-pointer
    `Maybe`.
  - Join points as `cf` blocks.
  - The arena.

## 10. Decisions

Made here, and no longer open:

- **Generalization is upward.**
- **The region is 1 GiB of lazily committed `.bss`**, set by
  `--region-size`.
- **Nat-like types are checked i64.**
- **The array API is Idris's own**, with no library of ours.
- **Loops are recursive join points.** `TailLoops.cc` goes.

For the user:

- Approval of the v4 contract changes in section 9.
- Whether M1 should wait for R4's SOP joins, or start after R4's first half
  (case as a terminator, and loops as join points). Memory needs only that
  first half; SOP joins are independent.
