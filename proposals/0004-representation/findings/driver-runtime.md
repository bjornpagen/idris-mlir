<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Representation survey: driver-runtime

Area: `foreign/idr/{include,lib}/idr/{Driver,Support,Target}`, `foreign/idr/tools/`,
`foreign/idr/unittests/`, and `runtime/` (Alloc, Big, Doubles, Io, Numerals,
Platform, Rc, Start, Strings, `idris_rt.h`, the `cpu_*.h`). Read whole, with the
callers in `lib/Conversion/{Runtime,RuntimeCalls,Counting,Elements,Entry}.cpp`
and the ODS the generator reads. Nothing was built or run.

## The area as it stands

The good representations are already here. A big is one word whose low bit is
the tag, and `rt::big::Operand` gives GMP one view of a small and a large value,
so every slow path is written once. A string is ASCII exactly when
`bytes == scalars`, so no flag says it twice. The count field holds 0
(persistent), 1 to MAX-1 and MAX (saturated), and one unsigned-wrap test
(`isCounted`) handles both marks. The dying list runs through the dead fields of
the cells. In the driver, `Plan` holds `Source` and `Product` as variants, and
`Verdict` is one total order held in one `Outcome`. The runtime ABI, the rules
and the big-to-word table are generated from ODS. The weak points are where a
value travels with no type to carry what is known about it:
- In the driver, a failure is a print at the site plus an `int`, `bool`, null or
  `optional` handed up, and the caller works out the verdict again.
- The command line is a set of flat `cl::opt` globals. They are checked
  piecemeal in `Main.cpp` and read deep inside the steps.
- In the runtime, the handle table leaves the three standard streams outside
  the table, so every file operation compares integers to find them.
- The generated ABI uses one `Kind` enum for operands and for results, so every
  switch over it carries cases that cannot happen.

The answers to the area's own questions:
- **Invalid option combinations:** D2.
- **Small/big and unique/shared casework:** essential, and already one tag
  each (kept list).
- **Per-target code outside the platform layer:** D4, R4.
- **Sentinels and nulls threaded through returns:** D1, R1, R7.
- **Documented semantics in two places:** R3, R2.

## Findings, ranked (branches removed against risk)

### D1. A driver failure is a print plus a sentinel, not a value that carries its class

- **Evidence:** `lib/Driver/*.cpp` has 40 `Report()` sites (28 with no
  "internal error" class, 15 literals `"internal error: ..."` spelled by hand)
  and 62 sentinel returns (`return failure/usage/nullptr/std::nullopt/false`).
  - `Run.cpp:74-77` `stopped()`.
  - `Run.cpp:135-160` `runPipeline` returns `usage` (`:140`) or a status.
  - `Run.cpp:167-237` `toObjects` returns `failure` at 5 sites without folding
    into the outcome.
  - `Run.cpp:338-339` returns `usage` after a diagnostic already set the verdict.
  - `Compile.cpp:105-107` `chain` maps `code == usage ? usage : statusOf(outcome.verdict())`.
  - Null, `optional` or `bool` after a print: `readRuntime`, `readMembers`,
    `prepareMember`, `nativeTarget`, `linkRuntime`, `namesApart`, `externalize`,
    `emit`, `writeObjects`, `makeDirectories`, `writeReport`.
  - `Prepare.cpp:63-162` returns ints throughout.
- **Counterexample:**
  - `idris-mlir x.idr -o a --report=r -mlir-print-ir-module-scope` with
    threading on: `applyPassManagerCLOptions` emits an error with no rule
    (verdict Internal) and `runPipeline` returns `usage`. The exit status is 2
    while the report says `verdict: internal`. The two copies of the outcome
    disagree.
  - A failed link (`Compile.cpp:82-86`), an unreadable runtime or
    `cannot write <obj>` writes a report of `verdict: internal` with no
    `diagnostic:` line. The report's stated purpose ("it says why the
    compilation failed") fails: driver errors never reach `Outcome`.
  - `cannot write`, `runtime member ... carries no bitcode` and `the program
    defines X` exit 1 as Internal but print no "internal error:" class. So the
    printed class and the verdict are two facts that differ.
- **Root cause:** a step's failure has no representation. Its class (usage,
  internal) lives in prose at the print site and in an int code. The verdict is
  then rebuilt by `stopped`, `Outcome::failed` and `chain`.
