// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a compilation reads and writes. The input's kind is its extension,
// and every file the compilation writes is named from one base but the
// report, which --report names. Each output is written whole or not at all,
// and is removed when the compilation fails; the report is never removed,
// since it says why one failed.
#ifndef IDR_DRIVER_ARTIFACTS_H
#define IDR_DRIVER_ARTIFACTS_H

#include "mlir/IR/Diagnostics.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/FileUtilities.h"

#include <memory>
#include <optional>
#include <string>
#include <system_error>
#include <variant>
#include <vector>

namespace llvm {
class Module;
class Target;
class TargetMachine;
class ThreadPoolInterface;
class Triple;
} // namespace llvm

namespace idr::driver {

// Where the compilation's module comes from, by the input's extension. A
// module is MLIR's, text or bytecode, and is itself what the compilation
// reads in process, so nothing writes a Core; what it holds decides where
// it goes, no option: a handoff module, as the frontend writes one, goes to
// the pipeline, and a module of the LLVM dialect alone, the pipeline's
// output, goes to LLVM. Anything else is Idris source, which the frontend
// reads into the Core and the module, both named from the base, with the
// frontend's own options: the frontend decides, by Idris's own extensions,
// whether it reads it, so only MLIR's are named here. A module has no
// frontend, so it holds no frontend's options.
//
// The frontend's options: the Idris prefix it reads its packages from, the
// directories it looks for packages in besides, the packages it loads, and
// whether the Prelude is imported implicitly. The frontend reads no
// environment, so these are the whole of its search path.
struct FrontendArgs {
  std::string prefix;
  std::vector<std::string> packagePath, packages;
  bool noPrelude;
};
struct FromIdris {
  std::string source, corePath, modulePath;
  FrontendArgs frontend;
};
struct FromModule {
  std::string modulePath;
};
using Source = std::variant<FromIdris, FromModule>;

// What the compilation makes, at the path -o names: the executable, which
// links the bins' objects, each written to a file of its own, with the
// runtime; or with -c the archive of the bins' objects, unlinked.
struct Executable {
  std::string path;
};
struct Archive {
  std::string path;
};
using Product = std::variant<Executable, Archive>;

// What a compilation reads and writes, each named from one base by
// appending to it: for an executable the base is its path, and each bin of
// the program's code is the object <base>.<bin>.o; for an archive the base
// is its path without its extension. Idris source also leaves <base>.core
// and <base>.mlirbc, the module the pipeline reads, as MLIR bytecode.
//
// The files every plan writes, its outputs and its report, are distinct
// from each other and from its input, which would otherwise be overwritten,
// or removed as a stale output when the compilation fails: `of` makes no
// other plan.
class Plan {
public:
  // The plan for `input`, `product` and the report, when one is asked for,
  // or none when two of the files it writes are one or one is the input.
  // Idris source takes `frontend`; a module, nothing of it.
  static std::optional<Plan> of(llvm::StringRef input, Product product,
                                std::optional<std::string> report, FrontendArgs frontend);

  // The directories of every file the compilation writes, made before
  // anything runs: the frontend, the pipeline and the link each write
  // where they are told, and none of them finds a directory missing after
  // the steps before it have run. An error in `context` for one that
  // cannot be made.
  mlir::LogicalResult makeDirectories(mlir::MLIRContext &context) const;

  // The module the compilation reads in process.
  const std::string &modulePath() const;

  const std::string base;
  const Source source;
  const Product product;
  // The file the compilation's report is written to, whatever its verdict:
  // no output, since a failure keeps it.
  const std::optional<std::string> report;

protected:
  Plan(std::string base, Source source, Product product, std::optional<std::string> report);

  // The files the compilation writes whose names are known before anything
  // runs and which it removes when it fails: the Core and the module for
  // Idris source, and the product.
  std::vector<std::string> outputs() const;

private:
  // Every file the compilation writes whose name is known before anything
  // runs: the outputs, and the report when there is one.
  std::vector<std::string> written() const;
};

// A plan under way: from its making, every file the compilation writes is
// removed unless the whole compilation succeeds (keep), a stale one from
// an earlier success too where the name is known before anything runs, so
// that nothing outlives a failure. Nothing is removed before: a usage error
// leaves every file as it was. The bins are known only once the program is
// optimized, so a bin's object is named and armed when it is about to be
// written; an object an earlier success wrote for a bin this compilation
// does not make is not one of its files.
class Artifacts : public Plan {
public:
  explicit Artifacts(Plan plan);

  // The compilation succeeded: what it wrote stays.
  void keep();

  // The object of the bin named `bin`, <base>.<bin>.o, appended to
  // `objects` and removed unless the compilation succeeds.
  const std::string &addObject(llvm::StringRef bin);

  // For an executable, the bins' objects in the order of their names: what
  // the link passes. writeObjects fills it.
  std::vector<std::string> objects;

private:
  std::vector<std::unique_ptr<llvm::FileRemover>> removers;
};

// The compiler's error, in `context`, that the file at `path` cannot be
// written, and why.
mlir::InFlightDiagnostic cannotWrite(mlir::MLIRContext &context, llvm::StringRef path,
                                     const std::error_code &error);

// Makes the directory a file is to be written in, and those it is in, so
// that an output goes where it is named whether or not its directory
// exists yet, as Idris's own -o did. A path with no directory part is in
// the working directory, which exists.
mlir::LogicalResult makeDirectoryOf(llvm::StringRef path, mlir::MLIRContext &context);

// Object code for the module, into the file at `path`, which is kept only
// once it is written whole: the prepared runtime, one object.
mlir::LogicalResult emit(llvm::Module &module, llvm::TargetMachine &machine, llvm::StringRef path,
                         mlir::MLIRContext &context);

// The optimized program's object code, one object per bin of its partition:
// the module written once as bitcode, each bin read lazily in a context of
// its own and compiled for the target, CPU and features on a task of
// `pool`, the largest first; for an executable each object written whole at
// its artifacts.addObject, for an archive all of them as the archive, in
// the order of their names. The objects are the
// same whatever the pool's size. Each failure is an error in `context`.
mlir::LogicalResult writeObjects(llvm::Module &optimized, const llvm::Target &target,
                                 const llvm::Triple &triple, llvm::StringRef cpu,
                                 llvm::StringRef features, llvm::ThreadPoolInterface &pool,
                                 Artifacts &artifacts, mlir::MLIRContext &context);

} // namespace idr::driver

#endif // IDR_DRIVER_ARTIFACTS_H
