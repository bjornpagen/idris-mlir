# U13 — One lowering for both pipelines: idr-entry, idr-meter

Mandatory findings: F-mode-1 F-mode-4 F-mode-5 F-mode-6 F-poison-2

## Permitted outcome

1. **No mode.** `lowerModule(ModuleOp)` takes no flag, and
   `idr-lower` has no `jit` option. `Counting.cppm` and `StackCell.cppm`
   do not branch on a mode. The facts are always applied (C6.1).
   Mandatory.
2. **`idr-entry`.** A new pass, in `IDR/Lower/Entry.cppm` and
   `IDR/Lower/Entry/Pass.cc`, makes the lowered root the program's entry
   (C6.3). It builds `@__idr_main`, which calls the root, then
   `@__idr_release_cafs`, then `idris_rt_main_return`. It also builds
   `@main(i32, !llvm.ptr) -> i32`, which passes `argc` and `argv` to
   `idris_rt_start`. Mandatory.
3. **`idr-meter`.** A new pass, in `IDR/Lower/Meter.cppm` and
   `IDR/Lower/Meter/Pass.cc` (C6.2). Mandatory.
4. **The lowering's lists.**
   - `Lower.cppm` exports U05's `:checks` partition.
   - `Patterns.cppm` calls `populateCheckPatterns`.
   - `lowerModule` stops calling the closure patterns, and calls
     `runtime.finish()` (U11) after the conversion.
   - `IDR/Lower/CMakeLists.txt` lists `Checks.cppm`, `Entry.cppm`,
     `Meter.cppm` and the two pass units.
   - `checkNoClosures` covers memo boxes' absence of laziness too: no
     lazy type and no `idr.suspend` is left.

   Mandatory.
5. **The sentinels.** The C2.4 sites in `Lower/{Lowering,TailPosition,Matches,Loops,Facts}.cppm`
   use no sentinel. Mandatory.
6. **The walk rule** (C7.2). `Lowering.cppm`'s `functionClosure`
   (`:101-129`), which tells whether a constant holds a closure, walks a
   run's cells and tail, never `getFields()[s]`. It keeps the `seen` set
   1677b8cb gave it, so a shared value is read once
   (`T/programs/eval/shared-result`). Its `!idr.lazy` exception goes:
   after `idr-defunctionalize` no suspension is a `#idr.closure` (C5.1),
   so any `#idr.closure` left is a closure. Mandatory.

## Owner / exclusive writes

- `IDR/Lower/Lowering.cppm`
- `IDR/Lower/Pass.cc`
- `IDR/Lower/Counting.cppm`
- `IDR/Lower/StackCell.cppm`
- `IDR/Lower/Facts.cppm`
- `IDR/Lower/Matches.cppm`
- `IDR/Lower/Loops.cppm`
- `IDR/Lower/TailPosition.cppm`
- `IDR/Lower/Lower.cppm`
- `IDR/Lower/Patterns.cppm`
- `IDR/Lower/CMakeLists.txt`
- `IDR/Lower/Entry.cppm`
- `IDR/Lower/Entry`
- `IDR/Lower/Meter.cppm`
- `IDR/Lower/Meter`

**Excluded:**

- `IDR/Lower/{Runtime,Closures,Cells,BuildBox,Fields}.cppm` (U11).
- `IDR/Lower/StaticData.cppm` (U12).
- `IDR/Lower/{Checks,Scalars,Strings,Bigs,Arrays,Buffers,Words,RuntimeCalls}.cppm`
  (U05).
- `INC/Passes.td`, where the coordinator adds `IdrEntry` and
  `IdrMeter` and removes the option.
- `IDR/Dialect/Registration`, where the coordinator puts `idr-entry`
  after `idr-lower`.
- `IDR/Eval/Round.cppm`, where U14 runs `idr-meter`.

## Read first

- `contracts.md` C6.1 to C6.3, C1.2, C1.3, C1.5, C5.1, C5.5, C2.4, C7.2
  and C13.
- `findings.md` F-mode-1, F-mode-4, F-mode-5 and F-mode-6.
- `IDR/Lower/Lowering.cppm`, all of it.
- `IDR/Lower/{Pass.cc,Counting.cppm,StackCell.cppm,Lower.cppm,Patterns.cppm,CMakeLists.txt}`.
- `IDR/Lower/TailCalls/Pass.cc`, a pass glue in a subdirectory, to
  copy its shape.

## Fixed decisions