- **Correction:** LLVM's mechanism, already used in this area by
  `Partition::of`, `compileBin` and `target::machine`: every driver step returns
  `llvm::Error` or `llvm::Expected<T>`. The payload is one `DriverError` ErrorInfo
  holding a `Verdict` (Internal, or Refused for `namesApart`'s program/runtime
  clash) and its message. `compile` is the one handler (`handleAllErrors`): it
  prints `idris-mlir: ` plus the class prefix from the verdict's row, folds the
  verdict, and appends the report's `diagnostic:` line. The two failures that
  happen inside `run` but depend only on the command line (the pass manager's CL
  options against `--mlir-disable-threading`, and `-log-actions-to`'s file) are
  checked at the boundary, before the plan is armed. So a usage error never meets
  a verdict, and the exit status is `statusOf(outcome.verdict())` alone.
- **Deletion:**
  - `stopped()` and the usage mapping in `chain`.
  - Every `int` status return in `run`, `runPipeline`, `toObjects` and `prepare`.
  - The 15 hand-written "internal error: " literals, and 40 `Report()` sites
    replaced by `make_error`.
  - The null/optional/bool-after-print returns of the 11 functions listed.
  - `Outcome::failed()`: a step either returns an error that carries its verdict
    or succeeds.
- **Consumers:** `lib/Driver/{Run,Compile,Main,Prepare,ReadRuntime,LinkRuntime,Artifacts,Outcome}.cpp`,
  `include/idr/Driver/{Verdict,Report,Compile,Runtime,Artifacts}.h`,
  `tests/no-behaviour-options/run` (no change), the driver's transcripts
  under `tests/compiler/` whose stderr names an internal error.
- **Discriminator:** (a) A report test with a link that cannot run (a
  `--runtime` naming a missing file): before, the report has no `diagnostic:`
  line; after, it has one. (b) `-mlir-print-ir-module-scope` without
  `--mlir-disable-threading`: before, exit 2 with `verdict: internal`; after,
  exit 2 at parse and no armed artifacts. (c) A spec: no `return failure|usage`
  in `lib/Driver` outside `Main.cpp`'s parse.
- **Verification here:** `make typecheck` compiles the driver. Nothing runs (it
  links MLIR).
- **Size and risk:** about 150 lines changed, about 60 sentinel branches and 15
  literals deleted. The risk is medium: stderr text must stay byte-identical where
  transcripts pin it. The class prefix is now uniform, so the 28 unclassified
  internal messages gain "internal error: ", a visible change. Essential cases
  that stay: the three verdicts, and usage as a parse-time exit.
- **Insight:** 5, 6 (null and sentinel replaced by a carried value), 8.

### R1. The standard streams live outside the handle table, so every file operation compares integers to find them

- **Evidence:**
  - `runtime/Io/Io.h:46-48,53`: `nullHandle = -1`, `firstHandle = 3`, and
    `Kind {Free, File, Directory, Times, String, KeptString}`, with no kind for a
    standard stream.
  - Integer-range branches: `Io/Bytes.cpp:16,20,35`; `Io/Files.cpp:17,47-48,59,61,71-72,120`;
    `Io/Input.cpp:91,93`; `Io/Lines.cpp:47`.
  - `Lines.cpp:19-51`: `Source{File *file}` uses `file == nullptr` to mean
    standard input, branched in `next()` and in `failed()`.
  - 8 sites of `handle - firstHandle` offset arithmetic (`Handles.cpp`).
  - About 17 branches in all.
- **Counterexample:**
  - `Source source{}` (as the code builds it, `Lines.cpp:66,107,119`) *is*
    standard input until `sourceOf` overwrites it. A null pointer stands for a
    stream.
  - Each new operation decides by hand what 0, 1 and 2 mean:
    - `idris_rt_io_eof(1)` gives 0 by one range test.
    - `idris_rt_io_file_error(2)` gives 0 by another.
    - `idris_rt_io_file_read_chars(_, 1)` fails with EBADF, because `readBytes`
      never asks.
  - `rt::io::writeBytes` returns -1 for EBADF, a sentinel that every ABI entry
    clamps again (`Bytes.cpp:51,57`), except `file_write_line`, where -1 and 0
    mean different things for an empty line.
- **Root cause:** a handle and a slot are two coordinate systems (`h` against
  `h - 3`). The streams' behaviour (stdin's buffer, stdout's buffer, stderr after
  a flush) is spread through each operation instead of held by the stream.
