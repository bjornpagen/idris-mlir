// idr.driver:dump: --dump-after, the module after a step, into a file of
// --dump-dir.
export module idr.driver:dump;

import idr.mlir;

import :options;

export namespace idr::driver {

// Writes the module after the step `name`, the `index`th, if --dump-after
// asks for it; false if the file cannot be written.
bool dump(mlir::ModuleOp module, unsigned index, llvm::StringRef name) {
  if (dumpAfter.empty() || (dumpAfter != "all" && dumpAfter != name))
    return true;
  llvm::SmallString<128> path(dumpDir);
  llvm::sys::path::append(path, llvm::formatv("{0:02}-{1}.mlir", index, name).str());
  std::error_code error;
  llvm::raw_fd_ostream out(path, error);
  if (error) {
    llvm::errs() << "idris-mlir-cc: cannot write " << path << ": " << error.message() << "\n";
    return false;
  }
  module->print(out, mlir::OpPrintingFlags().enableDebugInfo());
  return true;
}

} // namespace idr::driver
