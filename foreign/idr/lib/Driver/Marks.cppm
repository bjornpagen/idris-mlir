// idr.driver:marks: what the compiler records on the runtime's functions and
// on the prepared runtime's module.
export module idr.driver:marks;

import idr.mlir;

export namespace idr::driver {

// Marks on the runtime's functions, as function attributes, which survive
// optimization and go with a function into every clone of it. Two are the
// runtime's own annotations. "idris-rt-baseline" (the CPU test at a
// program's entry) keeps a function compiled for the target's baseline
// whatever the program's CPU, since it runs before anything shows that the
// CPU has more. "idris-rt-compiler" (the compile-time evaluation API) names
// a function only the compiler's evaluation child calls, natively, and no
// program: the prepared runtime has no entry for it, and what it alone sets
// (the arena) is constant there. The other two record what a function was
// compiled for, before --prepare-runtime optimizes it for the default CPU,
// so that a compilation for any CPU raises it from there (retarget).
inline constexpr llvm::StringLiteral baselineMark = "idris-rt-baseline";
inline constexpr llvm::StringLiteral compilerMark = "idris-rt-compiler";
inline constexpr llvm::StringLiteral cpuMark = "idris-rt-cpu";
inline constexpr llvm::StringLiteral featuresMark = "idris-rt-features";

// The prepared runtime records, as module flags, the CPU its native half is
// compiled for; a compilation reads them to decide whether that half runs
// wherever the program does.
inline constexpr llvm::StringLiteral preparedCpuFlag = "idris-rt-prepared-cpu";
inline constexpr llvm::StringLiteral preparedFeaturesFlag = "idris-rt-prepared-features";

} // namespace idr::driver
