// A closure label's parameters: its captures, then its arguments.
module idr.layout;

import idr.mlir;

llvm::ArrayRef<mlir::Type> idr::layout::Label::captureTypes() const {
  return type.getInputs().take_front(captures);
}

llvm::ArrayRef<mlir::Type> idr::layout::Label::argumentTypes() const {
  return type.getInputs().drop_front(captures);
}
