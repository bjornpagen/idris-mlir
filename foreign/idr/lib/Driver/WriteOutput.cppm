// idr.driver:writeoutput: an output file, kept only once everything was
// written, and the directory it goes in.
export module idr.driver:writeoutput;

import idr.mlir;

import :report;

export namespace idr::driver {

// Makes the directory a file is to be written in, and those it is in, so
// that an output goes where it is named whether or not its directory
// exists yet, as Idris's own -o did. A path with no directory part is in
// the working directory, which exists.
bool makeDirectoryOf(llvm::StringRef path) {
  llvm::StringRef directory = llvm::sys::path::parent_path(path);
  if (directory.empty())
    return true;
  if (std::error_code error = llvm::sys::fs::create_directories(directory)) {
    cannotWrite(path, error);
    return false;
  }
  return true;
}

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
