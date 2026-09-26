# 05. The middle IR (`Core`)

`Core` is the Idris-side IR, evolved from today's `IdrisMLIR.IR`. It sits
between the frontend and MLIR emission. It exists for the transformations
that need Idris-level facts: monomorphisation (v1), defunctionalisation (v2),
and, later, proved rewrites. Everything else is MLIR's job
([09-optimization](09-optimization.md)).

## Shape (v0)

This is normative in content, not in exact Idris syntax:

```idris
data Quantity = Q0 | Q1 | QW
data IntTy    = IdrisInt | SInt8 | SInt16 | SInt32 | SInt64
              | UInt8 | UInt16 | UInt32 | UInt64
data Ty       = IntT IntTy | DataT Name | ErasedT

record Field  where quantity : Quantity; type : Ty
record Con    where name : Name; tag : Nat; fields : List Field; loc : FC
record Data   where name : Name; cons : List Con; loc : FC

data PrimOp   = Add | Sub | Mul | Div | Mod | And | Or | Xor
              | Lt | Lte | Eq | Gte | Gt | Cast IntTy

data Expr     = Var Var | Lit IntTy Integer | Erased
              | Prim PrimOp IntTy (List Expr)
              | Call Name (List Expr)
              | Con Name Name (List Expr)           -- data type, constructor
              | Let Var Quantity Ty Expr Expr
              | MatchCon Var (List ConAlt) (Maybe Expr)
              | MatchLit Var IntTy (List (Integer, Expr)) Expr
data ConAlt   = MkConAlt Name (List Var) Expr        -- constructor, bound fields

record Param  where var : Var; quantity : Quantity; type : Ty
record Fn     where name : Name; params : List Param; result : Ty
                    body : Expr; loc : FC
record Program where datas : List Data; fns : List Fn; root : Name
```

Every `Expr` node carries an `FC` (`FE-LOC-1`). `Name` is the Idris full
name.

## Invariants

`Core.Check` verifies these invariants.

- **CORE-INV-1 (v0).** Closed: a function body refers only to its parameters
  and to variables bound inside it. Variable names are unique within a
  function.
- **CORE-INV-2 (v0).** First order: every `Call` names a function in `fns`
  with exactly as many arguments as it has parameters. Every `Con` names a
  constructor of a data type in `datas`, with one argument per field.
- **CORE-INV-3 (v0).** Monomorphic and typed:
  - every runtime value has type `IntT` or `DataT`, and every `DataT` names
    an entry of `datas`;
  - every quantity-0 position (parameter, field, `let`, argument) has type
    `ErasedT`, and its argument expression is `Erased`.
- **CORE-INV-4 (v0).** Quantities are recorded on every parameter, field and
  `let`, exactly as the checked TT had them.
- **CORE-INV-5 (v0).** A quantity-0 variable is used only in quantity-0
  positions.
- **CORE-INV-6 (v0).** Matches:
  - The scrutinee of `MatchCon` is a variable of a `DataT`. Its alternatives
    name distinct constructors of that type.
  - The scrutinee of `MatchLit` is a variable of the matching `IntT`. Its
    literals are distinct and in range.
  - A `MatchCon` without a default covers every constructor.
- **CORE-INV-7 (v0).** `datas` satisfies `PROF-DATA-*`:
  - constructor tags are `0..n-1` in Idris tag order;
  - runtime containment is acyclic.
- **CORE-INV-8 (v0).** Every function in `fns` is reachable from `root`.

- **CORE-CHECK-1 (v0).** The pipeline runs `Core.Check` after the frontend
  and after every middle-end pass. A failure is an internal compiler error
  (`DIAG-ICE-1`), never a user error.
  - Test: `tests/compiler` unit tests on hand-built invalid `Core`

## Pass order

- **CORE-PASS-1.** The middle end runs these passes in this order. A pass
  that belongs to a later version is absent until that version. No other
  pass may be inserted without changing this rule.

  | # | Pass | Version | Purpose |
  | --- | --- | --- | --- |
  | 1 | `Frontend.Translate` | v0 | checked TT → `Core` |
  | 2 | `Rewrite` | reserved | proved rewrites ([07](07-proved-rewrites.md)); runs before specialization so that replacements get specialized |
  | 3 | `Mono` | v1 | monomorphisation ([06](06-elimination.md)) |
  | 4 | `Defunc` | v2 | defunctionalisation ([06](06-elimination.md)) |
  | 5 | `Emit` | v0 | `Core` → `idr` contract text ([08](08-idr-dialect.md)) |

- **CORE-OPT-1 (v0).** The middle end performs only transformations that need
  Idris-level facts. It MUST NOT implement optimizations that MLIR performs:
  - inlining;
  - constant folding;
  - CSE;
  - dead-code elimination;
  - case-of-known-constructor.

  *Rationale:* `GOAL-P1`. Duplicating them in Idris would hide from MLIR the
  structure its passes need, and would spread one optimization across two
  implementations.
- **CORE-ERASE-1 (v0).** `Core` keeps quantity-0 values as `Erased`. The
  former Idris-side `Erase` pass is removed. Erasure happens in MLIR lowering
  (`LOW-ERASE-1`).

## Dumps

- **CORE-DUMP-1 (v0).** `Core` has a deterministic text printer. Its output
  is the `.core` artifact (`FE-ART-1`). The format is informative and may
  change without a contract change, but tests that match it must be updated
  in the same commit.
