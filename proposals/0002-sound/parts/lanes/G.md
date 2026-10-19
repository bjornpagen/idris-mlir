<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## G — one verdict rule, a report of every compilation, and the LLVM half reachable from a lowered module
Findings: F08, F09
Owner / exclusive writes: `foreign/idr/include/idr/Driver/**`, `foreign/idr/lib/Driver/**`. No excludes. `foreign/idr/lib/CMakeLists.txt` (which lists IdrDriver's sources) is the coordinator's, so you add no `.cpp`; a new header is fine. Read-only for you: `compiler/src/IdrisMLIR/Frontend/Driver.idr` (lane I's), `tests/no-behaviour-options/run` (X3's) and every test.
Read first:
- **Packet:** README §1 I4, §3 F08 and F09, §4.4, §6 (F08 is G's; I writes the frontend's half).
- **The verdict at HEAD (`foreign/idr/lib/Driver/Run.cpp`):**
  - 63-86: the old `Verdict {Clean, Internal, Rejected}` and `status()`; Rejected wins.
  - 96-116: `runPipeline`. Line 111 prints the internal error unless rejected.
  - 123-184: `toObjects`; 129-132 is the `#llvm.target` check.
  - 200-282: `run`. 207-213 is the handoff registry ("exactly the dialects the frontend writes"); 225 the context; 234-240 the handler, whose `std::max` at 238 is unsynchronized; 244-253 the parse; 254-262 the full registry; 276-277 the setup error.
- **The chain (`foreign/idr/lib/Driver/Compile.cpp`):**
  - 36-61: `frontend`; its status is `ok`, `rejected` or `failure`.
  - 66-80: `link`.
  - 90-120: `compile`.
- **The command line and files:**
  - `include/idr/Driver/Compile.h:51-54`: `run`'s declaration.
  - `Main.cpp:86-108` (`compileInput`) and `:111-184` (`main` and its action switch).
  - `Options.cpp:17-60` (options in `--help` order); `Options.h:64-68` (`ok`, `failure`, `usage`, `rejected`).
  - `Artifacts.h:29-90` and `Artifacts.cpp:52-91` (`Plan::of`, `outputs`, `makeDirectories`, `Artifacts`'s removers).
  - `Report.h` (`Report()`, `cannotWrite`).
- **Refusals:** `include/idr/IR/IdrDialect.h:338-352` (`refuse`, `refusalRule`); `IdrBase.td:146-158` and `:166-206` (`Rule`, `RuleCategory`, `Idr_RuleCase::category`). Only idris-mlir-tblgen reads `category` (`tools/idris-mlir-tblgen.cpp:2159-2174`); C++ has no accessor.
- **MLIR:**
  - `mlir/include/mlir/Pass/PassInstrumentation.h:58-70`.
  - `mlir/include/mlir/Pass/Pass.h:134-146` (`Pass::Statistic` is an `llvm::Statistic`; `getStatistics()`) and `:65-76` (`getName`, `getArgument`; an adaptor's argument is empty).
  - `mlir/include/mlir/IR/Threading.h:36-79`: a parallel group's diagnostics are held by a `ParallelDiagnosticHandler` and replayed in order on the group's own thread when it ends.
  - `mlir/include/mlir/IR/Location.h:42-55` (`findInstanceOf`); `FileLineColRange::getFilename`, `getStartLine`.
  - `LLVM::TargetAttr` parameters `triple`, `chip` and `features` (`LLVMAttrDefs.td:1555`).
  - `DialectRegistry::appendTo` and `getDialectAllocator` (`DialectRegistry.h:195-206`).
- **The pipeline's output:** `foreign/idr/lib/Transforms/Pipeline.cpp:161-165` (convert-to-llvm, then idr-tail-calls). Its end is LLVM dialect ops with idr-target's `#llvm.target` and DLTI attributes (`dlti.dl_spec`, `dlti.target_system_spec`).
- **The frontend's half:** `compiler/src/IdrisMLIR/Frontend/Driver.idr:212-226`, `statusOf` and `statusOfAll`: an `InternalError` anywhere gives 1, otherwise 3.
- **The spec:** `tests/no-behaviour-options/run:16-18` (`kept`, the allowed flags).
Permitted outcome:
- **Mandatory (F08):**
  - the driver's one verdict rule, `Accepted < Refused < Internal`, the worst seen winning, held in one header;
  - every step folded into it;
  - the exit status computed from it (except a usage error, which stays 2);
  - `--report=<file>`, written for every compilation that reaches `compile`, whatever its verdict.
- **Mandatory (F09):** `idris-mlir` accepts a module with no `idr.program` whose every op is the LLVM dialect's, and runs only `toObjects` on it.
- **Named consumer adaptations, returned as text:**
  - X3 adds `report` to `kept`;
  - fixtures for X1 or the coordinator.
- **Mandatory check, no write:** that lane I's `Driver.idr` holds the same order.
- **Optional:** none.
Fixed decisions:
- **New header `include/idr/Driver/Verdict.h`, header-only, everything inline.**
  - `enum class Verdict : std::uint8_t { Accepted, Refused, Internal };` with the comment: "What a compilation's errors make of it, each worse than the one before. Refused: an error that names a rule, the program's. Internal: any other error, or a step that failed with none reported, the compiler's. The worst seen wins. A refusal fails the step that makes it, so no step runs after it and no error is its cascade: an internal error beside a refusal is from the same step, the compiler's, which must be fixed before the refusal can be believed."
  - `int statusOf(Verdict)`: Accepted gives `ok`, Refused gives `rejected`, Internal gives `failure`.
  - `llvm::StringLiteral nameOf(Verdict)`: `accepted`, `refused`, `internal`.
  - `class Outcome`, safe across threads under one `std::mutex`, with:
    - `void see(Verdict)` (keeps the max);
    - `Verdict verdict() const`;
    - `void diagnostic(std::string fields)`;
    - `void count(std::string key, uint64_t by)` (adds into a `std::map<std::string, uint64_t>`, creating the key at 0);
    - `void write(llvm::raw_ostream &) const`.
- **Report format (§4.4).** One line `verdict: <name>`, then a line `diagnostic: <fields>` for each diagnostic in the order the handler received them, then a line `statistic: <key>=<value>` for each statistic in `std::map` order (bytewise). The fields are `<severity> <rule> <file:line> <pass>`. No category field: a rule's category is a function of the rule, which `IdrRules.txt` (phrase TAB category) already gives, so a reader joins on the rule; a C++ reading of the category would be custom code for a second copy of an ODS fact:
  - **severity:** `note`, `warning`, `error` or `remark`, from `mlir::DiagnosticSeverity`.
  - **rule:** `stringifyRule(*refusalRule(d))` with each space written `-` (no phrase contains `-`, so the change is reversible), or `-`.
  - **file:line:** `<getFilename()>:<getStartLine()>` of `d.getLocation()->findInstanceOf<mlir::FileLineColRange>()`, or `-`.
  - **pass:** the argument of the innermost pass with a non-empty argument that the report's instrumentation has begun, and not yet ended, on the thread delivering the diagnostic; `-` when there is none (the parse, the classification, the translation). A diagnostic emitted inside a group that MLIR runs in parallel is replayed after the group, on the thread that ran it. Such groups are the pipeline's own `nest<FuncOp>` groups and idr-optimize's waves of more than one component (`Optimize/Waves.cpp:267`). The diagnostic therefore names the innermost named pass on that thread: `-` for a function group, `idr-optimize` for a wave. Which case applies depends on the program, never on `--num-threads`; only `--mlir-disable-threading` names the inner pass. Write this in the comment.
  - **statistic key:** `<getArgument(), or getName() when empty>.<Statistic::getName()>`. The value is the sum, over every run of every instance of that pass, of the statistic's increase between `runBeforePass` and `runAfterPass` or `runAfterPassFailed`. Every statistic of a pass that ran gets a line, zeros included.
- **The report file.** It is never removed: it says why a compilation failed.
  - `--report` is `cl::opt<std::string> reportPath("report", cl::desc("Write the compilation's verdict, diagnostics and pass statistics to this file, whatever the verdict"), cl::init(""))` in `Options.cpp`, right after `-o`, with its `extern` in `Options.h`.
  - `Plan::of(llvm::StringRef input, Product product, std::optional<std::string> report)` stores `const std::optional<std::string> report;`. It returns nullopt when the report is the input (by path or `sys::fs::equivalent`) or equals any output. `makeDirectories` makes the report's directory too. `outputs()` and the removers leave it out.
  - `--report` with any action but compiling is a usage error: `--report is a compilation's: give an input and -o`.
  - If the report cannot be written (`cannotWrite`), the compilation fails with status 1 and keeps no artifact.
  - A refusal by the frontend writes `verdict: refused` with no diagnostic lines: the frontend prints its own on stderr.
- **F09, by content: no option chooses how a program is compiled (the spec).**
  - The parse registry `readable` is `handoff`, then `appendTo`, plus `mlir::LLVM::LLVMDialect` and `mlir::DLTIDialect`.
  - If the module holds an `idr.program` among its top-level ops, it is a handoff module, and every op nested in it must be of a dialect `handoff.getDialectAllocator(ns)` knows. Otherwise: `op->emitError("is of no dialect the frontend writes, in a module that holds an idr.program")`.
  - If not, every nested op must be `isa<mlir::LLVM::LLVMDialect>(op->getDialect())`, and the module runs only `toObjects`. Otherwise: `op->emitError("is no op of the LLVM dialect, in a module that holds no idr.program: such a module is the pipeline's output")`.
  - `toObjects` also refuses a `#llvm.target` triple other than `targetTriple`: `internal error: the module is compiled for <t>, and idris-mlir for <targetTriple>`. A missing target keeps today's message.
Inputs: §4.4. Lane I's frontend half, read only to check it.
Outputs:
- `Verdict`, `statusOf`, `nameOf` and `Outcome` in `include/idr/Driver/Verdict.h`.
- `run(Artifacts &, mlir::TimingScope &, Outcome &)` in `Compile.h`.
- The `--report` option.
- `Plan::report`.
- The behaviour on an LLVM-dialect module.
Implement:
1. **`Verdict.h`.** Write it as fixed. It includes `idr/Driver/Options.h` (for the statuses), `llvm/Support/raw_ostream.h`, `<algorithm>`, `<cstdint>`, `<map>`, `<mutex>`, `<string>` and `<vector>`.
2. **`Options.cpp` and `Options.h`.** Add `reportPath`.
3. **`Artifacts.h` and `Artifacts.cpp`.** Extend `Plan` as fixed, and change the constructor to carry `report`. Update the header comment: a handoff module goes to the pipeline; a module of the LLVM dialect alone, the pipeline's output, goes to LLVM.
4. **`Main.cpp`.** Before the `switch`, refuse `--report` with a non-compile action (usage). In `compileInput`, pass the report to `Plan::of` and change the collision message to `-o and --report name outputs that collide with each other or with the input`.
5. **`Run.cpp`.**
   - Delete the old `Verdict` and `status`.
   - Add, in the anonymous namespace: `struct Frame { mlir::Pass *pass; llvm::SmallVector<uint64_t, 4> before; };` and `thread_local std::vector<Frame> frames;`.
   - Add `ReportInstrumentation : mlir::PassInstrumentation`, holding `Outcome &`. `runBeforePass` pushes a `Frame` with every statistic's `getValue()`. `runAfterPass` and `runAfterPassFailed` both pop the frame and `count` each statistic's increase.
   - Add a helper giving the innermost named pass, or `-`, and a helper building the fields of a diagnostic.
   - In `run`:
     - take `Outcome &outcome` and build `readable` (include `mlir/Dialect/DLTI/DLTI.h`; IdrDriver already links every dialect through `MLIRRegisterAllDialects`);
     - the handler calls `outcome.see(rule ? Refused : Internal)` for an error and `outcome.diagnostic(fields)` for every diagnostic, then returns `mlir::failure()` as now;
     - after the parse, if `!module` or the verdict is not Accepted, stop: `outcome.see(Internal)` if the verdict is still Accepted, then return `statusOf(outcome.verdict())`;
     - then classify; a failed classification has emitted an error, so stop the same way;
     - keep the full registry, the debug handler and the `usage` return of 276-277;
     - run `runPipeline` for a handoff module only, then `toObjects`.
   - In `runPipeline(module, outcome, rootTiming)`: add `ReportInstrumentation` after `idr::profile::addInstrumentation(pm)` and before `enableTiming` (the timer stays last). On `!ran` or a verdict that is not Accepted: `see(Internal)` if still Accepted; print the internal error only when the verdict is Internal; return `statusOf`.
   - Treat the translation stop in `toObjects` the same way, and add the triple check.
   - Rewrite the comments at 63-72 and 200-206 to the new rule and the two kinds of module.
6. **`Compile.cpp` and `Compile.h`.**
   - `compile` makes an `Outcome`, runs the chain, then writes the report when `artifacts.report` is set, keeping it only once it is written whole (`llvm::ToolOutputFile` and `keep()`), and calls `artifacts.keep()` only when the status is `ok` and the report was written.
   - Folding the chain:
     - the frontend's `rejected` is `see(Refused)` and returns `rejected`; its `failure` is `see(Internal)` and returns `failure`;
     - a nonzero code from `run`: `failure` or `usage` is `see(Internal)`; return `usage` for `usage`, else `statusOf(outcome.verdict())`;
     - a failed link is `see(Internal)` and returns `failure`.
   - Update `Compile.h`'s comment on `run`.
7. **Check.**
   - `python3 tools/check-units.py foreign/idr/lib/Driver/Run.cpp foreign/idr/lib/Driver/Compile.cpp foreign/idr/lib/Driver/Main.cpp foreign/idr/lib/Driver/Options.cpp foreign/idr/lib/Driver/Artifacts.cpp foreign/idr/lib/Driver/Prepare.cpp`. Prepare.cpp is listed because it includes driver headers; check every other Driver unit that includes a header you changed (`grep -l`).
   - `IDRIS_MLIR_ROOT=$PWD sh tests/no-behaviour-options/run`, diffed against `expected`. The one expected difference is `foreign/idr/lib/Driver/Options.cpp: report` under "flags that are not an input...", until X3's change.
   - Read `Driver.idr:212-226` as it stands at your handoff, and say whether it holds `Accepted < Refused < Internal` (an `InternalError` anywhere gives 1; otherwise any error gives 3).
Delete:
- The old `Verdict {Clean, Internal, Rejected}` and `status()` (`Run.cpp:63-86`).
- The "a refusal decides the verdict whatever else was reported" rationale.
- The `verdict != Verdict::Rejected` print conditions (`:111`, `:150`).
- The handler's unsynchronized `verdict = std::max(...)`.
NOT TO DO:
- No option that changes what is compiled (no `--from-llvm`, no debug counter).
- No category field and no C++ reading of a rule's category (generated or written): the rule is printed, and its category is `IdrRules.txt`'s.
- No report from `idris-mlir-opt` or the frontend.
- No reading of the frontend's stderr into the report.
- No change to `Prepare.cpp`'s or `ReadRuntime.cpp`'s flows beyond what compiles against the new headers.
- No edit to `Driver.idr`, `tests/**` or any CMake file.
- No parsing of MLIR's printed statistics.
Stop and return: Return when steps 1-6 are in and check-units passes for every Driver unit, and you have the spec's diff and your reading of the frontend's half. Missing operands to return: X3's `kept` change, and the coordinator's placement of your fixtures.
Acceptance:
- **F08:**
  - Input: a module that fails parse verification with a refusal (the first chunk of `tests/verify-cycle/verify-cycle.mlir`). Outcome: exit 3; the report holds `verdict: refused` and `diagnostic: error cycle <path>:<line> -`.
  - Input: the same refusal reported beside an internal error. Outcome: exit 1, `verdict: internal`. At HEAD this exits 3 (`Run.cpp:73,238`). By source review this is the discriminator: the enum's order, `std::max`, and `statusOf`.
  - Input: an accepted module (`tests/e2e-exit-42/e2e-exit-42.mlir`) with `--report`. Outcome: `verdict: accepted`, no `diagnostic:` line, and `statistic: idr-optimize.<name>=<n>` lines in bytewise order. The report is byte-identical across `--num-threads 1, 3, 5, 13`.
- **F09:** `idris-mlir-opt exit-42.mlir --idr-target --idr-pipeline -o m.mlir`, then `idris-mlir -c m.mlir -o m.o`, then the pinned clang link: the program exits 42. At HEAD the parse fails on the `llvm` ops. A `func.func`-only module gives exit 1 and the classification error.
- **The spec:** `no-behaviour-options` matches its `expected` once `report` is in `kept`.
- **This machine:** check-units and the spec diff.
- **Only the owner's build:** the fixtures' runs.
Tempting partial solution: Swapping `Rejected` and `Internal` in the old enum and calling F08 done. That leaves the unsynchronized handler, the frontend's statuses folded nowhere, a step that fails silently mapped by accident, and no report; the acceptance's report lines and the cross-thread byte identity reject it. For F09, adding the LLVM dialect to the parse registry and skipping the pipeline when the module has no `idr.program`: that would also run `toObjects` on a half-lowered `func.func` module and fail in translation with a confusing error. The classification rejects it with a named one.
Escalate if:
- A site that reports a refusal does not fail its step (by your reading: the verifier's knot check and idr-demand's `checkInPlace` fail theirs at HEAD), so that a later step could run on a refused program: name the site; do not change the order.
- Lane I's `Driver.idr` gives 3 for a build that reported an internal error.
- X3 will not allow `report` in `kept`.
- MLIR's instrumentation does not pair `runBeforePass` with `runAfterPass` or `runAfterPassFailed` on one thread for some pass of the pipeline.
- An LLVM-dialect output of the pipeline holds an op of another dialect.
Handoff:
- **Shape (per parts/common.md):** changed paths, each mapped to an obligation; contracts supplied; consumer adaptations made; hub text the coordinator must apply; checks actually run with their results, or NotRun; unresolved seams, each with its evidence.
- **Requests:**
  1. For X3: `tests/no-behaviour-options/run`, add `report` to `kept` after `o c`. This is an output, as §4.4 says.
  2. Fixture texts for the coordinator to place under `tests/obs-debug-counter/` (X1's), each with a first-line `NEEDS-ACCEPTANCE`. Give the full text for:
     - `report-accepted.mlir`: exit-42's module, `--report`, and FileCheck of `verdict: accepted`, `CHECK-NOT: diagnostic:`, and a `statistic: idr-optimize.` line;
     - `report-refused.mlir`: the knot chunk, `%status 3`, `verdict: refused`, `diagnostic: error cycle `;
     - `lowered-input.mlir`: `idris-mlir-opt --idr-target --idr-pipeline`, then `idris-mlir -c`, `%cc` and `%status 42`;
     - `lowered-mixed.mlir`: a `func.func` module, `%status 1`, the classification error, and `verdict: internal`.
  3. Your reading of the frontend's half.
