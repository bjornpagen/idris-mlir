# Differential and metamorphic testing

How to find the miscompiles of an optimizer that acts on what Idris proves.
This stream judges what the repository already has, then designs the global
maximum: a generator of well-typed Idris programs, a lattice of oracles, a
type-aware reducer that bisects to the pass, IR-level fuzzing of `idr`, and a
concrete `--validate` mode. A prototype generator was run against Chez and
this compiler; what it found is in section 9. Everything the prototype needs
is in `findings/differential-prototype.md`.

## The questions

1. What do the existing fuzzer and differential tests generate, and how
   strong are they?
2. What does a test system for an aggressive, fact-driven optimizer have to
   generate, and against which oracles?
3. How is a failure reduced, in Idris terms, and bisected to one pass and
   one action?
4. What does IR-level fuzzing of the `idr` dialect add, and what is its
   oracle?
5. What is `--validate`, concretely?
6. How is all this wired into `make test` with budgets, plus a long mode?
7. What does a first prototype find today?

---

## 1. What exists, and how strong it is

readability.md (§ "The best safety nets are invisible") found that the
oracles exist and are hard to find. Here is exactly what each one generates
and checks. **Read**, from the files cited.

| Net | Input | Oracle(s) | In `make test` | Strength | Blind spot |
|---|---|---|---|---|---|
| `tests/Fuzz.idr` + `tests/lib/fuzz.sh` | closed expressions over every primitive, depth ≤ 4, 30 cases per program, 2 parts (`runtime`, `static`) | three spellings of each case agree (`d` folded, `j` a closed call of a total function, `r` behind a partial identity); eval vs `--no-eval`; Chez (libm lines aside) | seeds 1 and 2 only (`tests/fuzz/seed-{1,2}/run`) | primitive semantics at edge values, NaN, -0.0, subnormals, wrapping widths, Euclidean division; folder vs JIT vs runtime (`Fuzz.idr:1-38`) | no data type but one 3-constructor sum (`Fuzz.idr:466-477`), no heap, no closure, no recursion but a list of units, no quantity, no user type, no stdin-dependent control, no allocation at runtime (`Fuzz.idr:31-35`); fixed seeds, so a regression test, not a search |
| `tests/Sem.idr` | table-driven integer primitives, 63 generated v0 fixtures (`tests/e2e/v0/prim-*`) | `Oracle.idr` proves `Prog.main = 0` by `Refl` in the stock evaluator | yes | exhaustive over the tables | integers only |
| `tests/TwoLevels.idr` + `two-levels.sh` | closed terms over every primitive and a hand-written corpus of total Prelude functions | Idris's own evaluator (`normaliseAll`), the compiled program, Chez | yes | a third semantics that is not Chez | hand-written corpus, closed terms only |
| `tests/lib/equivalence.sh` | every e2e fixture (126, of which 63 prim) | eval vs `--no-eval`: stdout and status | yes (v0..v3, v0-sem) | exercises idr-eval on real programs | the 63 hand-written programs |
| `chez_agrees` (`tests/lib/chez.sh`) | every IO e2e fixture | Chez: stdout, status, crash prefix | inside every e2e test | the reference semantics | same corpus |
| `tests/lib/properties.sh` | every e2e fixture | 5 properties: dumps verify, simplify idempotent, deterministic dumps, no budget error, quantities kept (`properties.sh:108-185`) | yes | static invariants after every step | same corpus; nothing about behaviour |
| `tools/bisect.sh` | one program | `--no-eval` as reference, `-mlir-debug-counter` on one tag | manual | finds *the action* | 3 tags of ours (`Support/Actions.h:21-41`: `idr-eval-call`, `idr-specialize-clone`, `idr-raise`) plus MLIR's `apply-pattern`; no action in rc, stack, defunctionalize, tail loops, inline |
| `idris-mlir-reduce` | a module | mlir-reduce | manual | exists | the dialect provides no reduction patterns |
| `IDRIS_RT_LIVE=1` | any run | live cells = 0 at exit | e2e (`tests/idr/rc/live.mlir`) | catches leaks | a double free plus a leak cancel; a use after free is invisible |

