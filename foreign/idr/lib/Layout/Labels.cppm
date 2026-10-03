// idr.layout:labels: a closure label, and the name of its closures' code,
// which idr-lower defines and idr-eval's child looks up.
export module idr.layout:labels;

import idr.mlir;

export namespace idr::layout {

// A closure label: a function with the number of leading
// parameters that are captures. Closures of one label share their code.
struct Label {
  mlir::FlatSymbolRefAttr callee;
  unsigned captures;
  // The callee's type before idr-lower converts it.
  mlir::FunctionType type;

  llvm::ArrayRef<mlir::Type> captureTypes() const;
  llvm::ArrayRef<mlir::Type> argumentTypes() const;
};

// The name of the code of the label numbered `id`.
std::string codeName(unsigned id);

} // namespace idr::layout
