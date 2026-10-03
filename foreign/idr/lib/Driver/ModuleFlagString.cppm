// idr.driver:moduleflagstring: the string of a module flag.
export module idr.driver:moduleflagstring;

import idr.mlir;

export namespace idr::driver {

// The string a module flag holds, or nothing.
llvm::StringRef moduleFlagString(const llvm::Module &module, llvm::StringRef flag) {
  auto *text = llvm::dyn_cast_or_null<llvm::MDString>(module.getModuleFlag(flag));
  return text ? text->getString() : llvm::StringRef();
}

} // namespace idr::driver
