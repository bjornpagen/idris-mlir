<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L03's notes for INT (running lane, 2026-10-21)

- mlir-tblgen over the generated outputs:
  - `Generated/IdrTransformOps.td` writes `idr/Target/ScheduleOps.{h,cpp}.inc`;
  - `IdrInnerPasses.td` writes `idr/Transforms/InnerPasses.h.inc`
    (`-name IdrInner`);
  - `IdrPasses.td` writes `idr/Transforms/Passes.h.inc`.
- `StagedPass` is CRTP, with no virtual (C120, patch 76). Drop
  `override` from `runOnProgram` in 24 files. The running lanes are told.
  For the finished L05 (Lifetimes) and L08 (Ownership/{Exclusive,Knots},
  InPlace), the fix goes in their follow-ups or comes back as an INT
  build failure.
- Core's renames, for the finished L13: `Upstream X` → `Declares X`,
  `Ours i` → `Implements i`, `MkMethod Instance/Static` →
  `PerObject/PerClass`, `NoVerifier` → `Unverified`, and the `…InterfaceI`
  suffix dropped.
- BigToWord comes from each big op's `specializations`; `NoClass` prints
  `using Op = void;`. That is L13's follow-up.