**Answer.** The oracles are strong; the inputs are weak. Every behavioural
oracle runs over the same 63 hand-written programs, and the only generator
writes straight-line primitive expressions. Nothing generated reaches what
makes this optimizer aggressive: inlining through `do` blocks,
specialization and its clones, case-of-case, defunctionalization, idr-eval
on heap values, reset/reuse and borrowing, stack cells, tail loops, and above
all the quantities. The first 10 programs of a prototype that does reach
them found an internal error (section 9), which is the measure of the gap.

---

## 2. The global maximum

One sentence: **every generated program is compiled by a lattice of
compilations that must all agree with Chez, and every disagreement is
reduced, by construction well-typed, to the smallest Idris program and then
to one action of one pass.**

```text
   choice sequence ──► generator (typed, linear-aware, swarm policies)
                            │  Idris 2 source + stdin
            ┌───────────────┼──────────────────────────────┐
         Chez            idris-mlir                  Idris evaluator
       (reference)   ┌───────┴────────┐              (closed variant)
                     O0 (no simplify) … full    ×  metamorphic variants
                     └─ lattice: --no-eval, --disable=P, counter windows,
                        rc{reuse,borrow}=false, checked runtime, --validate
            └───────────────┬──────────────────────────────┘
               verdict: agree / reject(unsupported) / known crash / BUG
                            │ BUG
         reduce the choice sequence (well-typed by construction)
                            │
         bisect: step → pass (--disable) → action (debug counter)
                            │
         regression fixture: tests/gen/found/<hash>/ (Main.idr, stdin, expected)
```

Each piece exists in MLIR or in the repository already, except the
generator, the `--disable` generalization, the checked runtime and
`--validate`. The pieces, in the order of leverage:

1. the generator (section 3): the missing input;
2. oracles beyond Chez (section 4), mostly one flag each;
3. the reducer (section 5), which comes free with a choice-sequence
   generator;
4. `--validate` (section 7), the per-pass oracle, which reuses idr-eval's
   JIT;
5. IR-level fuzzing (section 6), which reaches IR no Idris program emits;
6. wiring (section 8).

---

## 3. The generator

### 3.1 What it must generate, and why

An optimizer that acts on facts is wrong when it trusts a fact that does not
hold, or when a transformation drops the fact and a later pass re-derives a
stronger one. So the generator must produce programs where the facts are
present, absent, and **present but weaker than they look**. AGENTS.md names
three such traps; each is a generator feature:

- *A linear binder does not imply unique heap ownership.* Idris accepts
  `f : (1 _ : List Int) -> List Int; f (x :: xs) = … xs … xs …`, because the
  fields of `(::)` are unrestricted (**measured**:
  `dup (x :: xs) = x :: x :: dup xs` type-checks with the pinned Idris, and
  `twice xs = length xs + length xs` is rejected). The caller can also pass
  a shared value to a linear parameter. The generator emits both on
  purpose: linear functions called on shared lists that are read again
  afterwards, and linear functions that duplicate their tails. A reuse that
  trusts the `1` without proving uniqueness shows as a changed second read.
- *Erased does not mean constant.* Quantity-0 arguments with different
  values at different call sites, and erased indices (`Vect n`) whose
  runtime witness is a different value.
- *Indexed vectors do not imply contiguous storage.* `Vect` built from
  `fromList` of a runtime list, zipped with its own reverse.

Beyond the traps, the generator produces the *opportunities* of each pass
(YARPGen's "generation policies", Livinskii, Babokin, Regehr, OOPSLA 2020:
generate code that the optimizations are known to fire on):

