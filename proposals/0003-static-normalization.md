# 0003: static normalization, and no compile-time evaluation feature

**Status:** decided by the owner (2026-10-10); not built. Read at 8395d4f7.
`idr-eval` is out of the simplify round. N2 deletes the pass.

**The idea.** A dependently typed compiler has no need for a "comptime" feature: its type
checker already normalizes total code, because deciding whether two types are equal requires
it. Compile-time evaluation, constant folding and monomorphisation are one operation:
**normalize the static part of the program.** It runs on the type checker's own evaluator, a
fast interpreter over flat terms and arrays. There is no JIT, no WebAssembly, no forked
child, and no second compiler inside the first.

**Claims** are marked: *read*, *measured*, *recalled*, *conjecture*, *decision*.

## 1. What it replaces

*Read* (`include/idr/Passes.td:119-157`, `lib/Eval/`): `idr-eval` runs every call whose
operands are all constants, of a function that performs no IO. It is not in the simplify
round (`lib/Simplify/Round.cppm`).
Each round it clones the callees and everything they reach into a scratch module,
defunctionalizes and lowers it as a program, meters it (`idr-meter`), compiles it with ORC's
LLJIT and runs it in a forked child (`Eval/Child.cppm`); results return as bytecode, up to
1 MiB. Total code gets 2³¹ ticks, partial code 2²⁵ (`Eval/Evaluate.cppm`). Calls whose
closures defunctionalization cannot follow stay for run time.

It is kept for what it buys:
- **choices computed by recursion**: a dictionary, implementation or shape computed by a
  recursive closed call is what lets AGENTS.md's middle way specialize the site instead of
  refusing it as megamorphic;
- **constant tables**: data computed from constants is static data, not startup work.

It is replaced for what it costs: it compiles the code it reaches twice per round; it keeps
MLIR threading off ("idr-eval may fork", `Driver/Run.cppm:59-62`); partial code needs a
divergence budget whose outcome depends on whether a call happened to finish; and it runs
in the C++ simplify loop, after the frontend has already committed to the instances its
results should have chosen.

## 2. The operation: normalize the static part

Three rules decide it. Each already exists in the compiler.

| Rule | Decides | Already exists as |
| --- | --- | --- |
| **totality** | whether normalizing is *safe*: it ends, and covering code cannot fail a match | the totality checker |
| **closedness** (binding time) | *what* is normalized: calls whose arguments are all known | the instance set monomorphisation computes |
| **a cost rule** | whether it is *worth it*: total is not cheap (Ackermann is total) | a counted, deterministic budget |

**Decision (D1, owner):** only total code is ever normalized at compile time. Partial and
covering code never is; it runs at run time.

What happens to a call, by how much of it is static:

- **A closed call of total code** normalizes to a value: a scalar, data, an array, or a
  function. Data becomes a static constant (cells at count 0; arrays of words as dense
  constants, 0007); a function becomes a specialized function. If the cost rule refuses it,
  it stays a **top-level constant computed once at startup**, at native speed, once per
  shard that demands it (0009 D6). The cost rule is this proposal's; 0009 D6
  is only which shard computes the constant. The program's startup *is* the compiled tier.
- **A partly static call** specializes only on the arguments that **steer control**: types,
  dictionaries, shapes, and constructors the callee matches on. Never on plain data, which
  would clone a function per distinct integer. **Monomorphisation is this rule when the
  static arguments are types**; in a dependently typed language they are the same rule.
- **A call under a binder** (an open term) is never normalized: that is full partial
  evaluation, supercompilation, and code explodes.
- **Code reaching a world** (IO, or a forged world: `unsafePerformIO`, `Linear.Array`'s
  operations) is stuck and runs at run time.

**Decision (D2):** the compiler has no compile-time evaluation feature, no annotation and no
keyword. It normalizes the static part of the program by these rules, and that is all.

## 3. The evaluator: a fast interpreter over flat terms and arrays

**Decision (D3):** one evaluator, the type checker's, serves type checking, proofs and
static normalization. It is an interpreter. There is no compiled tier: no JIT, no
WebAssembly, no native compilation of reductions.

- **Terms are flat and hash-consed** (0006 §2.1, 0005): an arena of nodes with integer ids,
  so equality is an id compare and normal forms are cached by id.
- **Evaluation is normalization by evaluation with glued values** (0006 §2.2): closures and
  suspensions are native to it, so it follows every lambda `idr-eval` could not
  defunctionalize.
- **Array operations run as whole-array primitives.** The interpreter dispatches once per
  array operation and the work runs as the runtime's vectorized primitive (0007's arrays,
  the runtime's meaning). This is the APL insight: interpretive overhead is paid per array,
  not per element, so array code interprets at close to native speed. A per-element lambda
  (`tabulate n (\i => …)`) is still interpreted once per element; when that is too slow for
  the cost rule, the value is a startup constant instead.
- **Failing primitives are values.** A primitive that fails (a division by zero) makes the
  call stuck, and it runs at run time where it fails as the program would. With only total
  code and no compiled tier there is nothing to isolate, so there is no fork.
- **One meaning of primitives.** The fork's primitives are backed by base's (*read*: 0004's
  ledger). Once the frontend is self-hosted it is compiled by idris-mlir, so the
  interpreter's primitives are the runtime's, as AGENTS.md requires. At stage 0, on Chez,
  the test matrix (D5) checks that normalized and run-time results agree.
- **Deterministic cost.** The budget counts steps and bytes, never time, so a call is
  normalized or deferred identically on every machine and schedule.

## 4. Where it runs

