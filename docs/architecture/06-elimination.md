# 06. Eliminating abstraction

Source-level abstraction (polymorphism, closures, laziness, monadic
plumbing, strings built only to be written) costs nothing in a compiled
profile program. Monomorphisation happens in Idris, where types are.
*Revised at the cutover:* everything else happens in MLIR, on the `idr`
dialect, by upstream passes and ours, run to a fixpoint (`OPT-PIPE-5`),
following MLton, Futhark and Lean. Before, one Idris pass, `Simplify`,
did it all, as a supercompiler over full Core, and MLIR received
first-order code.

What the heap-free profile accepts is decided by the documented pipeline
with its parameters fixed (`PROF-GEN-5`): a program is accepted exactly
when no dynamic allocation survives it (`PROF-HEAP-*`), so acceptance is a
rule, not optimizer luck.

Each rule below keeps the identifier it had, with its new owner. Each
preserves the semantics of [03](03-semantics.md); the reason is stated
with the rule.

## Erasure

- **ELIM-ERASE-1 (v0).** Quantity-0 values are kept as `Erased` in `Core`
  and as `!idr.erased` in the contract. No pass reads an erased value or
  treats it as a constant. They are removed by the 1:0 type conversion in
  `idr-lower` (`LOW-ERASE-1`); before that, `remove-dead-values` may drop
  an erased parameter that no one uses, like any other.
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

## The eliminations, in MLIR

What `Simplify` called a *static value* is now a *constant-like* value: an
`idr.constant`, or an `idr.con` or `idr.closure` whose operands are
constant-like or runtime values. Its *static part* is the value with its
runtime operands left out, and those operands are its *runtime leaves*.

- **ELIM-G-1 (v1). Beta.** `(\x => b) a` computes `b` with `x` bound to `a`.
  *Owner since the cutover:* `idr.apply` of an `idr.closure @f(caps)`, or
  of a constant closure, canonicalizes to `func.call @f(caps…, a…)`, and
  `inline` inlines the call (`IDR-CLOS-1`). The arguments are still
  evaluated first, since they are SSA values (`SEM-EVAL-1`).
  - Test: `tests/e2e/v1/ELIM-G-1-beta`, `tests/idr/canon/apply.mlir`
- **ELIM-G-2 (v1). Known constructor.** A match on a value built by a known
  constructor becomes the selected alternative, with its fields bound to
  the constructor's arguments. This removes `MkIO`, `MkIORes`, `MkPair`
  and records of functions. *Owner since the cutover:* `idr.field` and
  `idr.tag` fold on an `idr.con` or a constant, and an `idr.match` on
  either is replaced by its region, as is a match with one region left
  (`IDR-MATCH-5`); `canonicalize` runs them, inside the inliner and on its
  own.
  - Test: `tests/e2e/v1/ELIM-G-2-known-constructor`,
    `tests/idr/canon/match-known.mlir`, `tests/idr/fold/data.mlir`
- **ELIM-G-3 (v1). Specialization on static arguments.** A call in which
  some argument is constant-like calls a clone of the callee specialized
  for the argument's static part, whose parameters are the runtime leaves;
  inside the clone, the static part is known, so `ELIM-G-1` and `ELIM-G-2`
  apply. This is Futhark's defunctionalisation by static values and Lean's
  `fixedHO` specialization; it never introduces a branch or a closure.
  *Owner since the cutover:* `idr-specialize` (`ELIM-SPEC-1`).
  - Test: `tests/e2e/v1/ELIM-G-3-specialization`
- **ELIM-G-4 (v1). Static let.** A `let` of a constant-like value is known
  where it is used. *Owner since the cutover:* `Emit` writes a `let` as an
  SSA value, so every use sees its definition, and `sccp` propagates
  constants through calls and regions.
  - Test: `tests/e2e/v1/ELIM-G-4-static-let`, `tests/idr/fold/sccp.mlir`
