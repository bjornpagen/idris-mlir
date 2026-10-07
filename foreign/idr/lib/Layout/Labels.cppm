// idr.layout:labels: a closure label, a function and how many of its
// parameters are captures.
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
  // A suspension: the cell is large enough for the value as well as the
  // captures, and the code pointer is replaced when the value is written.
  bool suspension = false;

  // A closure label's parameters: its captures, then its arguments.
  llvm::ArrayRef<mlir::Type> captureTypes() const { return type.getInputs().take_front(captures); }
  llvm::ArrayRef<mlir::Type> argumentTypes() const { return type.getInputs().drop_front(captures); }
};

} // namespace idr::layout
