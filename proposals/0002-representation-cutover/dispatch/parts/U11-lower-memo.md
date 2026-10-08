# U11 — The lowering's runtime side: no mode, no closures, the force as a small evaluator

Mandatory findings: F-mode-2 F-clo-1 F-lazy-1 F-lazy-2 F-lazy-3 F-lazy-7 F-poison-3

## Permitted outcome

1. **`Runtime` has no mode.**
   - Every cell comes from `idris_rt_cell`.
   - `inc` and `dec` are always emitted.
   - A crash always calls `idris_rt_crash`.
   - `mayLoop` always emits `llvm.sideeffect`.
   - Nothing in it knows of closures or code (C6.1).

   Mandatory.
2. **The force is a switch.** `idr.force` of a memo-sum box lowers by
   one generic pattern that switches on the cell's tag, per C5.3's three
   tables: view, owned and not `excl`, owned and `excl`. It includes
   `by_name` and the `running` crash. Mandatory.
3. **The sentinels.** The five C2.4 sites in `IDR/Lower/Cells.cppm` use
   no sentinel. Mandatory.

## Owner / exclusive writes

- `IDR/Lower/Runtime.cppm`
- `IDR/Lower/Closures.cppm`
- `IDR/Lower/Cells.cppm`
- `IDR/Lower/BuildBox.cppm`
- `IDR/Lower/Fields.cppm`

**Excluded:**

- `IDR/Lower/Lowering.cppm`, `Pass.cc`, `Counting.cppm`,
  `StackCell.cppm` and `Patterns.cppm` (U13). U13 builds `Runtime`
  with no flag and stops calling the closure patterns.
- `IDR/Lower/StaticData.cppm` (U12). You still call
  `statics.constant(...)` and `statics.message(...)`, which keep their
  signatures.
- `IDR/Layout` (U10).
- `RT/` (U15).

## Read first

- `contracts.md` C5.2, C5.3, C6.1, C1.5, C2.4 and C13.
- `findings.md` F-mode-2, F-clo-1, F-lazy-1, F-lazy-2, F-lazy-3 and
  F-lazy-7.
- `IDR/Lower/Runtime.cppm` and `IDR/Lower/Closures.cppm`, all of both.
- `IDR/Lower/Cells.cppm`, `BuildBox.cppm` and `Fields.cppm`.
- `IDR/Lower/Matches.cppm`, to see how a box's tag is read and switched
  on.
- `runtime/idris_rt.h`: the header, the info word, `idris_rt_free_cell`.

## Fixed decisions

- **The constructor is `Runtime(ModuleOp, layout::Layouts &)`.**
  - There is no mode query.
  - `allocate` calls `idris_rt_cell(size, info)`.
  - `storeHeader` writes count 1; it is used only for stack cells.
  - `inc` and `dec` call the runtime.
  - `crash` calls `idris_rt_crash`.
  - `mayLoop` emits `llvm.sideeffect`.
  - The `noreturn` set in `call` is `idris_rt_crash`,
    `idris_rt_crash_str` and `idris_rt_io_exit`.
  - `Runtime::finish()` replaces the old end-of-lowering code emission.
    It calls `statics.emitReleaseCafs(b)` (U12), and `lowerModule` (U13)
    calls it once, after the conversion.
- **The force's pattern** (`populateLazyPatterns` keeps its name):
  - Read the tag (`loadTag`) and switch: one case per label, then
    `running`, then `forced`.
  - Each label case loads the captures from that state's layout
    (`Layouts::box(ctor)`) and calls the label's `func.func` directly by
    its symbol, the constructor's leaf name.
  - The view protocol writes the `running` info word before the call,
    with no inc of captures. After the call it stores `v` into the
    `forced` layout and writes the `forced` info word, keeping bit 31.
    It incs `v`'s counted components once more for the cell.
  - `by_name` cases inc each capture and call. They write nothing.
  - `running` crashes with the cause `a suspension forced itself`.
  - The `excl` protocol frees the cell's memory with
    `idris_rt_free_cell` after loading what it needs. It never writes.
  - An owned, non-`excl` operand runs the view protocol, then a dec.
