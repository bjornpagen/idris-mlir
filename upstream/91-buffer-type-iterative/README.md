<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][bufferization] getBufferType recurses once per value of a chain

On llvm main at 416f328b (the pin), and on main at 1204f6b4
(2026-10-21), whose `BufferizableOpInterface.cpp`, `.h` and `.td` are the
same files, `bufferization::getBufferType`
(`mlir/lib/Dialect/Bufferization/IR/BufferizableOpInterface.cpp:785`)
pushes the value on the invocation stack and asks its owner's
`BufferizableOpInterface::getBufferType` (`:797`), and an implementation
calls `bufferization::getBufferType` for each value its own buffer type
comes from: the default for the operand an op result is equivalent to
(`:1000`), `tensor.cast` and the reshapes and slices for their source,
`scf.if` and `scf.index_switch` for each yielded value, the loops for the
init_arg and then the yielded value
(`mlir/lib/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.cpp:512`)
(*read*). Two native frames, and the implementation's own, per value of a
chain of values whose buffer types depend on each other, so a chain of N
tensor values needs a native stack that grows with N. No pull request or
issue upstream changes it (searched 2026-10-21).

What reaches it in this repository: the bufferization of arrays, One-Shot
Bufferize over the compiler's models, whose `getBufferType`
implementations are steps of that recursion
(`foreign/idr/lib/Transforms/Bufferize/`: `Data.cpp`, `Linear.cpp`,
`Values.cpp`, `Generating.cpp`). A loop that carries an array through a
long body, or a long chain of array values, is a program-sized chain, and
under the compiler's one small, measured stack for every thread
(proposals/0000 D33, C43, C99) it reaches the guard: the tools' stack
limit would then be a limit on the programs the compiler accepts.

## Reproduce

`loop-chain.sh PAIRS` writes a function whose `scf.for` carries a tensor
through PAIRS pairs of `tensor.cast`; `mlir-opt -one-shot-bufferize`
computes the iter_arg's buffer type before it bufferizes the body, from
the yielded value back along the chain. On a small stack (`ulimit -s
256`) a few thousand casts overflow it at the pin (*conjecture* on the
length: no overflowing length is measured). The chain is flat, so the
textual parser and printer do not recurse on it and `mlir-opt` shows the
recursion alone.

## Patch

`llvm.patch`, applying after 24 and 27, which change the same header and
file: the computation keeps its place on an explicit stack,
`detail::BufferTypeQuery`, one frame per value whose buffer type is in
progress, in the order of the invocation stack, which the query owns
after the values its caller gave. A frame's step is what
`bufferization::getBufferType` did for its value after pushing it: the
owner's implementation, or the memory space and the unknown type
converter for an op that is not bufferizable. An implementation that
calls `bufferization::getBufferType` with the invocation stack it was
given reaches the query (found through `BufferizationState`, which holds
the innermost running query as it holds the symbol table cache) instead of
recursing: it gets its step's next answer if an earlier run of the step
asked for it, and otherwise a failure, with the value recorded as wanted,
after which every further question of that run fails too. A run that
wanted a value is void: the value is computed by a frame of its own, its
buffer type (or failure) becomes the step's next answer, and the step
runs again from the start. So every implementation is asked for the same
values, in the same order, with the same invocation stack, given the same
answers, and the loops' test of how often an iter_arg is on the stack
reads the same stack. Two conditions make it exact, both stated in the
interface's documentation and met by every implementation upstream
(arith, bufferization, func, scf, tensor and the unstructured control
flow model, *read*) and by the compiler's: an implementation asks for the
same values when run again, and acts on a failed question only by
returning failure, with no diagnostic of its own (a void run's failure is
not a real one). What changes: the part of an implementation before its
last question runs once per question (an `scf.index_switch` of k cases
runs k+1 times, so its joins are quadratic in k), and an option hook it
calls there (`reconcileBufferTypeMismatchFn`, the analysis state's
initializers) is called again with the same arguments; every upstream hook
is a function of its arguments. The unit test,
`BufferTypeTest.LongChainOnASmallStack` in the new
`mlir/unittests/Dialect/Bufferization/`, computes on a 256 KiB thread the
buffer type of the last of 10,000 values after an allocation, alternately
a `tensor.cast` (one question, its result built from the answer) and an
`arith.select` of the value before and the allocation (two questions, so
a step run three times), and gets the allocation's `memref<4xf32>`.
`tools/bootstrap.sh` applies it with every `upstream/*/llvm.patch`, in
name order. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, `[mlir][bufferization]`, after the RFC on
  Discourse for the family of MLIR's recursions on input size
  (upstream/10-recursive-attribute-parser's plan); it does not depend on
  24 or 27, whose hunks it only sits beside.
- Upstream test: the unit test above, with every One-Shot Bufferize lit
  test (`mlir/test/Dialect/*/one-shot-bufferize*.mlir`, the loops' and the
  function boundaries' among them) unchanged.
- The patch goes when the pin computes buffer types without recursion on
  the length of a chain.