- **`idr-entry`** runs on a module that `idr-lower` has lowered.
  - It finds the one public `func.func` and makes it private.
  - The root's kind comes from its signature: `() -> i64` returns the
    status, and `() -> ()` returns 0.
  - It moves `requiredCpuFeatures` and the body of the old main
    emission here, with the changes C6.3 lists.
  - It declares `idris_rt_main_return`, `idris_rt_start` and
    `__idr_release_cafs` where absent; the last is always present
    (U12).
  - `idris_rt_start` takes `(ptr, i64, i32, ptr) -> i32`.
- **`idr-meter`.** For every `func.func` with a body, it inserts
  `llvm.call @idris_rt_eval_tick()` at the start of its entry block, and
  right before each `llvm.call_intrinsic "llvm.sideeffect"`. It declares
  `llvm.func @idris_rt_eval_tick()` if absent.
- **`checkNoClosures`** also rejects any `!idr.lazy` type or
  `idr.suspend` op. It stays an internal error: `idr-defunctionalize`
  already reported an unknown key as `unsupported` (C5.1), so reaching
  it means a pass after that one made a closure.
- **The partitions** in `Lower.cppm` are today's list, plus `:checks`,
  `:entry` and `:meter`, minus none: `Closures.cppm` keeps its name and
  holds the force (U11).

## Inputs

- `Runtime(ModuleOp, Layouts &)` and `Runtime::finish()` (U11).
- `populateLazyPatterns` (U11) and `populateCheckPatterns` (U05).
- `createIdrEntry` and `createIdrMeter` from `Passes.td` (the
  coordinator).
- `@__idr_release_cafs`, always present (U12).
- `ConAttr`'s C7.2 accessors, U19's.

## Outputs

- `lowerModule(ModuleOp)`, `createIdrEntry` and `createIdrMeter`, with
  their pass glue.

## Implement

- **`Lowering.cppm`.** Remove the flag and every branch on it. Remove
  the root, main and CPU-feature code, which moves to `Entry.cppm`.
  Always apply the facts. Call `runtime.finish()` after the conversion.
- **`Pass.cc`.** Call `lowerModule(getOperation())`.
- **`Counting.cppm` and `StackCell.cppm`.** Remove the mode tests.
- **`Entry.cppm` with `Entry/Pass.cc`, and `Meter.cppm` with
  `Meter/Pass.cc`,** per the fixed decisions. Each pass glue follows
  `TailCalls/Pass.cc`.
- **`Lower.cppm`, `Patterns.cppm` and `CMakeLists.txt`** per outcome 4.
- **Sentinels.** Apply C2.4 to the six sites.
- **`functionClosure`.** Walk constants by C7.2's walk rule, keep its
  `seen` set, and drop its `!idr.lazy` exception (outcome 6).

## Delete

- `bool jit` from `lowerModule`, and every `if (jit)` and `if (!jit)`.
- The JIT-mode `idr.may_loop` at function entry, since `idr-meter`
  ticks.
- `findRoot`, `requiredCpuFeatures` and `emitMain` from `Lowering.cppm`.
  They move, and are not copied.
- The `populateClosurePatterns` call.
- `isJit` uses in `Counting.cppm` and `StackCell.cppm`.
- The six `ub.poison` sentinels.

## NOT TO DO

- Do not change the order or content of the conversion's patterns
  beyond adding the checks and removing closures.
- Do not change `idr-tail-calls`.
- Do not change what `@main` returns or how `idris_rt_start` judges the
  CPU.
- Do not edit `Runtime.cppm` (U11) or `Round.cppm` (U14).

## Acceptance

- `idr-lower` has no option; `--idr-lower=jit=1` is an unknown option.
- After `idr-lower` and `idr-entry`, a module has `@main(i32, !llvm.ptr) -> i32`
  calling `idris_rt_start` with four arguments, and `@__idr_main` calls
  `@__idr_release_cafs` before `idris_rt_main_return`.
- After `idr-meter`, every function's entry block starts with the tick,
  and every `llvm.sideeffect` is preceded by one.
- U22 writes `T/idr/lower/{no-mode,entry,meter}`.
- **Tempting partial:** keeping `jit` as an option that defaults to
  false. Rejected: the mode is the predecessor this lane deletes, and
  an option with no reader is a dead knob.

## Escalate if

- A pass between `idr-lower` and `idr-entry` needs the root to be
  public. Report it.
- `idris_rt_start`'s ABI needs more than C1.5 gives on one target.
  Report which.

## Stop and return

You are done when the six outcomes are in your files and the Delete
list is empty of survivors. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
