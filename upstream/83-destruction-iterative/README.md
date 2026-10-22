<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] Destroying an operation, and dropping its references, recurse once per level of nesting

On llvm main at 416f328b (the pin), destroying an operation recurses
through its regions (*read*): `Operation::destroy`
(`mlir/lib/IR/Operation.cpp:204-210`) runs `~Operation`, which runs each
region's destructor (`:197-198`); `~Region` drops the references of
everything in the region and deletes its blocks (`Region.cpp:16-20`);
each block's destructor clears it (`Block.cpp:20-25`), dropping its
references again and popping its operations (`Block.h:39-47`), each
deleted through `ilist_traits<Operation>::deleteNode` (`Operation.cpp:482-484`),
which is `destroy` again. Several native frames per level of nesting.
Dropping references recurses the same way: `Operation::dropAllReferences`
(`Operation.cpp:577-586`) calls `Region::dropAllReferences`
(`Region.cpp:181-184`), which calls `Block::dropAllReferences`
(`Block.cpp:89-92`), which calls `Operation::dropAllReferences` for each
operation. And since every region's and every block's destructor drops
the references of everything below it again, destroying a chain of
operations nested N deep visits about N²/2 operations.

Every erase in the compiler destroys (89 sites of `erase` and `eraseOp`
under `foreign/idr/lib`), and so does freeing a module. Under the
compiler's one small, measured stack for every thread (proposals/0000
D33, C43, C99), erasing or freeing a deeply nested function (a generated
`else if` chain is one match per branch, nested) reaches the guard: the
tools' stack limit would then be a limit on the programs the compiler
accepts.

## Reproduce

`nested-module.sh DEPTH` writes a module of unregistered operations
nested DEPTH deep, in the generic form; any run of `mlir-opt` destroys
the module when it ends. On a small stack (`ulimit -s 256`) a few
thousand levels overflow it at the pin (*conjecture* on the depth: no
overflowing depth is measured). The textual parser and printer recurse on
the same depth through each operation's parse and print hooks, so through
`mlir-opt` destruction is seen alone only on IR read from bytecode and
not printed back. The patch's unit test isolates it: it builds a chain of
operations nested 10,000 deep in memory and, on a thread whose stack is
256 KiB, drops its references, destroys it, and deletes a block holding
another such chain.

## Patch

`llvm.patch`, applying after 82 (the unit tests' `CMakeLists.txt`):

- `Block::dropAllReferences` visits the operations nested in its own in
  the order the recursion visited them, an operation's operands dropped,
  then everything in its regions, then its successors, moving through the
  IR's parent links (the next operation, the next non-empty block, the
  next region, the enclosing operation) with no stack at all.
  `Operation::dropAllReferences` and `Region::dropAllReferences` call it,
  one level each, as before.
- `Operation::destroy` tears down the operations nested in the one it
  destroys from an explicit stack, one entry per operation being torn
  down (the region whose blocks are being deleted, and the block,
  already unlinked, whose operations are being destroyed), in the order
  the destructors took them: for each region in turn its references
  dropped, its blocks unlinked and deleted front to back, each block's
  operations unlinked and destroyed back to front, each after everything
  nested in it. Each destructor then finds its regions empty and recurses
  no further. An operation with no regions is freed at once, as before.

What the destructors did is kept: no operation is freed while a use
inside its region tree remains, since a region's references are dropped
before any operation in it goes; blocks and operations go in the same
order; the check that a block's operation order is valid runs where
`~Block` ran it, with the operations still in it. Two things move, and
neither is observable: an operation's own operands and successors are
destroyed after the operations nested in it rather than before (none of
them is a use of a value defined inside it), and the references of a
nested operation's regions are not dropped a second time (dropping those
of the outermost region dropped them), which makes destruction linear in
the size of the IR. `~Region`, `~Block` and `Block::clear` are unchanged
and reach the nested operations through `destroy`. The unit test is
`mlir/unittests/IR/DestructionTest.cpp`. Not built.

Left recursive, outside this family: `Operation::dropAllDefinedValueUses`
and `Block::dropAllDefinedValueUses` (`Operation.cpp:590-596`,
`Block.cpp:94-100`), and the rewriter's `eraseOp`, whose `eraseTree`
recurses through a `std::function` once per level when a listener is
attached (`mlir/lib/IR/PatternMatch.cpp:193-229`).

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, after an RFC on Discourse for the family of
  MLIR's recursions on input size (proposals/0000 C99: walks, the printer
  and parser, attributes, clone, destruction, region DCE, call graph
  construction, slices), each family its own pull request.
- Upstream test: `DestructionTest.DropAllReferences` and
  `DestructionTest.DestroyAndDeleteBlock`; every lit test that erases
  checks that nothing else changed.
- The patch goes when the pin destroys operations and drops their
  references without recursion on nesting depth.