In the frontend, where choices are decided. Translate already "monomorphises on demand,
with Idris's own normalizer doing all type-level computation" (*read*:
`compiler/src/IdrisMLIR/Frontend/Translate.idr:1-3`); static normalization extends that to
the value level at the same point, so a choice computed by recursion reaches the instance
decision that needs it. A closed call needs only its callees, which a module's imports
provide, so normalization runs per module and is cached under the module's content hash
(0011 phase 1). **The C++ pipeline never runs program code.**

## 5. What changes against today

| | `idr-eval` today | static normalization |
| --- | --- | --- |
| what | every closed pure call, total or not | closed calls of total code; partly static calls on control-steering arguments |
| where | the pass remains, out of the simplify round | the frontend, once, per module |
| how | scratch module, LLJIT, forked child | the type checker's interpreter, array ops as whole-array primitives |
| closures | only those defunctionalization follows | all |
| budget | divergence and cost | cost only, counted |
| too expensive | stays for run time | a startup constant, computed once at native speed |
| MLIR threading | off | on |

**What is lost:** calls that become closed only after C++ inlining or specialization through
partial or IO code, and closed calls of partial or covering code. Both run at run time. N0
counts them.

## 6. What is deleted

*Read* at c50d176d:

| What | Where |
| --- | --- |
| the pass and its library, about 1,900 lines | `foreign/idr/lib/Eval/`, `IdrEval` in `include/idr/Passes.td` |
| metering | `idr-meter`: `lib/Lower/Meter.cppm`, `lib/Lower/Meter/Pass.cc`, its ops in `IdrOps.td` |
| the runtime's evaluation entries | `idris_rt_eval_begin`, `idris_rt_eval_crash`, `idris_rt_eval_meter`, `idris_rt_eval_unmetered`, `idris_rt_eval_tick` and their arena (`runtime/idris_rt.h`) |
| ORC and LLJIT in the compiler | `lib/Mlir.cppm`'s ExecutionEngine imports |
| the reason threading is off | `Run.cppm:59-62` |
| the pass's tests | `tests/idr/eval/` (23 files); program-level cases move to the frontend's tests |

**Kept:** `tests/programs/eval/` (24 programs), whose outputs do not change, and the test
matrix that runs every program test with and without static normalization
(`tests/README.md:27`): the check that the interpreter means what the runtime means (D5).

## 7. The interactive loop

0007 §2.13 runs a line as a program, compiled through the same pipeline and linked as an
executable, in a child. There is no JIT in the driver. The latency rule (0007: 1 s from
line to output) decides whether a resident frontend is built, not how the line is run (D4).
That is running a program, not normalizing one, and it stays out of compilation.

## 8. Rules changed

When N2 lands, in the same change:
- AGENTS.md:55-59 becomes: "No primitive has an implementation in Idris: its one meaning is
  the runtime's (`runtime/`), which folders and the evaluator call too. The compiler has no
  compile-time evaluation feature: it normalizes the static part of the program with the
  type checker's evaluator. Closed calls of total code become values within a counted
  budget, or startup constants beyond it; partly static calls specialize on the arguments
  that steer control; partial and covering code is never normalized."
- AGENTS.md:40: the C++ side holds "specialization, defunctionalization, loops, the
  heap-free check, lowering".
- AGENTS.md:64, the middle way: "which static normalization, specialization, closed sums and
  defunctionalization compile away".
- README.md:14-15 and 28: the simplify loop is "inline, specialize, canonicalize, to a
  fixpoint"; the frontend "normalizes the static part". README.md:201, 213-215: no JIT.

## 9. Staged plan

| Stage | Content | Proof |
| --- | --- | --- |
| N0 | on the arm64 toolchain (8395d4f7): per program, what `idr-eval` would still fold, split into total and partial, by running the pass on its own against the round that no longer contains it | committed record, sizing §5's losses |
| N1 | static normalization in the frontend on today's evaluator: closed total calls to values, control-steering specialization, the counted budget, startup constants beyond it | the constants equal `idr-eval`'s total-only results on the corpus (a differential while both exist); corpus outputs identical |
| N2 | delete §6's list; MLIR threading on (0011 S7); §8's rules | corpus outputs identical; `determinism.sh` across thread counts; compile times recorded |
| N3 | the evaluator on 0005's term arena and 0007's arrays as whole-array primitives | a fixture: a table of 10⁶ words built by array operations normalizes within the budget; reflection benchmarks recorded against N1 |

## 10. Rejected alternatives

- **A JIT or native compilation of reductions** (today's `idr-eval`; Coq's
  `native_compute`): a second compiler inside the first, and a fork to contain it.
- **WebAssembly**: a second lowering pipeline plus an embedded engine.
- **Eager evaluation of every closed call, partial included**: needs a divergence budget and
  gives schedule-sensitive refusals.
- **A `comptime` keyword or staging annotations**: the types already say what is static; the
  totality checker already says what is safe.
- **Specializing on every constant argument**: one clone per distinct value; only
  control-steering arguments specialize.
- **Normalizing open terms**: supercompilation's code explosion.

## 11. Decisions

- D1 (owner). Only total code is normalized at compile time; partial and covering code never
  is.
- D2. No compile-time evaluation feature: the compiler normalizes the static part of the
  program, and monomorphisation is the case where the static arguments are types.
- D3. One evaluator, the type checker's interpreter, with array operations as whole-array
  primitives; no JIT, no WebAssembly, no compiled tier. Too expensive means a startup
  constant.
- D4. The interactive loop runs lines as linked executables, outside compilation. There is
  no JIT in the driver.
- D5. Every program test runs with and without static normalization.
