<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
<!-- P0 wave 1 brief: moved out of proposals/0000-mlir-native.md §2 and §3 on 2026-10-21, unchanged; "P0 §2" and "P0 §3" in other documents mean this file. -->

# P0: the codebase brief and what history taught (wave 1)

## 2. The codebase today: wave 1's brief

Wave 1 works from this section and does not survey our code. All of it
is *measured* at e96bb991 (2026-10-21) unless marked otherwise.

**Size.**

| part | lines |
| --- | ---: |
| `foreign/idr` C++ (379 files) | 59,886 |
| of which `lib/Transforms` | 18,824 |
| of which `lib/IR` | 13,199 |
| of which `include/` | 10,457 |
| of which `lib/Conversion` | 5,034 |
| of which `lib/Analysis` | 3,564 |
| of which `tools/` (4 drivers, one custom TableGen backend) | 3,450 |
| of which `lib/Driver`, `lib/Target`, `lib/Support`, `unittests` | 5,358 |
| `foreign/idr` TableGen (21 `.td` files) | 5,900 |
| runtime C/C++ (`runtime/`) | 5,845 |
| Idris frontend (`compiler/src`), for scale | about 31,000 |

**The C++ standard** is already C++26 (*read*: `CMakeLists.txt:317`,
`CMAKE_CXX_STANDARD 26`), compiled against MLIR's headers at the pin.

**Patterns in the C++** (occurrences of each token, `lib`, `include`,
`tools`, `unittests`):

| pattern | count |
| --- | ---: |
| `isa<` | 275 |
| of which `isa<A, B, ...>` over several types | 48 |
| `dyn_cast<` (and `_or_null`, `_if_present`) | 452 |
| `cast<` | 217 |
| `std::variant<` | 60 |
| `std::visit`, `std::get_if`, `std::holds_alternative` | 192 |
| `function_ref<` | 84 |
| `switch (` | 44 |
| `TypeSwitch<` | 4 |
| `virtual` | 10 |
| `template <` | 139 |
| `requires` or `concept` | 20 |
| `hasTrait<` | 49 |
| `getEffects` or `MemoryEffects` | 139 |
| `getAnalysis<`, `getCachedAnalysis`, `AnalysisManager` | 105 |
| `worklist` | 87 |
| `DenseMap<` or `DenseSet<` | 212 |
| `std::mutex`, `std::atomic`, `SmartMutex` | 22 |
| `parallelFor*` | 10 |
| `.walk(` | 104 |
| `dataflow::` or `DataFlowSolver` | 44 |

**TableGen.** 191 op definitions, 13 types, 10 attributes, 15 native
traits or trait lists, 12 interfaces, 72 effect declarations
(`MemoryEffects<`, `MemRead`, `MemWrite`, `MemAlloc`, `MemFree`), 4 pass
definitions. A custom backend, `idris-mlir-tblgen`, generates the Idris
side's view of the dialect from the same records (*read*: b9d4d592's
message, "the dialect's table is one ODS record on both sides").

**The dialect's surface** (*read*: `foreign/idr/include/idr/IR/*.td`,
op mnemonics as their classes spell them, with the class's prefix):
- *Program and values* (`IdrOps.td`): `program`, `func`, `call`,
  `return`, `constant`, `con`, `field`, `tag`, `dest.write`;
  (`IdrMatchOps.td`) `match`, `match_lit`, `yield`.
- *Closures and suspensions* (`IdrClosureOps.td`): `closure`, `suspend`,
  `delay`, `force`, `apply`, `memo.run`.
- *Ownership and memory* (`IdrOwnershipOps.td`): `dup`, `drop`, `borrow`,
  `share`, `cell.new`, `cell.stack`, `cell.recycle`, `cell.init`, `take`,
  `unpack`, `own.adopt`, `own.give`, `lin.enter`, `lin.use`.
- *Big integers and naturals* (`IdrBigOps.td`, prefix `big.` on most):
  add, sub, mul, and, or, xor, shl, shr, div, mod, neg, pred, cmp,
  conversions to and from words, doubles, strings and `nat`.
- *Words* (`IdrScalarOps.td`): `divs`, `divu`, `mods`, `modu`, `shls`,
  `shlu`, `shrs`, `shru`, char and int conversions, `double_head`,
  `int_head_s`, `int_head_u`: one op per signedness.
- *Strings* (`IdrStringOps.td`, some under `str.`): append, cons,
  from_char, pack, concat, show (sint, uint, double), substr, reverse,
  tail, length, bytes_length, scalar_at, index, head, cmp, to_int,
  to_double, and byte-level ones.
