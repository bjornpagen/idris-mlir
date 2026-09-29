# Draft: ARCHITECTURE.md for idris-mlir

This is a draft of the one-page overview recommended in `readability.md`
section 4. It is written against the code as of `a8b061e`. It shows what
the page would contain, and it is meant to be edited, not copied blindly.
Every table row cites where it comes from. Rows marked **GAP** are
guarantees that nothing checks today.

---

# idris-mlir: how the compiler works

idris-mlir compiles a subset of Idris 2 to native code. The work is split
in two:

- **Idris decides what a program means.** The stock Idris front end checks
  the program. Our Idris code (`compiler/`) picks one representation for
  each value and writes the program as MLIR: the `idr` dialect plus
  func, arith, math and ub. We call that text the *contract*.
- **MLIR decides how to run it.** Our C++ passes (`foreign/idr/`) optimize
  the contract, make memory management explicit, and lower it to LLVM.

Every guarantee Idris proves that the passes need is kept in the IR's
*types*, where a pass cannot drop it:

- quantity 0 becomes `!idr.erased`;
- quantity 1 becomes `!idr.lin<T>`;
- IO is a `!idr.world` threaded through calls.

MLIR's verifier checks these after every pass.

## The pipeline

```
Prog.idr
  │  stock Idris 2 (pinned, unmodified): parse, elaborate, type-check
  ▼
checked TT + definitions
  │  Frontend (compiler/src/IdrisMLIR/Frontend): reject what we cannot compile
  │  with "unsupported (<rule>)"; translate to Core
  ▼
Core (IdrisMLIR.Term): monomorphic, closures converted, representations chosen
  │  Emit (compiler/src/IdrisMLIR/Emit)
  ▼
╔═ STAGE 1: PURE  ── the contract: idr + func + arith + math + ub ═══════════╗
║  idr-simplify, repeated until a round changes nothing (max 64 rounds):    ║
║    loop-breakers → effects → inline → specialize → sccp → canonicalize    ║
║    → cse → eval (runs closed calls in a JIT) → prune → symbol-dce         ║
║    → remove-dead-values → symbol-dce                                      ║
║  idr-defunctionalize   closures become sums of their possible functions   ║
║  canonicalize                                                             ║
║  idr-stack             cells that never leave their frame go on the stack ║
╚═══════════════════════════════════════════════════════════════════════════╝
  │  idr-rc: reuse dead cells, borrow read-only parameters, insert inc/dec.
  │  The module is marked idr.stage = "owned".
  ▼
╔═ STAGE 2: OWNED ── every reference consumed exactly once, on every path ══╗
║  idr-tail-loops        self tail calls become scf.while                   ║
╚═══════════════════════════════════════════════════════════════════════════╝
  │  idr-lower: matches become scf; idr types become runtime layouts;
  │  idr ops become arith, llvm and calls into the runtime
  ▼
STAGE 3: LOWERED  ── func + arith + scf + llvm
  │  canonicalize, cse → convert-scf-to-cf, convert-to-llvm
  │  → LLVM IR + the runtime's bitcode (LTO) → LLVM O3 → object
  ▼
lld: a static-PIE executable on musl, x86_64
```

The step list is `idr::pipelineSteps()` (`foreign/idr/lib/Registration.cc`).
The simplify round is `Passes/Simplify.cc`.

## What each stage guarantees, and who checks it

"Checked by" names the mechanism. A verifier rule runs after every pass. An
idr-expect property runs where a test asks for it. An oracle compares
behaviour with another implementation.

