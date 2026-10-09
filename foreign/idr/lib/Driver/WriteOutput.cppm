// idr.driver:writeoutput: an output file, kept only once everything was
// written.
export module idr.driver:writeoutput;

import idr.mlir;

import :report;

export namespace idr::driver {

// Writes `contents` to `path` only once everything succeeded, so a failure
// never leaves a partial output.
bool writeOutput(llvm::StringRef path, llvm::function_ref<bool(llvm::raw_ostream &)> write) {
  std::error_code error;
  auto file = std::make_unique<llvm::ToolOutputFile>(path, error, llvm::sys::fs::OF_None);
  if (error) {
    cannotWrite(path, error);
    return false;
  }
  if (!write(file->os()))
    return false;
  file->keep();
  return true;
}

} // namespace idr::driver
