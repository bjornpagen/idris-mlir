<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] FunctionOpInterface's signature edits never reach an operation's own

On llvm main at 416f328b (the pin), and on main at 1204f6b4
(2026-10-21), whose `FunctionInterfaces.td` is the same file,
`insertArguments`, `insertResults`, `eraseArguments` and `eraseResults`
are shared class declarations of `FunctionOpInterface`
(`mlir/include/mlir/Interfaces/FunctionInterfaces.td:148`, `:271`, `:299`,
`:324`, `:343`), not interface methods (*read*). `mlir-tblgen` pastes a
shared declaration into the interface class with `$_op` as `(*this)` and
into the operation's trait with `$_op` as the concrete operation
(`mlir/tools/mlir-tblgen/OpInterfacesGen.cpp:164-165`), so a caller
holding a `FunctionOpInterface` runs the interface's copy whatever the
operation is: an operation that defines its own edit is reached only
through its concrete class. The single-item forms (`insertArgument` and
the others, `:263`, `:291`, `:319`, `:338`) call the plural form
unqualified, so even on the concrete class they reach the trait's copy,
not the operation's. None of the hooks the edits call (`cloneTypeWith`,
`setFunctionTypeAttr`, `setArgAttrsAttr`) is given the indices. No pull
request or issue upstream changes it (searched 2026-10-21; #137130 made
the edits fallible, which is the present form).

What needs it in this repository: `idr.func` states facts by the
positions of its parameters and results (where each scoped value lives
and the bounds between lifetimes, what it gives back, its untouched and
bounded parameters), which its own edits move with the signature
(`foreign/idr/lib/IR/Func/Edits.cpp`), and upstream's passes and ours
edit functions through the interface. Through the interface, those facts
would be left at their old positions, naming the wrong parameters
(proposals/0000 C187).

## Reproduce

The patch's lit test, `mlir/test/IR/test-func-edit-overrides.mlir`: the
`test-func-insert-arg`, `-insert-result`, `-erase-arg` and `-erase-result`
passes edit every function through a `FunctionOpInterface` handle, and
`test.positional_func` overrides the four edits to keep a tag per argument
and result, which its verifier checks against its signature. With the
test operation and without the `.td` change, each pass runs the
interface's copy, the tags keep their old count, and the verifier after
the pass fails.

## Patch

`llvm.patch`: the four edits move from `extraSharedClassDeclaration` to
`methods` as `InterfaceMethod`s, each with its present body as its default
implementation and its present documentation, which adds that an
operation keeping facts by position overrides it and is reached through
the interface. An operation that overrides none, every one upstream (no
operation in llvm-project defines one of the four, *read*), behaves as
before: the model calls the trait's default, the same code. The
single-item forms call the plural form as `$_op.insertArguments(...)`, so
they reach an override from the interface and from the concrete class.
An override that extends the default calls it as
`FunctionOpInterface::Trait<ConcreteOp>::eraseArguments(...)`, as the test
operation does. The test operation, `test.positional_func`, declares the
four with `DeclareOpInterfaceMethods` (as `wasmssa.func` declares
`verifyBody`); its overrides compute the new tags, call the default and
set the tags. `tools/bootstrap.sh` applies it with every
`upstream/*/llvm.patch`, in name order. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, `[mlir]`, on its own (it depends on no other
  patch here and applies to the pin alone).
- Upstream test: the lit test above, with the four existing
  `mlir/test/IR/test-func-*.mlir` tests and the lit tests of every
  upstream caller of the edits (`-remove-dead-values` among them)
  unchanged.
- The patch goes when the pin's `FunctionOpInterface` dispatches the four
  edits to an operation's own.