- **Correction:** handle `h >= 0` *is* slot `h`. Slots 0, 1 and 2 are made with
  the table as kinds `Input`, `Output` and `Error`; they are never freed, and
  `releaseHandles` re-seeds them. Each stream kind has one row of a
  `constexpr StreamOps` table (Raymond's method table): `write`, `read`,
  `readByte`, `flush`, `close`, `failed`, `ended`, `descriptor`, `poll`. The
  `File` row runs over `rt::platform::File`, and the three standard rows run over
  the buffers. `streamOf(h)` is the one lookup, and EBADF is decided there once.
  The tagged union stays: the runtime links no C++ library, so `std::variant` is
  not available.
- **Deletion:**
  - The 17 integer-range branches and `firstHandle`.
  - The 8 offset subtractions.
  - `Source` and `sourceOf` (`readByte` is the stream's).
  - `descriptorOf`'s range test.
  - The internal -1 of `writeBytes` and `readBytes`, which become the op's own
    result at the ABI.
- **Consumers:** `runtime/Io/{Io.h,Handles,Bytes,Files,Input,Lines,FileTimes,Directories,Output}.cpp`,
  the handle prose in `runtime/idris_rt.h:369-380`, and
  `tests/toolchain/{io-buffer,runtime-api}`.
- **Discriminator:** a property program over every `idris_rt_io_*` file entry
  on the handles {-1, 0, 1, 2, an open file, a closed one, a directory}.
  Its results are the same before and after; the relation is the old
  build's, not an oracle. A grep spec: no comparison of a handle with a literal
  outside `Handles.cpp`.
- **Verification here:** the runtime units compile with the host clang
  (typecheck build). The runtime's C property programs run here as in 0002 §11.
- **Size and risk:** about 120 lines, about 17 branches and 8 offsets deleted.
  The risk is low to medium (stderr's flush-first order and stdout's close-is-flush
  must keep their meaning). Essential cases that stay: -1 as base's null pointer,
  the four stream behaviours (now table rows), and KeptString against String
  (base's ownership).
- **Insight:** 7, 8, 11.

### T1. The generated runtime ABI has one `Kind` for operands and results, so each consumer's switch has impossible cases

- **Evidence:**
  - `tools/idris-mlir-tblgen.cpp:916-950`: one `Word` enum, with `bool result`
    threaded through `wordsOf` (`:2159`) and the result's `World` filtered at
    `:2259-2261`.
  - `emitRuntimeAbiDefs:2334-2408` emits one `idr::runtime::Kind`.
  - Consumers in another area:
    - `lib/Conversion/Runtime.cpp:68-91` `takes`: a `Void` case and an
      `llvm_unreachable`.
    - `:94-115` `resultType`: `World`, `Signed`, `Unsigned` and `Buffer` cases,
      and an `llvm_unreachable`.
    - `:150-176` `Runtime::call`: a `Void` case and an unreachable.
    - `lib/Conversion/RuntimeCalls.cpp:55-85` `givenRange` lists 9 cases, 5 of
      which no result can be.
  - About 13 impossible cases and 3 unreachables in all.
- **Counterexample:** an ODS op `Idr_Runtime<"f">` whose result is
  `Idr_Rank1ArrayValue` generates `Function{..., result = Kind::Buffer}`, which
  compiles. The lowering then reaches `llvm_unreachable("the runtime's table
  gives a result of one C value, or none")`, which is undefined behaviour in a
  release build, at the first call. No check sits at the generator.
- **Root cause:** an operand's kinds (World, Int32, Int64, Double, Signed,
  Unsigned, Str, Big, Buffer) and a result's kinds (Void, Int32, Int64, Double,
  Wrapped, Order, Str, Big) are two different sets kept as one enum.
- **Correction:** the generator emits `enum class OperandKind` and
  `enum class ResultKind`, and `Function` holds
  `std::span<const OperandKind> operands` and `ResultKind result`. `wordsOf`
  splits into `operandWords` and `resultWord`. A result type outside
  `ResultKind` is a TableGen `PrintFatalError` naming the op.
- **Deletion:** the `Void` cases of `takes` and `call` with their unreachables;
  `resultType`'s 4 impossible cases and its unreachable; `givenRange`'s 5
  impossible cases; the generator's `result` flag and its World filter.
- **Consumers:** `tools/idris-mlir-tblgen.cpp`, `lib/Conversion/{Runtime,RuntimeCalls}.cpp`,
  `include/idr/Conversion/Runtime.h`, and `unittests/` (they use `Abi<Op>::function`
  only, unchanged).
- **Discriminator:** a scratch ODS op with a buffer result fails
  `idris-mlir-tblgen` (before, it generates); the generated
  `IdrRuntimeAbi.inc` otherwise lists the same symbols.
- **Verification here:** `make typecheck` (generator and Conversion compile);
  the generated `.inc` diffs by eye.
- **Size and risk:** about 40 lines, about 16 cases deleted, low risk. Essential
  cases that stay: Signed against Unsigned (an operand's extension), Wrapped and
  Order (a result's reading).
- **Insight:** 4, 7.

### D2. The command line is flat globals, checked piecemeal in `Main.cpp` and read deep in the steps

- **Evidence:**
  - `include/idr/Driver/Options.h:22-45`: 11 `extern cl::opt` globals plus an
    `Action` enum.
  - Checks at `lib/Driver/Main.cpp:88-104` (input and -o; frontend options with
    a module), `:159-162` (`--report` with a non-compile action) and `:178-185`
    (prepare with an input, or without -o): 6 combination checks.
  - The globals are read inside steps:
    - `Compile.cpp:42-48` reads `idrisPrefix`, `packagePath`, `packages` and
      `noPrelude`.
    - `Compile.cpp:77` reads `runtimePath`.
    - `ReadRuntime.cpp:62,71,88,184,209,221-243` reads `runtimePath` and
      `runtimeBitcodeHome()`.
    - `Prepare.cpp:71,92,144-159` reads the bitcode home, `runtimePath` and
      `outputPath`.
    - `Run.cpp:281,331-334` reads the thread budget and `logActionsTags`.
- **Counterexample:** these combinations are accepted, and the extra options
  silently ignored:
  - `idris-mlir --print-target-triple -c -p contrib x.idr` prints the triple.
  - `idris-mlir --prepare-runtime -o r.o -c --log-actions-tags=t` prepares.
  - `idris-mlir --print-link-flags --num-threads=4 --no-prelude` prints the
    flags.

  Meanwhile `--report` with any of them, and `-p` with a module, are refused. Half
  of the invalid combinations are refused and half pass.
- **Root cause:** what one invocation does is not a value. Each action's options
  are a product of every global, and validity is re-tested where each global is
  read.
- **Correction:** `Options.cpp` parses once into
  `using Invocation = std::variant<Compile, Prepare, Print>`, and the globals
  become file-local:
  - `Compile{Plan plan; FrontendArgs frontend; RuntimePath runtime; unsigned threads; Tags tags}`.
    `FrontendArgs` moves into `FromIdris`, so a module input cannot carry it.
  - `Prepare{std::string output; RuntimePath archive}`.
  - `Print{Question}`.

  Any option outside its action's set is a usage error at the parse. `main`
  visits the variant, and each step takes its own part as an argument.
  `cl::SubCommand` is rejected: it would change the user command line that
  scripts, CMake and `bench/run.sh` call (`--print-link-flags`), and MLIR's
  registered options would each need `cl::sub`.
- **Deletion:** the 6 ad-hoc checks in `Main.cpp`, every read of a driver
  global outside `Options.cpp`, and `frontendOptions`.
- **Consumers:** `include/idr/Driver/{Options,Artifacts,Runtime,Compile}.h`,
  `lib/Driver/{Options,Main,Compile,Run,Prepare,ReadRuntime,LinkRuntime}.cpp`,
  `tests/no-behaviour-options/run` (the kept list is unchanged).
- **Discriminator:** `idris-mlir --print-target-triple -c` exits 2 (before: 0).
  A spec: no driver `cl::opt` is `extern`.
- **Verification here:** `make typecheck`.
- **Size and risk:** about 120 lines, 6 checks folded into one parser. The risk
  is low; the behaviour change is stricter refusal of combinations that were
  already meaningless. Essential cases that stay: the input's kind by extension,
  and `Plan::of`'s collision check.
- **Insight:** 4, 6.

### T2. A buffer is passed to the runtime as three C values, of which the runtime reads one

- **Evidence:**
  - `tools/idris-mlir-tblgen.cpp:942-943,2304-2309`: `Word::Buffer` is the one
    word with three C parameters, through a special branch in `cDeclaration`.
  - `lib/Conversion/Runtime.cpp:156-161`: the lowering pushes the cell, then a
    GEP to its first byte (`elementsOf`), then the size.
  - `runtime/Io/Buffer.cpp:15-28` and `Io/Bytes.cpp:48-58`: every buffer entry
    leaves the cell and the size unnamed, and `idris_rt.h:335-339` says "Only the
    first byte is read".
  - `idris_rt_io_buffer_copy` takes 9 parameters, 4 of them dead (5 ops with
    `Idr_Rank1ArrayValue` operands).
- **Counterexample:** the caller passes `bytes` as a second copy of
  `(char *)(cell + 1)`, and nothing checks that they agree. Two words per buffer
  per call go dead, and they push `buffer_copy` onto the stack on x86-64 SysV.
- **Root cause:** the ABI word mirrors the lowered value's components
  (cell, size) rather than what the runtime reads. A string, by contrast, is one
  pointer to its cell, and the runtime derives its bytes (`idris_rt_str_bytes`).
- **Correction:** a buffer is one `idris_rt_array *`, as a string is one
  `const idris_rt_str *`. `idris_rt.h` gains an inline `idris_rt_array_bytes(cell)`,
  and `Word::Buffer` becomes an ordinary one-parameter row.
- **Deletion:** the Buffer branch of `cDeclaration`, the Buffer case of
  `Runtime::call` (the `elementsOf` and the append), and 4 dead parameters each
  in `write_bytes`, `read_bytes` and `buffer_set_string`, 6 in
  `buffer_get_string` and 8 in `buffer_copy`.
- **Consumers:** `tools/idris-mlir-tblgen.cpp`, `lib/Conversion/Runtime.cpp`,
  `runtime/{idris_rt.h,Io/Buffer.cpp,Io/Bytes.cpp}`, `tests/runtime-api`,
  and `tests/lower-buffer/lower-buffer.mlir` (checks calls only, unchanged).
- **Discriminator:** the generated `idris_rt_ops.h` declares
  `idris_rt_io_buffer_copy` with 5 parameters, and the runtime compiles against
  it. A definition with the old shape fails to compile, which is the ABI header's
  purpose.
- **Verification here:** `make typecheck`; the runtime compiles with the host
  clang.
- **Size and risk:** about 30 lines, 2 branches and about 30 dead parameters
  removed. The risk is low. Essential cases that stay: World, the one word with
  no C value.
- **Insight:** 6, 12 (one representation for every heap operand).

### D3. "Prepared or archive" is decided three times, and the CPU marks are stripped and written back

- **Evidence:**
  - `lib/Driver/ReadRuntime.cpp:228` decides by the file's magic.
  - `LinkRuntime.cpp:96-103` `preparedFor` decides again by module flags. It is
    read by `nativeRuns:43-45` and by `Prepare.cpp:91-95`.
  - Per function: `LinkRuntime.cpp:111-112`
    `hasFnAttribute(featuresMark) ? featuresMark : "target-features"`.
  - `retarget` removes the marks (`:115-116`), so `Prepare.cpp:96-107` saves
    every function's CPU and features in a `StringMap` before `retarget` and
    writes them back after.
- **Counterexample:** a plain `.bc` runtime without the flags takes the
  "prepared" path in `readRuntime` (not an archive), yet `preparedFor` says
  unprepared. `--prepare-runtime` accepts it as if it were the archive, and a
  compilation links it with every body external. One fact has two sources that
  disagree.
- **Root cause:** `readRuntime` learns the runtime's kind and returns a bare
  `unique_ptr<Module>`, so the kind is re-derived by each reader. The marks are
  written only on prepared functions, so every reader branches on whether a
  function carries them.
- **Correction:**
  - `readRuntime` returns `std::variant<Archived, Prepared>`, where
    `Prepared{module, PreparedFor}` requires the flags. A non-archive without
    them is refused at the read.
  - `prepare` reads `Archived` only. `linkRuntime` visits the variant:
    `nativeRuns` takes a `PreparedFor`, and Archived needs no linkage change.
  - `prepareMember` writes `cpuMark` and `featuresMark` on every definition of
    an archive member from its own target attributes, so every runtime function
    carries them.
  - `retarget` reads the marks only and leaves them. `linkRuntime` strips them
    once after the join.
- **Deletion:**
  - `preparedFor`'s null tests and `nativeRuns`'s `if (!compiledFor)`.
  - `prepare`'s "is prepared already" check (now the type) and its `compiledFor`
    map with its two loops.
  - `retarget`'s ternary.
- **Consumers:** `include/idr/Driver/Runtime.h`, `lib/Driver/{ReadRuntime,LinkRuntime,Prepare}.cpp`,
  `tests/runtime-prepared`.
- **Discriminator:** a flagless `.bc` given as `--runtime` is refused, with the
  message naming it as neither (before: accepted). `runtime-container` still
  prepares byte-identically.
- **Verification here:** `make typecheck`.
- **Size and risk:** about 50 lines, about 6 branches and one map pass. The risk
  is low. Essential cases that stay: the post-optimization check that every
  function kept its marks (a clone can lose them).
- **Insight:** 6, 4.

### S1. Each tool re-implements the reserved-stack trampoline and the tool registry

- **Evidence:** the trampoline is written four times:
  - `lib/Driver/Main.cpp:51-82`: `Compilation`, `enter`, `compilationExhausted`,
    `runOnLargeStack`.
  - `tools/idris-mlir-opt.cpp:41-45,108-128`: `Invocation`, `exhausted`, the
    no-stack branch.
  - `tools/idris-mlir-reduce.cpp:68-72,97-117`: the same again.
  - `idris_rt_gmp_init()` at each `main`.

  The registry is written three times: `idris-mlir-opt.cpp:61-69`,
  `idris-mlir-reduce.cpp:79-87`, and `Run.cpp:316-323` (all dialects,
  extensions, idr, the flow models, the schedule library).
- **Counterexample:** a fourth tool, or a change to the stack size or guard,
  takes three edits, and the exhaustion messages already differ in form.
- **Root cause:** "a tool runs on the runtime's reserved stack with GMP pointed
  at the runtime" and "a tool's dialects" are facts with no home. `Support/Stack.h`
  holds only the two sizes.
- **Correction:** `idr::support::runTool(StringLiteral name, function_ref<int()>)`
  in `Support` (Stack.h becomes Tool.h). It initializes GMP, runs on the reserved
  stack, writes the async-signal-safe message `<name>: the stack is exhausted`
  from a static set before the run, and reports no-stack once. An
  `idr/InitIdr.h` `registerIdrDialects(DialectRegistry &)` follows upstream's
  `InitAllDialects.h` layout.
- **Deletion:** 3 trampoline structs, 3 exhaustion handlers, 3 no-stack
  branches, 3 GMP calls and 2 registry blocks.
- **Consumers:** `include/idr/Support/Stack.h`, `lib/Support/` (and its CMake
  links `idris_rt`), `lib/Driver/{Main,Run}.cpp`, `tools/idris-mlir-{opt,reduce}.cpp`,
  and a new `include/idr/InitIdr.h` (the coordinator's CMake).
- **Discriminator:** a grep spec: `idris_rt_run_on_stack` has one call site in
  `foreign/idr`. `tests/stack-guard-page` is unchanged.
- **Verification here:** `make typecheck`.
- **Size and risk:** about 80 lines deleted, 3 error branches removed, low
  risk. Essential cases that stay: the driver's message keeps its
  "internal error" class (see D1).
- **Insight:** one fact, one place (AGENTS.md); 7.

### R2. The crash message format is assembled at eleven sites, and two contradict it

- **Evidence:** the format, documented at `runtime/idris_rt.h:392-396` as
  "idris-mlir: <cause>", is built by hand at:
  - `Io/Handles.cpp:172`;
  - `Start/Entry.cpp:42-44,72-73,102,115-118,154`;
  - `Platform/Posix/Memory.cpp:54`;
  - `Io/Ending.cpp:64` (`crash_str`);
  - `lib/Conversion/Runtime.cpp:59-62` (`crashMessage` prepends "idris-mlir: "
    and appends "\n");
  - `Alloc/Cells.cpp:159` writes `"idris runtime: out of memory\n"` and
    `Alloc/Arrays.cpp:26` writes `"idris runtime: array too large\n"`.
- **Counterexample:** exhausted memory prints `idris runtime: out of memory`,
  which is not the documented form. Every caller must remember the prefix and the
  newline.
- **Root cause:** `idris_rt_crash(msg, len)` takes the finished line, so the
  format is every caller's. `idris_rt_crash_str` already takes only the cause.
- **Correction:** `idris_rt_crash(cause, len)` writes `idris-mlir: `, the cause
  and `\n`. A baseline-annotated `rt::platform::writeCrash(parts...)` does the
  same for the messages written before the processor test (`checkCpu`,
  `checkPageSize`, `programExhausted`). Every caller passes the cause alone, and
  `crashMessage` passes cause and location.
- **Deletion:** 11 hand-written prefixes and newlines, and the two
  contradicting texts.
- **Consumers:** `runtime/{idris_rt.h,Io/Ending,Io/Handles,Alloc/Cells,Alloc/Arrays,Start/Entry,Platform/Posix/Memory,Platform/Platform.h}.cpp`,
  `lib/Conversion/Runtime.cpp`.
- **Discriminator:** `tests/crash-integer-shift-huge` (a
  substring match on `out of memory`) still passes. A new spec checks that every
  crash text the runtime writes starts with `idris-mlir: `.
- **Verification here:** the runtime compiles with the host clang;
  `make typecheck`.
- **Size and risk:** about 30 lines, low risk; the stderr text of two crashes
  changes.
- **Insight:** one fact, one place; 6.

### D4. The prepared runtime's bitcode container is a run-time option, validated by object format outside the target entry and re-read by the reader

- **Evidence:**
  - `lib/Driver/Options.cpp:69-73,127-131`: `--runtime-bitcode-section` parsed
    into `BitcodeHome`.
  - `Prepare.cpp:71-79`: `!triple.isOSBinFormatELF() && !triple.isOSBinFormatCOFF()`,
    an object-format case outside the target entry (AGENTS.md: "per-target cases
    elsewhere are bugs").
  - `ReadRuntime.cpp:177-210` `preparedBitcode` re-reads the option and searches
    sections by name, re-implementing `llvm::object::IRObjectFile::findBitcodeInMemBuffer`
    (pinned `IRObjectFile.cpp:73-103`, which finds a bitcode file as itself,
    ELF/COFF `.llvm.lto`, and Mach-O's bitcode section).
- **Counterexample:** a runtime prepared with `--runtime-bitcode-section=` and
  read without it fails with "carries no bitcode where its container keeps it".
  The container is a fact of the artifact held instead in two command lines that
  must agree (the test passes it twice:
  `tests/runtime-container/run:34,124`).
- **Root cause:** where the bitcode is kept is decided by the target entry
  (`CMakeLists.txt:171,211`), then reopened as an option, and not read off the
  artifact by the reader.
- **Correction:** the container is the target entry's `constexpr`
  (`BitcodeHome::InObject | BesideObject`), like `targetTriple`, and the option
  is deleted. The reader parses the artifact: `findBitcodeInMemBuffer`, then
  `besideObject(path)` when it reports no bitcode section.
- **Deletion:** the option, `runtimeBitcodeHome()` and its variant parse, the
  ELF/COFF guard, and the reader's `std::visit` over the home with its section
  walk.
- **Consumers:** `include/idr/Driver/Options.h`, `lib/Driver/{Options,Prepare,ReadRuntime}.cpp`,
  `foreign/idr/CMakeLists.txt:94,167`, `CMakeLists.txt`'s entries (a two-case
  value), `tests/runtime-container/run`, and
  `tests/no-behaviour-options/run` (`runtime-bitcode-section` leaves the
  kept list).
- **Discriminator:** `runtime-container` prepares with no option on each
  target, the reader finds the bitcode on both, and
  `--runtime-bitcode-section` is an unknown option (exit 2).
- **Verification here:** `make typecheck`.
- **Size and risk:** about 50 lines, 3 branches and one object-format case. The
  risk is medium: `runtime-container` loses its beside-the-object leg on ELF,
  which macOS covers natively. The option sits in the spec's kept list as a
  non-behaviour option, not as a representation decision.
- **Insight:** 6; AGENTS.md's one target decision.

### T3. The generator decides an ODS type's C word, and whether it counts bytes, by matching record names in C++ tables

- **Evidence:**
  - `tools/idris-mlir-tblgen.cpp:954-968` `dialectWord`: a 13-entry table of
    record names (`"Idr_StrRead"`, `"Idr_BigOrNatRead"`, ...).
  - It is read by `wordsOf:2161` and by `guardOf:1093-1098` (`Str` → `BytesOf`,
    `Buffer` → `LengthOf`).
  - `isCount:1019-1021` is `getName() == "I64"`.
  - `namesIn:275-282` splits `Idr_Guarded`'s operand list out of one
    comma-separated `string`.
- **Counterexample:** a new constraint such as `Idr_NatValueOwned` passed to a
  runtime op fails `PrintFatalError("... which no C function takes")` until
  someone edits the generator's table. The fact "how the C ABI holds this type"
  sits in C++, not beside the type in ODS.
- **Root cause:** the C word and the byte count are facts about a type
  constraint, but ODS does not carry them.
- **Correction:** an ODS class `Idr_AbiWord<string word, string count = "">`
  mixed into each type constraint the runtime takes (`IdrTypes.td`,
  `IdrBigOps.td:279`). `wordsOf` and `guardOf` read
  `type.getValueAsString("abiWord")` and `"abiCount"`. `Idr_Guarded`'s operands
  become `list<string>`.
- **Deletion:** `dialectWord` and its 13 entries, the name match in `isCount`,
  and `namesIn`.
- **Consumers:** `tools/idris-mlir-tblgen.cpp`, `include/idr/IR/{IdrBase,IdrTypes,IdrBigOps,IdrCheckOps}.td`
  (the IR area), and the regenerated `compiler/src/IdrisMLIR/Dialect/*`
  (coordinator).
- **Discriminator:** the generated ABI, guard and syntax outputs are
  byte-identical before and after (`make typecheck-dialects`). A new constraint
  that declares `Idr_AbiWord` needs no generator change.
- **Verification here:** `make typecheck` and `make typecheck-dialects`.
- **Size and risk:** about 40 lines, 3 lookups, low risk.
- **Insight:** strings naming things (the guideline); 6.

### D5. `ModuleKind` does not carry the module's target, so `toObjects` re-validates it and misclassifies a user's module

- **Evidence:**
  - `lib/Driver/Run.cpp:83,92-123`: `kindOf` returns `Handoff | Lowered`.
  - `toObjects:171-184` then tests the `#llvm.target` for presence ("internal
    error: the module lost its #llvm.target") and for its triple, for both kinds.
- **Counterexample:** a user's LLVM-dialect `.mlir` without `#llvm.target`
  exits 1 with "internal error: the module lost its #llvm.target". It is the
  input's fault, reported as the compiler's. For a Handoff module, idr-target
  writes the target from the same macro (`Target.cpp:68-85`), so both checks are
  dead there.
- **Root cause:** the Lowered kind's one precondition (a target for the build's
  triple) is validated after the parse, not parsed with the kind.
- **Correction:** `kindOf` returns `std::variant<Handoff, Lowered{LLVM::TargetAttr}>`.
  A Lowered module without a target, or for another triple, is refused there,
  naming the module, as F09 asked ("after checking its triple against the
  build's"). `toObjects` takes the `TargetAttr` (read off the module after the
  pipeline for Handoff).
- **Deletion:** `toObjects`'s two internal-error checks.
- **Consumers:** `lib/Driver/Run.cpp`.
- **Discriminator:** an LLVM-dialect module without a target exits 2 with a
  message naming it (before: exit 1, internal).
- **Verification here:** `make typecheck`.
- **Size and risk:** about 20 lines, 2 branches, low risk.
- **Insight:** 6.

### U1. The six exhaustive boxes each copy the same fixture and helpers

- **Evidence:** `foreign/idr/unittests/`:
  - The fixture class with `check` and live-cell `SetUp`/`TearDown`: 6 copies
    (`Tagged.cpp:33`, `TaggedBits.cpp:33`, `Words.cpp:54`, `Hooks.cpp:41`,
    `HooksCompare.cpp:48`, `Ranges.cpp:40`).
  - `Owned` and `big`: 5 copies.
  - `sign` and `inside`: 4.
  - `represents`/`is` and `boxB`: 3 each.
  - The `d64` points, `eachInterval`/`eachMember` and `operator<<(Bounds)`: 3
    each.
  - `member`, `inferred` and `eachPredicate`: 2 each.
- **Counterexample:** a change to the failure-count rule (the first failure
  with its operands) or to the small range's box takes six edits, and the copies
  have already diverged in signature (`eachInterval(Fn)` against
  `eachInterval(span, Fn)`).
- **Root cause:** a missing test API (AGENTS.md: "a brittle test means a
  missing test API").
- **Correction:** one `unittests/Box.h`, holding the fixture template
  `Box<Derived>`, `Owned`, the domains (`d64`, `boxB`, `dw`), the interval walks
  and the printers. Each box keeps only its rule's tests.
- **Deletion:** about 250 duplicated lines.
- **Consumers:** `foreign/idr/unittests/*.cpp` and its `CMakeLists.txt` (none
  of it is a hub).
- **Discriminator:** the boxes compile, and each still names the same tests
  (`--gtest_list_tests` unchanged on the owner's build).
- **Verification here:** `make typecheck` compiles the units against
  googletest's headers.
- **Size and risk:** about 250 lines, no branches, no risk.
- **Insight:** one fact, one place.

### P1. Partition keeps a symbol's role three times: `kind`, `nodeOf` and `Symbol::home`

- **Evidence:**
  - `lib/Target/Partition.cpp:120` `enum Kind {Declared, Node, Copied, Alias}`.
  - `:158-159` the parallel vectors `kind` and `nodeOf`
    (`std::optional<unsigned>`), beside `partition.symbols[].home` (variant
    `Declared | Copied | Defined`).
  - `Copied` is written into both (`:171-173`).
  - Branches: `baseOf:181`, `reach:195`, `:174`, `:307`.
- **Counterexample:** `kind[s] == Node` with `nodeOf[s]` empty, or
  `kind[s] == Copied` with `home` not `Copied`: both are representable, and the
  code keeps them in step by write order alone.
- **Root cause:** the per-symbol classification is held as a tag plus a
  parallel optional index plus the result variant.
- **Correction:** one per-symbol `std::variant<Declared, Copied, Node{unsigned index}, Alias{std::optional<unsigned> base}>`
  built in the first loop. `baseOf` becomes a visit, and `home` is derived once
  at the end.
- **Deletion:** the `kind` and `nodeOf` vectors, the double write of `Copied`,
  and 4 tag tests.
- **Consumers:** `lib/Target/Partition.cpp`, `include/idr/Target/Target.h`.
- **Discriminator:** bins and objects byte-identical (`runtime-container`,
  `tests/determinism` on the owner's build).
- **Verification here:** `make typecheck`.
- **Size and risk:** about 30 lines, 4 branches, low risk.
- **Insight:** 4; parallel arrays.

### R3. The runtime's meaning of a function is documented in two or three places

- **Evidence:**
  - `cast` from String: `idris_rt.h:480-494` and `Numerals/Numerals.h:3-20`.
  - Euclidean division: `idris_rt.h:508-512` and `Big/Arithmetic.cpp:6-9`.
  - Shifts: `idris_rt.h:515-521` and `Big/Bitwise.cpp:44-63`.
  - getChar's 255: `IdrIOOps.td:53`, `idris_rt.h:329` and `Io/Input.cpp:64-69`.
  - getLine: `IdrIOOps.td:57-61`, `idris_rt.h:330-334` and `Input.cpp:72-73`.
  - The handle table: `idris_rt.h:369-380`, `Io/Io.h:44-53` and
    `Io/Handles.cpp:3-20`.
  - Meanwhile `idris_rt.h:363-367` already says the IO group's "one meaning is
    documented beside its definition".
  - `R2` is one drift this has caused.
- **Counterexample:** the crash prefix (R2) drifted already. A change to
  substr's clamping must be made in prose twice.
- **Root cause:** no rule says where a primitive's meaning lives. AGENTS.md says
  only that it is the runtime's.
- **Correction:** each `idris_rt_*` function's meaning lives beside its
  definition in `runtime/**/*.cpp`, the IO group's convention made general.
  `idris_rt.h` keeps the layouts, the ownership rules and the non-op ABI, and
  ODS summaries name the op without restating the runtime.
- **Deletion:** the restated prose blocks in `idris_rt.h:425-538` and
  `Numerals.h`'s copy, and ODS comments restating runtime behaviour.
- **Consumers:** `runtime/idris_rt.h`, `runtime/**/*.cpp`, `include/idr/IR/Idr{IO,String,Big}Ops.td`
  (the IR area).
- **Discriminator:** none behavioural. A spec could hold that no `idris_rt_*`
  name is documented in `idris_rt.h` and in a `.cpp`.
- **Verification here:** reading.
- **Size and risk:** about 120 lines of prose, no branches, no risk.
- **Insight:** one fact, one place.

### R5. The baseline mark is spelled ten times

- **Evidence:** `[[clang::annotate("idris-rt-baseline")]]` appears 9 times in
  `runtime/`:
  - `Platform/Platform.h:141,208`;
  - `Platform/CpuBits.h:19`;
  - `Platform/{X86_64,Aarch64}/Cpu.cpp`;
  - `Platform/Posix/{Memory,Files,Process}.cpp`;
  - `Start/Entry.cpp:142`.

  `include/idr/Driver/Runtime.h:34` spells `baselineMark = "idris-rt-baseline"`,
  which `ReadRuntime.cpp:127` matches.
- **Counterexample:** a typo at one site leaves that function raised to the
  program's CPU, so it runs before the processor test on a CPU that may lack the
  features. Nothing checks it.
- **Root cause:** a name used as an identity across two languages, with no one
  definition.
- **Correction:** `idris_rt.h` defines `IDRIS_RT_BASELINE_MARK "idris-rt-baseline"`
  and `IDRIS_RT_BASELINE [[clang::annotate(IDRIS_RT_BASELINE_MARK)]]`.
  `Runtime.h` sets `baselineMark = IDRIS_RT_BASELINE_MARK`.
- **Deletion:** 9 string literals.
- **Consumers:** the runtime files listed, `include/idr/Driver/Runtime.h`.
- **Discriminator:** a grep spec: the literal appears once.
- **Verification here:** the runtime compiles; `make typecheck`.
- **Size and risk:** about 12 lines, no risk.
- **Insight:** strings naming things.

### D6. The process entry's name is spelled four times in C++

- **Evidence:** `lib/Driver/Run.cpp:224`, `lib/Conversion/Entry.cpp:109,137` and
  `lib/Transforms/Expect/Signature.cpp:89`. 0002 §9 records this as owed for the
  next wave; it was not decided.
- **Counterexample:** renaming the entry the lowering makes leaves the driver
  internalizing everything, and O3 then removes the program.
- **Root cause:** a name used as an identity with no one definition.
- **Correction:** one `inline constexpr StringLiteral entrySymbol = "main"` in
  `include/idr/Conversion/Runtime.h` (the lowering owns the entry), read by all
  four sites.
- **Deletion:** 3 literals.
- **Consumers:** the four files above (crosses into Conversion and Transforms).
- **Discriminator:** a grep spec.
- **Verification here:** `make typecheck`.
- **Size and risk:** about 8 lines, no risk.
- **Insight:** strings naming things.

### R4. Target address-space facts sit in rt::rc and rt::start, not in the platform layer

- **Evidence:**
  - `runtime/Rc/Freeing.cpp:15-18` `stackAddressBits = 47` ("on every target of
    ours"). Its comment claims "Dying's assertions check that a dying cell holds
    that many", but only `static_assert`s on the constants exist (`:49-54`).
  - `Start/Entry.cpp:27-32` caps the program stack at `2^44`, "a quarter of the
    address space Darwin grants".
  - `Alloc/Alloc.h:17` `heapAddressBits = 48` (checked against snmalloc's PAL,
    `Cells.cpp:135`).
- **Counterexample:** a target with a 52-bit user space (an AArch64 Linux entry)
  compiles. The dying list then truncates a stack cell's address silently, and
  the stack cap is Darwin's.
- **Root cause:** the target's user address width is decided nowhere, so each
  user writes its own assumption (AGENTS.md: nothing may assume a target outside
  the one place it is decided).
- **Correction:** `rt::platform::userAddressBits`, from the target entry. It is
  `static_assert`ed against snmalloc's `DefaultPal::address_bits`. Freeing's
  bound and the stack ceiling derive from it.
- **Deletion:** `stackAddressBits`, the Darwin-derived literal and the false
  comment.
- **Consumers:** `runtime/{Platform/Platform.h,Rc/Freeing.cpp,Start/Entry.cpp,Alloc/Alloc.h,CMakeLists.txt}`,
  and the root `CMakeLists.txt` entries (coordinator).
- **Discriminator:** the static checks now relate the dying list's 48 bits to
  the entry's width. A scratch entry with 52 fails to compile.
- **Verification here:** the runtime compiles with the host clang.
- **Size and risk:** about 15 lines, no branches, no risk.
- **Insight:** AGENTS.md's one target decision.

### T4. The generator returns `optional` plus an out-parameter `why`, and `enumKind` encodes three states with an empty string

- **Evidence:**
  - `tools/idris-mlir-tblgen.cpp:1245-1266` `enumKind` returns `nullopt` with
    `why` empty ("not an enum parameter") or with `why` set ("an enum the
    generator cannot write"). `fieldOf:1282` tells the two apart with
    `!kind && !why.empty()`.
  - The same out-parameter pattern recurs in `fieldOf`, `elements:1332`,
    `piecesOf:1444` and `memberOf:1889`.
- **Counterexample:** a caller that forgets to clear `why` between calls reads
  an earlier reason as this call's refusal.
- **Root cause:** a three-case result (written, not mine, cannot be written)
  carried as an optional plus a sentinel string.
- **Correction:** `template <class T> using Written = std::variant<T, Omitted>`
  with `Omitted{std::string why}`. `enumKind` returns
  `std::variant<Kind, NotEnum, Omitted>`.
- **Deletion:** the `std::string &why` parameters at 6 functions, and the
  empty-string test.
- **Consumers:** `tools/idris-mlir-tblgen.cpp`.
- **Discriminator:** the regenerated Idris modules are byte-identical.
- **Verification here:** `make typecheck-dialects`.
- **Size and risk:** about 40 lines, 1 sentinel test, no risk.
- **Insight:** 5, 8.

### R6. The one empty string is chosen at each constructor, not by the allocator

- **Evidence:** `n == 0 → &emptyString` at `Strings/Making.cpp:29,37,51`,
  `Strings/Replacement.cpp:72`, and `Scalars.cpp:64,96,143`. `str_alloc`
  `const_cast`s the persistent string.
- **Counterexample:** a new constructor that calls `newString(0, 0)` allocates
  an empty cell, so empty strings get two representations (shared and counted).
  `idris_rt.h:440-443` promises one.
- **Root cause:** the Null Object for "empty" is not the allocator's answer
  for zero bytes.
- **Correction:** `newString` returns the persistent empty string for
  `bytes == 0`; the persistent header is never written, since a zero-byte fill
  writes nothing.
- **Deletion:** 4 constructor checks: `stringOf`, `asciiOf`, `str_alloc` and
  `from_bytes`.
- **Consumers:** `runtime/Strings/{Strings.h,Making,Replacement}.cpp`.
- **Discriminator:** a runtime-strings property: every operation that gives an
  empty string gives the persistent one (count 0).
- **Verification here:** the runtime's C property programs here.
- **Size and risk:** about 10 lines, 4 branches, low risk.
- **Insight:** 8.

### R7. The runtime's kept-string slots are made on first use, so their handles may be null everywhere

- **Evidence:**
  - `runtime/Io/Io.h:55-60,77`: `DirectoryPayload.entry` and the global
    `environmentHandle` are null until the first call.
  - `keepString:125-135` branches on a null handle.
  - `releaseSlot:139,144-145` tests `entry != nullHandle`.
  - `releaseHandles:156` resets the global.
- **Counterexample:** a Directory slot whose `entry` is null or valid depends
  on history, and every user tests it.
- **Root cause:** the slot a directory refills is created lazily instead of
  with the directory.
- **Correction:** `dir_open` makes the directory's entry slot (holding the
  persistent empty string) with the directory. `keepString` takes a live
  handle. The environment slot is made once by `idris_rt_start`'s seeding of the
  table (R1).
- **Deletion:** 3 null tests and the global's reset.
- **Consumers:** `runtime/Io/{Io.h,Handles,Directories,Process}.cpp`.
- **Discriminator:** `tests/directory-listing` and
  `environment-arguments` unchanged; live cells are 0 at exit.
- **Verification here:** the runtime compiles.
- **Size and risk:** about 15 lines, 3 branches, low risk.
- **Insight:** 5, 8.

## Judged essential and kept

- **Bigs:**
  - The small/large tag and the inline small paths with overflow tests
    (performance on a chosen coordinate).
  - The Euclidean sign casework and the shift direction by sign (the
    arithmetic itself).
  - `Operand` already unifies small and large for GMP.
- **Strings:** the ASCII fast paths in `advance`, `reverse` and `drop_bytes` are
  speed on an existing coordinate (`bytes == scalars`), not a flag. `append`'s
  sharing of an empty side is sharing, not representation.
- **Counting:**
  - The count marks 0 and MAX (one wrap test) and the stack bit (a distinct
    storage class).
  - `IDRIS_RT_OBJS_WIDE`, a space trade that lifts a field limit by a
    representation.
  - `steppedLength`'s array case: an array keeps its stride while it dies.
- **`idris_rt_free_cell`'s guards:** `isObject` is essential (a token may be
  null, by the IR's token type). `isCounted` and `isStack` are redundant after
  `is_unique` at every current call site but state the documented meaning for
  any caller, so they are kept, for two branches.
- **The C ABI's sentinels that are base's contract:**
  - `-1` as the null handle.
  - OSClock `-1` and the three `clock >= 0` reads.
  - getChar's `255` at end of input (the Prelude's `Char` has no room).
  - `nprocessors` `-1` (base's `Maybe`).
  - `file_errno`'s numbering (base's `FileError`).
  - `dir_entry`'s null with errno (base's end-or-failure protocol).
  - The clamps of `write_bytes` and `read_bytes`.
- **The platform layer's C-library conventions** (null or -1 plus `lastError`):
  they are the C library's, read once in rt::io. The `__APPLE__` in
  `Posix/Files.cpp:60` and `MAP_NORESERVE` in `Posix/Memory.cpp:73` are inside
  the platform layer, as AGENTS.md requires. `runsSimdutf`'s name strings are
  simdutf's vocabulary, in the per-target CPU file.
- **`Numeral`:** a flat struct, but every consumer switches on `kind` first, so
  a sum would remove no branch.
- **`formatDouble` re-parsing Ryu's text:** the pinned, unmodified Ryu exports
  text only. A patch exposing `d2d` would be an upstream patch under 0006's ryu
  pin.
- **Schedules' `vectorWidth` optional and internal error:** idris-mlir-opt runs
  the transform on modules idr-target never saw, so it is a boundary.
- **Partition's positions matched across bitcode write and read:** stated in
  `Target.h:114-119` and checked once in `extract`.
- **The verdict:** `Verdict.h`'s `rowOf` switch (a table in switch form,
  upstream style). The frontend and driver exit-status protocol is held once per
  language, decided in 0002 §4.4.
- **`idris-mlir-opt` opening its own input:** upstream's argv entry builds its
  own config, so the contracts and profile setup hook needs the lower-level
  `MlirOptMain`.
- **Small parses already at the boundary:** the `ThreadCount` parser and
  `Plan::of`'s collision check.
- **`Artifacts::objects` empty for an archive:** guaranteed by the flow. Moving
  it into `Executable` would make the plan's product mutable.
- **Profile:** the `tracedProc` checks would save two branches as a null
  object, which is not earned. `IDR_ZONE_IN`'s ignored subsystem argument is a
  dead parameter to delete in passing; it removes no branch.
