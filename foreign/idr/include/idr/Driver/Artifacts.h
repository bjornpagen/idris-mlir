// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a compilation reads and writes. The input's kind is its extension,
// and every file the compilation writes is named from one base. Each output
// is written whole or not at all, and is removed when the compilation
// fails.
#ifndef IDR_DRIVER_ARTIFACTS_H
#define IDR_DRIVER_ARTIFACTS_H

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/FileUtilities.h"

#include <memory>
#include <string>
#include <vector>

namespace llvm {
class Module;
class Target;
class TargetMachine;
class ThreadPoolInterface;
class Triple;
} // namespace llvm

namespace idr::driver {

// A module is MLIR's, text or bytecode, and goes straight to the pipeline.
// Anything else is Idris source: the frontend decides, by Idris's own
// extensions, whether it reads it, so only MLIR's are named here.
enum class Input { Idris, Module };

Input inputKind(llvm::StringRef path);

// What a compilation writes, each named from one base by appending to it:
// without -c the base is -o, which is the executable, and each bin of the
// program's code is the object <base>.<bin>.o; with -c the base is -o
// without its extension, and -o is the archive of the bins' objects. Idris
// source also leaves <base>.core and <base>.mlirbc, the module the pipeline
// reads, as MLIR bytecode; a module input is itself that module, and
// nothing writes a .core.
// Once armed, every file written is removed unless the whole compilation
// succeeds (keep), a stale one from an earlier success too where the name
// is known before anything runs, so that nothing outlives a failure. The
// bins are known only once the program is optimized, so a bin's object is
// named and armed when it is about to be written; an object an earlier
// success wrote for a bin this compilation does not make is not one of its
// files.
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

  // The object of the bin named `bin`, <base>.<bin>.o, appended to
  // `objects` and, once armed, removed unless the compilation succeeds.
  const std::string &addObject(llvm::StringRef bin);

  // With -c, the archive of the bins' objects is archivePath, the path -o
  // names; without, archivePath is empty.
  const std::string base, corePath, modulePath, archivePath, executablePath;

  // Without -c, the bins' objects in the order of their names: what the
  // link passes. writeObjects fills it.
  std::vector<std::string> objects;

private:
  std::vector<std::string> paths;
  std::vector<std::unique_ptr<llvm::FileRemover>> removers;
  bool armed = false;
};

// Makes the directory a file is to be written in, and those it is in, so
// that an output goes where it is named whether or not its directory
// exists yet, as Idris's own -o did. A path with no directory part is in
// the working directory, which exists.
bool makeDirectoryOf(llvm::StringRef path);

// Object code for the module, into the file at `path`, which is kept only
// once it is written whole: the prepared runtime, one object.
bool emit(llvm::Module &module, llvm::TargetMachine &machine, llvm::StringRef path);

// The optimized program's object code, one object per bin of its partition:
// the module written once as bitcode, each bin read lazily in a context of
// its own and compiled for the target, CPU and features on a task of
// `pool`, the largest first; without -c each object written whole at its
// artifacts.addObject, with -c all of them as the archive at
// artifacts.archivePath, in the order of their names. The objects are the
// same whatever the pool's size. Reports what fails, and returns false.
bool writeObjects(llvm::Module &optimized, const llvm::Target &target, const llvm::Triple &triple,
                  llvm::StringRef cpu, llvm::StringRef features, llvm::ThreadPoolInterface &pool,
                  Artifacts &artifacts);

} // namespace idr::driver

#endif // IDR_DRIVER_ARTIFACTS_H
