# 05. The Idris IR (`Core`)

`Core` is the Idris-side IR. It sits between the frontend and MLIR emission,
and exists for the work that needs Idris-level facts:
- monomorphisation ([06](06-elimination.md), `ELIM-MONO-*`);
- the representation of each data instance: an unboxed sum, a box, or a
  big (`IDR-DATA-4`, `IDR-IN-3`);
- the facts `Emit` writes into the contract: quantities, totality, loop
  breakers;
- later, proved rewrites.

Everything else is MLIR's job ([09-optimization](09-optimization.md)).

*Revised at the cutover:* `Core` is one language, full Core
(`IdrisMLIR.Term`). First-order Core (`IdrisMLIR.Code`), its join points,
its checker and `Simplify`, which produced it, are deleted. Abstraction
(closures, laziness, monadic plumbing, strings built at runtime) is no
longer removed in Idris: `Emit` writes full Core into the `idr` dialect as
it is, and MLIR removes it.

## Shape

This is normative in content, not in exact Idris syntax.

```idris
data Quantity = Q0 | Q1 | QW
data IntTy    = IdrisInt | SInt8 | SInt16 | SInt32 | SInt64
              | UInt8 | UInt16 | UInt32 | UInt64

-- One type language: every type exists at runtime, and MLIR removes
-- abstraction. A data instance records its representation where it is
-- declared; Nat-like types are BigT.
data Ty       = IntT IntTy | CharT | DoubleT | StrT | BigT | WorldT | ErasedT
              | DataT DataId
              | FunT Quantity Ty Ty
              | LazyT Ty
data Repr     = Sop | Box

data Lit      = LInt IntTy Integer | LChar Integer | LStr String
              | LDouble Double | LBig Integer
data Prim     = IntOp ArithOp IntTy | FloatOp FArith | Negate | Math MathFn
              | Compare Cmp Scalar | Cast Scalar Scalar
              | StrAppend | StrCons | StrLength | StrHead | StrTail | StrIndex
              | StrReverse | StrSubstr | StrCompare Cmp | ...  -- shows and reads
              | BigArith ArithOp | BigNegate | BigCompare Cmp
              | ToBig Scalar | FromBig Scalar | BigShow | BigRead
data IOOp     = PutStr | PutChar | ...

-- Full Core: a nested datatype (Bird and Paterson, "de Bruijn notation as
-- a nested datatype", JFP 1999). Its free variables have type `a`; a
-- binder of k variables holds a `Term (Under k a)`.
data Under : Nat -> Type -> Type where
  Bound : Fin k -> Under k a
  Free  : a -> Under k a

data Term : Type -> Type where
  Var         : Loc -> a -> Term a
  Literal     : Loc -> Lit -> Term a
  Erased      : Loc -> Term a
  PrimApp     : Loc -> Prim -> List (Term a) -> Term a
  Effect      : Loc -> IOOp -> List (Term a) -> DataId -> Term a -- PROF-IO-4
  Call        : Loc -> FnId -> List (Term a) -> Term a           -- saturated
  ConApp      : Loc -> ConId -> List (Term a) -> Term a          -- fields only
  Let         : Loc -> Quantity -> Term a -> Term (Under 1 a) -> Term a
  Case        : Loc -> a -> List (Alt a) -> Maybe (Term a) -> Term a
  CaseLit     : Loc -> a -> List (Lit, Term a) -> Term a -> Term a
  Lam         : Loc -> Label -> Vect k a -> Binder -> Term (Under 1 (Fin k)) -> Term a
  App         : Loc -> Term a -> Term a -> Term a
  Suspend     : Loc -> Label -> Vect k a -> Term (Fin k) -> Term a  -- Delay
  Resume      : Loc -> Term a -> Term a                             -- Force
  Unreachable : Loc -> Term a                                       -- SEM-DATA-2
  Crash       : Loc -> String -> Term a                             -- SEM-CRASH-2
data Alt a    = MkAlt ConId (Vect k Binder) (Term (Under k a))
```

- Every node carries its source location (`FE-LOC-1`), and every location
  the origin the registry gave its module ([17-registry](17-registry.md)),
  so no pass reads a namespace.
- `FnId`, `DataId`, `ConId` and `Label` are distinct types. A `FnId` is an
  Idris full name or an instance name (`ELIM-MONO-4`). The Idris name of a
  function or data type is `Shown`: it can be printed, not compared.
- **Scoping is by type.** A closed term is a `Term Void`, and a function's
  body is a `Term (Fin arity)`, parameter `i` being `i`, as in Idris's case
  trees. An unbound variable is a type error, so no check looks for one.
  An alternative binds its constructor's fields: field `i` is `Bound i`.
- **Derived traversals.** Renaming is the derived `Functor`, the free
  variables are the derived `Foldable`, and strengthening is the derived
  `Traversable`, from base's `Deriving.*`. Every other traversal (emission,
  printing, the facts) is a fold over the base functor `TermF`: `cata`, or
  `para` where the algebra needs a part as it was.
- **Closures.** A lambda and a `Delay` are closure-converted when they are
  built: each has a `Label` (its program point, unique in the program),
  the variables it captures, and a body closed over exactly those. `Emit`
  lifts each into a private function whose leading parameters are the
  captures (`IDR-FN-1`).
- **`let` has no type**: TTC does not keep let types (`FE-TR-1`), and `Emit`
  synthesizes them.
- **Representations.** A data instance records its representation once,
  where it is declared: `Sop` (an unboxed sum, including data holding
  closures) or `Box` (a recursive instance: its containment is cyclic).
  An instance whose constructors Idris flags `ZERO`/`SUCC` is no data at
  all: it is `BigT`.
