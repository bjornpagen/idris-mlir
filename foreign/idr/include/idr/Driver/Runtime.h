// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime on the LLVM side: its archive read and prepared once for
// every program (--prepare-runtime), and what that wrote joined with each
// program's module, every function of it for the program's CPU.
#ifndef IDR_DRIVER_RUNTIME_H
#define IDR_DRIVER_RUNTIME_H

#include "idr/Driver/BuiltRuntime.h"
#include "idr/Driver/Options.h"

// The runtime's C ABI: the names of its annotations and of the constant
// the driver defines.
#include "idris_rt.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/StringRef.h"

#include <memory>
#include <string>

namespace llvm {
class LLVMContext;
class Module;
class TargetMachine;
} // namespace llvm

namespace mlir {
class MLIRContext;
} // namespace mlir

namespace idr::driver {

// The runtime's own annotation of a function (IDRIS_RT_BASELINE), as the
// function attribute it becomes when the archive is read: the CPU test at a
// program's entry, and what it calls, stays compiled for the target's
// baseline whatever the program's CPU, since it runs before anything shows
// that the CPU has more.
inline constexpr llvm::StringLiteral baselineMark = IDRIS_RT_BASELINE_MARK;

// The runtime's mark of its fault handler (IDRIS_RT_HANDLER), as the
// function attribute it becomes: the kernel calls it on the signal stack,
// whose size the stack bound gives from the handler's deepest path.
inline constexpr llvm::StringLiteral handlerMark = IDRIS_RT_HANDLER_MARK;

// The constant the runtime reads what only the driver knows of the program
// from (idris_rt_built): the driver defines it, in an object of its own.
inline constexpr llvm::StringLiteral builtSymbol = IDRIS_RT_PROGRAM_BUILT_NAME;

// What a runtime is: the SHA-256 digest of the archive its code was read
// from, and the CPU its functions take, LLVM's name and features. A
// compilation joins a runtime prepared from an archive the build made
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

// The runtime archive at `path` as one module, for `machine`, the
// program's, which --prepare-runtime reads: the members joined, where a
// symbol two members define is an error. Every function of it is compiled
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
// archive's bitcode, and every program would carry it, so it goes. Every
// failure is an error in `context`.
struct Archived {
  std::unique_ptr<llvm::Module> module;
  // The archive's digest, and the program's CPU, which it was read for.
  Identity identity;
};
mlir::FailureOr<Archived> readArchive(llvm::StringRef path, llvm::LLVMContext &llvmContext,
                                      const llvm::TargetMachine &machine,
                                      mlir::MLIRContext &context);

// The runtime --prepare-runtime wrote, whose object is at `path`, which a
// compilation reads: its bitcode, which is the file beside the object on
// every target and which no link names, and the identity the flags of that
// bitcode record. A file with no bitcode beside it, or bitcode without the
// flags, is no runtime --prepare-runtime wrote, an archive among them: an
// error in `context`, as every failure is.
struct Prepared {
  std::unique_ptr<llvm::Module> module;
  Identity identity;
};
mlir::FailureOr<Prepared> readPrepared(llvm::StringRef path, llvm::LLVMContext &llvmContext,
                                       mlir::MLIRContext &context);

// The file beside the prepared runtime's object that holds its bitcode: the
// object's name with .bc.
std::string besideObject(llvm::StringRef object);

// The program and the prepared runtime at `path` become one module, linked
// once with LinkOnlyNeeded: only what the program reaches joins it. The
// runtime is one idris-mlir is built with (Identity), or the compilation
// fails, naming what differs. Its bodies join as they are,
// available_externally: the optimizer inlines what pays and drops the
// rest, which the link line resolves in the native half, where every piece
// of runtime state has its one definition; a program function past the
// inlining budget calls them (idr::target::inlineCallerInstructions), all
// but the bodies the runtime marks always inline.
// No program symbol can be a runtime symbol: every one the lowering names
// carries the program's prefix, which no C identifier has. Every failure is
// an error.
mlir::LogicalResult linkRuntime(llvm::Module &program, mlir::ModuleOp source,
                                llvm::StringRef path);

// --prepare-runtime: the archive's members, joined, read for the program's
// CPU and optimized as a program is, with everything but the C ABI programs
// reach (idris_rt_*, less the functions no program calls) internal, and
// recorded with its identity: the archive's digest and the program's CPU.
//
// The result is an object whose native code is what every executable's link
// line takes, and the same module as bitcode with every definition
// available_externally, which is what joins each program's module
// (linkRuntime), in the file beside the object. The two halves come from
// the one module, so they name the same symbols: a body the program's
// optimizer inlines becomes program code, one it does not is dropped and
// resolves to the native half, and runtime state (the allocator's
// thread-locals, the output buffer) is defined once, in the native half,
// whichever bodies were inlined. The bitcode also records what code
// generation gave the native half's frames (StackBound.h), since a program
// whose call reaches one of its bodies stacks that body's frames too. Its
// diagnostics are folded and printed as a compilation's; the exit status of
// their verdict.
int prepare(const Prepare &invocation);

} // namespace idr::driver

#endif // IDR_DRIVER_RUNTIME_H