- **ELIM-G-5 (v3). A call's consumer moves into the callee.** When the
  result of a call has a single consumer of one of these kinds, the call
  and the consumer become one call of a clone of the callee that
  consumes, at each of its tails, what it would have returned:
  - **an apply** (*arity raising*): `idr.apply` of the result, or of one
    field of it (an IO action is `MkIO f`). The clone also takes the
    apply's arguments and returns what the apply returns. This removes the
    closure of an action built at runtime and run at once: a loop breaker
    `echo$lam0 : Char -> IO ()` that returns an action over its runtime
    character, which its only caller runs.
  - **output**: `idr.io.put_str` of the result (a string). The clone also
    takes the world, writes at each tail what the callee would return, and
    returns the next world. This removes a string built at runtime only to
    be written: a recursive `show` writes its pieces instead.

  A tail is the operand of the clone's return and, through each match
  whose result reaches the return and has no other use, the yields of its
  regions. There the consumer usually meets what the body built: an apply
  meets an `idr.con` or `idr.closure` (`ELIM-G-2`, `ELIM-G-1`), and output
  meets a string builder (`ELIM-G-7`), which canonicalization reduces.
  *Revived at the cutover, in MLIR:* before, `Simplify` raised the arity
  of Core definitions, moving the code that computed an action from where
  it was built to where it was run, which `PROF-HEAP-5` had to police. Now
  only a call moves, and only to a consumer that follows it.
  - **Where.** A step of `idr-specialize`, which raises each call before
    it specializes it, so that the raised call, which now takes the world
    or the apply's arguments, is specialized in the same run.
  - **The key** is the callee and the consumer: an apply with no
    projection, an apply of a field (the constructor and the index), or
    output. Calls with equal keys share one clone, also across rounds (the
    key is kept in `idr.spec_key` as `raise @f`, `raise @f[@C, i]` or
    `write @f`). A call of the callee inside the clone whose result is
    consumed the same way calls the clone itself: once inlining exposes
    the call that an IO loop makes when its action runs, or output fusion
    the call that a recursive `show` appends, the recursion is a self
    call, which `idr-tail-loops` makes a loop when it is a tail call
    (`LOW-TAIL-5`).
  - **The clone** has the callee's parameters, then the apply's arguments
    or the world, with `idr.quantity` from their types (`"1"` for the
    world, which each path of the clone uses once, `IDR-FN-1`,
    `IDR-WORLD-1`). It is private, named `@<origin>$raise$<n>` or
    `@<origin>$write$<n>`, numbered with the other clones of its origin in
    order of first request (`FE-DET-1`), counted against the clone limit
    (`ELIM-SPEC-2`), and inherits `no_inline` from a loop breaker
    (`OPT-PIPE-3`). Its parameters are not its callee's, so it is the
    origin of its own specializations (`ELIM-SPEC-1`). A clone that applies has `idr.total` when its callee
    has it and every tail applies a known closure of a function that has
    it, and is pure and may crash as its callee and those functions are; a
    clone that writes is total and may crash as its callee, and is
    effectful (`IDR-FACT-1`).
  - **When.** The consumer, and the projection, are in the call's block,
    and either every op between the call and the consumer is free of
    memory effects, or the callee is pure and total and cannot crash. The
    callee takes no world. A closed call of a pure, total callee is not
    raised: it is evaluated (`ELIM-EVAL-1`, `SEM-EVAL-6`), and its
    consumer then folds.
  - *Why this is exact:* the clone runs the callee's body and then the
    consumer, as the call and the consumer did. Raising moves the body
    only past the ops between them, which have no effect, cannot crash and
    always terminate (a crash is an effect, `IDR-EFF-1`), or else the body
    itself cannot be observed; so no crash or divergence moves past an
    effect (`SEM-EVAL-4`), output stays in the world's order, and each
    operand is still evaluated once, at the call or at the consumer.
  - Check: the pass `idr-specialize`
  - Test: `tests/idr/raise/`, `tests/e2e/v1/ELIM-G-5-arity-raising`,
    `tests/e2e/v1/echo`, `tests/e2e/v3/show-values`
- **ELIM-G-6 (v1). Compile-time evaluation of primitives.** A primitive
  applied to constants becomes a constant, except where it would crash,
  which is left to crash at runtime. *Owner since the cutover:* folders.
  Upstream folds `arith` and `math`; the dialect folds `idr.div`,
  `idr.mod`, `idr.to_char`, `idr.to_int`, `idr.str.*` and `idr.big.*`, the
  last two through the runtime's own functions (`LOW-RT-1`). A call of
  constants is `idr-eval`'s (`ELIM-EVAL-1`).
  - Test: `tests/e2e/v1/ELIM-G-6-compile-time`,
    `tests/e2e/v3/prelude-user-types`
