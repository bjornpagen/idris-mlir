// idr.driver:dump: --dump-dir, the module after each step, into a file of
// that directory.
export module idr.driver:dump;

import idr.mlir;

import :options;
import :report;

export namespace idr::driver {

// Writes the module after the step `name`, the `index`th, if --dump-dir
// names a directory; false if the file cannot be written.
bool dump(mlir::ModuleOp module, unsigned index, llvm::StringRef name) {
  if (dumpDir.empty())
    return true;
  llvm::SmallString<128> path(dumpDir);
  llvm::sys::path::append(path, llvm::formatv("{0:02}-{1}.mlir", index, name).str());
  std::error_code error;
  llvm::raw_fd_ostream out(path, error);
  if (error) {
    cannotWrite(path, error);
    return false;
  }
  module->print(out, mlir::OpPrintingFlags().enableDebugInfo());
  return true;
}

} // namespace idr::driver