| Stage | Guarantee | Checked by | Where |
|---|---|---|---|
| Contract | Exactly one public function (the root), of type `() -> i64` or `(!idr.world) -> !idr.world` | verifier | `Dialect.cc:215-230` |
| Contract | Every data type used is declared; no type contains itself except through a box | verifier | `Dialect.cc:237-290` |
| Contract | A world or `!idr.lin` value is used at most once on every path | verifier | `Dialect.cc:397` |
| Contract | Only the dialects idr, func, arith, math and ub | spec test + parser registry | `tests/spec/emit-dialects` |
| All stages | No pass drops or widens a quantity | property `quantities-kept`, over every e2e program and every step | `tests/properties/quantities-kept` |
| Simplify | Reaches a fixpoint: running it again changes nothing | property `simplify-idempotent` | `tests/properties/` |
| Simplify | Terminates: every sub-pass is finite, and `max-rounds` turns a runaway into `unsupported (compile-time budget)` | budget + property `no-budget-error` | `Simplify.cc`, `tests/properties/` |
| Simplify | Inlining terminates: every cycle of references has a `no_inline` loop breaker | idr-expect `every-cycle-has-breaker` (tests only) | `Expect/Breakers.cc` |
| Eval | A compile-time result equals the runtime result | oracles: `--no-eval` vs eval (`tests/equivalence`), the fuzzer, Idris's own evaluator (`tests/twolevels`), folders vs JIT (`idr/eval/fold-vs-jit`) | `tests/` |
| Defunctionalize | No closure remains | idr-lower rejects one as an internal error | `Lower/Pass.cc:60` |
| idr-stack | A stack cell never outlives its frame | **GAP**: after idr-stack, only the attribute's form is checked. A later pass that moves a marked `idr.con` is not caught | `Dialect.cc:455-460` |
| Owned | Every reference is consumed exactly once on every path; nothing is used after its last reference | the ownership verifier, after every pass | `Ownership/Verify.cc` |
| Owned | A reused cell has the right size for its new constructor | the ownership verifier | `Ownership/Verify.cc`, `IdrOps.td:32` |
| Owned, at runtime | Every cell is freed by exit | `IDRIS_RT_LIVE=1` reports 0 live cells | `tests/idr/rc/live.mlir` |
| Tail loops | No self tail call remains | **GAP**: nothing checks it (tests look for `scf.while` in FileCheck) | |
| Lowered | Header fields fit their bits (tag < 2^16, objs < 2^8) | **GAP**: unchecked | `Lower/Layout.h:21-22`, `review-external.md` |
| Lowered | idr-lower and the runtime agree on layouts | shared header + runtime API test | `runtime/idris_rt.h`, `tests/toolchain/runtime-api` |
| Executable | Links only the allowed libc symbols (`write`, `read`, `_exit`, ...) | every e2e test | `tests/lib/heap.sh` |
| Executable | Same output and exit status as the stock Chez backend | every e2e test | `tests/lib/chez.sh` |
| Whole compile | Deterministic: the same input gives the same dumps, byte for byte | property `deterministic-dumps` | `tests/properties/` |

## Code map