- **ELIM-G-7 (v1). Output fusion.** When the argument of `putStr` (the
  Prelude's `prim__putStr`) is built from pieces, the call writes the
  pieces in order instead, applied repeatedly:
  1. `putStr (a ++ b)` becomes `putStr a`, then `putStr b`, in the world
     chain;
  2. `putStr (strCons c s)` becomes `putChar c`, then `putStr s`;
  3. `putStr (cast_CharString c)` becomes `putChar c`;
  4. `putStr (cast_TString n)` becomes `idr.io.put_int n`, and from v2
     `putStr (cast_DoubleString x)` becomes `idr.io.put_double x`;
  5. `putStr (case x of alts)` becomes `case x of alts'`, with the `putStr`
     moved into each alternative.

  *Owner since the cutover:* cases 1 to 4 are DRR canonicalizations of
  `idr.io.put_str` (`IDR-IO-1`); case 5 is case-of-case, a canonicalization
  of `idr.match` (`IDR-MATCH-5`).
  *Why this is exact:* the UTF-8 encoding of a concatenation is the
  concatenation of the encodings (`SEM-IO-2`). The case scrutinee is still
  evaluated before any output of this call.
  - Test: `tests/e2e/v1/ELIM-G-7-output-fusion`,
    `tests/idr/canon/output-fusion.mlir`, `tests/idr/canon/case-of-case.mlir`
- **ELIM-G-8 (v1). Force of Delay.** `Force (Delay e)` becomes `e`
  (`SEM-LAZY-1`). *Owner since the cutover:* a `Lazy` value is a closure of
  no arguments, so this is `ELIM-G-1` with no arguments.
  - Test: `tests/e2e/v1/ELIM-G-8-force-delay`, `tests/idr/canon/apply.mlir`
- **ELIM-G-9 (v1). Dead static values.** A constant-like value that is
  never used is removed: building it has no effect. *Owner since the
  cutover:* upstream dead-code elimination. `idr.closure` and an unboxed
  `idr.con` are `Pure`, and a box's `idr.con` allocates only its own
  result, which MLIR ignores when it decides that an op is dead.
  - Test: `tests/e2e/v1/ELIM-G-9-dead-static`, `tests/idr/effects/alloc.mlir`
- **ELIM-G-15 (v3). What is known about a string built at runtime.** Two
  facts are used when a string has runtime pieces:
  - it is not `""` when one of its pieces is known not to be empty (a shown
    number, a character, a non-empty literal), which decides a match whose
    only literal alternative is `""`;
  - its first character is known when its first piece gives it: a
    literal's or a runtime character, or for a number shown at runtime
    what the printer writes first.

  The Prelude's `show` for constructors uses both, to put `-5` in
  parentheses (`Just (-5)`). *Owner since the cutover:* canonicalizations
  of `idr.str.head` and `idr.match_lit` (`IDR-STR-2`, `IDR-MATCH-6`), with
  `idr.int_head` and `idr.double_head` (`IDR-DBL-3`, `LOW-DBL-4`).
  - Test: `tests/e2e/v3/show-values`, `tests/idr/canon/head.mlir`,
    `tests/idr/canon/match-lit-string.mlir`
- **ELIM-G-17.** *Withdrawn at the cutover:* specialization per literal
  rebuilt a specialization with its literals fixed when its body needed a
  value that could not exist at runtime (an `Integer` made from a `Char`
  in the Prelude's `show` for characters). Every such value now has a
  representation, so the cause is gone.
- **ELIM-G-19.** *Withdrawn at the cutover:* one driver, positive
  supercompilation with a whistle, generalization and a budget, decided
  every call: it unfolded, evaluated or specialized it. Its parts are now
  separate, each with its own rule: unfolding is upstream `inline` with no
  size threshold (`OPT-PIPE-5`); a residual call on a static argument is
  `idr-specialize` (`ELIM-SPEC-1`), bounded by the clone limit
  (`ELIM-SPEC-2`) instead of the whistle; evaluation is `idr-eval`
  (`ELIM-EVAL-1`), on total code only (`SEM-EVAL-6`), with no budget. A
  literal in a matched position (`ack 0 n`) is specialization on a
  constant, without the bound of four unfoldings.
- **ELIM-G-20.** *Withdrawn at the cutover:* a match whose alternatives
  yielded static values of different shapes had a *choice* as its value,
  a runtime tag with the atoms of every alternative. A value picked at
  runtime is now an ordinary value: data built from constants is a
  constant in each region, a closure is defunctionalized
  (`ELIM-CLOS-1`), and a use that folds against the alternatives moves
  into them by case-of-case (`IDR-MATCH-5`), which is what choices did for
  consumers (`putStr (maybe "none" show m)`).

### Specialization

- **ELIM-SPEC-1 (v3). `idr-specialize`.** A `func.call` of a function with
  a body, one of whose arguments is constant-like and not a runtime value,
  calls a clone of the callee instead.
  - **The key** is the callee and the static parts of the arguments, with
    each runtime leaf a hole (`#idr.hole`, internal to the pass). Calls with
    equal keys share one clone. *Constant-like includes partially static
    values*: a list with one runtime element, `Just n`, or a closure with a
    runtime capture is specialized on its shape, and its runtime leaves
    become the clone's parameters, in order.
  - **The clone** is the callee with the static parts substituted, so
    `ELIM-G-1` and `ELIM-G-2` apply inside it. It is private, is named after
    its callee and numbered in order of first request (`FE-DET-1`),
    inherits `no_inline` from a loop breaker (`OPT-PIPE-3`), and has
    `idr.total` when its callee and every function named in its key have
    it (`IDR-FACT-1`).
  - **A closed call is never specialized**, where every argument is a
    constant, erased or a world. It is evaluated when its callee is total
    and pure (`ELIM-EVAL-1`), and otherwise left as it is: specializing a
    partial function on constants would unroll it one clone at a time,
    which is evaluation under another name, bounded only by the clone
    limit (`SEM-EVAL-6`). The world carries no value to specialize around:
    an IO loop called with a literal, whose call raising gave the world
    (`ELIM-G-5`), stays a loop.
  - *Why this is exact:* a clone computes what its callee computes on
    arguments of that shape; specialization never duplicates an effect or
    a crash, since the arguments are evaluated once, at the call.
  - Check: the pass `idr-specialize`
- **ELIM-SPEC-2 (v3). Growth and the clone limit.** A clone that calls its
  own origin with static arguments that grow is not specialized further:
  each argument's pattern is the clone's own or contains it, and one
  strictly (`iter (\y => f (f y))`). Such a specialization would never end.
  Beyond that, `idr-specialize` makes at most `N` clones of one original
  callee in a compilation, `N` being `idris-mlir-cc --clone-limit=N`
  (default 4096), which bounds growth in other shapes. A call either stops
  stays a call of the function it called, with a `Missed` remark naming the
  reason, and both get `idr.spec_stopped`. A closure that then survives is
  a `PROF-HEAP-4` rejection. Both bounds stop only specializations that
  would not end, so acceptance depends on neither for any program
  `PROF-HEAP-4` does not name.
  - Check: the pass `idr-specialize`

### Evaluation

- **ELIM-EVAL-1 (v3). `idr-eval`.** Every closed call that `SEM-EVAL-6`
  allows is replaced by its results, as constants.
  - **What is evaluated**: a `func.call`, or an `idr.apply` of a constant
    closure, whose operands are all constants; its callee is pure and has
    `idr.total`, and so does every function a closure in its operands
    names, recursively through captures and fields.
  - **One compile per round.** The pass collects every such call of the
    module, and clones the callees' transitive closure into one scratch
    module. For each call it adds a wrapper that materializes the arguments
    as static data, calls the callee, and stores the flattened results. The
    scratch module is lowered by the executable's own `idr-lower`, in JIT
    mode (`LOW-JIT-1`), and LLVM pipeline, then compiled once by ORC's
    `LLJIT` (`PINS.md`: `orc-lljit`). The runtime's symbols are bound to
    `idris-mlir-cc`'s own copies, so the JIT runs the same runtime as the
    executable (`LOW-RT-1`). Results are cached per callee and arguments
    for the compilation.
  - **The child.** `idris-mlir-cc` runs MLIR single-threaded, so it can
    fork. The child runs the round's calls on a stack reserved as large as
    the address space allows (committed as it is touched), turns each
    result into attribute text with the layout code `idr-lower` uses, and
    writes it to a pipe; the parent parses it and replaces the call.
  - **Crashes and exhaustion.** A crash that the runtime reports leaves
    that call in place, to crash at runtime (`SEM-EVAL-4`), and the parent
    forks again for the remaining calls. A fault on the stack's guard, a
    failed arena mapping, or the child killed by the kernel for memory is
    `EVAL-1`. Any other signal is an internal error (`DIAG-ICE-1`).
  - **Remarks.** `--remarks=idr-eval` reports a `Passed` remark per call,
    with its wall-clock time, and a `Missed` remark per call that crashed,
    with its call-site chain.
  - **`--no-eval`** turns the pass off, which changes no program's meaning
    (`SEM-EVAL-6`, `TEST-EQUIV-1`).
  - *Why this is exact:* the call runs the code the executable would run,
    with the runtime it links (`SEM-EVAL-6`, `SEM-EVAL-7`).
  - Check: the pass `idr-eval`

### Closures

- **ELIM-CLOS-1 (v3). `idr-defunctionalize`.** After the simplify loop,
  the closures left are replaced by data where the set of functions that
  can reach them is known (Reynolds's defunctionalization, as MLton's
  `ClosureConvert` and Futhark do it):
  - The analysis runs on MLIR's dataflow framework. Its lattice holds sets
    of functions. A closure reaches fields through one anchor per
    (type, constructor, field), and at an `idr.apply` the arguments of each
    possible callee are updated, because the framework's interprocedural
    mode follows symbol callees only.
  - Sums are keyed by closure type and set of functions: each value,
    argument, result and field gets the sum of its type and its set. A key
    whose set is finite and not empty becomes a sum over those functions
    whose fields are their captures, each with the key of that capture,
    unless it is on a cycle of "a capture of one of its functions holds,
    directly or through unboxed data, a value of that key". A closure may
    capture another of its own type when the sets differ (a state monad's
    bind). `idr.closure` becomes the constructor, and `idr.apply` becomes a
    match on it with a direct call in each region. Where a value moves
    into a slot of a larger set, a match rebuilds it in that sum.
  - A closure that remains is rejected by the heap-free profile
    (`PROF-HEAP-1`, `PROF-HEAP-2`, `PROF-HEAP-4`).
  - *Why this is exact:* applying the constructor of a function applies
    that function to its captures and arguments, which is what applying the
    closure did.
  - Check: the pass `idr-defunctionalize`

## Withdrawn earlier

- **ELIM-G-10.** *Withdrawn in v3:* unfolding string functions was a
  reason the driver unfolded a call (`ELIM-G-19`). Since the cutover,
  `inline` inlines every legal call.
- **ELIM-G-11.** *Withdrawn in v3:* unfolding case and with blocks was a
  reason the driver unfolded a call (`ELIM-G-19`); since the cutover, as
  `ELIM-G-10`.
- **ELIM-G-12.** *Withdrawn in v3:* unfolding on known arguments was a
  reason the driver unfolded a call (`ELIM-G-19`). Since the cutover, it is
  specialization (`ELIM-SPEC-1`) or evaluation (`ELIM-EVAL-1`).
- **ELIM-G-13.** *Withdrawn in v3:* library `%inline` was a reason the
  driver unfolded a call (`ELIM-G-19`). Since the cutover, `%inline` is
  ignored (`PROF-LIB-2`).
- **ELIM-G-14.** *Withdrawn in v3:* a string join point was a choice
  (`ELIM-G-20`). Since the cutover, a string picked at runtime is a value.
- **ELIM-G-16.** *Withdrawn in v3:* evaluation of known calls was the
  driver unfolding calls on known arguments, bounded by its budget
  (`ELIM-G-19`). Since the cutover, it is `ELIM-EVAL-1`, on total code.
- **ELIM-G-18.** *Withdrawn in v3:* call-pattern specialization was the
  driver unfolding on a literal the body matches on (`ELIM-G-19`). Since
  the cutover, it is specialization on a constant (`ELIM-SPEC-1`).
- *ELIM-G-ORDER* (termination and determinism of `Simplify`'s rules) and
  *ELIM-G-SCOPE* (`Simplify` applies only its rules) are withdrawn at the
  cutover with `Simplify`: the simplify loop has its own termination
  argument (`OPT-PIPE-5`), and no optimizer is left in Idris
  (`CORE-OPT-1`).

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
- **ELIM-FORCE-2 (v0).** Idris's `newtypeArg` is not used: single-constructor
  types already lose their tag in lowering (`LOW-DATA-1`). *Revised at the
  cutover:* `Nat`-like types are bigs, decided from Idris's `ZERO`/`SUCC`
  constructor flags (`IDR-IN-3`), which is what Idris's own
  Nat-to-Integer optimization reads.
  - Check: review (no code reads `newtypeArg`)