| Pass | Policy that creates its opportunity |
|---|---|
| idr-inline, known constructor, case-of-case | nested `case` on constructed values; `case` of `if`; `do` blocks of n statements |
| idr-specialize, idr-raise | higher-order functions called with static lambdas and partially static data; accumulators whose shape grows (the `specialize-growing-accumulator` fixture's pattern) |
| idr-eval | closed calls (literals only) next to open ones; total calls that run long; partial loops whose trip count straddles the partial budget (`Eval.cc`: 2^25 ticks) |
| idr-defunctionalize | closures stored in data, returned from functions, applied later |
| idr-rc reset/reuse, borrow | same-size rebuilds (`map`-like over linear and non-linear lists and trees), read-only parameters, a value read after a function consumed it |
| idr-stack | cells that never leave a frame; cells that escape through a closure capture |
| idr-tail-loops | accumulator recursion; mutual recursion |
| output fusion | strings built only to be printed, and strings built and kept |
| remove-dead-values, idr-prune | dead arguments; match regions ruled out by a constant that appears only after sccp (the PINS.md `prune-before-remove-dead-values` case) |

Swarm testing (Groce, Zhang, Eide, Chen, Regehr, ISSTA 2012) chooses, per
program, a random subset of the features and policies: a program that never
builds a closure stresses reuse harder than one where defunctionalization
changes every shape. The prototype turns features on per template; the real
generator should draw the subset from the seed.

### 3.2 Well-typed by construction

Three ways to get well-typed programs, from weakest to strongest:

1. **Generate, then filter by the type checker.** The prototype does this
   for its templates: Idris rejects what the templates got wrong. Cheap,
   but the rejection rate must be watched: a template Idris always rejects
   silently removes a feature (measured: the prototype's linear
   accumulator was always rejected until fixed, because `acc` flows into
   the unrestricted field of `(::)`).
2. **Type-directed generation** (Pałka, Claessen, Russo, Hughes, AST 2011,
   "Testing an optimising compiler by generating random lambda terms"): pick
   a goal type, choose a typing rule whose conclusion matches, recurse on
   the premises; they found strictness-analysis bugs in GHC this way, the
   closest precedent to this compiler. The prototype is this for
   unrestricted code: every expression is generated at a target type from
   an environment of typed variables and a library of already generated
   functions, which are a DAG plus structural self recursion, so every call
   terminates unless the generator chose a partial loop.
3. **Resource-aware generation.** Quantities make the context a resource
   (QTT: Atkey, LICS 2018; McBride, "I got plenty o' nuttin'", 2016). The
   generator carries each binder's quantity and remaining uses, and chooses
   among rules whose usage fits (the "leftover" presentation of linear
   typing: a rule consumes from the context and returns the rest). Written
   in Idris, the generator's term type itself can index the context with
   usages, so an ill-quantified term is unrepresentable (King's "parse,
   don't validate", as principle-representation.md asks), the same way
   QuickChick derives generators from inductive typing relations
   (Lampropoulos, Paraskevopoulou, Pierce, POPL 2018, "Generating good
   generators for inductive relations").

Termination and crashes are chosen, not stumbled on: totality is a
generator parameter. Total code recurses structurally; partial code
recurses on an `Int` with a trip count the generator picks (below, near, or
above the partial meter); crashes (`div` by zero through a runtime value,
`idris_crash` in an impossible branch reached at runtime) are generated
deliberately in a fraction of programs, and the verdict compares "both
crash, same output before the crash" as `chez_agrees` already does.

Csmith (Yang, Chen, Eide, Regehr, PLDI 2011) had to avoid C's undefined
behaviour with safe-math wrappers; Idris has none, but it has two things a
comparison must neutralize: Chez's unbounded stack against our 8 MiB one
(the known non-tail `map` overflow), and host libm. The generator bounds
non-tail recursion depth by construction (sizes ≤ 40 in the prototype) and
keeps libm out of the compared lines, as `Fuzz.idr` does with its `L` lines.

### 3.3 Where it lives

In Idris, in `tests/`, next to `Fuzz.idr`, as `runtests --gen-program SEED
[FEATURES]`, so the corpus is reproducible from the runner and the typed
term representation of 3.2(3) is available. The prototype is Python only
because it was faster to write in a scratch directory.

---

## 4. Oracles: a lattice of compilations

Every oracle below compiles the same program another way; all must print
the same stdout and exit alike, or reject with `unsupported (…)`. A
rejection is a verdict, not a pass: the histogram of rejection reasons over
the generated corpus is the map of what the compiler does not yet accept.

| # | Oracle | Mechanism | Exists? |
|---|---|---|---|
| O1 | Chez | stock backend, `chez_agrees` rules | yes |
| O2 | `--no-eval` | action handler skips `idr-eval` (`idris-mlir-cc.cc:422-437`) | yes |
| O3 | **`--disable=P,…`**: any optional pass skipped | the same handler, keyed by pass argument, over a declared set of optional passes | small change |
| O4 | **counter windows** | `-mlir-debug-counter=TAG-skip=a,TAG-count=b` for a random window: every subset of actions is a valid compilation | yes, for 4 tags |
| O5 | `idr-rc{reuse=false borrow=false}` | pass options exist (`Passes.td:334-335`) | needs a driver flag |
| O6 | **O0**: contract → `idr-lower` with no simplify loop | a pipeline variant | **works today from outside the driver** (section 9): idris-mlir-opt with the steps after `idr-simplify`, mlir-translate, clang with `build/dev/runtime/libidris_rt.a`; a driver flag would make it one command. Separates frontend bugs (Chez ≠ O0) from pass bugs (O0 ≠ full) |
| O7 | Idris's evaluator | the two-levels helper on a closed variant (stdin replaced by its literals) | helper exists |
| O8 | live cells 0 | `IDRIS_RT_LIVE=1` | yes |
| O9 | **checked runtime** | a second runtime archive (`idris-mlir-cc --runtime=`, which exists) that quarantines freed cells and poisons them, and traps an inc, dec or read of a poisoned header | new, small |
| O10 | static properties | `idr-expect`'s `quantities-kept`, `folds-balanced`; `dumps-verify`, `simplify-idempotent`, `deterministic-dumps`, `no-budget-error` over the generated corpus, not only the e2e fixtures | a loop over a different corpus |
| O11 | `--validate` | section 7 | new |

O3 in detail. The optional set is a property of each pass, so it belongs in
the pass's definition, not in a list in the driver: a pass is optional when
skipping it leaves a module that every later step accepts. Today:
`idr-inline`, `idr-specialize`, `sccp`, `idr-canonicalize`, `cse`,
`idr-eval`, `symbol-dce`, `canonicalize`, `idr-stack`, and `idr-tail-loops`
(which only changes stack depth). **Measured** on one program (section 9's
O0 pipeline, run with idris-mlir-opt): dropping `idr-stack`,
`idr-tail-loops` or `canonicalize`, or setting `idr-rc{reuse=false
borrow=false}`, still lowers, links and prints the same, with 0 live cells.
Not optional: `idr-prune` before `remove-dead-values` (it is the PINS.md
workaround, so skipping it crashes upstream code); `idr-defunctionalize`
(**measured**: without it `idr-lower` stops with "internal error: a closure
is left after idr-defunctionalize"); `idr-rc`; `idr-lower`. The driver already intercepts
`PassExecutionAction` for `idr-eval`; generalizing it to a list is ten
lines. The same handler lets the long mode pick a random subset per program.

O4 in detail. A counter window is a random compilation in the lattice
between "no action of TAG" and "every action". bisect.sh already relies on
"a skipped action leaves the IR as it was" (`tools/bisect.sh:15-18`); random
windows turn that into a search. Every transformation of ours that can be
skipped should be an action, so the lattice and the bisection reach it:
`idr-rc` (one action per reset/reuse, per borrowed parameter), `idr-stack`
(per cell), `idr-defunctionalize` (per label), `idr-tail-loops` (per loop),
`idr-inline` (MLIR's inliner has no action per call; ours can wrap its
`shouldInline`). MLIR's own `apply-pattern` covers every greedy rewrite.

O9 in detail. `IDRIS_RT_LIVE` counts; it does not see a double free that a
leak cancels, nor a read of a freed cell whose memory the allocator has not
reused. With static reuse coming (memory-theory, mlir-ownership-types), the
failure mode "reused in place although shared" becomes a wrong value, not a
leak; only a poisoned, never-reused cell turns it into a deterministic
trap. It must be a separate archive, not an environment variable, to keep
the check off the release hot path.

---

## 5. Reduction, and bisection to the pass

**R1. Reduce the choice sequence, not the text.** The generator is a
function of a sequence of random choices. Shrinking the sequence (delete a
block of choices, lower a choice toward 0) and regenerating yields a
program that is well-typed and well-quantified by construction, so no
candidate is wasted on the type checker. This is Hypothesis's internal
reduction (MacIver, Donaldson, ECOOP 2020, "Test-case reduction via
test-case generation"), and it is the type-aware reducer the task asks for,
for free. For generated programs it is the only reducer needed.

**R2. For hand-written programs, a reducer that asks the frontend for
types.** Text-level reduction (C-Reduce, Regehr et al., PLDI 2012; Perses,
Sun et al., ICSE 2018) wastes most candidates on type errors: the
prototype's line-and-subterm reducer (`differential-prototype.md`) spends
every candidate on a full compile. The frontend has checked TT with source
spans; a directive that lists, per application node, its span and type
lets a reducer replace a subterm by a canonical value of its type (`0`,
`[]`, the first nullary constructor, a variable in scope of that type) and
never produce an ill-typed candidate. Linear binders need the replacement
to consume the same resources, which the listing can report too.

**R3. IR level.** `idris-mlir-reduce` is mlir-reduce with the dialect
registered (`tools/idris-mlir-reduce.cc`); the dialect provides no
`DialectReductionPatternInterface` patterns
(`mlir/include/mlir/Reducer/DialectReductionPatternInterface.td`), so it
can only delete ops. **Measured**: on the 1479-line module of section 9's
crash, `idris-mlir-reduce --reduction-tree='traversal-mode=0 test=…'` ran 6
minutes and then aborted: a candidate lost the terminator of an `idr.match`
region ("region #1 must end in idr.yield or ub.unreachable") and the tool
crashed instead of rejecting the candidate. Deleting ops is not a valid
reduction step for a dialect whose regions have required terminators.
Patterns to add: replace an op by `idr.constant` of its
result type; a match by one of its regions; a call by a constant; a
closure by a known label. With them the reducer respects types and
quantities at the IR level too. Note the tester convention: mlir-reduce
counts a *non-zero* exit as interesting (`mlir/lib/Reducer/Tester.cpp:78`),
the opposite of C-Reduce's; every script must say so.

**R4. Bisect to the step, then the pass, then the action.**
1. *Step*: `--dump-after=all` gives the module after each step; a
   `--start-after=STEP` option in idris-mlir-cc (parse with every dialect,
   skip the steps up to STEP) runs each dump to an executable, so the first
   dump whose program differs names the step. Today only the contract text
   can be compiled (`idris-mlir-cc.cc:342-346` parses with the contract's
   dialects).
2. *Pass*: within the simplify loop, the O3 lattice (`--disable=P`) names
   the pass whose absence removes the difference.
3. *Action*: `tools/bisect.sh SOURCE TAG` with the pass's tag. The
   reference should be a parameter (today it is always `--no-eval`,
   `bisect.sh:109`): with O3, the reference is `--disable=P`.

---

## 6. IR-level fuzzing of `idr`

What it reaches that source generation cannot: IR the frontend never emits
but a pass might (a match on a value two passes rewrote, a linear value in
a region the inliner duplicated), and the verifier's completeness.

**Corpus.** Every contract module the frontend emits: the e2e fixtures and
every generated program, thousands of verified modules with real types.

**Mutators, type- and quantity-aware** (MLIRod, Suo et al., 2024, mutates
MLIR guided by operation dependencies; MLIRSmith, Wang et al., ASE 2023,
generates MLIR from dialect definitions; neither knows quantities):
- *valid-preserving*: replace an operand by another dominating value of the
  same type; change an integer constant to an edge value; swap the
  constructor of an `idr.con` within its data type; reorder independent
  ops; duplicate a pure call; inline or outline a region;
- *quantity-breaking*, **must be rejected**: use an `!idr.lin` value twice
  on a path; use an `!idr.erased` value at runtime; consume a world twice;
  pass a `!idr.lin<T>` where `T` is expected without `idr.lin.use`.

**Oracles.**
1. The verifier: a quantity-breaking mutant it accepts is a verifier bug
   (`verifyLinearity`, `Dialect.cc:397-420`, counts uses per path; the
   mutants test the path logic: repetitive regions, exclusive regions,
   multi-block regions, `idr.inc` not counting).
2. A valid mutant: the pipeline never fails with an internal error; the
   verifier holds after every pass (it does by default in the pass
   manager); `idr-expect holds=quantities-kept,folds-balanced` at the end.
3. Behaviour: the mutant compiled O0 and full, with the lattice of section
   4, prints the same. There is no Chez for a mutant, so O0 is the
   reference, which is why O6 matters.

---

## 7. `--validate`, concretely

architecture.md Part III §5 proposes differential execution of each
changed function through the JIT. Here is how, reusing idr-eval's parts
(`Eval.cc`: `scratch`, `runInChild`, `Reifier`, the meters).

1. **Where.** A `PassInstrumentation` installed by `idris-mlir-cc
   --validate[=PASS,…]`. `runBeforePass` clones the module (the snapshot);
   `runAfterPass` validates; `runAfterPassFailed` discards. Inside the
   simplify loop the instrumentation must be attached to the loop's own
   pass manager, which `idr-simplify` builds (`Simplify.cc:62-68`), so the
   loop needs a hook to pass instrumentations down.
2. **What changed.** Hash every function with `structural()`
   (`Simplify.cc` already has it, constants by value, values by position)
   before and after; the changed functions are the units.
3. **Which unit is comparable.**
   - A function with the same symbol and type before and after is compared
     directly.
   - A clone (`idr.clone = #idr.clone<…, #idr.spec_key<…>>`) is compared
     with its origin applied to the key: the key names which arguments are
     static and their values, so the wrapper builds them.
   - A function whose signature changed (remove-dead-values, arity raising)
     is not comparable alone: its callers are validated instead, up to a
     function whose type did not change (`main` at worst).
   - A function that performs IO (`idr.effects`) is validated by running
     the whole program in the child with a fixed stdin buffer and captured
     output, which needs the runtime's output buffer to write to a pipe.
4. **Inputs, enumerated from types** (SmallCheck: Runciman, Naylor,
   Lindblad, Haskell 2008): integers at their edges and a few random
   values, Doubles with NaN, ±0, ±∞ and a subnormal, short strings with
   non-ASCII, boxes from the module's `idr.data` declarations up to depth 3,
   closures from the module's known labels with enumerated captures. An
   erased parameter needs no input. A linear parameter gets a fresh value
   for each run, since the after-version may reuse it in place.
5. **Run.** One scratch module holds both versions (the before-version's
   symbols renamed) and one wrapper per (version, input), exactly as
   `Eval::scratch` builds wrappers per call. Lower in JIT mode, run in the
   child with the meter of total or partial code, reify both results with
   the `Reifier`, compare the attributes.
6. **Verdicts.** Equal: pass. Both crash: pass (compare the crash cause).
   One over budget: inconclusive, not a failure. Unequal: an error naming
   the pass, the function, the input, with both functions printed; and the
   live-cell delta of each call must be 0 after `idr-rc` (the same check
   `folds-balanced` makes for folders).
7. **What it can and cannot prove.** Bounded validation, like Alive2's: it
   misses bugs outside the inputs but raises no false alarm when the
   inputs meet the function's preconditions (`lopes-2021-alive2`,
   abstract). The precondition that matters here is quantity: a function
   with an `!idr.lin` parameter may be called only with an unshared value
   *if* the compiler relies on uniqueness; a validation input built fresh
   is unshared, so validation cannot catch "reused although shared". That
   bug needs the whole-program oracles (O1-O9) and the sharing-injection
   relation of section 8.2.
8. **Cost.** Proportional to changed functions × inputs. In `make test`,
   validate the passes that act on facts (`idr-specialize`, `idr-rc`,
   `idr-stack`, `idr-defunctionalize`) on the generated corpus; in the long
   mode, every pass.

---

## 8. Metamorphic relations, and wiring

### 8.1 EMI

Equivalence modulo inputs (Le, Afshari, Su, PLDI 2014): profile the program
on its input and delete, or insert, code in regions that input never
executes. The generator knows its stdin, so it can insert dead code
directly: a branch guarded by a condition on `n1` that is false for the
chosen digits, holding arbitrary well-typed code that shares variables with
the live code. The optimizer sees a real branch; the output must not
change. Live-code mutation (Sun, Le, Su, OOPSLA 2016, Athena/Hermes) extends
it to executed regions with semantics-preserving rewrites.

### 8.2 Relations that vary the facts

These are the relations specific to this compiler: the program's meaning
does not change, but the facts the optimizer sees do. Each is a
source-to-source rewrite of a generated program, applied when the result
type-checks.

| Relation | Rewrite | What it tests |
|---|---|---|
| quantity weakening | `(1 x : T)` → `(x : T)` | nothing may depend on the `1` for meaning |
| sharing injection | keep a reference: `let keep = xs` before a consuming call, `printLn (sum keep)` at the end | reuse happens only when unique; the key test of static reuse |
| erasure | `(0 n : Nat)` ↔ an unrestricted unused `n` | erased ≠ constant |
| totality | `total` ↔ `partial` annotation, `assert_total` | only the evaluation budget may change |
| binding time | a literal ↔ the same value read from stdin | idr-eval and specialization agree with runtime |
| representation | `List Int` ↔ the prototype's `LL` (linear tail field) ↔ `Vect n Int` | reuse, contiguity and index facts |
| eta / closure | `f` ↔ `\x => f x`; a function passed through an identity HOF | defunctionalization, known-closure apply |
| layout | permute constructors and fields of a user type | tags and field offsets |

### 8.3 Coverage feedback

The statistics every pass already keeps (`-stats`, `PatternCounts.cc`, the
rc statistics `incs decs resets reuses borrowed`) are an optimization
coverage signal, as Zest uses branch coverage (Padhye et al., ISSTA 2019):
the long mode keeps a seed that raises a counter no earlier seed raised
(the first program where a reuse happens under sharing, the first
evaluation of a partial call over budget), and reports which canonicalize
patterns no generated program ever fired.

### 8.4 Wiring

- **`make test`**, deterministic and bounded:
  - `tests/gen/seed-N` for a fixed set of seeds (say 24): each program
    compiled full, `--no-eval`, one `--disable` subset and one counter
    window chosen by the seed (swarm over the lattice), and by Chez; run
    with `IDRIS_RT_LIVE=1`. Measured cost today: three builds of one
    generated program take 15-20 s of CPU (two idris-mlir builds at 5 s
    each unloaded, one Chez at 1 s, plus runs); 24 seeds at `threads=4`
    fit in the existing 1800 s `test_limit`.
  - the five properties of `properties.sh` over the same programs;
  - the reduced regression corpus `tests/gen/found/*`, each an ordinary e2e
    fixture (Main.idr, stdin, expected-stdout from Chez).
- **`make fuzz budget=8h`**, the long mode: fresh seeds, the whole lattice,
  the metamorphic relations, `--validate`, IR mutation; each failure is
  reduced (R1, then R4) and written to `tests/gen/found/<hash>/` with its
  verdict, ready to become a regression test.
- **Verdict lines** follow the runner's convention (one line per check,
  the same on every successful run): `gen seed 7: 3 builds agree with
  Chez`, `… rejects: unsupported (runtime closure)`; the rejection reasons
  are listed, not failed, as equivalence.sh lists fixtures that compile
  only with evaluation.

---

## 9. What the prototype found

(See `differential-prototype.md` for the generator, the runner and the
reproducers.)

RESULTS-PLACEHOLDER

---

## What it means for idris-mlir

- **Representation first applies to the tests too.** The generator's term
  type should make ill-quantified programs unrepresentable (3.2(3)); the
  reducer then shrinks choice sequences, never text (R1).
- **Optionality is a fact about a pass.** Declare it where the pass is
  defined, and let the driver derive `--disable`, the counter windows and
  bisection from it (O3, O4, R4).
- **Every transformation is an action.** Today 3 of ours are; rc, stack,
  defunctionalize, tail loops and inline should be, so the lattice and
  bisect reach them.
- **O0 is the missing reference.** It separates frontend (Emit) bugs from
  pass bugs and is the only oracle for IR-level mutants.
- **The checked runtime is the oracle static reuse needs.** Live-cell
  counting cannot see "reused although shared".
- **`--validate` is idr-eval's machinery pointed at a pass**, with one
  limit to state honestly: it validates functions on fresh inputs, so it
  cannot see uniqueness bugs; the sharing-injection relation can.

## Open questions

- Which passes are optional today? `idr-defunctionalize`, if the lowering
  of runtime closures covers every label, and `idr-tail-loops`, if the
  stack suffices, need a measurement.
- How much of Chez's disagreement surface is noise? Double printing is
  shared by construction (`idris_rt_io_put_double` prints as Chez does);
  stack depth and libm are the known sources.
- Can the Idris generator's typed terms be produced fast enough in the
  runner (Idris on Chez) to keep generation under a second per program?
  The existing `Fuzz.idr` suggests yes.
- The O0 path: does `idr-lower` accept every verified contract module
  without the simplify loop? If not, what it rejects is a list of lowering
  gaps.
