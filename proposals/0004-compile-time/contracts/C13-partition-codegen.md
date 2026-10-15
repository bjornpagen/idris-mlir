## C13 Partition and parallel code generation

Producer: U07. Decisions: 0004 §5.3, §5.4 (S2, the step this cutover
builds), D20, D21, D26, D32, D33, D41; 0003 §7.1, D20, D29. Every line
number below was read at `main` on 2026-10-14. `L/` and `M/` are the pinned
LLVM and MLIR under `.toolchain/build/llvm-project/`.

### 1. Files

| Path | Holds | State |
| --- | --- | --- |
| `foreign/idr/include/idr/Target/Target.h` | every declaration of §2 | changed |
| `foreign/idr/lib/Target/Target.cpp` | idr-target (§3) | changed |
| `foreign/idr/lib/Target/Optimize.cpp` | `machine`, `optimize` | unchanged |
| `foreign/idr/lib/Target/Schedules.cpp` | the schedule library, its loading, the transform op of §4 | new |
| `foreign/idr/include/idr/Target/ScheduleOps.td` | the ODS of §4's op | new |
| `foreign/idr/lib/Target/Partition.cpp` | `Partition` (§5) | new |
| `foreign/idr/include/idr/Driver/Artifacts.h`, `lib/Driver/Artifacts.cpp` | the files of a compilation, `emit`, `writeObjects` (§6) | changed |

`lib/Target/Vectors.cpp` and `lib/Target/TargetOptions.cpp` are U07's and
stay absent: the vector width is idr-target's own step (§3) and the
machine stays in `Optimize.cpp`.

### 2. Declarations

`include/idr/Target/Target.h`, whole (Pipeline.h includes it for the pass
declaration, `include/idr/Transforms/Pipeline.h:12`, so it includes no
LLVM IR or thread header):

```cpp
namespace llvm { class Module; class Target; class Triple; }
namespace mlir { class DialectRegistry; }

namespace idr {
#define GEN_PASS_DECL_IDRTARGET
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::target {

// Unchanged (Target.h:35-40 today).
std::unique_ptr<llvm::TargetMachine> machine(const llvm::Target &target, const llvm::Triple &triple,
                                             llvm::StringRef cpu, llvm::StringRef features);
void optimize(llvm::Module &module, llvm::TargetMachine &machine);

// The DLTI names idr-target writes and the schedule reads.
inline constexpr llvm::StringLiteral cpuDevice = "CPU";
inline constexpr llvm::StringLiteral vectorWidthKey = "max_vector_op_width";

// The schedule library: the entry point the vectorization group's
// transform-interpreter runs, and the call that puts the library and its op
// on a registry.
inline constexpr llvm::StringLiteral vectorizeSchedule = "idr.vectorization";
void registerScheduleLibrary(mlir::DialectRegistry &registry);

// The bin target, in LLVM instructions of the optimized module (D26).
inline constexpr std::uint64_t binInstructions = std::uint64_t{1} << 15;

struct Bin {
  std::string name;               // 16 hex digits, C21's contentHash
  std::uint64_t instructions = 0; // Function::getInstructionCount, summed
};

class Partition {
public:
  // The bins of the optimized program, a function of its content alone,
  // and in `optimized` itself the linkage every bin reads: each symbol
  // another bin names becomes external, hidden, dso_local and is named
  // under the reserved prefix. An internal error is the Error.
  static llvm::Expected<Partition> of(llvm::Module &optimized);
  // In bin-name order; the first holds the module's inline assembly.
  llvm::ArrayRef<Bin> bins() const { return binList; }
  // Keeps in `lazy`, read lazily from the bitcode of `optimized` as `of`
  // left it, what bin `bin` defines, holds a copy of or declares, and
  // drops the rest; materializes its bodies.
  llvm::Error extract(unsigned bin, llvm::Module &lazy) const;

private:
  struct Symbol {
    int bin = -1;        // the bin that defines it; -1: none (a declaration, a copy)
    bool copied = false; // a constant every bin that names it holds privately
    llvm::SmallVector<unsigned, 4> refs; // the symbols its body or initializer names
  };
  std::vector<Symbol> symbols;                      // by position, §5.1
  std::vector<Bin> binList;
  std::vector<llvm::SmallVector<unsigned, 0>> members; // per bin, its symbols
};

} // namespace idr::target
```

