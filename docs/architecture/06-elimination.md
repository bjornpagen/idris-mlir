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
  quantity-0 arguments that determine runtime types, and from v2 by the
  implementations it is passed (`FE-TR-6`), by position. Data types are
  instantiated the same way, so `Pair Int Char` becomes its own monomorphic
  `Data`.
- **ELIM-MONO-2 (v1).** Normalization after substitution uses Idris's
  normalizer, so type-level computation is done by Idris and never
  re-implemented.
- **ELIM-MONO-3 (v1).** Polymorphic recursion makes the set of instances
  infinite, as MLton notes for its own monomorphiser. An instantiation path
  on which the same definition recurs with a strictly larger key is rejected
  (`PROF-POLY-1`). A hard cap on instances per definition backs this up.
  `Frontend.Translate.request` records, for each instance, the chain of
  instances that requested it; a new instance of a definition on its own
  chain with a longer key is rejected, and so is a 65th instance of one
  definition.
- **ELIM-MONO-4 (v1).** An instance is named `<name>[<arg>,…]`, with the
  arguments in their normal forms printed by Idris. This is deterministic
  (`FE-DET-1`), and is mangled for MLIR by `IDR-FN-2`. Names are printed so
  that different names differ (a `DN` shows its underlying name, a case
  block its index), and two instances that still print alike are told
  apart by a suffix `'k`: instance names are injective. Arguments equal up
  to the names of their binders (`(x : a) -> b` and `a -> b`) name one
  instance: the first printed form is kept.

## The guaranteed eliminations (v1): `Simplify`

