<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][bytecode] The reader decodes an op's properties by its own registry, not by the writer's

On llvm main at 7208ba24 (the pin), and at b43c0361 (main on 2026-10-15,
where `mlir/lib/Bytecode` is unchanged since the pin), the bytecode reader chooses how to decode an operation's properties by whether
the operation is registered where the file is read. The writer chose the
encoding by whether it was registered where the file was written, and
records that choice in the file. When the two disagree, an operation
written without its dialect and read with it, the reader runs the
operation's native property decoder over an attribute number, and reading
fails or reads garbage. The test that was meant to follow the writer's
choice, `if (wasRegistered)` on a `std::optional<bool>`, tests whether the
flag is present, which it always is from version 5 on, so its other branch
is dead.

## Reproduce

Upstream, as a unit test (the test of `pull-request.diff`): parse
`OpPropertiesTest`'s `"test_op_properties.op_with_properties"() <{a = -42 :
i32, ...}>` in a context that allows unregistered dialects and does not
load `test_op_properties`, write it with `writeBytecodeToFile`, and read the
bytes back with `parseSourceString` in a context that loads the dialect.
The read fails: `has properties but missing BytecodeOpInterface for
test_op_properties.op_with_properties`. The op has no interface because it
needs none: what the file holds for it is an attribute.

With the tools at the pin, `written-unregistered.mlir`, the smallest
program the idr dialect verifies, in the generic form:

```mlir
"idr.program"() <{root = @main, stage = 1 : i32, sym_name = "written"}> ({
  "idr.func"() <{function_type = () -> i64, sym_name = "main"}> ({
    %c = "arith.constant"() <{value = 7 : i64}> : () -> i64
    "idr.return"(%c) : (i64) -> ()
  }) : () -> ()
}) : () -> ()
```

`mlir-opt -allow-unregistered-dialect -emit-bytecode written-unregistered.mlir
-o x.mlirbc` writes it (the toolchain's `mlir-opt` has no `idr` dialect);
`idris-mlir-opt x.mlirbc` then fails in `ProgramOp::readProperties`, at its
first property, with `expected ...StringAttr, but got: {root = @main, stage
= 1 : i32, sym_name = "written"}`: the native decoder reads the number of
the properties dictionary as the number of `sym_name`. `idris-mlir-opt`
reads the same file as text.

## Expected

The properties of an operation written unregistered are read as the
attribute the writer stored, whatever the reader has registered, and set
from that attribute as the generic text form's are
(`Operation::setPropertiesFromAttribute`).

## Cause

- The writer (`mlir/lib/Bytecode/Writer/BytecodeWriter.cpp`) records, for
  each operation name, whether it was registered (`emitVarIntWithFlag(...,
  name.name.isRegistered(), ...)`, `:861-865`). For an operation with
  properties it writes an index into the properties section
  (`:1038-1044`). The entry there is the native encoding for a registered
  operation (`writeProperties`, `:537-545`) and, for an unregistered one,
  the number of the attribute the properties are stored as (`:524-535`).
- The reader keeps the flag as `std::optional<bool> wasRegistered`, present
  from version 5 (`kNativePropertiesEncoding`) on
  (`mlir/lib/Bytecode/Reader/BytecodeReader.cpp:2126-2141`). In
  `parseOpWithoutRegions` (`:2586-2609`) it returns an error when the flag
  is absent, then tests `if (wasRegistered)` (`:2597`), which is the same
  presence test and so always true: the else branch, which reads an
  attribute, never runs.
- The branch it runs calls `PropertiesSectionReader::read`
  (`:1262-1302`), which finds the entry and then decides by the reader's
  registry: the operation's `BytecodeOpInterface` if it has one, an error
  if it is registered without one, and an attribute only if it is not
  registered (`:1293-1302`).
- So the encoding the writer chose is read right only when the reader's
  registry agrees with the writer's. And the dead branch, made live as
  written (`*wasRegistered`), would be wrong too: it reads the attribute
  from the operation's own encoding, where the writer put the properties
  index, not from the properties section, so every unregistered operation
  that round-trips today would break.

## How this compiler met it

The frontend's bytecode writer (`compiler/src/IdrisMLIR/MLIR/Bytecode.idr`)
used to flag every operation name unregistered and put each operation's
properties dictionary, as an attribute number, in the operation's own
encoding, counting on the else branch. The reader took that number for a
properties index, so no module the frontend wrote could be read (the
representation wave, bfdcac70; its proposal's §7, ruling B1, is at
484d6403). The writer's assumption, written in the pipeline cutover's
emitted-module contract (C22 §2 of the cutover's proposal, c7aa7b62 and
5d5f3312, text at 484d6403: "the reader then takes an op's properties as
one dictionary attribute and sets them with setPropertiesFromAttribute"),
was wrong twice: the branch is dead, and it is not the layout upstream's
writer produces for an unregistered operation.

The frontend now writes each operation honestly: its name flagged
registered, as it is where the file is read, and its inherent attributes
in its attribute dictionary with its discardable ones, with no
`kHasProperties`. `Operation::create` hands the dictionary to
`Operation::setAttrs`, which moves each inherent attribute into the
properties (`mlir/lib/IR/Operation.cpp:301-317`), as the generic text parser
accepts inherent attributes mixed into the dictionary
(`mlir/lib/AsmParser/Parser.cpp:1586-1608`), and as upstream's own writer
does for versions before 5 (`BytecodeWriter.cpp:1019-1031`). That carries
every property that is an attribute and the segment sizes, the inherent
attributes `getInherentAttr` knows
(`mlir/tools/mlir-tblgen/OpDefinitionsGen.cpp:1517-1579`); a property that
is not an attribute (an `I32Prop`, an `EnumProp`) would stay a discardable
attribute, its property at its default. So every property the frontend
writes is declared in ODS as an attribute, and the frontend's builders,
generated from that ODS (`foreign/idr/tools/idris-mlir-tblgen.cpp`), write
no other kind.

## The fix

`pull-request.diff` passes the writer's flag to
`PropertiesSectionReader::read`, which reads the entry as an attribute when
the operation was written unregistered, and otherwise as before. The dead
else branch goes, and `parseOpWithoutRegions` reads every operation's
properties from the properties section, where the writer puts them.
`Operation::create` sets an attribute read so through
`setPropertiesFromAttribute` (`Operation.cpp:38-45`), as it does for an
unregistered operation today.

Left as it is: an operation written registered and read where it is not
still has its native encoding read as an attribute
(`BytecodeReader.cpp:1301-1302`), which reads garbage. Nothing can decode a
native encoding without the dialect; an error there would be the honest
answer, and it is a separate change.

Test: `OpPropertiesTest.BytecodeWrittenUnregistered` in
`mlir/unittests/IR/OpPropertiesTest.cpp`, the reproducer above, which needs
two contexts and so no lit test can state.

## Why there is no patch

There is no `llvm.patch` and no `PINS.md` entry. Nothing in the tree writes
an operation unregistered and reads it registered any more: the frontend
writes no property through the properties section, and every other
bytecode file of the tree (the driver's, `make self`'s `.mlirbc`) is
written by upstream's writer in a context where every operation it holds is
registered. The bug was met only through the frontend's old encoding, which
relied on the dead branch.

## Testing

On arm64 macOS, 2026-10-15:

- `pull-request.diff` applies with `git apply --check`, with no offset, to
  the pin (`.toolchain/llvm-project`, 7208ba24) and to llvm main at
  b43c0361. Neither `BytecodeReader.cpp` nor `OpPropertiesTest.cpp`
  changed between the two.
- The patched `BytecodeReader.cpp` passes `-fsyntax-only` with the
  typecheck build's command for that unit (Apple clang, the unit's own
  flags, `-Werror=global-constructors` among them); the patched
  `OpPropertiesTest.cpp` passes with the same command, googletest's and
  googlemock's headers added and `-Wno-global-constructors`, as LLVM's
  unit tests are built.
- The open bytecode pull requests (#229910, #229735) touch other hunks of
  `BytecodeReader.cpp`; the diff applies after either.

Not run: no `mlir-opt` or `MLIRIRTests` is built on this machine, so the
reproducer has not been run, the test has not been seen to fail without the
change or pass with it, and `check-mlir` has not run. That the test fails
without the change is read from the code: the reader reaches
`PropertiesSectionReader::read`'s registered-without-interface error. The
lines are not checked with clang-format (none here); the C++ lines are
within 80 columns.

## Upstreaming plan

Status: ready to file, not filed. `submission.md` has the pull request
title and body and the checklist to run before posting. No issue or pull
request covers it: searched llvm/llvm-project for the reader's
`wasRegistered`, bytecode properties and unregistered operations,
2026-10-15.

- Where: one pull request to llvm/llvm-project (MLIR, bytecode). No issue:
  the pull request carries the reproducer as its test.
- Upstream test: `OpPropertiesTest.BytecodeWrittenUnregistered`.
- Before sending: `submission.md`'s checklist. The diff applies to
  then-current main and is clang-format clean; `check-mlir`, which runs
  `MLIRIRTests`, is the pull request's pre-merge CI's (upstream/README.md,
  **CI decides**).
- A check that the pinned tools still have the bug,
  `tests/upstream-bytecode-unregistered-properties`, is to run the
  two-tool reproducer above and expect `idris-mlir-opt` to fail; when the
  pin has the fix it reads the file, the check fails, and this directory
  and the check go.
- Nothing in this repository depends on it.