- *Checks* (`IdrCheckOps.td`, prefix `check.`): `crash`, `crash_str`,
  `may_loop`, `nonzero`, `in_bounds`, `nonempty`, `finite`, `range`.
- *Arrays* (`IdrArrayOps.td`, some under `array.`): `tabulate`,
  `tabulate_io`, `fold_last`, `scan_last`, `transpose`, `yield`, `new`,
  `get`, `set`, `update`, `element.update`, `nat.to_extent`, `tie_shape`.
- *IO* (`IdrIOOps.td`, prefix `io.`): put_str, put_char, put_sint,
  put_uint, put_double, get_byte, get_line, write_bytes, read_bytes, eof,
  buffer load, store, copy and string access, `world.new`, and others.
- *Platform* (`IdrPlatformOps.td`): about 60 ops, one per OS call: files
  (open, close, read_line, read_chars, write_line, flush, seek, size,
  poll, the six stat times as separate ops, chmod, remove), directories,
  arguments, environment, sleep, time, pid, exit, terminal, errno, eight
  clocks, handles.
- *Types* (`IdrTypes.td`, `IdrOwnershipOps.td`): `token`, `cell`, `data`,
  `box`, `fn`, `lazy`, `str`, `big`, `nat`, `world`, `q` (the grade),
  `dest`. `data` is a mutable type: a name whose body the program's table
  holds once.
- *Attributes* (`IdrAttrs.td`): `con`, `closure`, `big`, and the
  program's table of data types (`#idr.types<...>`).
- *Native traits and interfaces*: SameValue, TakesReference,
  BuildsValue, NoReturn, MayCrash, GuardedOp, PerformsIO, ObservableIO,
  ConsumesOperands, ConsumesOnly, Primitive, NoRuntimeForm,
  CarriesOperand, ResultCarriesOperand; op interfaces Flow, MayCrash,
  Guard, Match, RunsLabels, YieldTargets, Generating, Update,
  LastAxisFold, StrBuilder; type interfaces ValueFacts, Literal.
- *Effect resources*: Crash, IO, Divergence, Lin, Reference, MemoState.
- An `Idr_Runtime<"symbol">` trait ties a primitive op to the runtime
  function that is its one meaning.

**Types that carry what Idris proved.** `!idr.q<quantity, permission, T,
lifetime>`, with `!idr.lin<T>` = (one, plain), `!idr.own<T>` = (many,
own), `!idr.excl<T>` = (many, excl); a verifier checks the grades after
every pass (*read*: `foreign/idr/include/idr/IR/IdrTypes.td:270`).
AGENTS.md forbids keeping a proved fact in a discardable attribute.

**The pipeline** (*read*: `foreign/idr/lib/Transforms/Pipeline.cpp`),
one fixed sequence, no flags: deduplicate, defunctionalize (every
closure becomes a constructor of a closed sum; everything after is
first-order), knots, effects, contify, optimize (inline and specialize,
each function once, bottom-up), symbol DCE, columns, canonicalize and
CSE, structure loops (arrays to linalg), bufferize, accumulate, frames,
counting (`idr-rc-cells`, `idr-rc-stack`, `idr-rc-grades`,
`idr-rc-exclusive`), demand, TRMC, tail loops, narrow, lower to
func/memref/vector, entry, the vectorization schedule (transform
dialect), linalg to loops, upstream's lowering to LLVM, tail calls.

**Analyses and solvers of ours** (*read*: file names): in
`lib/Analysis`: BindingTimes, CallCycles, Constants, Effects,
Identities (three files), Inline, Labels and LabelSites (the
defunctionalization label solve), Ranges, Recursion; in
`lib/Analysis/Ownership`: Borrows, Captures, Exclusivity (three files:
the solve, the analyses, the graph), Reuses, Uses, Values. More live
inside passes (`Transforms/Stack`'s lifetime inference, `Tail/Frames`'s
plan, `Optimize`'s demand). `lib/Support/Scc.cpp` holds an SCC utility;
`lib/Support/Actions.cpp` and `Profile.cpp` the tracing.

**Still on upstream's dataflow framework** (*measured*, files naming
`dataflow::` or `DataFlowSolver`): `Analysis/Constants`, `Analysis/Ranges`,
`Analysis/Ownership/Borrows`, `Transforms/Narrow/{Lanes,Copy}`,
`Transforms/Tail/Returned`, `Transforms/Effects/Constants`.