`Simplify` runs after `Mono`. It is an evaluator with two levels: it
evaluates full `Core` to a *static value* and emits first-order `Core` for
the runtime parts (Futhark's defunctionalisation judgment, written in
Kovács's code-generation monad). The rules below are what it does to each
construct. Each rule preserves the semantics of [03](03-semantics.md); the
reason is stated with each rule.

**Static values.** A *static value* is a value whose shape is known at
compile time. Following Futhark, it is one of:
- a closure: a lambda or a `Delay`, identified by its label
  ([05](05-middle-ir.md)), with the values it captured;
- a constructor of static data (data holding a function or `Lazy` value,
  such as `IO`), with its fields;
- a deferred call of a function whose result is static, with the
  eliminations applied to it so far (`ELIM-G-5`);
- a string known up to runtime characters, strings and numbers
  (`ELIM-G-6`, `ELIM-G-7`);
- a runtime value: an atom of first-order `Core`.

A known function applied to fewer arguments than its arity is a closure,
since the frontend eta-expands it. The runtime values inside a static value
are its *atoms*. Only its *shape*, the static value with its atoms left out,
is static.

- **ELIM-G-1 (v1). Beta.** `(\x => b) a` becomes `let x = a in b`. The `let` is
  strict, so `a` is still evaluated first (`SEM-EVAL-1`).
- **ELIM-G-2 (v1). Known constructor.** A match on a value built by a known
  constructor (directly, or through a `let`) becomes the selected
  alternative, with its fields bound to the constructor's arguments. This
  removes `MkIO`, `MkIORes`, `MkPair` and records of functions. From v3 a
  constructor of runtime data whose fields are all known stays a known
  value too (`True`, `Nothing`, an enumeration), and is built only where it
  must exist at runtime. A match on a runtime value of a type with one
  constructor is not a choice either: when its alternative yields a static
  value (an `IORes` holding a function, as the Prelude's `(*>)` for IO
  makes), the fields are read in place and the value is used where the
  match is, instead of being returned from a residual match.
  - Test: `tests/e2e/v3/prelude-traverse`
- **ELIM-G-3 (v1). Specialization on static arguments.** A call `f a₁ … aₙ`
  in which some argument is a static value becomes a call to a specialized
  copy of `f` for the shapes `σ` of its arguments:
  - the atoms of the arguments, in order, become its parameters;
  - inside the copy, the static arguments are known, so `ELIM-G-1` and
    `ELIM-G-2` apply.

  Copies are memoized by `(f, σ)`, and shapes are compared structurally:
  two closures are the same when their labels and captured shapes are. The
  `k`-th copy of `f` is named `f#k`; a call whose arguments are all runtime
  values calls `f` itself. This is Futhark's defunctionalisation by static
  values and Lean's `fixedHO` specialization. It never introduces a branch
  or a closure.
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
  - Moving is observable only when an effect (an IO primitive, or a call
    passed the world) happens between building an action and running it.
    So the rule applies to a raised function only if one of its actions is
    run after such an effect; an action run as soon as it is built, as in
    a `do` block, may move any code.
  - `Simplify` raises optimistically and records each operation it moves.
    Once every copy is made, it computes which functions satisfy the rule,
    as a greatest fixpoint (recursion between copies is why it must be the
    greatest), and checks the recorded operations against it.
- **ELIM-G-6 (v1). Compile-time evaluation of primitives.** A primitive applied
  to literal arguments becomes a literal (`SEM-INT-*`, `SEM-CHAR-*`,
  `SEM-STR-2`). The exception is a primitive that would crash, such as `div`
  by 0, which is left in place to crash at runtime. This turns
  `putStrLn "hello"` into one literal, `"hello\n"`: a string known at
  compile time is a static argument, so a function that receives it is
  specialized on its value (`ELIM-G-3`). From v3 this covers `strHead`,
  `strTail`, `strIndex` and `strSubstr` on literals too (the Prelude's
  `show` for `Char` and `String`, `unpack`, `length`), computed with the
  reference's own primitives, since the compiler runs on it; an empty
  string or an index out of range is left to fail at runtime as the
  reference does.
  - Test: `tests/e2e/v3/prelude-user-types`
- **ELIM-G-7 (v1). Output fusion.** When the argument of the `putStr`
  primitive (`prim__idrPutStr`) is not a literal, the call is rewritten by
  the first matching case, applied repeatedly:
  1. `putStr (a ++ b)` becomes `putStr a`, then `putStr b`, in the world
     chain;
  2. `putStr (strCons c s)` becomes `putChar c`, then `putStr s`;
  3. `putStr (cast_CharString c)` becomes `putChar c`;
  4. `putStr (cast_TString n)` becomes `idr.io.put_int n`, and from v2
     `putStr (cast_DoubleString x)` becomes `idr.io.put_double x`;
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

- **ELIM-G-15 (v3). What is known about a string built at runtime.** Two
  facts are used when a string has runtime pieces:
  - it is not `""` when one of its pieces is known not to be empty (a shown
    number, a character, a non-empty literal), which decides a match whose
    only literal alternative is `""`;
  - its first character is known when its first piece gives it: a literal's
    or a runtime character, or for an integer shown at runtime its sign or
    leading digit, which straight-line code computes by comparing with the
    powers of ten that fit the type.

  The Prelude's `show` for constructors uses both, to put `-5` in
  parentheses (`Just (-5)`). For a `Double` shown at runtime the first
  character depends on the shortest digits (the double nearest `1e23`
  prints as `1e23`), so it comes from the printer itself
  (`idr.double_head`, `LOW-DBL-4`).
  - Test: `tests/e2e/v3/show-values`
- **ELIM-G-17 (v3). Specialization on literals.** A specialization is keyed
  by the shapes of its arguments, and their atoms, literals included, become
  its parameters (`ELIM-G-3`). When that specialization cannot be built
  (its body would need a value that cannot exist at runtime, such as an
  `Integer` made from a `Char` in the Prelude's `show` for characters), and
  some atoms are literals, it is built again with those literals fixed, and
  keyed by them too. The first attempt is undone. A loop whose argument is
  a literal is still one specialization; only code that could not be
  compiled otherwise is specialized per literal.
  - Test: `tests/e2e/v3/prelude-user-types` (`printLn 'x'` twice)
- **ELIM-G-19 (v3). The driver.** Every call is decided by one driver,
  positive supercompilation's (Sørensen, Glück and Jones, JFP 1996):
  - **Drive.** A call is unfolded, evaluated where it is called with the
    values of its arguments, when it carries static information:
    - it is an Idris case or with block, or a library definition marked
      `%inline`;
    - its result is a `String`, which must reach `ELIM-G-6` or `ELIM-G-7`
      where it is used;
    - an argument has static structure (a closure, a constructor, a
      deferred call, a string, a choice);
    - every argument is known (no runtime variable occurs in it), so the
      call is evaluated at compile time, recursion included: `fib 15` is
      `610`, and a library's recursion over known values (`Nat` in `power`,
      Euclid's algorithm on `Integer`) costs nothing at runtime;
    - or a literal is in a position the body matches on (`ack 0 n`).

    Otherwise the call is residual: a call of the specialization for its
    shapes (`ELIM-G-3`, `ELIM-G-17`). A call unfolded only for a literal
    its body matches on is unfolded at most four times on one path, as
    call-pattern specialization is bounded; the fifth generalizes the
    innermost of them, so a loop counting down from a literal stays a loop
    instead of being unrolled. A deferred call (`ELIM-G-5`) is
    unfolded only if no effect happened between building it and applying
    it.
  - **Whistle.** A call's *configuration* is its function, its arguments'
    shapes with their literals, and its eliminations. Unfolding stops when
    the configuration of a call on the path of calls being unfolded or
    specialized *embeds* in the new one: homeomorphic embedding (Kruskal),
    with integer literals ordered by absolute value, strings by subsequence,
    characters by equality, and any double embedding any other: a loop that
    computes a new double each time never repeats one, so equality on
    doubles would not stop it. Every infinite sequence of configurations
    has one that embeds in a later one, so every path is finite (Leuschel,
    SAS 1998). The test is a dynamic program over pairs of subterms, so
    its cost is the product of the sizes.
  - **Generalization.** When the whistle blows on an ancestor being
    unfolded, the ancestor is generalized to the most specific
    generalization of the two configurations: equal literals stay, other
    atoms become runtime values. What the ancestor's unfolding did is
    undone and it becomes a call of the specialization for that
    generalization. When it blows on a specialization being made, the call
    calls the specialization for the generalization, often itself. A call
    whose shapes have no generalization (a static value that grows with
    each call) is rejected (`PROF-HEAP-4`), and so is one whose result has
    no runtime representation (`PROF-HEAP-1`, `PROF-HEAP-2`,
    `PROF-DATA-3`, `PROF-TYPE-4`), where the call is.
  - **Budget.** A bound on compile time and code size, not a termination
    argument:
    - a residual body may unfold 20000 calls that emit code;
    - it may unfold 20000 calls in a row without emitting code, which
      bounds a compile-time evaluation such as `fib 27`.

    An unfolding that emitted no code costs the body nothing. When either
    count is spent, the outermost unfolding of the function being called
    is generalized to its shapes and residualized.
  - *Why this is exact:* evaluation is strict (`SEM-EVAL-1`), so evaluating
    a body with the values of the arguments is the call; generalization
    only makes a specialization serve more calls.
  - Test: `tests/e2e/v3/static-evaluation`,
    `tests/e2e/v3/compile-time-evaluation`, `tests/e2e/v3/call-pattern`,
    `tests/e2e/v2/string-functions`, `tests/e2e/v2/math-showcase`,
    `tests/profile/v1/reject/PROF-HEAP-4-growing-function.idr`
- **ELIM-G-20 (v3). Choices.** A match on a runtime value whose
  alternatives yield static values of different shapes has their least
  upper bound as its value: where the shapes agree, their common shape;
  where they differ, a *choice*, a runtime `Int` tag saying which one. The
  match continues at a join point that takes the tag and the atoms of every
  alternative. An alternative passes undefined atoms (`ub.poison`) for the
  others, and erased atoms are never passed. A use of a choice (applying
  it, forcing it, matching on it, a primitive, `putStr`, reifying it)
  dispatches on the tag, with the use in each alternative. So a function, a
  `Lazy` value, a string or a list picked at runtime from a known set costs
  a tag and no heap; the match writes each alternative's output where it
  is (`ELIM-G-7`, as `maybe "none" show m` does); and a choice crosses a
  specialization as its tag and atoms.
  - *Why this is exact:* using the value of the chosen alternative is what
    using the match's value does, and the tag records which one was chosen.
  - Test: `tests/e2e/v3/choice`, `tests/e2e/v3/prelude`
- **ELIM-G-ORDER (v1). Termination and determinism.** Rules apply in one fixed
  traversal order: definitions in `FE-DET-1` order, terms outermost first.
  The result is a fixpoint. The rules that can grow the program are bounded:
  - `ELIM-G-3` by memoization;
  - `ELIM-G-4` by the number of uses;
  - `ELIM-G-5` at one application per function;
  - `ELIM-G-7` case 5 by the number of alternatives;
  - `ELIM-G-19` by the whistle, and its budget bounds compile time;
  - `ELIM-G-20` by the number of alternatives.

  Every other rule makes the program smaller. `ELIM-G-3` can diverge only
  when a recursive function passes itself a growing static value, which is
  reported as `PROF-HEAP-4`. A cap on copies per definition backs this up.
- **ELIM-G-SCOPE (v1).** `Simplify` applies only these rules. Everything else
  (CSE, dead code, general constant folding, and first-order inlining
  beyond `ELIM-G-19`) is MLIR's job (`CORE-OPT-1`).

`Simplify` enforces `PROF-HEAP-*` as it goes: a static value that would
have to exist at runtime (as a runtime argument, field, result or match
scrutinee) has no first-order representation, and is reported there. Each
rejection names the construct that survived, and the rule that could not
remove it, with the reason (`DIAG-HEAP-1`). A point Idris proved impossible
(`Unreachable`) makes the code that reaches it `Absurd` in first-order
`Core`.

## Withdrawn

- **ELIM-G-10.** *Withdrawn in v3:* unfolding string functions is a reason
  the driver unfolds a call (`ELIM-G-19`).
- **ELIM-G-11.** *Withdrawn in v3:* unfolding case and with blocks is a
  reason the driver unfolds a call (`ELIM-G-19`).
- **ELIM-G-12.** *Withdrawn in v3:* unfolding on known arguments is a
  reason the driver unfolds a call (`ELIM-G-19`).
- **ELIM-G-13.** *Withdrawn in v3:* library `%inline` is a reason the
  driver unfolds a call (`ELIM-G-19`).
- **ELIM-G-14.** *Withdrawn in v3:* a string join point is a choice
  (`ELIM-G-20`).
- **ELIM-G-16.** *Withdrawn in v3:* evaluation of known calls is the
  driver unfolding calls on known arguments, bounded by its budget
  (`ELIM-G-19`).
- **ELIM-G-18.** *Withdrawn in v3:* call-pattern specialization is the
  driver unfolding on a literal the body matches on, with the whistle's
  generalization keeping the literals that repeat (`ELIM-G-19`).

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
  - Check: review (no code reads `newtypeArg`)