# 05. The middle IR (`Core`)

`Core` is the Idris-side IR. It sits between the frontend and MLIR emission,
and exists for the work that needs Idris-level facts:
- monomorphisation;
- the guaranteed eliminations ([06](06-elimination.md)), which also enforce
  `PROF-HEAP-*`;
- later, proved rewrites.

Everything else is MLIR's job ([09-optimization](09-optimization.md)).

`Core` is two languages with two types, following MLton, Lean and Kovács's
two-level type theory:
- **Full Core** (`IdrisMLIR.Term`), produced by the frontend. It is
  higher-order: it has lambdas, application of arbitrary terms, `Delay` and
  `Force`, and values of function, `Lazy` and static data types.
- **First-order Core** (`IdrisMLIR.Code`), produced by `Simplify`. It is in
  A-normal form and mentions only value types. It is the only form `Emit`
  accepts.

What the types of these languages rule out needs no check: an unbound
variable in full Core, and a function value, a `Lazy` value or a string
operation in first-order Core, cannot be built.

## Shape

This is normative in content, not in exact Idris syntax.

```idris
data Quantity = Q0 | Q1 | QW
data IntTy    = IdrisInt | SInt8 | SInt16 | SInt32 | SInt64
              | UInt8 | UInt16 | UInt32 | UInt64

-- Value types exist at runtime and may be stored in data.
data VTy      = IntT IntTy | CharT | StrT | WorldT | ErasedT | DataT DataId
-- Types add what exists only at compile time: functions, Lazy, and static
-- data (data holding a function or Lazy value, such as IO).
data Ty       = V VTy | FunT Quantity Ty Ty | LazyT Ty | StaticT DataId

data Lit      = LInt IntTy Integer | LChar Integer | LStr String
data Prim     = IntOp ArithOp IntTy | Compare Cmp Scalar | Cast Scalar Scalar
data StrOp    = Append | Cons | Length | ... | ToStr Scalar | FromStr Scalar
data PrimOp   = Run Prim | Str StrOp        -- string operations: compile time only
data IOOp     = PutStr | PutChar | PutInt IntTy | PutDouble | GetByte

-- Full Core: well scoped, with de Bruijn indices (like Idris's `Term vars`).
data Term : Nat -> Type where
  Var         : Fin n -> Term n
  Literal     : Lit -> Term n
  Erased      : Term n
  PrimApp     : PrimOp -> List (Term n) -> Term n
  Effect      : IOOp -> List (Term n) -> DataId -> Term n   -- IO primitives (PROF-IO-4)
  Call        : FnId -> List (Term n) -> Term n              -- saturated
  ConApp      : ConId -> List (Term n) -> Term n             -- saturated, fields only
  Let         : Quantity -> Term n -> Term (S n) -> Term n
  Case        : Fin n -> List (Alt n) -> Maybe (Term n) -> Term n
  CaseLit     : Fin n -> List (Lit, Term n) -> Term n -> Term n
  Lam         : Label -> (caps : Vect k (Fin n)) -> Binder -> Term (S k) -> Term n
  App         : Term n -> Term n -> Term n
  Suspend     : Label -> (caps : Vect k (Fin n)) -> Term k -> Term n   -- Delay
  Resume      : Term n -> Term n                                       -- Force
  Unreachable : Term n
data Alt n    = MkAlt ConId (fields : List Binder) (Term (length fields + n))

-- First-order Core: A-normal form with join points (Maurer et al.,
-- "Compiling without continuations", PLDI 2017; Lean's LCNF), indexed by
-- its phase as LCNF is by its purity.
data Atom     = AVar VarId | ALit Lit | AErased
data Param    = MkParam VarId Quantity VTy
data Op       = OPrim Prim (List Atom) | OCall FnId (List Atom)
              | OCon ConId (List Atom) | OField Atom ConId Nat
              | OIO IOOp (List Atom) DataId
data Branch r = MkBranch ConId (List VarId) r
data Phase    = Pure | Mem
data Code : Phase -> Type where
  Let     : List Param -> Op -> Code p -> Code p      -- binds an op's results
  Join    : JoinId -> List Param -> (body : Code p) -> (rest : Code p) -> Code p
  Jump    : JoinId -> List Atom -> Code p
  Case    : Atom -> List (Branch (Code p)) -> Maybe (Code p) -> Code p
  CaseLit : Atom -> List (Lit, Code p) -> Code p -> Code p
  Ret     : List Atom -> Code p
  Crash   : String -> Code p                          -- SEM-CRASH-2
  Absurd  : Code p                                    -- Idris proved it unreachable
  Mark    : VarId -> Code Mem -> Code Mem             -- the memory plan (v4)
  Release : VarId -> Code Mem -> Code Mem
```

