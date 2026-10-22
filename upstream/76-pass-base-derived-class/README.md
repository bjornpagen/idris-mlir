<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][Pass] A pass's CRTP base class is undocumented

On llvm main at 416f328b (the pin), `PassBase`'s `baseClass` is spliced
into the generated `<Pass>Base` template, whose parameter is the derived
pass, `DerivedT` (`mlir/tools/mlir-tblgen/PassGen.cpp`,
`baseClassBegin`, *read*), so a project may give its passes a base class
that takes the derived pass's type. Nothing documents it: PassBase.td
calls the field "the C++ base class", and PassManagement.md names only
`OperationPass` and `InterfacePass`. The compiler's `StagedPass` becomes
CRTP that way, deleting its last virtual (proposals/0000 C120); relying
on an undocumented splice is relying on an accident.

## Reproduce

Nothing to run: documentation (*read*).

## Patch

`llvm.patch`, documentation only: the field's comment in PassBase.td and
a paragraph with an example in PassManagement.md. Not built (nothing to
build).

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one NFC pull request to llvm/llvm-project, `[mlir][Pass]`.
- Upstream test: none (documentation).
- The patch goes when the pin documents it.
