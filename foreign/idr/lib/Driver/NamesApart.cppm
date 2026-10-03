// idr.driver:namesapart: whether the program and the runtime define their
// symbols apart.
export module idr.driver:namesapart;

import idr.mlir;

export namespace idr::driver {

// The program names a symbol of the runtime only to refer to it. The
// linker binds every reference the runtime makes to a name, wherever its
// code lands, to the definition of that name the joined module has: one the
// program also defined would take the runtime's place in the runtime's own
// code, and no renaming would show it. A local symbol of either side is
// told apart by the linker, and the frontend's names are namespaced, so no
// Idris program defines one of the runtime's; a module that does is
// refused before anything is linked.
bool namesApart(const llvm::Module &program, const llvm::Module &runtime) {
  for (const llvm::GlobalValue &value : program.global_values()) {
    if (value.isDeclaration() || value.hasLocalLinkage())
      continue;
    const llvm::GlobalValue *named = runtime.getNamedValue(value.getName());
    if (!named || named->hasLocalLinkage())
      continue;
    llvm::errs() << "idris-mlir-cc: the program defines " << value.getName() << ", which the runtime "
                 << (named->isDeclaration() ? "refers to" : "defines")
                 << " too: the runtime's references would bind to the program's definition\n";
    return false;
  }
  return true;
}

} // namespace idr::driver
