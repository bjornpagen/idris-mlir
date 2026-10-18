// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The module's target and what is done for it: idr-target, which decides
// the target once and writes it on the module with the facts the schedules
// read; the machine and LLVM's pipeline for it; the schedule library; and
// the partition of the optimized program into the bins whose code is
// generated at once.
#ifndef IDR_TARGET_TARGET_H
#define IDR_TARGET_TARGET_H

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

// The machine a program, or the runtime prepared for every program, is
// compiled for: IEEE arithmetic with no fused operations, every function
// and datum in a section of its own, position-independent, optimized as
// far as LLVM goes. The triple, CPU and features are the module's target.
// The error says that LLVM has no machine for them.
llvm::Expected<std::unique_ptr<llvm::TargetMachine>>
machine(const llvm::Target &target, const llvm::Triple &triple, llvm::StringRef cpu,
        llvm::StringRef features);

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