`include/idr/Driver/Artifacts.h`: as today (`Artifacts.h:22-73`) with
`objectPath` replaced, one member function added, and one function added
(the names U06 codes against):

```cpp
class Artifacts {
public:
  // ... the constructor, distinctFromInput, makeDirectories, arm, keep as today.

  // A bin's object, <base>.<bin>.o, named from the base like every other
  // file of the compilation, appended to `objects` and, once armed, removed
  // unless the compilation succeeds. Its path.
  const std::string &addObject(llvm::StringRef bin);

  // With -c the archive of the bins, at the path -o names; empty without.
  const std::string base, corePath, modulePath, archivePath, executablePath;
  // Without -c, the bins' objects in bin-name order, filled by
  // writeObjects; what the link passes. Empty with -c.
  std::vector<std::string> objects;
  ...
};

// Unchanged (Artifacts.h:75-77): one module, one object. Prepare.cpp's
// runtime is one object and stays on it (Prepare.cpp:148).
bool emit(llvm::Module &module, llvm::TargetMachine &machine, llvm::StringRef path);

// Stages 14 and 15: Partition::of, the module written once as bitcode,
// each bin read lazily in an LLVMContext of its own and compiled by
// machine(target, triple, cpu, features) on a task of `pool`, largest bin
// first; then without -c each bin's object at artifacts.addObject(name),
// in bin-name order, and with -c the objects as one archive at
// artifacts.archivePath, in bin-name order, LLVM's deterministic mode, the
// archive kind of the triple. Reports what fails (Report.h); false then.
bool writeObjects(llvm::Module &optimized, const llvm::Target &target, const llvm::Triple &triple,
                  llvm::StringRef cpu, llvm::StringRef features, llvm::ThreadPoolInterface &pool,
                  Artifacts &artifacts);
```

