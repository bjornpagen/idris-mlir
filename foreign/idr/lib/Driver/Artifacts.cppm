// idr.driver:artifacts: what a compilation reads and writes. The input's
// kind is its extension, and every file the compilation writes is named
// from one base, so that what it leaves is known before anything runs.
export module idr.driver:artifacts;

import idr.mlir;

export namespace idr::driver {

// A module is MLIR's, text or bytecode, and goes straight to the pipeline.
// Anything else is Idris source: the frontend decides, by Idris's own
// extensions, whether it reads it, so only MLIR's are named here.
enum class Input { Idris, Module };

Input inputKind(llvm::StringRef path) {
  llvm::StringRef extension = llvm::sys::path::extension(path);
  return extension == ".mlir" || extension == ".mlirbc" ? Input::Module : Input::Idris;
}

// What a compilation writes, each named from one base by appending its
// extension: without -c the base is -o, which is the executable, and the
// object is <base>.o; with -c -o is the object, and the base is -o without
// its extension. Idris source also leaves <base>.core and <base>.mlir, the
// module the pipeline reads; a module input is itself that module, and
// nothing writes a .core. Once armed, every file written is removed unless
// the whole compilation succeeds (keep), a stale one from an earlier
// success too, so that nothing outlives a failure.
class Artifacts {
public:
  Artifacts(llvm::StringRef input, Input kind, llvm::StringRef output, bool objectOnly)
      : base(baseOf(output, objectOnly)), corePath(base + ".core"),
        modulePath(kind == Input::Idris ? base + ".mlir" : input.str()),
        objectPath(objectOnly ? output.str() : base + ".o"),
        executablePath(objectOnly ? "" : output.str()) {
    if (kind == Input::Idris) {
      paths.push_back(corePath);
      paths.push_back(modulePath);
    }
    paths.push_back(objectPath);
    if (!objectOnly)
      paths.push_back(executablePath);
  }

  // The files this compilation writes are distinct, and none of them is its
  // input, which would otherwise be overwritten, or removed as a stale
  // output when the compilation fails.
  bool distinctFromInput(llvm::StringRef input) const {
    llvm::StringSet<> seen;
    for (const std::string &path : paths)
      if (!seen.insert(path).second || path == input || llvm::sys::fs::equivalent(path, input))
        return false;
    return true;
  }

  // From here on, a file the compilation writes is removed when it fails.
  // Only once the paths are known to be distinct from the input: the input
  // is never removed.
  void arm() {
    for (const std::string &path : paths)
      removers.push_back(std::make_unique<llvm::FileRemover>(path));
  }

  // The compilation succeeded: what it wrote stays.
  void keep() {
    for (const std::unique_ptr<llvm::FileRemover> &remover : removers)
      remover->releaseFile();
  }

  const std::string base, corePath, modulePath, objectPath, executablePath;

private:
  static std::string baseOf(llvm::StringRef output, bool objectOnly) {
    llvm::SmallString<256> path(output);
    if (objectOnly)
      llvm::sys::path::replace_extension(path, "");
    return path.str().str();
  }

  std::vector<std::string> paths;
  std::vector<std::unique_ptr<llvm::FileRemover>> removers;
};

} // namespace idr::driver
