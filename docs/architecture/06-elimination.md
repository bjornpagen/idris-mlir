# 06. Eliminating abstraction

The middle end removes source-level abstraction before MLIR sees the
program, following MLton and Futhark. What reaches the `idr` dialect is
first-order and monomorphic, with no closures, no thunks, no monadic
plumbing, and no runtime-built strings (`GOAL-P2`).

The eliminations are a fixed list, applied deterministically. A program is
accepted exactly when they remove everything `PROF-HEAP-*` forbids, so
acceptance is a rule, not optimizer luck.

## Erasure

- **ELIM-ERASE-1 (v0).** Quantity-0 values are kept as `Erased` in `Core` and
  as `!idr.erased` in the contract. They are removed only by the 1:0 type
  conversion in `idr-lower` (`LOW-ERASE-1`). No stage before `idr-lower` drops
  an erased parameter, argument or field.
- **ELIM-ERASE-2 (v0).** Definitions reachable only at compile time (types,
  proofs) are not translated. They stay available in `Defs` throughout
  compilation, for checks (`PROF-ESC-1`) and for proved rewrites later
  (`RW-DAY1-2`).
- **ELIM-ERASE-3 (v0).** Only quantity-0 positions are erased. Idris's extra
  collapsibility analysis (`safeErase`, `detagabbleBy`) is not used
  (`FE-IN-4`).

## Monomorphisation (v1)

- **ELIM-MONO-1 (v1).** Instances are created on demand from the root. An
  instance is keyed by the definition and the normal forms of those
  quantity-0 arguments that determine runtime types. Data types are
  instantiated the same way, so `Pair Int Char` becomes its own monomorphic
  `Data`.
- **ELIM-MONO-2 (v1).** Normalization after substitution uses Idris's
  normalizer, so type-level computation is done by Idris and never
  re-implemented.
- **ELIM-MONO-3 (v1).** Polymorphic recursion makes the set of instances
  infinite, as MLton notes for its own monomorphiser. An instantiation path
  on which the same definition recurs with a strictly larger key is rejected
  (`PROF-POLY-1`). A hard cap on instances per definition backs this up.
- **ELIM-MONO-4 (v1).** An instance is named `<name>[<arg>,…]`, with the
  arguments in their normal forms printed by Idris. This is deterministic
  (`FE-DET-1`), and is mangled for MLIR by `IDR-FN-2`.

## The guaranteed eliminations (v1): `Simplify`

`Simplify` runs after `Mono`. It applies the rules below until none applies.
Each rule preserves the semantics of [03](03-semantics.md); the reason is
stated with each rule.

**Static values.** A *static value* is a value whose shape is known at
compile time. Following Futhark, it is one of:
- a lambda;
- a known function applied to fewer arguments than its arity;
- a `Delay`;
- a constructor application with a static value in some field;
- a variable bound to any of these.

The captured variables of a static value are ordinary runtime values. Only
the shape is static.

- **ELIM-G-1 (v1). Beta.** `(\x => b) a` becomes `let x = a in b`. The `let` is
  strict, so `a` is still evaluated first (`SEM-EVAL-1`).
- **ELIM-G-2 (v1). Known constructor.** A match on a value built by a known
  constructor (directly, or through a `let`) becomes the selected
  alternative, with its fields bound to the constructor's arguments. This
  removes `MkIO`, `MkIORes`, `MkPair` and records of functions.
- **ELIM-G-3 (v1). Specialization on static arguments.** A call `f a₁ … aₙ`
  in which some argument is a static value becomes a call to a specialized
  copy `f{σ}`:
  - `σ` records each static argument's shape;
  - the captured variables become extra parameters;
  - inside `f{σ}`, the static argument is known, so `ELIM-G-1` and
    `ELIM-G-2` apply.

  Copies are memoized by `(f, σ)`. This is Futhark's defunctionalisation by
  static values and Lean's `fixedHO` specialization. It never introduces a
  branch or a closure.
- **ELIM-G-4 (v1). Static let.** `let k = v in body`, where `v` is a static
  value, substitutes `v` into `body` and removes the binding. Copying a
  static value copies only its shape; its captured variables are already
  evaluated.