| Concept | Where |
|---|---|
| The rules of what we accept (named reasons for rejection) | `compiler/src/IdrisMLIR/Rule.idr`; checks in `Frontend/Profile.idr`, `Frontend/Translate/*` |
| Which library functions are trusted, and hooks | `compiler/src/IdrisMLIR/Registry/` |
| Core, our typed intermediate language | `compiler/src/IdrisMLIR/Term.idr`, `Types.idr` |
| Writing MLIR | `compiler/src/IdrisMLIR/Emit/` |
| The dialect: every type, op and attribute | `foreign/idr/include/idr/IdrOps.td` (read this first) |
| Every pass: summary, options, statistics | `foreign/idr/include/idr/Passes.td` |
| Verifiers and canonicalization | `foreign/idr/lib/Dialect/` |
| The simplify loop, loop breakers, defunctionalization, prune, tail loops | `foreign/idr/lib/Passes/` |
| Inlining (MLton's rule) | `foreign/idr/lib/Inline/` |
| Specialization and arity raising | `foreign/idr/lib/Specialize/` |
| Compile-time evaluation (JIT, child process) | `foreign/idr/lib/Eval/`; folders in `lib/Fold/` |
| What code may do (IO, crash, loop forever) | `foreign/idr/lib/Facts/` |
| Stack allocation (escape analysis) | `foreign/idr/lib/Stack/` |
| Reference counting and its verifier | `foreign/idr/lib/Ownership/` |
| Lowering and runtime layouts | `foreign/idr/lib/Lower/` |
| Test properties (idr-expect) | `foreign/idr/lib/Expect/` |
| The runtime (allocation, counting, strings, bigs, IO) | `runtime/`; its C API is `idris_rt.h` |

## Glossary

| Term | Meaning |
|---|---|
| **contract** | The `.mlir` text Emit writes, and idris-mlir-cc's input |
| **root** | The one public function. idr-lower renames it and adds `@main` |
| **box** / `!idr.box<@T>` | A value of a recursive type, stored in a heap cell |
| **unboxed sum** / `!idr.data<@T>` | A value of a non-recursive type, spread over scalar *slots* |
| **cell** | A heap object: an 8-byte header (count, info), then fields |
| **slot** | One scalar component of an unboxed sum or of a cell |
| **persistent** | A cell with count 0: static data, never counted or freed |
| **world** / `!idr.world` | The token that orders IO. It is linear |
| **quantity** | Idris's multiplicity: 0 is `!idr.erased`, 1 is `!idr.lin<T>`, ω is a plain type |
| **label** | The function a closure calls. Closures with the same label share code |
| **closed call** | A call whose arguments are all constants. idr-eval may run it at compile time |
| **only computes** | Does no IO, cannot crash, and returns (`Facts/Moves`). Such code may be moved or dropped |
| **effects** | `idr.effects<io, crash>` on a function: what a call may do besides compute |
| **round** | One run of simplify's sub-pipeline. Rounds repeat until one changes nothing |
| **loop breaker** | A function marked `no_inline` to cut a cycle of calls, so that inlining ends |
| **clone** | A copy of a function made by specialization or raising, named `f$spec$N` or `f$raise$N`. `idr.origin` names `f` |
| **key** | What makes two clones the same: the origin plus the known parts of the arguments (`idr.spec_key`). Equal keys share one clone |
| **static shape**, **leaves** | An argument partly known at compile time (constants, constructors, closures). The leaves are its runtime parts, which become the clone's parameters |
| **binding time** | For each parameter: free, fixed, decreasing, bounded or other. It decides which known values specialization may substitute without making infinitely many clones |
| **raising** | Arity raising: a call whose result is only applied becomes a call of a clone that does the apply itself |
| **consumer** | The single user of a value |
| **tails** | The places a function body returns from: the return, and the yields of matches that reach it |
| **meets** | Finds next to it after a move, typically a constructor that a field read can fold against |
| **owned stage** | The module after idr-rc: counting is explicit, and the ownership verifier applies |
| **borrowed** | A parameter that holds no reference of its own. The caller keeps the reference |
| **reset / reuse / token** | `idr.reset` frees a dead box's fields and keeps its cell as a `!idr.token` if that was the last reference. `idr.reuse` builds a new constructor in it |
| **take** | `idr.take`: a match region takes its dying scrutinee apart. The fields move out with no count changed |
| **stack cell** | An `idr.con` marked `idr.stack`: its cell lives in the function's frame |
| **may_loop** | `idr.may_loop` in the loop of a function Idris did not prove total, so that an unused loop is not deleted |
| **budget** | A bound that turns non-termination into an error: `max-rounds`, `clone-limit`, and eval's ticks, arena and stack |
| **action** | An MLIR action: one evaluation (`idr-eval-call`), one clone (`idr-specialize-clone`), one raise (`idr-raise`). Actions can be counted, skipped and bisected |

## Reading a dump

**Get one.**

```sh
tools/compile.sh --directive dump-mlir Prog.idr prog   # dumps in prog.dump/
idris-mlir-cc prog.mlir --check --dump-after=all --dump-dir=out/
```

Files are named by step: `01-idr-simplify.mlir`, `02-idr-defunctionalize.mlir`,
..., `05-idr-rc.mlir`, `06-idr-tail-loops.mlir`, `07-idr-lower.mlir`. To see
one function, open its step and search for `func.func private @Prog.f(`.
Today every line carries a full source path (`loc(...)`). Filter it with
`sed 's/ loc([^)]*)//g'` until dumps print short locations.

**What to look for, by step.**

- *After simplify (01).*
  - Look for calls replaced by constants: evaluation worked.
  - Look for clones named `f$spec$N` (specialization) and `f$raise$N`
    (raising).
  - Functions marked `no_inline` are loop breakers.
  - A closed call that is still there crashed, or ran out of budget. Rerun
    with `--remarks-filter=idr-eval` to see which.
- *After defunctionalize (02).* No `!idr.fn` is left. Each closure type is
  now an `idr.data ... closures` whose constructors are named after their
  labels.
- *After idr-stack (04).* An `idr.con ... {idr.stack}` builds its cell in
  the frame.
- *After idr-rc (05).*
  - `idr.inc` and `idr.dec` are explicit.
  - `{idr.borrowed}` on a parameter means the function only reads it.
  - `idr.take` / `idr.reset` / `idr.reuse` mean a dead cell is reused in
    place.
  - A function you expected to reuse its input but that calls `idr.con`
    instead is where to look first.
- *After tail loops (06).* A loop reads like this:

  ```
  %r:3 = scf.while (%acc0 = %acc, %xs0 = %xs) : (i64, !idr.box<@L>) -> (i64, !idr.box<@L>, i64) {
    %p:4 = idr.match %xs0 ... -> (i1, i64, !idr.box<@L>, i64) {
      case @N() { ... idr.yield %false, poison, poison, %acc0 }   // stop, result = %acc0
      case @C(%h, %t) { ... idr.yield %true, %acc1, %t, poison }  // continue with (%acc1, %t)
    }
    scf.condition(%p#0) %p#1, %p#2, %p#3
  } do { ... scf.yield (the arguments) }
  return %r#2
  ```

  Each exit of the old body yields `(continue?, next arguments, result)`.
  Poison fills the half that is not used.
- *After lower (07).* No `idr.` op is left. Cells are LLVM structs.
  Counting is calls into the runtime (`idris_rt_*`), which LTO inlines.

**When something is wrong.**

| Symptom | First tool |
|---|---|
| The program behaves differently with evaluation than with `--no-eval` | `tools/bisect.sh Prog.idr idr-eval-call` finds the evaluation that changes it |
| A specialization or raise changes behaviour | `tools/bisect.sh Prog.idr idr-specialize-clone` (or `idr-raise`) |
| A pass crashes or fails the verifier | save the input of the failing step from the dump, then `idris-mlir-opt in.mlir --<pass>`, then shrink it with `idris-mlir-reduce` |
| Simplify runs out of rounds | `--remarks-filter=idr-simplify` shows what each round changed |
| A program leaks | run it with `IDRIS_RT_LIVE=1`, then read the owned-stage dump (05) of the functions it calls |
| Compile time | `--timing` and `--stats` on idris-mlir-cc |

## Where the rules for contributors are

- `AGENTS.md`: the working rules (what may import what, where facts must
  live, the checks to run).
- `PINS.md`: workarounds for upstream bugs.
- `upstream/`: those bugs, written to be filed.
