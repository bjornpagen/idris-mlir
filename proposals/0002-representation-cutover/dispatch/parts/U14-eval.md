# U14 — The evaluator runs the program's own pipeline: defunctionalized scratch, reify of sums

Mandatory findings: F-clo-2 F-clo-3 F-const-2

## Permitted outcome

1. **The program's pipeline.** `idr-eval` lowers each round's scratch
   module with the evaluation pipeline of C1.3: defunctionalization
   first, by `idr::defunctionalize::defunctionalize(scratch)`, the
   function, not the pass; then `idr-lower` (no option), `idr-meter`,
   then today's steps. When the function returns any unknown key (a
   closure or suspension it could not convert, C5.1), every call of the
   round is left for runtime with the reason "a closure the analysis
   cannot follow". Mandatory.
2. **No code table.** The code table and its global are gone. Mandatory.
3. **Reify reads sums.** It reads closure sums and memo sums back per
   C5.7, and builds list spines with `ConAttr::getRun`. Mandatory.
4. **Constants as runs in `Encoding.cppm`.** `decodeResults` builds each
   list with `getRun`, not one `ConAttr::get` per cell
   (`Encoding.cppm:134`), and the encoder walks a run's cells and tail
   (C7.2). Mandatory.

## Owner / exclusive writes

- `IDR/Eval`

**Excluded:**

- `IDR/Defunctionalize` (U09).
- `IDR/Lower` (U11, U12, U13).
- `IDR/Layout` (U10).
- `RT/Eval` and `RT/Alloc` (U15): the child's crash entry and the arena.
- `INC/` (the coordinator).

## Read first

- `contracts.md` C1.3, C5.1, C5.7, C6.4, C7.2 and C13.
- `findings.md` F-clo-2, F-clo-3, F-const-1 and F-const-2.
- `IDR/Eval/Round.cppm`, `Scratch.cppm`, `Reify.cppm`, `Encoding.cppm`,
  `Child.cppm` and `Jit.cppm`.
- `review.md` R7.
- `IDR/Defunctionalize/Pass.cc`, for the function's signature and
  counts.
- `IDR/Facts/ClosureLabel.cppm`.
- `IDR/Defunctionalize/Sums.cppm`'s header: how closure sums are named.

## Fixed decisions

- **The lowering in `Round.cppm`:**
  1. `idr::defunctionalize::defunctionalize(scratch)` (U09's function);
  2. then a pass manager with `idr::createIdrLower()`,
     `idr::createIdrMeter()`, `createConvertLinalgToLoopsPass()`,
     `createCanonicalizerPass()` and `createCSEPass()`.

  The LLVM-dialect steps after them are unchanged.
- **Unknown keys.** If step 1 returns any, the round's calls stay for
  runtime with `Unread::Why::Unreadable` and the reason above. Nothing
  else decides it: no walk of your own for closures, since the function
  already says what it could not convert. Nothing is reported as an
  error.
- **Layouts.** They are read from the defunctionalized pristine clone,
  as today's code reads them after preparing.
- **Reify:**
  - A box or unboxed value of a closure sum, where `closureLabel` names
    the constructor, reads as `#idr.closure<@label, [captures]>`.
  - A memo-sum box in state `L(caps)` reads as
    `#idr.closure<@L, [caps]>`; in `forced`, it is refused as
    `Memoized`; in `running`, it is refused as `Unreadable`.
  - The original call's result type, `!idr.fn` or `!idr.lazy`, is
    what the attribute is checked against.
- **The JIT's runtime symbols.** `IDR/Eval/Jit.cppm`'s `symbols()` binds
  every runtime function that lowered pure code may call. It gains
  `idris_rt_inc` and `idris_rt_dec` (C6.1 emits them in every lowering;
  today's table at `Jit.cppm:85-122` has neither, because JIT mode never
  emitted them), `idris_rt_caf_release` (`@__idr_release_cafs` is emitted
  in every module, C5.5), `idris_rt_free_cell` (the `excl` force),
  `idris_rt_handle_is_null` and `idris_rt_handle_string`. It loses each entry that lowered code no
  longer names: grep the lowering for each one before you remove it.
- **Lists.** A list reads as a run: Reify collects the cells of one
  constructor along its spine into a vector, then calls
  `ConAttr::getRun` once. A list with one cell reads as a plain
  `ConAttr`.

## Inputs

- `createIdrMeter` and the `IdrLower` constructor with no options, from
  `Passes.td` (the coordinator).
- Memo sums and closure sums (U09), and U10's layouts, with
  `Layouts::isMemo(Type)`.
- `ConAttr::getRun` and the C7.2 accessors (U19).
- `idr::defunctionalize::defunctionalize` and its unknown keys (U09).

## Outputs

- The evaluator on the program's lowering.
- Reify of sums and runs.

## Implement

- Per the fixed decisions, in `Round.cppm`, `Reify.cppm`,
  `Encoding.cppm` and `Jit.cppm`.
- Remove the label-number plumbing from `Encoding.cppm` and
  `Child.cppm` if the code table fed them.

## Delete

- `codesName`, the global table built after `toLLVM`, and the
  `codes` map in `Reifier` with its constructor parameter.
- `IdrLowerOptions{/*jit=*/true}`.
- The branch of `Reifier` that reads a code address after the header.

## NOT TO DO

- Do not change the meter's budgets, the child, or the round's batching.
- Do not evaluate a call whose scratch keeps a closure.
- Do not change what counts as a closed call.
- Do not change the reify of strings, bigs, scalars or arrays.

## Acceptance

- `T/programs/eval/*` give the same output with and without
  `--directive no-eval`. The coordinator runs it.
- `T/programs/eval/closure-result-roundtrip` evaluates a call returning
  a list of partially applied functions, and the program runs them.
  U23 writes it.
- `T/programs/eval/deep-list-constant` reifies a 10^5-element list as
  one run, and decodes it in time linear in its length. U23 writes it.
- `grep -rn 'codes' foreign/idr/lib/Eval` finds nothing, and no
  `IdrLower` option is passed.
- Compile times within 10% (`T/compile-times.sh`). That is the
  coordinator's qualification.
- **Tempting partial:** keeping a closure lowering "just for eval".
  Rejected: that is the mode this packet deletes.

## Escalate if

- `idr-defunctionalize` cannot run on a scratch module because it
  requires a single public root. Report the check that refuses it.

## Stop and return

You are done when the round uses the pipeline above, reify reads sums
and runs, and the code table is gone. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
