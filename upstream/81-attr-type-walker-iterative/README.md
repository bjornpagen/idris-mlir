<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] The attribute and type walker and replacers recurse once per level of nesting

On llvm main at 416f328b (the pin), `AttrTypeWalker` walks an element's
sub-elements by recursion: `walkImpl` (`mlir/lib/IR/AttrTypeSubElements.cpp:26`)
calls `walkSubElements` before or after the walk functions (`:37`, `:52`),
whose callback calls `walkImpl` again for each sub-element (`:63`). The
replacers do the same: `replaceElementImpl` (`:200`) calls
`replaceSubElements` (`:219`), whose callback calls the replacer's
`replace` on each sub-element (`updateSubElementImpl`, `:166`), which is
`cachedReplaceImpl` and `replaceBase` again, for `AttrTypeReplacer`
(`:246`) and `CyclicAttrTypeReplacer` (`:282`) alike (*read*). Several
native frames per level of attribute or type nesting: walking or
replacing a value nested N deep needs a native stack that grows with N.

The tree reaches both on every compilation: the compiler's own
substitution of a family's index terms (`AttrTypeReplacer`,
`foreign/idr/lib/IR/Families/Substitute.cpp`) and its type graph
(`AttrTypeWalker`, `foreign/idr/lib/IR/TypeGraph.cpp`), and upstream's
symbol uses, which walk every operation's attributes for references
(`walkSymbolRefs`, `mlir/lib/IR/SymbolTable.cpp`) and replace them on a
rename (`replaceAllSymbolUsesImpl`). Under the compiler's one small,
measured stack for every thread (proposals/0000 D33, C43, C99), a value
nested deeply enough (a data type whose index terms or constants nest,
an attribute a program builds) would reach the guard: the tools' stack
limit would then be a limit on the programs the compiler accepts.

## Reproduce

`nested-attribute.sh DEPTH` writes a module whose function holds a
reference to a private function inside builtin arrays nested DEPTH deep.
`mlir-opt -symbol-dce` looks for the private function's uses, which walks
that attribute down to the reference; under a small stack (`ulimit -s
256`), a few thousand levels overflow it at the pin (*conjecture* on the
depth: no overflowing depth is measured). The textual parser and printer
of nested arrays recurse on the same depth unless
`upstream/10-recursive-attribute-parser` is applied, as it is before this
patch. The patch's unit test isolates the walk and the replacement: it
builds an array attribute nested 10,000 deep in memory and walks and
replaces it on a thread whose stack is 256 KiB, which frames per level
overflow.

## Patch

`llvm.patch`: the walker and both replacers keep their place in an
explicit stack, one frame per element whose sub-elements are being
visited, holding those sub-elements as `walkImmediateSubElements` gives
them (which only enumerates them) and the next one to visit. What the
recursion did is kept:

- the walker enters an element in its visited set before anything else,
  so an element met again, even while its own walk is in progress, is
  given the result recorded for it; its walk functions run, most recently
  added first, before its sub-elements in pre-order and after them in
  post-order; a skip passes over its sub-elements, an interrupt ends the
  walk of every element it is under, and a post-order walk records the
  interrupt as the result of each, as before (a pre-order walk records it
  only for the element whose walk function interrupted); null
  sub-elements are passed over;
- each replacer looks an element up in its cache first (`AttrTypeReplacer`
  marking it in progress as its own replacement, so a re-occurrence while
  it is replaced is left as it is; `CyclicAttrTypeReplacer` through its
  cycle-breaking cache), runs the replacement functions, most recently
  registered first, until one handles it, and unless they skip, replaces
  the sub-elements of the replacement in order, stopping at the first that
  fails, which fails the element; a null sub-element is replaced by null;
  the element is rebuilt with `replaceImmediateSubElements` only when a
  sub-element changed, and its result is recorded in the cache after
  theirs, a failure as null;
- the cyclic replacer's unresolved entries are resolved in the reverse
  order of their lookups, as its cache requires; each entry is made in
  place on the heap and never copied, since an unresolved entry may not
  be destroyed;
- a replacement function that calls `replace` itself starts a walk of its
  own, as before, and the public interface is unchanged.

`replaceBase` and each replacer's `cachedReplaceImpl` (protected and
private) give way to `replaceWithCache` on the base and a cache lookup
and resolution on each replacer, which the base reads as a friend. The
unit test is `AttrTypeSubElementsTest.testDeepNestingOnASmallStack` in
`mlir/unittests/IR/AttrTypeReplacerTest.cpp` (pre- and post-order walks,
an interrupt, and both replacers on the same nested array); upstream's
replacer tests in that file, the cyclic ones among them, check that
nothing else changed. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, after an RFC on Discourse for the family of
  MLIR's recursions on input size (proposals/0000 C99: walks, the printer
  and parser, attributes, clone, destruction, region DCE, call graph
  construction, slices), each family its own pull request.
- Upstream test: `AttrTypeSubElementsTest.testDeepNestingOnASmallStack`,
  with the file's cyclic replacer tests unchanged.
- The patch goes when the pin walks and replaces sub-elements without
  recursion on nesting depth.
