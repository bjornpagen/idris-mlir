// idr.driver:writeoutput: the output file, kept only once everything was
// written.
export module idr.driver:writeoutput;

import idr.mlir;

import :options;

export namespace idr::driver {

// Writes `contents` to the output path only once everything succeeded, so a
// failure never leaves a partial or stale output.
bool writeOutput(llvm::function_ref<bool(llvm::raw_ostream &)> write) {
  std::error_code error;
  auto file = std::make_unique<llvm::ToolOutputFile>(outputPath, error, llvm::sys::fs::OF_None);
  if (error) {
    llvm::errs() << "idris-mlir-cc: cannot write " << outputPath << ": " << error.message() << "\n";
    return false;
  }
  if (!write(file->os()))
    return false;
  file->keep();
  return true;
}

} // namespace idr::driver
