# U15 — The runtime's core: one crash entry, arguments, no closure kind, no kept list

Mandatory findings: F-mode-3 F-clo-5 F-lazy-5

## Permitted outcome

1. **One crash entry.** `idris_rt_crash` ends an evaluation child as
   `idris_rt_eval_crash` does, when called in one. So lowered code has
   one crash entry (C1.5, C6.5). Mandatory.
2. **Arguments.** `idris_rt_start(body, cpu, argc, argv)` keeps the
   arguments. `rt.start` exports `rt::start::argumentCount()` and
   `rt::start::argument(int64_t)` (C6.5). Mandatory.
3. **No closure kind; no kept list.** Freeing treats
   `IDRIS_RT_KIND_THUNK` as a box. The closure release and the kept list
   go. `idris_rt_caf_release` releases a persistent cell's object slots
   (C5.6). Mandatory.

## Owner / exclusive writes

- `RT/Rc`
- `RT/Start`
- `RT/Eval`
- `RT/Alloc`

**Excluded:**

- `RT/idris_rt.h` (the coordinator applies C1.5).
- `RT/CMakeLists.txt` (U16). Add no new file. If you must, name it in
  your handoff, and U16 registers it from C1.5's text.
- `RT/Io` and `RT/Platform` (U16).

## Read first

- `contracts.md` C1.5, C5.6, C6.5 and C13.
- `findings.md` F-mode-3, F-clo-5 and F-lazy-5.
- `RT/idris_rt.h`, all of it.
- `RT/Rc/*`, `RT/Start/*`, `RT/Eval/*` and `RT/Alloc/{Blocks,Cells}.cppm`
  (`arenaActive`).

## Fixed decisions

- **`idris_rt_crash`.** When `rt::alloc::arenaActive`, it does what
  `idris_rt_eval_crash` does: it writes the message to the report
  descriptor and exits with `IDRIS_RT_EVAL_CRASHED`. Otherwise it does
  what it does today.
- **`idris_rt_start`** stores `argc` and `argv` before running the body.
  `argument(i)` returns a new runtime string of `argv[i]` (UTF-8 as
  given), or the empty string out of range. `argumentCount()` returns
  `argc`.
- **`idris_rt_caf_release(void *cell)`** releases each object slot of a
  persistent cell once: what `releaseKept` does today. It does nothing
  for null, an odd word, or a counted cell.
- **`idris_rt_main_return`** walks no list. `@__idr_main` calls
  `@__idr_release_cafs` before it.
- **Freeing.** `IDRIS_RT_KIND_THUNK` (value 1) is freed by the walk over
  `objs`, as a box is. The closure case goes.

## Inputs

- C1.5's header text (the coordinator writes the header).

## Outputs

- The runtime entry points above, and `rt::start`'s two exports, which
  U16 reads.

## Implement

- Per the fixed decisions, in `RT/Start/{Entry,Runner}.cppm`,
  `RT/Rc/{Counting,Freeing}.cppm` and `RT/Eval/Child.cppm` (or wherever
  the crash entry lives).

## Delete

- `idris_rt_lazy_kept`, the `Kept` struct, the `kept` list, and the
  list walk in `idris_rt_release_persistent`. Keep the function only if
  something else calls it; check with
  `grep -rn release_persistent runtime foreign`.
- The `IDRIS_RT_KIND_CLOSURE` case in freeing.

## NOT TO DO

- Do not change counting, saturation, stack cells, the live-cell report,
  or `idris_rt_free_cell`.
- Do not add a thread, or any thread-local state, beyond what exists.
- Do not touch `RT/Io` or `RT/Platform`.
- Do not change the evaluator's statuses.

## Acceptance

- A program whose only static thunk was forced reports 0 live cells
  under `IDRIS_RT_LIVE=1`, through `@__idr_release_cafs`. The
  coordinator runs `T/programs/eval/memo-lazy`.
- A crash during compile-time evaluation is reported as an evaluation
  crash, as today. `T/programs/eval` covers it.
- `getArgs` returns the program's arguments (U23's
  `environment-arguments`).
- `grep -rn 'lazy_kept\|KIND_CLOSURE' runtime` finds nothing.
- **Tempting partial:** keeping `idris_rt_eval_crash` as the lowered
  crash in eval and adding a second path. Rejected: the point is one
  entry.

## Escalate if

- `arenaActive` is not visible where `idris_rt_crash` is defined, and
  the module graph forbids importing it there. Report the import you
  need.

## Stop and return

You are done when the three outcomes hold and the Delete list is empty
of survivors. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
