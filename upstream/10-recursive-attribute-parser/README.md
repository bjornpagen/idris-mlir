<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] The textual parser and printer recurse once per level of attribute nesting, and overflow the stack

`mlir-opt` crashes with a signal on a module whose attribute is a
builtin array nested a few thousand deep: the parser calls itself for
every level, and the stack runs out. The printer and the alias
collection before it recurse the same way. Nothing checks the depth, so
the crash is a bare segmentation fault, with no diagnostic.

Values nested this deep are ordinary for a compiler: a list of 10,000
elements becomes a constant nested 10,000 deep. And under the compiler's
one small, measured stack for every thread (proposals/0000 D33, C43,
C99), any recursion on the depth of the input is a limit on the programs
it accepts.

## Reproduce

`nested.sh 10000 > nested.mlir` writes:

```mlir
module attributes {test.nested = [[[[ ... ]]]]} {
}
```

with the array nested 10,000 deep (20 KB of text).

```
$ ulimit -s 8192
$ mlir-opt nested.mlir
Stack dump:
0.	Program arguments: mlir-opt nested.mlir
1.	MLIR Parser: custom op parser 'builtin.module'
Segmentation fault
```

*Measured* at `llvmorg-23.1.2`: `mlir-opt` exits with status 139; on an
8 MiB stack, 4,000 levels parse and print, and 6,000 crash. *Measured*
at llvm main 7208ba24 on arm64 macOS (2026-10-09,
`tests/upstream-recursive-attribute-parser`): 1,000 levels parse, and
100,000 end `mlir-opt` with a signal. At 416f328b, the pin, the code is
the same (*read*). Expected: the module parses and prints back.

## Cause

At the pin (*read*):
- `Parser::parseAttribute` (`mlir/lib/AsmParser/AttributeParser.cpp:74`)
  parses an array's elements through `parseCommaSeparatedListUntil`
  with a callback that calls `parseAttribute` again, and a dictionary's
  values through `parseAttributeDict` (`:108`), which does the same:
  every level costs several frames.
- `AsmPrinter::Impl::printAttributeImpl`
  (`mlir/lib/IR/AsmPrinter.cpp:2478` and `:2516`) prints a dictionary's
  values and an array's elements by calling `printAttribute` for each.
- The alias collection before printing (`AliasInitializer::visitImpl`,
  `:1219`) visits an attribute's children through
  `DummyAliasDialectAsmPrinter` (`:969`, `:974`), which calls `visit`
  for each: two frames and a printer object per level.
  `markAliasNonDeferrable` (`:1254`) recurses through the child aliases
  too.

The bytecode reader has no such limit: it reads attributes from a
worklist.

## Patch

`llvm.patch`: builtin arrays and dictionaries nested in one another are
handled from an explicit stack in all three places, with the same
result as the recursion:
- the parser's `parseArrayOrDictionaryAttr` consumes the same tokens,
  builds the same attributes and reports the same diagnostics; every
  element that is not an array or dictionary still goes through
  `parseAttribute`. The entry-name half of `parseAttributeDict` is
  shared as `parseAttributeEntryName`;
- the printer's `printArrayOrDictionaryAttr` prints the same text: a
  nested array or dictionary with an alias prints its alias, one without
  is opened in place;
- the alias collection's `visitArrayOrDictionary` adds the same entries
  in the same order, with the same child indices and depths, and
  `markAliasNonDeferrable` marks the same aliases from a worklist.

A lit test (`mlir/test/IR/attribute-nesting.mlir`) round-trips arrays
and dictionaries nested in each other with an alias inside. Not built.
`nested.sh 100000` round-tripping on an 8 MiB stack with the patch is
*conjecture* until the toolchain is built with it.

What it leaves, each recursion on nesting through a hook the patch
cannot see into: a dialect attribute whose parameters are attributes
(its parser calls `parseAttribute`, its printer `printAttribute`, for
each); the op parser and printer, which reach a nested region through
the op's own parse and print hooks (`parseRegion`, `printRegion`), the
alias collection's dummy printer among them. Those are the families of
proposals/0000 C99 that no explicit stack inside MLIR's code removes,
since the recursion runs through code each dialect writes.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: an RFC on LLVM Discourse (MLIR) first, for MLIR's recursions on
  input size (proposals/0000 C99: walks, the printer and parser,
  attributes, clone, destruction, region DCE, call graph construction,
  slices), citing the bytecode reader's worklist; then this pull
  request, one per family.
- Upstream test: `mlir/test/IR/attribute-nesting.mlir`, and `nested.sh
  10000` round-tripping through `mlir-opt` on an 8 MiB stack.
- The patch goes when the pin parses, prints and aliases nested arrays
  and dictionaries without recursion on their depth.
