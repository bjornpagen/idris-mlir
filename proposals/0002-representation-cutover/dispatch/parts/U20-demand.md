# U20 — The in-place promise: idr-demand and its flag

Mandatory findings: F-prom-2

## Permitted outcome

1. **The pass.** `idr-demand{promises=in-place}` rejects a call that
   passes a shared value to a quantity-1 parameter its callee matches
   and rebuilds at the same size. The message is C10.2's,
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
- `IDR/Expect/ReusesInPlace.cppm` (what "rebuilt in place" is), and
  `IDR/Expect/TestsNothing.cppm`.
- `IDR/Ownership/ExclusiveAnalysis.cppm` and `Exclusive.cppm`.
- `IDR/Driver/{Options,Run}.cppm` (how options become pipeline steps;
  how `--no-eval` works).
- `CS/Frontend/Main.idr:100-120` (directives).
- `sources/papers/lorenzen-2023-fp2`, the abstract and §2.

## Fixed decisions

- **Which parameters.** A parameter `p` of `f` is checked when:
  - its type has quantity 1 (`isLinear`);
  - `f`'s body matches `p` and, on a path, builds a constructor of the
    same cell size from it. That is the same test
    `IDR/Expect/ReusesInPlace.cppm` uses. Call it, or repeat its few
    lines; do not change it.
- **Which calls.** Every `func.call` of `f` must pass `p` with grade
  `excl`. A call that passes `own` or `borrow` is rejected.
- **The reason** names the dup or the use that kept the value shared.
  Read it from `ExclusiveAnalysis`'s state at the call: the value's
  defining dup, or the later use. If the analysis gives no reason, the
  message says "it may be shared" without one.
- **The flags.** `--demand <list>` is a comma list, and only `in-place`
  is known. An unknown promise is a usage error. `Run.cppm` replaces the
  `idr-demand` step's text with `idr-demand{promises=in-place}` when it
  is asked. `--directive demand-in-place` maps to `--demand in-place`,
  as `no-eval` maps today.

## Inputs

- `createIdrDemand` and its `promises` option (the coordinator).
- The `Uniqueness` rule (C1.6), used by its phrase only.
- `ExclusiveAnalysis` (U03 keeps it).

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

- `ExclusiveAnalysis` cannot be queried at a call after `idr-rc`.
  Report the API you need from U03.

## Stop and return

You are done when the pass and the flags exist. Return the changed
paths, `Verification: NotRun (swarm policy)`, and seams.