- Every node carries its source location (`FE-LOC-1`), and every location
  the origin the registry gave its module ([17-registry](17-registry.md)),
  so no pass reads a namespace.
- `FnId`, `DataId`, `ConId`, `VarId` and `Label` are distinct types. A
  `FnId` is an Idris full name, an instance name (`ELIM-MONO-4`) or a
  specialization name (`ELIM-G-3`). The Idris name of a function or data
  type is `Shown`: it can be printed, not compared.
- A function carries its facts (whether it terminates, is a case or with
  block, is inlined as its author's hint), each with its provenance.
- In full Core, a function's body is in scope of its arity, and parameter
  `i` is variable `i`, as in Idris's case trees. An alternative binds its
  constructor's fields, the first field innermost.
- A lambda and a `Delay` are closure-converted when they are built: each has
  a `Label` (its program point, unique in the program), the variables it
  captures, and a body closed over them. `Simplify` identifies closures by
  label.
- `let` has no type in full Core: TTC does not keep let types
  (`FE-TR-1`), and `Simplify` knows a value's type when it evaluates it.
- A match is a terminator. What follows a match is a join point: a block
  with parameters that the match's alternatives jump to. A join point's
  body may jump to it, which makes it a loop (`CORE-LOOP-1`). Join points
  are MLIR's blocks with arguments, and `Emit` writes them as such.
- `Let` and `Ret` hold several values: a function may return several atoms.
- `Code` has a base functor, `CodeF p r`, and every traversal of
  first-order Core (binders, join points, calls, data, uses, safety, the
  contract version, printing, typing, emission) is a fold with an algebra,
  or a paramorphism where the algebra needs a part as it was.

## Invariants of first-order Core

`Code.Check` verifies these; each is marked with what enforces it.

- **CORE-INV-1 (v0).** Closed: a function body refers only to its parameters
  and to variables bound inside it. Variable names are unique within a
  function.
- **CORE-INV-2 (v0).** First order:
  - there is no lambda, application, `Delay` or `Force`: by construction,
    since `Code` has none;
  - every `OCall` names a function in `fns`, with one argument per
    parameter;
  - every `OCon` has one argument per field.
- **CORE-INV-3 (v0).** Monomorphic and typed:
  - there are no function, `Lazy` or static types: by construction, since
    `Code` mentions only `VTy`; every `DataT` names an entry of `datas`;
  - every binding, argument, field read and result has the type its
    position requires;
  - every quantity-0 position has type `ErasedT` and argument `AErased`.
- **CORE-INV-4 (v0).** Quantities are recorded on every parameter, field and
  binding, as the checked TT had them, or as the elimination that created the
  binder defines them.
  - Check: review (`Simplify.specialize` and `Frontend.Translate`)
- **CORE-INV-5 (v0).** A quantity-0 variable is used only in quantity-0
  positions, and no erased field is read.
- **CORE-INV-6 (v0).** Matches:
  - An `OCase`'s scrutinee has a `DataT`, and its alternatives name distinct
    constructors of that type.
  - An `OCase` without a default covers every constructor. An alternative
    Idris proved impossible is present, with body `Absurd` (`FE-TR-4`,
    `SEM-DATA-2`).
  - Every match has an alternative that is not `Absurd`.
  - An `OCaseLit`'s literals are distinct and have the scrutinee's type.
  - An `OField` reads a type with exactly one constructor.
- **CORE-INV-7 (v0).** `datas` satisfies `PROF-DATA-*`:
  - tags are `0..n-1` in Idris tag order;
  - runtime containment is acyclic.
- **CORE-INV-8 (v0).** Every function in `fns` is reachable from `root`.
- **CORE-INV-9 (v1).** Every `WorldT` variable is used at most once on each
  control-flow path (`IDR-WORLD-1`). A jump continues in its join point's
  body, so it counts that body's uses; a loop's body runs any number of
  times, so a world from outside the loop may not be used in it. `%MkWorld` never appears: the root
  wrapper receives the world as its parameter, and raised IO functions
  (`ELIM-G-5`) receive and return it.
- **CORE-INV-10 (v1).** Every `StrT` value is a string literal or a variable:
  `Prim` has no string operation (`PROF-HEAP-3`).
  - Check: review (by construction: string operations are `StrOp`, which
    `Code` cannot hold)

- **CORE-INV-11 (v3).** Join points are declared once per function, and a
  jump names a join point in scope (declared around it, or the loop it is
  in) with one argument of the right type per parameter. A join point's body
  sees the variables in scope where it is declared, never those of the code
  that jumps to it, which is what makes it a dominating block in MLIR.
  - Test: `tests/compiler` unit tests on hand-built invalid `Core`

- **CORE-CHECK-1 (v0).** The pipeline runs `Term.Check` on full Core after
  `Translate` (references resolve; calls, constructors and alternatives
  have the right number of arguments) and `Code.Check` on first-order Core
  before `Emit`. A failure is an internal compiler error (`DIAG-ICE-1`).
  - Test: `tests/compiler` unit tests on hand-built invalid `Core`

## Pass order

- **CORE-PASS-1.** The middle end runs these passes in this order. A pass of a
  later version is absent until that version. No other pass may be inserted
  without changing this rule.

  | # | Pass | Version | Purpose |
  | --- | --- | --- | --- |
  | 1 | `Frontend.Translate` | v0 | checked TT → full Core |
  | 2 | `Rewrite` | reserved | proved rewrites ([07](07-proved-rewrites.md)); before specialization, so that replacements get specialized |
  | 3 | `Mono` | v1 | monomorphisation (`ELIM-MONO-*`) |
  | 4 | `Simplify` | v1 | the guaranteed eliminations (`ELIM-G-*`) and `PROF-HEAP-*`: full Core → first-order Core |
  | 5 | `Code.Loops` | v3 | loops as recursive join points (`CORE-LOOP-1`) |
  | 6 | `Emit` | v0 | first-order Core → `idr` contract text ([08](08-idr-dialect.md)) |

  `Mono` is fused into `Frontend.Translate`: instances are requested on
  demand while translating, keyed by their type arguments (`ELIM-MONO-1`),
  so full `Core` is already monomorphic. There is no separate pass.

  There is no separate heap check: `Simplify` produces first-order Core,
  which cannot hold what `PROF-HEAP-*` forbids, and reports each violation
  where it finds it, with its reason (`DIAG-HEAP-1`). Its last step checks
  `PROF-HEAP-5` on the finished program (`ELIM-G-5`).
- **CORE-LOOP-1 (v3).** A function that calls itself in tail position, with
  its results returned unchanged, becomes a join point that the function
  enters once and that each such call jumps to. First, a join point whose
  body returns exactly its parameters is the return itself, so a call
  whose result a match passes straight out is a tail call. This is the
  only place loops are made; `Code.Check` runs again after it.
  - Check: `Code.Loops.loopify`
  - Test: `tests/e2e/v0/tail-loop-deep` (10^8 iterations with the stack
    limited to 1 MiB), `tests/profile/v0/accept/PROF-FN-6-tail-loop.idr`

- **CORE-OPT-1 (v0).** The middle end performs only monomorphisation and the
  guaranteed eliminations. It MUST NOT add any other optimization:
  - first-order inlining, beyond the driver's unfolding (`ELIM-G-19`),
    which decides static control before code exists (v3);
  - CSE;
  - dead-code elimination of first-order code;
  - constant folding beyond `ELIM-G-6`;
  - case-of-known-constructor on first-order data beyond `ELIM-G-2`.

  *Rationale:* `GOAL-P1`. The eliminations happen in Idris because MLIR has no
  closures, thunks or strings to eliminate them from. Everything else MLIR
  does better, and duplicating it would split one optimization across two
  implementations.
- **CORE-ERASE-1 (v0).** `Core` keeps quantity-0 values as `Erased`. The
  former Idris-side `Erase` pass is removed. Erasure happens in MLIR lowering
  (`LOW-ERASE-1`).

## Dumps

- **CORE-DUMP-1 (v0).** `Core` has a deterministic text printer for each
  language. The `.core` artifact (`FE-ART-1`) is the first-order Core that
  `Emit` receives. With `--directive dump-core`, the frontend also writes the
  full Core after `Translate` and the first-order Core after `Simplify`
  (`DRV-DUMP-1`). Full Core prints variables as de Bruijn indices (`#0` is
  the innermost); first-order Core prints them as `%n`, and prints above
  each specialization the function and argument shapes it was made for.
  - Test: every e2e fixture checks the `.core` artifact exists; the
    `ELIM-G-*` fixtures match the dumped Core with `FileCheck`. The format
    is informative and may change without a contract change, but tests that
    match it must be updated in the same commit.
