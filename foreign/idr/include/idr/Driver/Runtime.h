// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime on the LLVM side: read from the file a compilation names,
// prepared once for every program (--prepare-runtime), and joined with
// each program's module, raised to the program's CPU.
#ifndef IDR_DRIVER_RUNTIME_H
#define IDR_DRIVER_RUNTIME_H

#include "idr/Driver/Options.h"

// The runtime's C ABI: the name of its baseline annotation.
#include "idris_rt.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/StringRef.h"

#include <memory>
#include <string>
#include <variant>

namespace llvm {
class DataLayout;
class LLVMContext;
class Module;
class Target;
class TargetMachine;
class Triple;
} // namespace llvm

namespace mlir {
class MLIRContext;
} // namespace mlir

namespace idr::driver {

// Where the prepared runtime keeps the bitcode that joins every program, as
// the target entry decides (CMakeLists.txt): in its object's .llvm.lto
// section, which every link leaves out (ELF), or in a file of its own
// beside the object, which no link names (Mach-O, which has no such
// section). Only --prepare-runtime reads it: a compilation reads where the
// bitcode is off the runtime it is given.
enum class BitcodeHome { InObject, BesideObject };
inline constexpr BitcodeHome runtimeBitcodeHome = BitcodeHome::IDRIS_MLIR_RUNTIME_BITCODE_HOME;

// Marks on the runtime's functions, as function attributes, which survive
// optimization and go with a function into every clone of it. One is the
// runtime's own annotation (IDRIS_RT_BASELINE): the CPU test at a
// program's entry stays compiled for the target's baseline whatever the
// program's CPU, since it runs before anything shows that the CPU has
// more. The other two record what every function of the runtime was
// compiled for, written when its archive's member is read, so that any
// compilation, or --prepare-runtime, raises it from there (retarget); a
// compilation removes them once the runtime has joined the program.
inline constexpr llvm::StringLiteral baselineMark = IDRIS_RT_BASELINE_MARK;
inline constexpr llvm::StringLiteral cpuMark = "idris-rt-cpu";
inline constexpr llvm::StringLiteral featuresMark = "idris-rt-features";

// The prepared runtime records, as module flags, the CPU its native half is
// compiled for; a compilation reads them to decide whether that half runs
// wherever the program does.
inline constexpr llvm::StringLiteral preparedCpuFlag = "idris-rt-prepared-cpu";
inline constexpr llvm::StringLiteral preparedFeaturesFlag = "idris-rt-prepared-features";

// What a prepared runtime's native half is compiled for, as its flags
// record it.
struct PreparedFor {
  std::string cpu, features;
};

// The runtime as one module, for the program's triple and data layout, of
// one of two kinds, read once off the file: the members of the runtime's
// archive joined, where a symbol two members define is an error, each
// function marked with what it was compiled for; or the bitcode of what
// --prepare-runtime wrote, with what its native half is compiled for. Its
// debug info describes the runtime's C++ sources, not the program: it is
// most of the archive's bitcode, and every program would carry it, so it
// goes.
struct Archived {
  std::unique_ptr<llvm::Module> module;
};
struct Prepared {
  std::unique_ptr<llvm::Module> module;
  PreparedFor target;
};

// The runtime at `path`. A file that is not an archive is the prepared
// runtime's object, or its bitcode: its bitcode is the file itself, in the
// object's bitcode section, or, exactly when the object has none, in the
// file beside it; one without both flags is neither kind, an error. Every
// failure is an error in `context`.
mlir::FailureOr<std::variant<Archived, Prepared>>
readRuntime(llvm::StringRef path, llvm::LLVMContext &llvmContext, const llvm::Triple &triple,
            const llvm::DataLayout &layout, mlir::MLIRContext &context);

// The file beside the prepared runtime's object that holds its bitcode when
// its container keeps no section for it: the object's name with .bc.
std::string besideObject(llvm::StringRef object);

// Runtime code was compiled for the target's baseline, plus the features a
// function asks for itself (a simdutf kernel's AVX2, say). It takes the
// program's CPU and keeps every feature it asked for, so it inlines into
// program code and no function loses an instruction it relies on; the
// baseline functions keep the baseline. Every definition of the runtime
// carries the marks of what it was compiled for, and is raised from them;
// the marks stay.
void retarget(llvm::Module &runtime, const llvm::TargetMachine &machine);

// The program and the runtime at `path` become one module, linked once with
// LinkOnlyNeeded: only what the program reaches joins it, raised to the
// program's CPU. From the prepared runtime, when its native half runs on
// the program's CPU, the bodies join as they are, available_externally: the
// optimizer inlines what pays and drops the rest, which the link line
// resolves in the native half, where every piece of runtime state has its
// one definition. Otherwise (a runtime prepared for a larger CPU) every
// body the program reaches becomes a definition of its own and compiles
// with the program, so that its object is the whole program and the link
// line's runtime goes unused, as the archive's bodies are from the start.
// A program that defines a symbol of the runtime is refused at `source`,
// the module it was translated from. Every failure is an error.
mlir::LogicalResult linkRuntime(llvm::Module &program, mlir::ModuleOp source,
                                llvm::StringRef path, const llvm::Target &target,
                                const llvm::Triple &triple, const llvm::TargetMachine &machine);

// --prepare-runtime: the archive's members, joined, raised to the target's
// CPU and optimized as a program is, with everything but the C ABI programs
// reach (idris_rt_*, less the functions no program calls) internal. Each
// function carries the marks of what it was compiled for, so that a
// compilation can raise it to any CPU from there; the optimization copies
// the marks into every function it makes from another (a clone, a thunk),
// and one without them could not be retargeted, so none may be left.
//
// The result is an object whose native code is what every executable's link
// line takes, and the same module as bitcode with every definition
// available_externally, which is what joins each program's module
// (linkRuntime), kept where the target entry's container says
// (runtimeBitcodeHome). The two halves come from the one module, so they
// name the same symbols: a body the program's optimizer inlines becomes
// program code, one it does not is dropped and resolves to the native
// half, and runtime state (the allocator's thread-locals, the output
// buffer, the live-cell count) is defined once, in the native half,
// whichever bodies were inlined. Its diagnostics are folded and printed as
// a compilation's; the exit status of their verdict.
int prepare(const Prepare &invocation);

} // namespace idr::driver

#endif // IDR_DRIVER_RUNTIME_H
