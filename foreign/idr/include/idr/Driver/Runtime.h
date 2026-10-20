// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime on the LLVM side: read from the file a compilation names,
// prepared once for every program (--prepare-runtime), and joined with
// each program's module, every function of it for the program's CPU.
#ifndef IDR_DRIVER_RUNTIME_H
#define IDR_DRIVER_RUNTIME_H

#include "idr/Driver/BuiltRuntime.h"
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
class LLVMContext;
class Module;
class TargetMachine;
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

// The runtime's own annotation of a function (IDRIS_RT_BASELINE), as the
// function attribute it becomes when the archive is read: the CPU test at a
// program's entry, and what it calls, stays compiled for the target's
// baseline whatever the program's CPU, since it runs before anything shows
// that the CPU has more.
inline constexpr llvm::StringLiteral baselineMark = IDRIS_RT_BASELINE_MARK;

// What a runtime is: the SHA-256 digest of the archive its code was read
// from, and the CPU its functions take, LLVM's name and features. A
// compilation joins a runtime read from an archive the build made
// (builtArchives) for the program's CPU, and no other (linkRuntime).
//
// So a fold computes what the program would: the folders run the
// archive's native code and the program its bitcode, which one compile of
// each member made from one source with one set of flags (the runtime's
// profile: its page size, address width and no floating-point
// contraction), and both link the one GMP archive. What is left to differ
// is the CPU each is compiled for (the baseline's, the program's) and
// LLVM's second optimization of the program, and neither changes a value:
// the runtime's integers and strings are exact on any CPU, and its
// floating point is IEEE operations, never fused, on both. The fuzzer
// states it, a fold against a run of the same expression
// (harness/Fuzz.idr). The checked runtime differs from the runtime only
// where a program counts a cell that died, which it ends.
struct Identity {
  std::string archive, cpu, features;
};

// The prepared runtime records its identity as module flags, which a
// compilation reads.
inline constexpr llvm::StringLiteral preparedArchiveFlag = "idris-rt-prepared-archive";
inline constexpr llvm::StringLiteral preparedCpuFlag = "idris-rt-prepared-cpu";
inline constexpr llvm::StringLiteral preparedFeaturesFlag = "idris-rt-prepared-features";

// The runtime as one module, for the program's machine, of one of two
// kinds, read once off the file: the members of the runtime's archive
// joined, where a symbol two members define is an error; or the bitcode of
// what --prepare-runtime wrote. Either way every function of it is compiled
// for the program's CPU, as the program's own functions are, and for
// nothing else: it carries no CPU or features of its own, so it inlines
// into any program function; but for two kinds, each data the archive
// holds. A baseline function (baselineMark) keeps the baseline it was
// compiled for. A function compiled for features beyond its unit's (a
// target region, such as a simdutf kernel's AVX2) keeps exactly those, on
// top of the program's: its features less the baseline's, which every
// function of the archive was compiled with (a function without them is an
// error). The archive's other functions must inline into a program
// function, as the inliner judges it, or reading it fails. Its debug info
// describes the runtime's C++ sources, not the program: it is most of the
// archive's bitcode, and every program would carry it, so it goes.
struct Archived {
  std::unique_ptr<llvm::Module> module;
  // The archive's digest, and the program's CPU, which it was read for.
  Identity identity;
};
struct Prepared {
  std::unique_ptr<llvm::Module> module;
  Identity identity;
};

// The runtime at `path`, for `machine`, the program's. A file that is not an
// archive is the prepared runtime's object, or its bitcode: its bitcode is
// the file itself, in the object's bitcode section, or, exactly when the
// object has none, in the file beside it; one without its identity's flags
// is neither kind, an error. Every failure is an error in `context`.
mlir::FailureOr<std::variant<Archived, Prepared>> readRuntime(llvm::StringRef path,
                                                              llvm::LLVMContext &llvmContext,
                                                              const llvm::TargetMachine &machine,
                                                              mlir::MLIRContext &context);

// The file beside the prepared runtime's object that holds its bitcode when
// its container keeps no section for it: the object's name with .bc.
std::string besideObject(llvm::StringRef object);

// The program and the runtime at `path` become one module, linked once with
// LinkOnlyNeeded: only what the program reaches joins it. The runtime is
// one idris-mlir is built with (Identity), or the compilation fails,
// naming what differs. From the prepared runtime the bodies join as
// they are, available_externally: the optimizer inlines what pays and drops
// the rest, which the link line resolves in the native half, where every
// piece of runtime state has its one definition; the archive's bodies are
// definitions, which compile with the program; a program function past
// the inlining budget calls them (idr::target::inlineCallerInstructions).
// A program that defines a symbol of the runtime is refused at `source`,
// the module it was translated from. Every failure is an error.
mlir::LogicalResult linkRuntime(llvm::Module &program, mlir::ModuleOp source,
                                llvm::StringRef path, const llvm::TargetMachine &machine);

// --prepare-runtime: the archive's members, joined, read for the program's
// CPU and optimized as a program is, with everything but the C ABI programs
// reach (idris_rt_*, less the functions no program calls) internal, and
// recorded with its identity: the archive's digest and the program's CPU.
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
