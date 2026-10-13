// What a compilation reads and writes. The input's kind is its extension,
// and every file the compilation writes is named from one base, so that
// what it leaves is known before anything runs. Each output is written
// whole or not at all.
#ifndef IDR_DRIVER_ARTIFACTS_H
#define IDR_DRIVER_ARTIFACTS_H

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/FileUtilities.h"

#include <memory>
#include <string>
#include <vector>

namespace llvm {
class Module;
class TargetMachine;
} // namespace llvm

namespace idr::driver {

// A module is MLIR's, text or bytecode, and goes straight to the pipeline.
// Anything else is Idris source: the frontend decides, by Idris's own
// extensions, whether it reads it, so only MLIR's are named here.
enum class Input { Idris, Module };

Input inputKind(llvm::StringRef path);

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
  Artifacts(llvm::StringRef input, Input kind, llvm::StringRef output, bool objectOnly);

  // The files this compilation writes are distinct, and none of them is its
  // input, which would otherwise be overwritten, or removed as a stale
  // output when the compilation fails.
  bool distinctFromInput(llvm::StringRef input) const;

  // The directories of every file the compilation writes, made before
  // anything runs: the frontend, the pipeline and the link each write
  // where they are told, and none of them finds a directory missing after
  // the steps before it have run.
  bool makeDirectories() const;

  // From here on, a file the compilation writes is removed when it fails.
  // Only once the paths are known to be distinct from the input: the input
  // is never removed.
  void arm();

  // The compilation succeeded: what it wrote stays.
  void keep();

  const std::string base, corePath, modulePath, objectPath, executablePath;

private:
  std::vector<std::string> paths;
  std::vector<std::unique_ptr<llvm::FileRemover>> removers;
};

// Makes the directory a file is to be written in, and those it is in, so
// that an output goes where it is named whether or not its directory
// exists yet, as Idris's own -o did. A path with no directory part is in
// the working directory, which exists.
bool makeDirectoryOf(llvm::StringRef path);

// Object code for the module, into the file at `path`, which is kept only
// once it is written whole.
bool emit(llvm::Module &module, llvm::TargetMachine &machine, llvm::StringRef path);

} // namespace idr::driver

#endif // IDR_DRIVER_ARTIFACTS_H
