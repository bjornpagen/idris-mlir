# U20 — The in-place promise: idr-demand and its flag

Mandatory findings: F-prom-2

## Permitted outcome

1. **The pass.** `idr-demand{promises=in-place}` rejects a call that
   passes a value other than `excl` to a promised parameter: a
   quantity-1 parameter whose cell an `idr.reuse` in the callee takes
   from an `idr.take` of it (C10.2). The message is C10.2's,
   `unsupported (uniqueness): ...`, at the call. Without `promises`, the
   pass does nothing. Mandatory.
2. **The flags.** `idris-mlir-cc --demand in-place` and
   `idris-mlir --directive demand-in-place` run the pass with the
   promise. Mandatory.

## Owner / exclusive writes

- `IDR/Demand`: `Demand.cppm`, `Pass.cc`, and `CMakeLists.txt` defining
  `idr_demand`.
- `IDR/Driver/Options.cppm`
- `IDR/Driver/Run.cppm`
- `CS/Frontend/Main.idr`

**Excluded:**

- `INC/Passes.td`, where the coordinator defines `IdrDemand` and its
  `promises` option.
- `IDR/Dialect/Registration`, where the coordinator puts `idr-demand`
  after `idr-rc`.
- `foreign/idr/CMakeLists.txt` (the coordinator adds the area).
- `CS/Rule.idr` (the coordinator adds `Uniqueness`).
- `IDR/Ownership` (U03) and `IDR/Expect` (U06), which you read and do
  not write.

## Read first

- `contracts.md` C10.2, C1.2, C1.3 and C13.
- `findings.md` F-prom-2.
- `README.md` at the repository root, "Why not Lean 4".
- `review.md`, the smaller point on C10.2.
- `IDR/Ownership/Take.cppm` and the `idr.take` and `idr.reuse` ops, the
  two ops the promise reads.
- `IDR/Ownership/Cells.cppm` (`Sharing`: `Unknown`, `Exclusive`,
  `Shared`, with no reason).
- `IDR/Driver/{Options,Run}.cppm` (how options become pipeline steps;
  how `--no-eval` works).
- `CS/Frontend/Main.idr:100-120` (directives).
- `sources/papers/lorenzen-2023-fp2`, the abstract and §2.

## Fixed decisions

- **Which parameters.** A parameter `p` of `f` is promised when:
  - its type has quantity 1 (`isLinear`);
  - an `idr.reuse` in `f` takes its token from an `idr.take` whose
    operand is `p`, or the region argument a match of `p` binds it to.

  That is a fact of two ops in `f`'s body. It needs no analysis, and it
  does not use `idr-expect`'s per-function `reuses-in-place` property.
- **Which calls.** Every `func.call` of `f` must pass a promised `p`
  with grade `excl`. A call that passes it `own`, or as a plain view, is
  rejected.
- **The note.** When the argument is the result of an `idr.dup`, a note
  at the dup says `shared here`. That is read from the operand's
  defining op. Nothing else is reported: `ExclusiveAnalysis` keeps no
  reason, and you add none.
- **The flags.** `--demand <list>` is a comma list, and only `in-place`
  is known. An unknown promise is a usage error. `Run.cppm` replaces the
  `idr-demand` step's text with `idr-demand{promises=in-place}` when it
  is asked. `--directive demand-in-place` maps to `--demand in-place`,
  as `no-eval` maps today.

## Inputs

- `createIdrDemand` and its `promises` option (the coordinator).
- The `Uniqueness` rule (C1.6), used by its phrase only.
- The `excl` grade `idr-rc` writes (U03).

## Outputs

- The pass, and the two flags.

## Implement

- Per the fixed decisions.

## Delete

- Nothing.

## NOT TO DO

- Do not make the promise the default (O5).
- Do not change `idr-rc`'s decisions.
- Do not add a promise beyond `in-place`.
- Do not check functions that do not rebuild in place.
- Do not add provenance to `ExclusiveAnalysis` or any U03 file.

## Acceptance

- `T/reject/uniqueness-shared-rebuild` is rejected naming the call, and
  every `T/programs/linear/leet-*` compiles with the directive. U23
  writes both.
- With no flag, every program's output and dumps are unchanged.
- **Tempting partial:** checking only that `f`'s parameter is linear.
  Rejected: linearity says the callee uses it once, not that the caller
  holds it alone (`substrate.md` §3, Marshall). The check is at the
  call.

## Escalate if

- A leet fixture that rebuilds in place is rejected under the
  directive. Report the call: either the fixture shares the value, or
  `idr-rc` does not write `excl` where it could.

## Stop and return

You are done when the pass and the flags exist. Return the changed
paths, `Verification: NotRun (swarm policy)`, and seams.
