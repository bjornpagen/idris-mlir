## C23 Deduplication

Producer: U16, alone. `idr-deduplicate` after the cutover: Modular's
EliminateDuplicateFunctions ported under proposal 0001's protocol, on
`idr.func`, with our comparison. Paths are under `foreign/idr/`. Line
numbers are the tree at a3e61f3a.

### 1. The pass (C12's row; U06 writes the `def`)

`IdrDeduplicate`, argument `idr-deduplicate`, anchor `::mlir::ModuleOp`,
no option, statistics `numGroups "groups"` ("Classes of two or more
functions merged") and `numMerged "merged"` ("Duplicate functions
erased"), dependent dialect `::idr::IdrDialect`. Constructor: the
generated `std::unique_ptr<::mlir::Pass> idr::createIdrDeduplicate()`.
Position: row 1 of C12's pipeline (0004 stage 3), on the module the
frontend emitted (C22), before `idr-defunctionalize`. The facts its
description states are section 3's; the wording is U06's.

### 2. Files

- `include/idr/Transforms/Deduplicate.h` (`0BSD`, ours), exactly:

```cpp
#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/Pass.h"

#include "llvm/ADT/Hashing.h"

namespace idr {

#define GEN_PASS_DECL_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"

namespace deduplicate {

// The hash of what two copies of one function share: its facts and its body.
llvm::hash_code hashFunction(FuncOp fn);

// Whether `lhs` and `rhs` are one function twice over.
bool sameFunction(FuncOp lhs, FuncOp rhs);

} // namespace deduplicate
} // namespace idr
```

- `lib/Transforms/Deduplicate/Equivalence.cpp` (`0BSD`, ours): defines
  `hashFunction` and `sameFunction`, with today's `hashAttr`, `sameAttr`,
  `sameAttrs`, `BodyHash` and `BodyEqual`
  (`lib/Transforms/Deduplicate/Deduplicate.cpp:53-257`) in its anonymous
  namespace.
- `lib/Transforms/Deduplicate/EliminateDuplicateFunctions.cpp`
  (`Apache-2.0 WITH LLVM-exception`, ported): the SPDX line, Modular's
  header verbatim (`sources/code/modular/Mojo/lib/Transforms/EliminateDuplicateFunctions.cpp:1-12`),
  one changes line naming revision `9211931` and what changed, the site
  `PIN(eliminate-duplicate-functions)`; `GEN_PASS_DEF_IDRDEDUPLICATE` and
  the pass.
- `lib/Transforms/Deduplicate/Deduplicate.cpp`: deleted.
- `PINS.md` entry `eliminate-duplicate-functions` names the ported file's
  path, the source path and `9211931` (what `tests/spec/licenses` reads).
- Build list (the coordinator's, `lib/Transforms/CMakeLists.txt`,
  `IdrSmallPasses`): `Deduplicate/Deduplicate.cpp` replaced by
  `Deduplicate/EliminateDuplicateFunctions.cpp` and
  `Deduplicate/Equivalence.cpp`.

`hashFunction` and `sameFunction` are this lane's own seam between its two
units; no other lane calls them.

### 3. What the pass guarantees

**Candidates.** A function is a candidate when all hold:
- it is private;
- it is not a member of a strongly connected component of two or more
  functions of the reference graph (a function that refers only to itself
  is a candidate);
- every use of its symbol is renamable: inside its own body, or the
  callee of an `idr.call`, an `idr.closure` or an `idr.suspend`, or held by
  an `idr.constant` (a `#idr.closure` constant). A use by any other op,
  by an attribute of an `idr.func` itself, or by an op outside every
  function makes the function no candidate.

The reference graph has a node for every `idr.func` and an edge from `f` to
`g` for each `SymbolRefAttr` whose root names `g`, held by an op in `f`'s
body or by `f`'s own attributes, found as `SymbolTable` finds uses (the
attribute dictionary and the inherent attributes, pre-order, never inside
a reference's nested part).

**Equivalence** (`sameFunction`), an equivalence relation:
- the facts are equal: every attribute of the `idr.func` but `sym_name` and
  `instance` (the function type, the argument and result attributes,
  `total`, `effects`, and whatever else C01 declares), each compared with
  the self rule below. `instance` is provenance: no pass reads it, and two
  copies of one function from different definitions are one function;
- the bodies match op for op: names, operand and result counts, operands
  by the correspondence of values met so far, result and block argument
  types, attributes and properties, successors by the correspondence of
  blocks, regions recursively; locations are not compared;
- the self rule: a reference to the function itself in one matches a
  reference to the function itself in the other; any other reference must
  name the same symbol in both.

**Order and classes.** Heights over the condensed graph (a component that
refers to no other has height 0, any other one more than the highest it
refers to). Heights are processed in increasing order. Within one height:
first every function of that height has each renamable reference to a
function merged at a lower height rewritten to that function's kept name,
and every candidate is hashed (`hashFunction`), in parallel; then the
candidates form classes in module order, each joining the class of the
first earlier candidate it is `sameFunction` with. Two functions that are
one function twice over have one height, so a class is complete before
any function of a greater height reads it.

**The kept function** of a class of two or more is its member with the
lexicographically smallest symbol. It keeps its own attributes (its
`instance` among them) and body, and its location becomes
`mlir::FusedLoc::get(ctx, {each member's location, members in symbol
order})` (C24 reads it: every member's name finds the kept function).
Every other member is erased, serially, in module order, through the
module's `SymbolTable` analysis, which stays preserved.

**Invariants**, each a test of U17's:
- every use that named an erased function names the kept function of its
  class, and no other use changes;
- transitivity in one run: two callers that differ only in which member of
  one class they call merge in the same run;
- idempotence: a second run on the output changes nothing;
- determinism: the output does not depend on `--num-threads` or on the
  order of a parallel join;
- the pass never fails and never refuses: a module it cannot improve is
  left as it is.

### 4. Preconditions it relies on (from C01 and C22)

- Every reference to a function is a `SymbolRefAttr` that
  `SymbolTable::getSymbolUses` would list; a name held as a `StringAttr`
  (as `instance` holds one) is no use.
- At stage 3 no type body names a function: the sums whose constructors
  are labels are made by defunctionalization (C06), after this pass. A
  constructor naming a label is a use by an op that is not renamable.
- `idr.call`, `idr.closure`, `idr.suspend` and `idr.constant` keep their
  names; a new op that names a function by symbol is not renamable until
  this list says so.

### 5. Consumers

- U06: the `def` in `Passes.td` (C12 row), `idr::createIdrDeduplicate()`
  in row 1 of `buildPipeline`, `Pipeline.h`'s include of `Deduplicate.h`.
- U17: `tests/idr/dedup` (merge, merge-named, transitive merge, the self
  reference, idempotence, the fused location) and `idr-expect`'s lookup by
  location (C24).
- U18: nothing reads the statistics' values; a program's output never
  depends on which member is kept.
- The coordinator: the build list of section 2.
