// idr.driver:externalize: the optimized runtime's symbols, made nameable
// from a program.
export module idr.driver:externalize;

import idr.mlir;

import :report;

export namespace idr::driver {

// The optimized runtime's symbols, so that a program's object can name each
// one: a body it did not inline, a global an inlined body reads. Every
// local one becomes external with hidden visibility; the names are unique,
// since readRuntime's linker named the members' local symbols apart.
bool externalize(llvm::Module &runtime) {
  for (llvm::GlobalValue &value : runtime.global_values()) {
    if (value.isDeclaration())
      continue;
    if (!llvm::isa<llvm::GlobalObject>(value) || !value.hasName()) {
      Report() << "internal error: the optimization left the runtime "
               << (value.hasName() ? "alias " : "an unnamed global ") << value.getName()
               << ", which the native half cannot name";
      return false;
    }
    if (value.hasLocalLinkage()) {
      value.setLinkage(llvm::GlobalValue::ExternalLinkage);
      value.setVisibility(llvm::GlobalValue::HiddenVisibility);
    }
    value.setDSOLocal(true);
  }
  return true;
}

} // namespace idr::driver