- **The force's result** is owned, as today: one reference the caller
  holds.
- **Borrowed parameters** follow C5.3, "Captures and borrowed
  parameters": a moved capture passed to a borrowed parameter (one
  whose type is plain, C2.2) is decd after the call, and a `by_name`
  capture is inc'd only for an owned parameter.
- **A memo sum with one label** emits no switch between labels. It
  still tests `running` and `forced`.

## Inputs

- Memo sums (C5.1), with the `by_name` attribute read through the
  generated `getByName()`.
- U10's layout accessors: `Layouts::box(CtorOp)` and
  `Layouts::isMemo(Type)`.
- The force operand's grade: `isExclusive` and `isOwned` on its type.

## Outputs

- `Runtime` with no mode.
- `populateLazyPatterns` holding the one force pattern.

## Implement

- **Remove the mode** from `Runtime` per the fixed decisions.
- **Remove every closure and code path** from `Runtime` and
  `Closures.cppm`.
- **Write the force pattern**, building the switch with `scf.index_switch`
  or `cf.switch`, whichever `Matches.cppm` uses for boxes. Every
  load and store goes through the layout's slots.
- **`Cells.cppm`, `BuildBox.cppm`, `Fields.cppm`.** A memo sum's
  constructors are boxes; check that building one (`idr.con`) uses
  `Layouts::box`'s size. Apply C2.4 to the five sites.

## Delete

- The `jit` member, the constructor flag, and `isJit`.
- `idris_rt_arena_alloc` and the `idris_rt_eval_crash` choice in the
  lowering.
- `code`, `codeType` and `emitCode`.
- `emitClosure`, `emitSuspension` and `doneCode`.
- `storeForcedInfo`, as it stands. The force pattern keeps bit 31
  itself.
- `distinguish(`.
- The `idris_rt_lazy_kept` call.
- `populateClosurePatterns`, `LowerClosure`, `LowerApply`,
  `LowerSuspend`, and the old `LowerForce` through a code pointer.
- The closure comments in `Closures.cppm`'s header.
- The five `ub.poison` sentinels in `Cells.cppm`.

## NOT TO DO

- Do not memoize a `by_name` constructor.
- Do not inc captures in the view protocol's label case.
- Do not write `running` for an `excl` force.
- Do not touch `StaticData.cppm` (U12) or `Lowering.cppm` (U13).
- Do not add a runtime function: every call above exists, or C1.5
  declares it.
- Do not change the lowering of boxes that are not memo sums.

## Acceptance

- A view force of a two-label memo box lowers to:
  - one switch on the tag;
  - in each label case: captures loaded, the `running` info stored, a
    direct `call` of the label, `v` stored, the `forced` info stored
    with bit 31 kept, and `v` returned with one extra inc.
- An `excl` force lowers to loads, `idris_rt_free_cell` and the call,
  with no store to the cell.
- U22 writes `T/idr/lower/force-*`.
- `T/programs/eval/thunk-consumes-list` keeps the list's count at 1, so
  it is reused in place. `T/programs/partial/self-forcing-caf` ends with
  `a suspension forced itself`. U23 writes both; the coordinator runs
  them.
- **Tempting partial:** keeping the code pointer and adding a `running`
  tag beside it. Rejected: two homes for the state, and reify would
  still read code.

## Escalate if

- `Matches.cppm`'s switch on a box tag cannot be reused from your
  partition. Report the export you need from U13.
- A force reaches the lowering with an operand that is not a memo-sum
  box. That is a U09 seam; report the input.

## Stop and return

You are done when `Runtime` has no mode, no closure path is left, and
the force pattern is as above. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
