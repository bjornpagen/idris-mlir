// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The module's target and what is done for it: idr-target, which decides
// the target once and writes it on the module with the facts the schedules
// read; the machine and LLVM's pipeline for it; the schedule library; and
// the partition of the optimized program into the bins whose code is
// generated at once.
#ifndef IDR_TARGET_TARGET_H
#define IDR_TARGET_TARGET_H

// The target entry's description, generated from CMakeLists.txt.
#include "idr/TargetEntry.h"

#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Error.h"
#include "llvm/Target/TargetMachine.h"

#include <cstdint>
#include <memory>
#include <string>
#include <variant>
#include <vector>

namespace llvm {
class GlobalValue;
class Module;
class Target;
class Triple;
} // namespace llvm

namespace mlir {
class DialectRegistry;
} // namespace mlir

namespace idr {
#define GEN_PASS_DECL_IDRTARGET
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::target {

// A CPU of the target as the code generator reads it: LLVM's name for it
// and its features, the list a function's "target-features" holds.
struct Cpu {
  llvm::StringLiteral name;
  llvm::StringLiteral features;
};

// The target, as its entry describes it once (CMakeLists.txt), each CPU as
// the pinned C compiler derives it from the entry's flags: the triple; the
// CPU programs are compiled for, whose features hold the baseline's; and
// the baseline, which every machine of the target has and the runtime's
// code is compiled for. A program's code, and every function of the
// runtime but the baseline's, is compiled for the program's CPU and nothing
// else (idr/Driver/Runtime.h).
inline constexpr llvm::StringLiteral triple = IDRIS_MLIR_TARGET_TRIPLE;
inline constexpr Cpu programCpu{IDRIS_MLIR_PROGRAM_CPU_NAME, IDRIS_MLIR_PROGRAM_CPU_FEATURES};
inline constexpr Cpu baselineCpu{IDRIS_MLIR_BASELINE_CPU_NAME, IDRIS_MLIR_BASELINE_CPU_FEATURES};

// The program's target as the module's #llvm.target, which idr-target
// writes and every later step reads.
mlir::LLVM::TargetAttr programTarget(mlir::MLIRContext *context);

// The machine a program, or the runtime prepared for every program, is
// compiled for: the target's triple and the program's CPU, IEEE arithmetic
// with no fused operations, every function and datum in a section of its
// own, position-independent, optimized as far as LLVM goes. The error says
// that LLVM has no machine for them.
llvm::Expected<std::unique_ptr<llvm::TargetMachine>> machine(const llvm::Target &target);

// LLVM's O3 pipeline for the machine, with MergeFunctions: identical
// functions (clones that specialization left equal) become one.
void optimize(llvm::Module &module, llvm::TargetMachine &machine);

// What idr-target writes in the module's dlti.target_system_spec and the
// schedules read: the device, and the width in bits of its fixed vector
// registers, which LLVM answers for the target entry's CPU.
inline constexpr llvm::StringLiteral cpuDevice = "CPU";
inline constexpr llvm::StringLiteral vectorWidthKey = "max_vector_op_width";

// The schedule library: the entry point that computes the loops over
// arrays on the target's lanes, which the vectorization group's
// transform-interpreter runs on each function, and the call that puts the
// library and the transform op it uses on a registry. It is called after
// upstream's transform ops it is written in are put on the registry
// (registerIdrDialects, idr/InitIdr.h), so that they are registered when
// the transform dialect loads and the library is parsed.
inline constexpr llvm::StringLiteral vectorizeSchedule = "idr.vectorization";
void registerScheduleLibrary(mlir::DialectRegistry &registry);

// The library's cleanup of the unit dimensions vectorizing left, within its
// rounds, on the ops its handle holds. The schedule includes it with a
// spent budget suppressed; run alone, as a test does with
// `--transform-interpreter=entry-point=idr.vectorization.cleanup`, a spent
// budget is an error, so a cycle among its patterns fails the test.
inline constexpr llvm::StringLiteral cleanupSchedule = "idr.vectorization.cleanup";

// The size a bin of the optimized program aims at, in LLVM instructions. A
// bin's fixed cost (its context, machine and bitcode read) is per bin and
// its code generation linear in its instructions, so bins are as large as
// balance allows. The cut closes a bin at a quarter of this at the
// earliest and at twice it at the latest.
inline constexpr std::uint64_t binInstructions = std::uint64_t{1} << 15;

// The size, in LLVM instructions as the program's module is translated,
// past which a program function calls the runtime instead of inlining it:
// an optimization's budget, which leaves such a function's calls of the
// runtime as calls and changes nothing it computes. Code generation is
// superlinear in a function's size (LLVM's live ranges), and a function
// this large holds thousands of counting calls, whose inlined branches
// made one program's code generation 2.8 s become 95. The bodies the
// runtime marks always inline are outside the budget: a call of one costs
// more than its body, and the frame-bound account's entries, empty in the
// shipped runtime, must inline away from every shipped function however
// large, which a call marked noinline would stop.
inline constexpr std::uint64_t inlineCallerInstructions = std::uint64_t{1} << 12;

// One bin: the name of its object, the hash of its members' names, and
// the instructions it holds.
struct Bin {
  std::string name;
  std::uint64_t instructions = 0;
};

// The bins of an optimized program. Each definition lives in exactly one
// bin; the bins and their names are a function of the module's content, so
// the objects are the same whatever the number of threads, and an edit
// moves only the cuts beside it.
class Partition {
public:
  // The bins of `optimized`, and, in `optimized` itself, the linkage every
  // bin then reads: a symbol another bin names becomes external, hidden and
  // dso_local, under the name idr::reservedName("bin", its name), which no
  // C name and no mangled name is, so no static link meets it. The Error is
  // the compiler's.
  static llvm::Expected<Partition> of(llvm::Module &optimized);

  // In name order; the first holds the module's inline assembly.
  llvm::ArrayRef<Bin> bins() const { return binList; }

  // Keeps in `lazy`, read lazily from the bitcode of the module `of` left,
  // what bin `bin` defines, the constants it holds a copy of and the
  // declarations of everything else they name; drops the rest and
  // materializes the bodies it keeps. The Error is the compiler's.
  llvm::Error extract(unsigned bin, llvm::Module &lazy) const;

private:
  // Every global value of `module`, by list: functions, variables, aliases,
  // ifuncs, each in module order. A symbol is its place here. The bitcode
  // writer writes each list in order and the reader appends in record
  // order, so the module `extract` reads back has the places `of` numbered.
  static std::vector<llvm::GlobalValue *> positions(llvm::Module &module);

  // Components of the reference graph that stay together: their nodes,
  // the names of their symbols, the instructions they hold, and the place
  // of their first node.
  struct Part {
    llvm::SmallVector<unsigned> nodes;
    std::vector<llvm::StringRef> names;
    std::uint64_t size = 0;
    unsigned position = 0;
  };

  // A bin, and the parts it holds, by their index.
  struct Cut {
    Bin bin;
    llvm::SmallVector<unsigned> parts;
  };

  // The bins `parts` are cut into, in name order: grouped by the top-level
  // namespace their names keep and cut by their hash, so a cut depends only
  // on its neighbours (Bins.cpp). The Error is the compiler's.
  static llvm::Expected<std::vector<Cut>> cut(llvm::ArrayRef<Part> parts);

  // Where a global value lives: declared only (a declaration, or an alias
  // of nothing a bin defines), copied into each bin that names it (a
  // constant whose address nothing tells apart), or defined by one bin.
  struct Declared {};
  struct Copied {};
  struct Defined {
    unsigned bin;
  };
  using Home = std::variant<Declared, Copied, Defined>;

  // A global value of the module, by its place in the module's lists.
  struct Symbol {
    Home home;
    // The symbols its body, initializer, aliasee or resolver names.
    llvm::SmallVector<unsigned, 4> refs;
  };

  std::vector<Symbol> symbols;
  std::vector<Bin> binList;
  // Each bin's own symbols: its definitions and the aliases of them.
  std::vector<llvm::SmallVector<unsigned, 0>> members;
};

} // namespace idr::target

#endif // IDR_TARGET_TARGET_H
