// idr.driver:frontend: idris-mlir-front, the Idris side, which idris-mlir
// runs on Idris source: Idris builds the program, and the frontend writes
// its Core and its idr module where the artifacts say.
export module idr.driver:frontend;

import idr.mlir;

import :artifacts;
import :options;
import :report;

export namespace idr::driver {

// idris-mlir-front beside this executable, by its real path: the build
// links the frontend there, and a copy of idris-mlir alone runs no other
// frontend, nor one found on PATH.
std::string frontendBeside(const char *argv0) {
  std::string self =
      llvm::sys::fs::getMainExecutable(argv0, reinterpret_cast<void *>(&frontendBeside));
  llvm::SmallString<256> path(llvm::sys::path::parent_path(self));
  llvm::sys::path::append(path, "idris-mlir-front");
  return path.str().str();
}

// Idris source to the Core and the module the artifacts name. The frontend
// reads no environment, so its prefix and package directories are its
// arguments. It prints Idris's errors and its own rejections as Idris
// prints them, and exits with this tool's statuses: 3 is the program's and
// passes through; anything else but 0, or a frontend that did not run or
// did not finish, is the compiler's.
int frontend(llvm::StringRef frontendPath, llvm::StringRef source, const Artifacts &artifacts) {
  std::vector<std::string> args{frontendPath.str(), "--prefix", idrisPrefix.getValue()};
  for (const std::string &directory : packagePath)
    args.insert(args.end(), {"--package-path", directory});
  for (const std::string &package : packages)
    args.insert(args.end(), {"-p", package});
  if (!breakShape.empty())
    args.insert(args.end(), {"--break-shape", breakShape.getValue()});
  if (noPrelude)
    args.emplace_back("--no-prelude");
  args.insert(args.end(),
              {"--core", artifacts.corePath, "-o", artifacts.modulePath, source.str()});
  std::vector<llvm::StringRef> argv(args.begin(), args.end());
  std::string error;
  bool notRun = false;
  int status = llvm::sys::ExecuteAndWait(frontendPath, argv, std::nullopt, {}, 0, 0, &error,
                                         &notRun);
  if (notRun) {
    Report() << "cannot run " << frontendPath << ": " << error;
    return failure;
  }
  if (status == ok || status == rejected)
    return status;
  if (status < 0)
    Report() << "internal error: " << frontendPath << " did not finish: " << error;
  else
    Report() << "internal error: " << frontendPath << " exited with status " << status;
  return failure;
}

} // namespace idr::driver