- **ELIM-G-5 (v1). Arity raising.** A function `f` whose result is a function
  (after monomorphisation) gets that function's parameter as an extra
  parameter: `f args` applied to `y` becomes `f' args y`. For this rule, a
  value of a single-constructor type with exactly one runtime field of
  function type (such as `IO a = MkIO (PrimIO a)`) counts as that function.
  So every IO-returning function takes the world as a parameter and returns
  `IORes a`, and every state-monad function takes the state.
  - Raising moves the code that computes the lambda (the *prefix*) from where
    the action is built to where it is run. The prefix may contain only
    code that cannot crash and cannot fail to terminate:
    - primitives other than `div` and `mod` by a divisor not known to be
      nonzero;
    - constructor applications;
    - `let` and `case`;
    - calls to functions that Idris's checker reports total and whose bodies
      satisfy this rule transitively.
  - Otherwise `f` is not raised. Its result survives as a function value and
    is reported as `PROF-HEAP-5`. This is what keeps raising within
    `SEM-EVAL-4` and `SEM-EVAL-5`: moving a crash from build time to run time
    could otherwise reorder it relative to output.
- **ELIM-G-6 (v1). Compile-time evaluation of primitives.** A primitive applied
  to literal arguments becomes a literal (`SEM-INT-*`, `SEM-CHAR-*`,
  `SEM-STR-2`). The exception is a primitive that would crash, such as `div`
  by 0, which is left in place to crash at runtime. This turns
  `putStrLn "hello"` into one literal, `"hello\n"`.
- **ELIM-G-7 (v1). Output fusion.** When the argument of the `putStr`
  primitive (`prim__idrPutStr`) is not a literal, the call is rewritten by
  the first matching case, applied repeatedly:
  1. `putStr (a ++ b)` becomes `putStr a`, then `putStr b`, in the world
     chain;
  2. `putStr (strCons c s)` becomes `putChar c`, then `putStr s`;
  3. `putStr (cast_CharString c)` becomes `putChar c`;
  4. `putStr (cast_TString n)` becomes `idr.io.put_int n`;
  5. `putStr (case x of alts)` becomes `case x of alts'`, with the `putStr`
     moved into each alternative.

  *Why this is exact:* the UTF-8 encoding of a concatenation is the
  concatenation of the encodings (`SEM-IO-2`). The case scrutinee is still
  evaluated before any output of this call.
- **ELIM-G-8 (v1). Force of Delay.** `Force (Delay e)` becomes `e`
  (`SEM-LAZY-1`). Together with `ELIM-G-3` and `ELIM-G-4`, this removes the
  `Lazy` in `>>` and in every other known use.
- **ELIM-G-9 (v1). Dead static values.** A static value that is never used is
  removed. Building a static value has no effect.

- **ELIM-G-ORDER (v1). Termination and determinism.** Rules apply in one fixed
  traversal order: definitions in `FE-DET-1` order, terms outermost first.
  The result is a fixpoint. The rules that can grow the program are bounded:
  - `ELIM-G-3` by memoization;
  - `ELIM-G-4` by the number of uses;
  - `ELIM-G-5` at one application per function;
  - `ELIM-G-7` case 5 by the number of alternatives.

  Every other rule makes the program smaller. `ELIM-G-3` can diverge only
  when a recursive function passes itself a growing static value, which is
  reported as `PROF-HEAP-4`. A cap on copies per definition backs this up.
- **ELIM-G-SCOPE (v1).** `Simplify` applies only these rules. Everything else
  (first-order inlining, CSE, dead code, general constant folding) is MLIR's
  job (`CORE-OPT-1`).

After `Simplify`, `Core.HeapCheck` enforces `PROF-HEAP-*`. Each rejection
names the construct that survived, and the rule that could not remove it,
with the reason (`DIAG-HEAP-1`).

## Withdrawn

- **ELIM-DEFUNC-1.** *Withdrawn in draft 2:* superseded by `ELIM-G-3` and
  `PROF-HEAP-4`.
- **ELIM-DEFUNC-2.** *Withdrawn in draft 2:* superseded by `ELIM-G-3`.
- **ELIM-DEFUNC-3.** *Withdrawn in draft 2:* dictionaries are records of
  static values, so `ELIM-G-2` and `ELIM-G-3` remove them. Interfaces arrive
  in v2 without new machinery.

## Forcing, detagging, collapsing (later)

Source: Brady, McBride, McKinna, "Inductive families need not store their
indices" (TYPES 2003).

- **ELIM-FORCE-1 (reserved).** Constructor arguments determined by indices, and
  constructors determined by an index, are removed from the runtime layout.
  The frontend decides this from TT, where the index relationships live, and
  records it as a fact. C++ never infers it.
- **ELIM-FORCE-2 (v0).** Idris's `newtypeArg` and its Nat-to-Integer
  optimization are not used. Single-constructor types already lose their tag
  in lowering (`LOW-DATA-1`), and `Nat` is not a runtime type.