- A function carries its facts, each with its provenance
  (`IdrisMLIR.Facts`): today, whether it terminates, read from Idris's
  totality checker. It becomes `idr.total` (`IDR-FACT-1`).

## Invariants

- **CORE-INV-1.** *Withdrawn at the cutover*, with first-order Core:
  closedness and unique names. Full Core is scoped by its type, and in
  MLIR SSA dominance holds, which the verifier checks.
- **CORE-INV-2.** *Withdrawn at the cutover:* first order and arities. MLIR
  checks arities: the symbol verifier of `func.call`, and the verifiers of
  `idr.con` (one operand per field), `idr.closure` and `idr.apply`
  (`IDR-CON-1`, `IDR-CLOS-1`).
- **CORE-INV-3.** *Withdrawn at the cutover:* monomorphic and typed code,
  and erased positions. These are MLIR's types; `idr.ctor` quantities
  match `!idr.erased` fields (`IDR-DATA-2`), and the argument attribute
  verifier checks each `idr.quantity` against its type (`IDR-FN-1`).
- **CORE-INV-4.** *Withdrawn at the cutover:* quantities recorded on every
  binder. `Emit` writes them into the contract (`IDR-FN-1`, `IDR-DATA-2`).
- **CORE-INV-5.** *Withdrawn at the cutover:* quantity-0 values only in
  quantity-0 positions. An `!idr.erased` value can flow only to erased
  positions, by its type.
- **CORE-INV-6.** *Withdrawn at the cutover:* the shape of matches. The
  verifiers of `idr.match` (distinct constructors of the scrutinee's type,
  a region's arguments are its constructor's fields) and `idr.match_lit`
  (distinct literals of the scrutinee's type) check it (`IDR-MATCH-5`,
  `IDR-MATCH-6`).
- **CORE-INV-7.** *Withdrawn at the cutover:* tags and acyclic data. They
  are `IDR-DATA-2` and `IDR-DATA-4`, as revised.
- **CORE-INV-8.** *Withdrawn at the cutover:* every function reachable from
  the root. `symbol-dce` makes it true, and nothing depends on it.
- **CORE-INV-9.** *Withdrawn at the cutover:* world linearity. It is
  `IDR-WORLD-1`, a verifier aware of regions.
- **CORE-INV-10.** *Withdrawn at the cutover:* strings are literals. A
  string built at runtime is a value of the contract, and the heap-free
  profile rejects one that survives (`PROF-HEAP-3`).
- **CORE-INV-11.** *Withdrawn at the cutover:* join points. There are none;
  control flow is regions.
- **CORE-CHECK-1.** *Withdrawn at the cutover:* `Term.Check` and
  `Code.Check` checked full and first-order Core. Full Core's scoping is
  its type, and MLIR verifies everything else: `mlir::verify` runs when
  `idris-mlir-cc` parses the module and after every pass, and a failure is
  an internal error (`DIAG-ICE-1`).

## Pass order

- **CORE-PASS-1.** The Idris side runs these passes in this order. A pass of
  a later version is absent until that version. No other pass may be
  inserted without changing this rule.

  | # | Pass | Version | Purpose |
  | --- | --- | --- | --- |
  | 1 | `Frontend.Translate` | v0 | checked TT → full Core, monomorphic (`ELIM-MONO-*`, fused), with each instance's representation |
  | 2 | `Rewrite` | reserved | proved rewrites ([07](07-proved-rewrites.md)); before specialization, so that replacements get specialized |
  | 3 | `Emit` | v0 | full Core → `idr` contract text ([08](08-idr-dialect.md)), with loop breakers (`OPT-PIPE-3`) |

  `Mono` is fused into `Frontend.Translate`: instances are requested on
  demand while translating, keyed by their type arguments (`ELIM-MONO-1`),
  so full `Core` is already monomorphic. *Revised at the cutover:*
  `Simplify` (the guaranteed eliminations and `PROF-HEAP-*`) and
  `Code.Loops` (`CORE-LOOP-1`) are deleted. The heap-free rules are checked
  in MLIR (`PROF-GEN-3`).
- **CORE-LOOP-1.** *Withdrawn from this document at the cutover:* a self
  tail call became a join point of first-order Core. Loops are made in
  MLIR, by `idr-tail-loops` (`LOW-TAIL-5`).
- **CORE-OPT-1.** *Withdrawn at the cutover:* the middle end performed only
  monomorphisation and the guaranteed eliminations. It now performs no
  optimization at all: `Emit` writes what `Translate` produced, and every
  optimization is MLIR's or LLVM's (`GOAL-P1`, [09](09-optimization.md)).
- **CORE-ERASE-1 (v0).** `Core` keeps quantity-0 values as `Erased`.
  Erasure happens in MLIR lowering (`LOW-ERASE-1`).

## Dumps

- **CORE-DUMP-1 (v0).** `Core` has a deterministic text printer. The `.core`
  artifact (`FE-ART-1`) is full Core after `Translate`, the Core that
  `Emit` receives. With `--directive dump-core`, the frontend also writes it
  as `01-translate.core` (`DRV-DUMP-1`). Variables print as de Bruijn
  indices (`#0` is the innermost). *Revised at the cutover:* there is one
  printer, for full Core; `02-simplify.core` is gone, and what the program
  becomes after that is MLIR, dumped by `idris-mlir-cc --dump-after`.
  - Test: every e2e fixture checks the `.core` artifact exists;
    `tests/registry/FE-TR-7-identity-hook` matches `01-translate.core`. The
    format is informative and may change without a contract change, but
    tests that match it must be updated in the same commit.
