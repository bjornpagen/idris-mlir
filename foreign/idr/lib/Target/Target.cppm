// idr.target: the module's target, decided once (idr-target), and the LLVM
// side of the pipeline that idris-mlir-cc and idr-eval's JIT share: one
// semantics for Double at compile time and at runtime.
export module idr.target;

export import :optimize;
export import :targetoptions;
export import :vectors;