**Upstream patches** that touch the analyses and the infrastructure
(*measured*: which `upstream/<bug>/` directories hold an `llvm.patch`, the
carried form, and which only a `pull-request.diff` or a submission, the
retired form; corrected 2026-10-21 from the history lane's reading):
- *Carried*: `remove-dead-values` at an unreachable block (06); liveness
  at a non-forwarded terminator (28) and its trivially-dead check (63);
  dead code under a nested symbol use (29); forward dataflow's callee
  lookup (05); the greedy driver's multi-region ancestors (62); one-shot
  bufferization's module function interface (24); bytecode's deferred
  quadratic (03); CSE (23, 56); integer ranges (09, 57); and others. Of
  these, 06, 28 and 63 reach no pass of ours since 16005000 dropped
  `remove-dead-values` (`audits/p0/20-history.md`, hist-Q3).
- *Retired*: `remove-dead-values` (01, 16, 22), SCCP (02, 17), bytecode
  (25), one-shot bufferization's tensor-like copy (27).

**The trait layer, as another agent read it today** (*recalled*, from
that agent's report to the owner; wave 2 checks it):
- Right already: `GuardedOp` (the trait supplies the interface method,
  guards read from a compile-time tuple); `Idr_ConsumesOnly` and
  `Idr_ResultCarriesOperand` as `TraitList`s bundling a marker, the
  memory-effects interface and a range interface; effect resources
  (`IOResource`, `ReferenceResource`) rather than effect flags; the
  `Decides` trait, declared in ODS, with a `verifyTrait`. Correction
  (*measured*, 2026-10-21, `audits/p0/07-ownership-analysis.md`): no
  `Decides` trait exists at e96bb991, the tree P0 audits; the word occurs
  once, in a comment (`include/idr/IR/Symbols.h:197`). The report may
  describe work not on this checkout.
- Gaps: traits that state a checkable fact with no `verifyTrait`
  (`SameValue`); `isa<>` ladders restating trait classes
  (`IR/Canon/Sink.cpp:114`, `Transforms/StructureLoops/Forms.cpp:132`,
  four copies of `isa<ReturnOp, YieldOp>` in `Transforms/Tail`); three
  representations of "does IO" (the `PerformsIO` trait, `IOResource`
  effects, and a body effect read off world operands); traits read once
  or never (`TakesReference`, `BuildsValue`, `ObservableIO`).

## 3. What history has already taught

Every design in this proposal must fit **the stage-1 module**: the
frontend compiling itself writes a 71 MB MLIR module of some 70,000
functions, with matches of tens of thousands of cases (*measured*,
proposal 0001). The pipeline has never finished on it. The fixes of
2026-10-20 and 21 each removed a wall (*read*, the commits):

| commit | what ran out | why |
| --- | --- | --- |
| ffa91113 | exclusivity on `DataFlowSolver`: 627 GB footprint | a lattice per value, an `Executable` per program point, a predecessor state per function, nested maps, uniqued program points |
| 16005000 | upstream `remove-dead-values`: 52 GB | a whole-program liveness state per value (after four carried patches) |
| e96bb991 | building exclusivity's own graph: did not finish | an interface query per pair of terminator and region successor, quadratic in a match's case count |
| 16005000 | `idr-frames`: 43 GB | ours: a body cloned per pair of member and result type |
| b8301ebe | `idr-rc-stack`: 47 GB | ours: a candidate bit vector per value, copied along every edge |
| 3a96c407, 7987388b | `idr-optimize`: 75 million pattern attempts | ours: patterns matching any op |
| 98c6315c | `idr-optimize`: threads queued on the context's write lock | ours: a mutable type's facts read under the context's lock |
| 73bba53f | `idr-defunctionalize`: 843 s | ours: the table of data types rebuilt per declaration |

What that suggests (*conjecture*, for the lanes to confirm or refute):
- Upstream's analysis framework failed on its **state model** (what it
  keeps per value and per program point), not its algorithms. The
  answer may be a scoped solve (per function, per call-graph SCC), a
  patch to the state's representation, or an honest solver of ours.
- The interface layer (`RegionBranchOpInterface` and kin) has costs that
  scale with region and successor counts; how upstream expects a client
  to query it at scale is a research question, not a reason to bypass it.
- Several walls were ours, and each was fixed by a representation: those
  lessons carry over into the solver layer's design.

Wave 2's history lane completes this table from the whole git history,
the audits as they stood at 77eaa5b1 (`audits/rederived.md`, the label
solve, the leak audit), `PINS.md`'s workarounds and `upstream/`'s reports.

