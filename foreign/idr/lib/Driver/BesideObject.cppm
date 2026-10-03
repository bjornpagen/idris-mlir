// idr.driver:besideobject: where the prepared runtime's bitcode is when no
// section holds it.
export module idr.driver:besideobject;

import idr.mlir;

export namespace idr::driver {

// The file beside the prepared runtime's object that holds its bitcode when
// its container keeps no section for it: the object's name with .bc.
std::string besideObject(llvm::StringRef object) {
  llvm::SmallString<128> path(object);
  llvm::sys::path::replace_extension(path, "bc");
  return path.str().str();
}

} // namespace idr::driver
