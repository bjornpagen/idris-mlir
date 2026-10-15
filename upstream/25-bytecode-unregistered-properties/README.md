# [mlir][bytecode] The reader decodes an op's properties by its own registry, not by the writer's

On llvm main at 7208ba24 (the pin), and on GitHub's main on 2026-10-15, the
bytecode reader chooses how to decode an operation's properties by whether
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

With the tools at the pin, `written-unregistered.mlir`:

```mlir
"idr.crash"() <{message = "boom"}> : () -> ()
```

`mlir-opt -allow-unregistered-dialect -emit-bytecode written-unregistered.mlir
-o x.mlirbc` writes it (the toolchain's `mlir-opt` has no `idr` dialect);
`idris-mlir-opt x.mlirbc` then fails in `CrashOp::readProperties`, with
`expected ...StringAttr, but got: {message = "boom"}`: the native decoder
read the number of the properties dictionary as the number of `message`.

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
properties index, so no module the frontend wrote could be read (0005 §7,
B1). The writer's assumption (0004's C22 §2, "the reader then takes an op's
properties as one dictionary attribute and sets them with
setPropertiesFromAttribute") was wrong twice: the branch is dead, and it is
not the layout upstream's writer produces for an unregistered operation.

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

## Testing at the pin

On arm64 macOS, at 7208ba24:

- `pull-request.diff` applies (`git apply --check` in
  `.toolchain/llvm-project`).
- The patched `BytecodeReader.cpp` and `OpPropertiesTest.cpp` pass
  `-fsyntax-only` with the typecheck build's compiler and flags (Apple
  clang, `-std=c++2c`) against the pinned headers, the test with
  googletest's and googlemock's.

Not run: no `mlir-opt` or `MLIRIRTests` is built on this machine, so the
reproducer has not been run, the test has not been seen to fail without the
change or pass with it, and `check-mlir` has not run. The lines are not
checked with clang-format (none here).

## Upstreaming plan

Status: not filed, not ready. No issue or pull request covers it: searched
for the reader's `wasRegistered` and for unregistered operations' properties
in bytecode, 2026-10-15.

- Where: one pull request to llvm/llvm-project (MLIR, bytecode). No issue:
  the pull request carries the reproducer as its test.
- Upstream test: `OpPropertiesTest.BytecodeWrittenUnregistered`.
- Before sending: build `MLIRIRTests` with the change and see the test
  pass, and fail with the `BytecodeReader.cpp` change reverted; the diff
  must apply to then-current main and be clang-format clean;
  `check-mlir` is the pull request's pre-merge CI's (upstream/README.md,
  **CI decides**). Write `submission.md` then.
- A check that the pinned tools still have the bug,
  `tests/upstream/bytecode-unregistered-properties`, is to run the
  two-tool reproducer above and expect `idris-mlir-opt` to fail; when the
  pin has the fix it reads the file, the check fails, and this directory
  and the check go.
- Nothing in this repository depends on it.
