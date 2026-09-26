# 05. The middle IR (`Core`)

`Core` is the Idris-side IR, evolved from today's `IdrisMLIR.IR`. It sits
between the frontend and MLIR emission. It exists for the work that needs
Idris-level facts:
- monomorphisation;
- the guaranteed eliminations ([06](06-elimination.md));
- the heap check;
- later, proved rewrites.

Everything else is MLIR's job ([09-optimization](09-optimization.md)).

`Core` has two forms, which share one data type:
- **Full Core**, produced by the frontend. It may contain lambdas,
  application of arbitrary expressions, `Delay`/`Force`, and, before `Mono`,
  type parameters.
- **First-order Core**, produced by `Simplify` and accepted by `HeapCheck`.
  It satisfies every invariant below, and it is the only form `Emit`
  accepts.

## Shape

This is normative in content, not in exact Idris syntax:

```idris
data Quantity = Q0 | Q1 | QW
data IntTy    = IdrisInt | SInt8 | SInt16 | SInt32 | SInt64
              | UInt8 | UInt16 | UInt32 | UInt64
data Ty       = IntT IntTy | CharT | StrT | WorldT | ErasedT
              | DataT Name (List Ty)            -- instance; no args after Mono
              | FunT Quantity Ty Ty | LazyT Ty  -- full Core only
              | TyVar Name                      -- before Mono only

data Lit      = LInt IntTy Integer | LChar Int | LStr String
data Expr     = Var Var | Lit Lit | Erased | World     -- World: %MkWorld (root only)
              | Prim PrimOp (List Expr)
              | IOPrim IOOp (List Expr)                -- IdrisMLIR.IO primitives
              | Call Name (List Expr)
              | Con Name Name (List Expr)
              | Let Var Quantity Ty Expr Expr
              | MatchCon Var (List ConAlt) (Maybe Expr)
              | MatchLit Var (List (Lit, Expr)) Expr
              | Lam Var Quantity Ty Expr | App Expr Expr   -- full Core only
              | Delay Expr | Force Expr                    -- full Core only
data IOOp     = PutStr | PutChar | GetChar | Exit | PutInt IntTy
```

Every `Expr` node carries an `FC` (`FE-LOC-1`). `Name` is the Idris full name,
or an instance or specialization name derived from it deterministically.

## Invariants of first-order Core

`Core.Check` verifies these.

- **CORE-INV-1 (v0).** Closed: a function body refers only to its parameters
  and to variables bound inside it. Variable names are unique within a
  function.
- **CORE-INV-2 (v0).** First order:
  - there is no `Lam`, `App`, `Delay` or `Force`;
  - every `Call` names a function in `fns`, with one argument per parameter;
  - every `Con` has one argument per field.
- **CORE-INV-3 (v0).** Monomorphic and typed:
  - there are no `TyVar`, `FunT` or `LazyT` types, and every `DataT` has no
    arguments and names an entry of `datas`;
  - every quantity-0 position has type `ErasedT` and argument `Erased`.
- **CORE-INV-4 (v0).** Quantities are recorded on every parameter, field and
  `let`, as the checked TT had them, or as the elimination that created the
  binder defines them.
- **CORE-INV-5 (v0).** A quantity-0 variable is used only in quantity-0
  positions.
- **CORE-INV-6 (v0).** Matches:
  - A `MatchCon`'s scrutinee has a `DataT`, and its alternatives name
    distinct constructors of that type.
  - A `MatchLit`'s literals are distinct and have the scrutinee's type.
  - A `MatchCon` without a default covers every constructor.
- **CORE-INV-7 (v0).** `datas` satisfies `PROF-DATA-*`:
  - tags are `0..n-1` in Idris tag order;
  - runtime containment is acyclic.
- **CORE-INV-8 (v0).** Every function in `fns` is reachable from `root`.
- **CORE-INV-9 (v1).** Every `WorldT` variable is used at most once on each
  control-flow path (`IDR-WORLD-1`). `World` appears only in the root
  wrapper.
- **CORE-INV-10 (v1).** Every `StrT` value is a string literal or a variable,
  and `Prim` has no string-building operation (`PROF-HEAP-3`).

- **CORE-CHECK-1 (v0).** The pipeline runs `Core.Check` on first-order Core
  before `Emit`, and runs the full-Core subset of the checks after every
  earlier pass. A failure is an internal compiler error (`DIAG-ICE-1`),
  except where `HeapCheck` reports a user error first.
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
  | 4 | `Simplify` | v1 | the guaranteed eliminations (`ELIM-G-*`) |
  | 5 | `HeapCheck` | v1 | `PROF-HEAP-*`, with errors at source locations |
  | 6 | `Emit` | v0 | first-order Core → `idr` contract text ([08](08-idr-dialect.md)) |

  A v0 program has no lambdas or type parameters, so passes 3–5 leave it
  unchanged.
- **CORE-OPT-1 (v0).** The middle end performs only monomorphisation and the
  guaranteed eliminations. It MUST NOT add any other optimization:
  - first-order inlining;
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

- **CORE-DUMP-1 (v0).** `Core` has a deterministic text printer. The `.core`
  artifact (`FE-ART-1`) is the first-order Core that `Emit` receives. With
  `--directive dump-core`, the frontend also writes the Core after every
  pass (`DRV-DUMP-1`). The format is informative and may change without a
  contract change, but tests that match it must be updated in the same
  commit.
