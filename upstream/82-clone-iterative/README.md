<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] Cloning a region recurses once per level of nesting

On llvm main at 416f328b (the pin), `Region::cloneInto`
(`mlir/lib/IR/Region.cpp:76-149`) clones a region in two steps, its
blocks and operations created and mapped first (`:94-128`, each operation
by `Operation::clone` with no regions and no operands), then each
operation's operands set and each of its regions cloned, by calling
itself (`:145-146`, through the overload at `:70-73`) (*read*). One native
frame per level of region nesting, and `Operation::clone` enters it for
every region of the operation it copies (`mlir/lib/IR/Operation.cpp:744-747`).
So cloning IR nested N deep needs a native stack that grows with N, and
the tree clones nested IR wherever it copies an operation with regions:
upstream's inliner copies a callee's body (`InliningUtils.cpp`, through
`cloneInto`), and the compiler copies operations with regions in the
e-graph's elaboration (`foreign/idr/lib/Transforms/EGraph/Elaborate.cpp`),
in loop copies (`Transforms/Narrow/Copy.cpp`) and in bufferization
(`Transforms/Bufferize/`). Under the compiler's one small, measured stack
for every thread (proposals/0000 D33, C43, C99), a deeply nested function
(a generated `else if` chain is one match per branch, nested) reaches the
guard: the tools' stack limit would then be a limit on the programs the
compiler accepts.

## Reproduce

`nested-callee.sh DEPTH` writes a module whose private function nests
`scf.execute_region` DEPTH deep and is called once; `mlir-opt -inline`
clones the callee's body into the caller. On a small stack (`ulimit -s
256`) a few thousand levels overflow it at the pin (*conjecture* on the
depth: no overflowing depth is measured). The textual parser and printer
recurse on the same depth through each operation's parse and print hooks,
so through `mlir-opt` the clone is seen alone only on IR read from
bytecode and not printed back. The patch's unit test isolates it: it
builds a chain of operations nested 10,000 deep in memory, each taking
its block's argument as its operand, and clones it on a thread whose
stack is 256 KiB.

## Patch

`llvm.patch`, applying after 80 (the unit tests' `CMakeLists.txt`): the
first step, creating and mapping a region's blocks, block arguments and
operations, is its own function, `cloneBlocksAndOperations`, the code the
pin had. The second step keeps its place in each region it is inside on
an explicit stack, one entry per region being cloned: its source and
cloned block and operation, and the next region of that operation to
clone. Reaching an operation sets its operands; reaching one of its
regions runs the first step on it and pushes an entry; an entry is popped
when its region has no operation left. What the recursion did is kept:
blocks, block arguments, operations and mappings are created in the same
order (a nested region in full, both steps, when the operation holding it
is reached, before that operation's next region and the next operation),
every operand is set by `lookupOrDefault` once every value it can name is
mapped, an argument the caller mapped beforehand is still dropped, an
empty region is still skipped, and `CloneOptions` reach `Operation::clone`
as before. Nothing is notified: cloning tells no listener, and a builder
that clones tells its listener of the nested operations by a walk
afterwards, as it did. The unit test is `mlir/unittests/IR/CloneTest.cpp`;
it destroys its chains innermost first, so that it needs no other patch
(83 makes destruction iterative too). Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, after an RFC on Discourse for the family of
  MLIR's recursions on input size (proposals/0000 C99: walks, the printer
  and parser, attributes, clone, destruction, region DCE, call graph
  construction, slices), each family its own pull request.
- Upstream test: `CloneTest.DeepNestingOnASmallStack`; the lit tests
  that clone (`mlir/test/Transforms/inlining*.mlir`, the
  `test-clone` pass) check that nothing else changed.
- The patch goes when the pin clones regions without recursion on
  nesting depth.
