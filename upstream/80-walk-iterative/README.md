<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] Every walk recurses once per level of operation nesting

On llvm main at 416f328b (the pin), each of the six walks in
`mlir/include/mlir/IR/Visitors.h` (over regions, blocks and operations,
void and interruptible: `detail::walk<Iterator>`, lines 101-250) calls
itself for every operation of every block of every region it visits
(`Visitors.h:111`, `:129`, `:148`, `:181`, `:210`, `:241`), and so do the
two stage-aware walks in `mlir/lib/IR/Visitors.cpp` (`:32`, `:59`); the
pin's own comment says it, "TODO: This walk should be iterative over the
operations" (`Visitors.h:142`, `:235`) (*read*). One native frame per
level of nesting: every pass walks, so every pass needs a native stack
that grows with the depth of the IR. Under the compiler's one small,
measured stack for every thread (proposals/0000 D33, C43, C99), a deeply
nested function (a generated `else if` chain is one match per branch,
nested) reaches the guard: the tools' stack limit would then be a limit
on the programs the compiler accepts.

## Reproduce

`nested-ops.sh DEPTH` writes a module of unregistered operations nested
DEPTH deep, in the generic form. Any pass over it walks it to the bottom;
run under a small stack (`ulimit -s 256`), a few thousand levels overflow
it at the pin (*conjecture* on the depth: no overflowing depth is
measured). The textual parser and printer recurse on the same depth
through each operation's parse and print hooks, so through `mlir-opt` the
walk is seen alone only on IR read from bytecode and not printed back.
The patch's unit test isolates it: it builds a chain of operations
nested 10,000 deep in memory and walks it, with every kind of walk, on a
thread whose stack is 256 KiB, which a frame per level overflows.

## Patch

`llvm.patch`: the eight walks share one engine, `detail::walkIteratively`,
which keeps its position in an explicit stack, one entry per operation
whose walk has begun, each holding the ranges it is inside (the
operation's regions, the region's blocks, the block's operations) and its
iterators into them. Each walk is a visitor that says where its callback
is made, how the callback's result skips or interrupts the walk, and
whether the next block or operation is taken before the current one is
walked. What the recursion did is kept, for every iterator kind
(forward, reverse and both dominance orders):

- each range is made where the recursive walk made it (an operation's
  regions after its pre-order callback, a block's operations after its
  block's) and dropped where it was (before the callback that follows
  the loop over it);
- the operation walks take the next operation, and the block walks the
  next block, before walking the current one, as their
  `make_early_inc_range` did, so a callback may erase the one it is given
  in post-order, or in pre-order when it then skips; every other range,
  regions always, is advanced only after its element is walked;
- skip and interrupt mean what they meant: a pre-order skip of an
  operation, region or block passes over its contents, a stage callback's
  skip before a region ends that operation's walk, a post-order skip is
  not checked, an interrupt ends the walk at once, and the root's result
  is returned as the recursion returned it (a post-order callback's own
  result included);
- the stage-aware walks call back before each region and once after the
  last, with the same `WalkStage`; the interruptible one takes the next
  operation first and the void one does not, as before.

A stack entry never moves while it is on the stack: the reverse-dominance
iterator's range is a post-order traversal whose iterators point into it
("PostOrderTraversal keeps state outside of iterators"). The first four
entries live in the stack object itself, so a walk nested no deeper than
that allocates nothing; deeper entries live in chunks of 32, allocated
when the walk first descends that far and kept until it ends. The unit
test is `mlir/unittests/IR/WalkTest.cpp`; upstream's lit tests of the
walks (`mlir/test/IR/visitors.mlir`, `test-ir-visitors`: orders, skips,
interrupts and erasure) check that nothing else changed. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, after an RFC on Discourse for the family of
  MLIR's recursions on input size (proposals/0000 C99: walks, the printer
  and parser, attributes, clone, destruction, region DCE, call graph
  construction, slices), each family its own pull request. The review
  will weigh the engine's cost against the recursion on shallow walks,
  which the inline entries are for.
- Upstream test: `WalkTest.DeepNestingOnASmallStack` in
  `mlir/unittests/IR`, with `visitors.mlir` unchanged.
- The patch goes when the pin walks nested regions without recursion on
  nesting depth.