Idris source's module, the handoff, is `<base>.mlirbc`, MLIR bytecode
(C22, 0004 D36); a module input is itself the module. Without `-c` the
link passes `objects` (0004 §5.3 item 6: "the objects
themselves"); with `-c` the output is the archive (D32), which a link
takes whole: every definition is reached from `main` after O3
(`Run.cpp:187-192`), and the module holds no constructor or appending
global (`ReadRuntime.cpp:143-164`; the lowering writes none). Archive
members are named `<bin name>.o`. A bin object an earlier success wrote
under a bin name this compilation does not make is not this compilation's
file and is left as it is; every object this compilation writes is armed
the moment it is named.

### 3. idr-target

The pass keeps its declaration (Passes.td, U06; C12 row of `IdrTarget`)
and today's steps (`Target.cpp:40-72`: the triple and CPU of the entry,
LLVM's features, the data layout combined into `dlti.dl_spec`). It adds
one: the width of the machine's fixed vector registers, LLVM's answer for
the entry's CPU, `TargetTransformInfo::getRegisterBitWidth(RGK_FixedWidthVector)`
(`L/include/llvm/Analysis/TargetTransformInfo.h:1436`) asked of the
machine for a function declaration of a scratch module (no attributes, so
the machine's own CPU and features answer), written on the module as

```mlir
dlti.target_system_spec = #dlti.target_system_spec<
  "CPU" = #dlti.target_device_spec<"max_vector_op_width" = 256 : i64>>
```

replacing any spec there. 256 on `x86-64-v3` and 128 on `apple-m1`, today's
values of the deleted `vectorBits` (`Target.cpp:78-87`), now LLVM's and no
per-target case. `L1_cache_size_in_bytes` is 0003's stage 3 and is not
written. Passes.td's description of `IdrTarget` names this attribute (U06).

The fact is read with `mlir::DataLayout::closest(op).getDevicePropertyValue`
(`M/lib/Interfaces/DataLayoutInterfaces.cpp:760-778`), which finds the
module's target system spec through `ModuleOp::getTargetSystemSpec`
(`M/lib/IR/BuiltinDialect.cpp:149-158`). `transform.dlti.query` cannot read
it on our modules: it stops at the first queryable attribute of the
closest op, and `dlti.dl_spec` sorts before `dlti.target_system_spec`
(`M/lib/Dialect/DLTI/DLTI.cpp:523-534`; the failure is upstream's own
expectation, `M/test/Dialect/DLTI/query.mlir:358`).

### 4. The vectorization schedule

**The op.** `foreign/idr/include/idr/Target/ScheduleOps.td`:

```tablegen
include "mlir/Dialect/Transform/IR/TransformDialect.td"
include "mlir/Dialect/Transform/Interfaces/TransformInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def VectorizeLanesOp : Op<Transform_Dialect, "idr.vectorize_lanes", [
    DeclareOpInterfaceMethods<TransformOpInterface>,
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    ReportTrackingListenerFailuresOpTrait]> {
  let cppNamespace = "::idr::target";
  let summary = "Computes each loop over an array on the target's vector lanes";
  let arguments = (ins TransformHandleTypeInterface:$target);
  let results = (outs TransformHandleTypeInterface:$vectorized);
  let assemblyFormat = "$target attr-dict `:` functional-type(operands, results)";
}
```

tablegen'd (`-gen-op-decls`, `-gen-op-defs`, target
`IdrScheduleOpsIncGen`) into the build's include tree as
`idr/Target/ScheduleOps.h.inc` and `idr/Target/ScheduleOps.cpp.inc`, which
is a system include directory (`foreign/idr/CMakeLists.txt:19-26`), so the
generated code meets the system rule for warnings like every other ODS;
included by `Schedules.cpp` alone. The `.td` sits under `include/` as every
ODS does (`tests/spec/zones/run`); its tablegen lines are the coordinator's,
in `include/idr/Target/CMakeLists.txt`. Effects:
consumes `target`, produces `vectorized`, modifies the payload.

Semantics, for each payload op of `target` (non-`linalg.generic` ops are
passed by), the logic of today's `Vectorize.cpp:60-165` with one change of
tile shape:
- A generic without pure buffer semantics or without a parallel loop is
  passed by.
- `W` is the module's `max_vector_op_width` for `"CPU"` (§3); a module
  without it is a definite failure, `internal error: the module states no
  max_vector_op_width for its CPU`.
- `lanes = max(1, W / widest)`, `widest` the widest word of the generic's
  operands' elements and body results, at least 8 (`Vectorize.cpp:60-77`).
- The lane dimension is the generic's last parallel dimension. Tile sizes
  are `lanes` there and 1 on every other dimension. (Today every parallel
  dimension gets `lanes`, `Vectorize.cpp:103-106`, and the full tiles are
  vectorized assuming every dynamic size matches, `:141-146`, which is
  exact only at rank 1, the only rank today's arrays have; at rank 2 its
  inner tiles would read past a row. With one dimension of `lanes` the
  full tiles are full in every dimension. At rank 1, and for a generic
  with one parallel dimension, the shape is today's.)
- Decided before anything changes: `linalg::vectorizeOpPrecondition(op,
  check, scalable = false)` (`M/include/mlir/Dialect/Linalg/Transforms/Transforms.h:507-511`),
  `check[d]` the tile size where the loop range is dynamic and the static
  range where it is static. A refused generic stays a generic, remark
  `Scalar` (category `idr-lanes`), and convert-linalg-to-loops later runs
  its body in program order (`Vectorize.cpp:16-21`).
- Tiled with `scf::tileUsingSCF`; the loop of the lane dimension (its
  position among the loops is the dimension's, every size being nonzero)
  is peeled with `scf::peelForLoopAndSimplifyBounds`; each tile in the
  peeled loop is vectorized at the tile sizes assuming dynamic sizes
  match, each tile in the remainder masked (`linalg::vectorize`, as
  `Vectorize.cpp:142-146`). A tile that does not vectorize is a definite
  failure, `internal error: a tile of a loop the vectorizer takes did not
  vectorize`. Remark `Vectorized` (category `idr-lanes`) with the lanes.
- `vectorized` holds the function (`FunctionOpInterface`) of each generic
  vectorized, each function once, in the order first met.

**The library**, `Schedules.cpp`, two string constants around the entry
point's name, which is spliced from `vectorizeSchedule` so the name is held
once, parsed once per context:

```mlir
module attributes {transform.with_named_sequence} {
  transform.named_sequence @idr.vectorization(%root: !transform.any_op {transform.readonly}) {
    %loops = transform.structured.match ops{["linalg.generic"]} in %root
        : (!transform.any_op) -> !transform.any_op
    %vectorized = transform.idr.vectorize_lanes %loops
        : (!transform.any_op) -> !transform.any_op
    transform.apply_patterns to %vectorized {
      transform.apply_patterns.vector.drop_unit_dims_with_shape_cast
      transform.apply_patterns.vector.transfer_permutation_patterns
      transform.apply_patterns.vector.lower_masked_transfers
    } : !transform.any_op
    transform.yield
  }
}
```

The three pattern ops are today's clean set (`Vectorize.cpp:177-186`,
upstream's populate functions at `M/lib/Dialect/Vector/TransformOps/VectorTransformOps.cpp:81-121`)
without the vector canonicalizations: the one canonicalization
configuration is `idr::createCanonicalizerPass()`, which follows in the
same group (C12 row 20).

**Why one op of ours.** The transform dialect has no arithmetic on params
(`M/include/mlir/Dialect/Transform/IR/TransformOps.td`, every op `:26-1393`),
so `W / widest` is not expressible, and `transform.structured.vectorize`
takes one param per dimension (`LinalgTransformOps.cpp:146-162`), so no
script can name the sizes of a generic of any rank; and
`transform.dlti.query` cannot read the width on our modules (§3). The op is
one of 0003 §20's gaps filled by ours, ratified by the owner on 2026-10-14
against the letter of 0003 D29: it goes when upstream can express the
schedule, arithmetic on params and sizes for a loop of any rank, and the
library then names upstream's ops alone.

**Registration.** `registerScheduleLibrary(registry)` adds two extensions, in
this order: a `mlir::transform::TransformDialectExtension` that registers
`VectorizeLanesOp` (dependent dialect `linalg`; generated `affine`,
`arith`, `memref`, `scf`, `vector`), and a
`mlir::DialectExtension<…, mlir::transform::TransformDialect>` whose
`apply` parses the library with `mlir::parseSourceString<ModuleOp>` and
calls `TransformDialect::loadIntoLibraryModule`
(`M/include/mlir/Dialect/Transform/IR/TransformDialect.td:93-95`); a library
that fails to load is an error diagnostic, `internal error: the schedule
library does not load`. A tool calls it after `mlir::registerAllExtensions`
on the same registry, so upstream's transform ops are registered when the
library is parsed. `transform-interpreter` finds the entry point in the
library when its anchor holds none (`M/lib/Dialect/Transform/Transforms/InterpreterPass.cpp:129-153`).

**The loops it leaves** (U09's input): a vectorized generic becomes the
tile loops of its dimensions, outer to inner, every one but the lane
dimension's of step 1; the lane dimension's `scf.for` steps by `lanes`
from the lower bound to the largest multiple below the upper bound and
holds unmasked vector transfers and vector arithmetic; its remainder, an
`scf.for` after it in the same block, runs at most once and holds the
masked tile (after `lower_masked_transfers`, masked transfers). A refused
generic is left as it was.

### 5. The partition (`Partition::of`)

1. **Positions.** A symbol is addressed by its list and its place in it:
   every `Function` in module order, then every `GlobalVariable`, every
   `GlobalAlias`, every `GlobalIFunc`. The bitcode writer writes each list
   in order and the reader appends in record order
   (`L/lib/Bitcode/Writer/BitcodeWriter.cpp:1683-1798`), so the lazily read
   module has the same positions; `extract` checks the count and treats a
   difference as an internal error.
2. **Refusal of the impossible.** An appending global (`llvm.used`,
   constructors) is an internal error: it belongs to every object, and the
   runtime's reader and the lowering write none.
3. **Kinds.** A *copied* symbol is a `GlobalVariable` definition that is
   constant, of local linkage, at least `local_unnamed_addr` (for a local
   symbol the module is the whole program, so its address is significant
   nowhere), in no comdat, and named by no alias. A *node* is every other
   definition: a function with a body, a variable with an initializer, an
   ifunc. An alias is no node and goes where its aliasee's base object goes.
   Declarations, and available_externally definitions (none survive O3,
   `L/lib/Passes/PassBuilderPipelines.cpp:1389-1390`; one that did would be
   resolved by the runtime's native half), have no bin.
4. **References.** A symbol's refs are the global values its body (every
   instruction operand and every function operand: personality, prefix,
   prologue) or initializer or aliasee or resolver names, through any
   constant expression or aggregate.
5. **Graph and joins.** Edges go from a node to each node it refs, where a
   ref to a copied symbol stands for that symbol's refs (transitively) and
   a ref to an alias for its base object. Components are `idr::components`
   (`include/idr/Support/Scc.h:23-24`). Then joined: a node and the direct
   callee of each of its `musttail` calls when the callee is a node (D33;
   a `musttail` across bins is then not expressible); every node of one
   comdat; an ifunc and its resolver. A joined set is a *part*.
6. **Each part:** size = the sum of `Function::getInstructionCount()` of
   its functions; key = its nodes' names, sorted bytewise, joined by `\n`;
   hash = C21's `contentHash(key)` read back as a 64-bit number;
   namespace group = the part of its smallest name before the first `.`,
   or the empty group for a name with no `.` (one group holds every
   dotless name: the runtime's, 0004 §5.3 item 2).
7. **Cut (D41).** Groups in bytewise order; within one, parts by (hash,
   smallest name, first position). A bin is open; before a part is added,
   the open bin closes when it is not empty and the part would take it
   past `2 * binInstructions`; after the part is added, the bin closes when
   it holds at least `binInstructions / 4` and `hash / 2^49 < size`
   (`2^49 = 2^64 / binInstructions`, so this is D41's fraction exactly);
   the group's last bin closes at its end. A part larger than `2 *
   binInstructions` is a bin of its own.
8. **Names.** A bin's name is C21's `contentHash` of its nodes' names,
   sorted, joined by `\n`. Bins are kept in name order; two bins with one
   name are an internal error (D18). Bin 0 holds the module inline
   assembly (SplitModule's rule, `L/lib/Transforms/Utils/SplitModule.cpp:293-294`).
9. **Linkage (D41).** A node or alias of local linkage that a symbol of
   another bin refs (directly or through copies that bin holds) becomes
   `ExternalLinkage`, `HiddenVisibility`, dso_local, and is named
   `__idr.` followed by its name with LLVM's `\01` escape dropped
   (`GlobalValue::dropLLVMManglingEscape`); a name already under `__idr.`
   (U10's static data) keeps it. A name taken by another symbol, or an
   unnamed symbol that must be named, is an internal error. Symbols read
   only inside their bin stay internal; copied constants stay private in
   every bin that holds them. Tail calls stay inside a bin by item 5.

`extract(bin, lazy)`: own = the bin's members; kept = copied symbols an
own or kept symbol refs; declared = every other symbol they ref; the rest
dropped. Every function not own loses its body (`Function::deleteBody`);
every variable not own or kept loses its initializer and comdat and
becomes external; an alias or ifunc that is declared becomes a function or
variable declaration of its value type with its name, visibility and
dso_local, and one dropped is erased; `Module::materializeAll`; every
dropped function and variable is erased (one with a use left is an
internal error); a bin other than 0 has no module inline assembly.

### 6. Code generation (`writeObjects`)

Zones (`IDR_ZONE_IN`, Profile.h): `partition`, `write bitcode`, one zone
per bin named by the bin's name (the task constructs
`idr::profile::ThreadTrace` first, C12 §5), `archive`. The bitcode is
`llvm::WriteBitcodeToFile` into memory on the calling thread, the one
serial step (D21). Tasks run on `llvm::ThreadPoolTaskGroup(pool)`, one per
bin, submitted largest first (ties in name order), each writing only its
own slot of a vector sized before the first task; the calling thread
reports failures in bin-name order after `wait()`. Each task: an
`llvm::LLVMContext`, `llvm::getLazyBitcodeModule`
(`L/include/llvm/Bitcode/BitcodeReader.h:203-206`; reading one immutable
buffer from several contexts at once is the LTO backends' pattern,
`L/lib/LTO/LTOBackend.cpp:517-570`), `Partition::extract`, a machine from
`idr::target::machine(target, triple, cpu, features)`, the object
emitted into memory. Without `-c` the calling thread then writes each
object whole (`llvm::ToolOutputFile`, kept once written) at
`artifacts.addObject(bin.name)`, in bin-name order; the zone is
`objects`. With `-c`, the archive: `llvm::writeArchive(path, members,
SymtabWritingMode::NormalSymtab, object::Archive::getDefaultKindForTriple(triple),
/*Deterministic=*/true, /*Thin=*/false)` (`L/include/llvm/Object/ArchiveWriter.h:63-68`,
`L/lib/Object/Archive.cpp:1098-1108`), which writes a temporary and renames
it, so the archive is written whole or not at all. The bin count and every
byte depend on the module alone, never on the pool's size.

### 7. Consumers

- U06 (written against these names): `Run.cpp`'s stage 13 ends with
  `writeObjects(*llvmModule, target, triple, cpu, features, pool,
  artifacts)` under a zone and a timing scope `codegen`, `pool` the
  context's (`Run.cpp:232-239`); `Compile.cpp`'s link passes
  `artifacts.objects`, then the runtime, `-o`, the link flags; with `-c` no
  link. `Prepare.cpp:148` keeps `emit`. idris-mlir (on its `everything`
  registry, after `registerAllExtensions`), idris-mlir-opt and
  idris-mlir-reduce call `registerScheduleLibrary`. `Pipeline.cpp` row 20
  builds `mlir::transform::createInterpreterPass` with `entryPoint =
  idr::target::vectorizeSchedule.str()`. Passes.td's `IdrTarget`
  description names `dlti.target_system_spec` and `max_vector_op_width`.
- U09: §4's loop form; idr-narrow-lanes runs on it.
- U10: static data named under `__idr.` keep their names when promoted.
- U17: a fixture that runs the schedule runs `--idr-target` first or
  writes §3's attribute; `vectorized` is read after row 20's group; the
  remarks are `Vectorized` and `Scalar` in category `idr-lanes`.
- U18: a build without `-c` leaves `<base>.core`, the handoff
  `<base>.mlirbc` (C22), one
  `<base>.<bin>.o` per bin (16 hex digits) and the executable; with `-c`
  the archive at `-o`; `object_imports` and `determinism` read every
  object, or every member of the archive (the undefined symbols are the
  union of the members' less the union of their definitions, 0004 §5.3
  item 6); each corpus program's bin count is its
  number of objects; the test that records which kind of
  inline assembly the runtime brings, on both targets (0004 §5.3 item 5);
  D33's program over two bins whose tail-call cycles would overflow the
  stack without their tail calls; D41's edit fixture (one definition
  edited, every other bin's members unchanged); determinism at 1, 2 and 8
  threads over the objects, the archive and the executable.
- Coordinator: `include/idr/Target/CMakeLists.txt` tablegens `ScheduleOps.td`
  (§4); `lib/Target/CMakeLists.txt` adds `Schedules.cpp`, `Partition.cpp`,
  `IdrScheduleOpsIncGen` and `IdrOpsIncGen` in `DEPENDS`, and links `IdrIR` (C21's `contentHash`), `IdrSupport`
  (`Scc.h`), `MLIRParser`, `MLIRTransformDialect`,
  `MLIRTransformDialectInterfaces`, `MLIRLinalgDialect`,
  `MLIRLinalgTransforms`, `MLIRSCFDialect`, `MLIRSCFTransforms`,
  `MLIRVectorDialect`, `MLIRTilingInterface`, `MLIRDataLayoutInterfaces`,
  `LLVMAnalysis`, `LLVMBitReader`, `LLVMBitWriter`; `lib/CMakeLists.txt`'s
  `IdrDriver` links `LLVMObject`, `LLVMBitWriter` and `LLVMBitReader`.

### 8. Outside this contract

§5.4's second step (the split before O3, the runtime's bitcode per unit,
MLIR translation per unit, facts as attributes on cross-unit declarations)
is after the cutover. The tile-and-fuse schedule and the entry's L1 size
are 0003's stage 3.
