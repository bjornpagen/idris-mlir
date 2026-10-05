// idr.driver:namesapart: whether the program and the runtime define their
// symbols apart.
export module idr.driver:namesapart;

import idr.mlir;

namespace idr::driver {

// The name the linker sees for a symbol, as LLVM's Mangler writes it from the
// module's data layout: the object format's prefix before an IR name, and
// nothing before one that is already the assembly name. Two IR names can be
// one symbol: Darwin's headers give C functions their assembly names, so the
// runtime refers to write as "\01_write", which the linker reads as the
// program's "write".
std::string linkerName(const llvm::GlobalValue &value) {
  llvm::SmallString<64> name;
  llvm::Mangler().getNameWithPrefix(name, &value, /*CannotUsePrivateLabel=*/false);
  return std::string(name);
}

} // namespace idr::driver

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
  llvm::StringMap<const llvm::GlobalValue *> runtimeNames;
  for (const llvm::GlobalValue &value : runtime.global_values())
    if (!value.hasLocalLinkage())
      runtimeNames.try_emplace(linkerName(value), &value);
  for (const llvm::GlobalValue &value : program.global_values()) {
    if (value.isDeclaration() || value.hasLocalLinkage())
      continue;
    auto named = runtimeNames.find(linkerName(value));
    if (named == runtimeNames.end())
      continue;
    llvm::errs() << "idris-mlir-cc: the program defines " << value.getName() << ", which the runtime "
                 << (named->second->isDeclaration() ? "refers to" : "defines")
                 << " too: the runtime's references would bind to the program's definition\n";
    return false;
  }
  return true;
}

} // namespace idr::driver
