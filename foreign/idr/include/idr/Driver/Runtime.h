// The runtime on the LLVM side: read from what --runtime names, prepared
// once for every program (--prepare-runtime), and joined with each
// program's module, raised to the program's CPU.
#ifndef IDR_DRIVER_RUNTIME_H
#define IDR_DRIVER_RUNTIME_H

#include "llvm/ADT/StringRef.h"

#include <memory>
#include <string>

namespace llvm {
class DataLayout;
class LLVMContext;
class Module;
class Target;
class TargetMachine;
class Triple;
} // namespace llvm

namespace idr::driver {

// Marks on the runtime's functions, as function attributes, which survive
// optimization and go with a function into every clone of it. One is the
// runtime's own annotation: "idris-rt-baseline" (the CPU test at a
// program's entry) keeps a function compiled for the target's baseline
// whatever the program's CPU, since it runs before anything shows that the
// CPU has more. The other two record what a function was compiled for,
// before --prepare-runtime optimizes it for the target's CPU, so that a
// compilation raises it from there (retarget).
inline constexpr llvm::StringLiteral baselineMark = "idris-rt-baseline";
inline constexpr llvm::StringLiteral cpuMark = "idris-rt-cpu";
inline constexpr llvm::StringLiteral featuresMark = "idris-rt-features";

// The prepared runtime records, as module flags, the CPU its native half is
// compiled for; a compilation reads them to decide whether that half runs
// wherever the program does.
inline constexpr llvm::StringLiteral preparedCpuFlag = "idris-rt-prepared-cpu";
inline constexpr llvm::StringLiteral preparedFeaturesFlag = "idris-rt-prepared-features";

// The runtime as one module, for the program's triple and data layout: the
// bitcode of what --prepare-runtime wrote, or the members of the archive
// joined, where a symbol two members define is an error. Its debug info
// describes the runtime's C++ sources, not the program: it is most of the
// archive's bitcode, and every program would carry it, so it goes.
std::unique_ptr<llvm::Module> readRuntime(llvm::LLVMContext &context, const llvm::Triple &triple,
                                          const llvm::DataLayout &layout);

// The file beside the prepared runtime's object that holds its bitcode when
// its container keeps no section for it: the object's name with .bc.
std::string besideObject(llvm::StringRef object);

// Whether a runtime module is what --prepare-runtime wrote.
bool isPrepared(const llvm::Module &module);

// Runtime code was compiled for the target's baseline, plus the features a
// function asks for itself (a simdutf kernel's AVX2, say). It takes the
// program's CPU and keeps every feature it asked for, so it inlines into
// program code and no function loses an instruction it relies on; the
// baseline functions keep the baseline. A prepared function remembers what
// it asked for in its marks, which the archive's functions still carry as
// their attributes; the marks are read off here.
void retarget(llvm::Module &module, const llvm::TargetMachine &machine);

// The program and the runtime become one module, linked once with
// LinkOnlyNeeded: only what the program reaches joins it. From the prepared
// runtime, when its native half runs on the program's CPU, the bodies join
// as they are, available_externally: the optimizer inlines what pays and
// drops the rest, which the link line resolves in the native half, where
// every piece of runtime state has its one definition. Otherwise (the
// archive, or a runtime prepared for a larger CPU) every body the program
// reaches becomes a definition of its own and compiles with the program, so
// that its object is the whole program and the link line's runtime goes
// unused.
bool linkRuntime(llvm::Module &program, const llvm::Target &target, const llvm::Triple &triple,
                 const llvm::TargetMachine &machine);

// --prepare-runtime: the archive's members, joined, raised to the target's
// CPU and optimized as a program is, with everything but the C ABI programs
// reach (idris_rt_*, less the functions no program calls) internal. Each
// function first records what it was compiled for, so that retarget can
// raise it to any CPU from there; the optimization copies the marks into
// every function it makes from another (a clone, a thunk), and one without
// them could not be retargeted, so none may be left.
//
// The result is an object whose native code is what every executable's link
// line takes, and the same module as bitcode with every definition
// available_externally, which is what joins each program's module
// (linkRuntime), kept where the target entry's container says: in a section
// of the object that every link leaves out, as a fat LTO object keeps its
// bitcode, or in a file beside it. The two halves come from the one module,
// so they name the same symbols: a body the program's optimizer inlines
// becomes program code, one it does not is dropped and resolves to the
// native half, and runtime state (the allocator's thread-locals, the output
// buffer, the live-cell count) is defined once, in the native half,
// whichever bodies were inlined. An exit status.
int prepare();

} // namespace idr::driver

#endif // IDR_DRIVER_RUNTIME_H
