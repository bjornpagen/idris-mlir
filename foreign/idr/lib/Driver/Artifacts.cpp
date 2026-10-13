// The files of one compilation, named before anything runs, and each
// output written whole or not at all, into directories made for it.

#include "idr/Driver/Artifacts.h"

#include "idr/Driver/Report.h"

#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/FileUtilities.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Target/TargetMachine.h"

#include <memory>
#include <string>
#include <system_error>

using namespace idr::driver;

static std::string baseOf(llvm::StringRef output, bool objectOnly) {
  llvm::SmallString<256> path(output);
  if (objectOnly)
    llvm::sys::path::replace_extension(path, "");
  return path.str().str();
}

Input idr::driver::inputKind(llvm::StringRef path) {
  llvm::StringRef extension = llvm::sys::path::extension(path);
  return extension == ".mlir" || extension == ".mlirbc" ? Input::Module : Input::Idris;
}

Artifacts::Artifacts(llvm::StringRef input, Input kind, llvm::StringRef output, bool objectOnly)
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

bool Artifacts::distinctFromInput(llvm::StringRef input) const {
  llvm::StringSet<> seen;
  for (const std::string &path : paths)
    if (!seen.insert(path).second || path == input || llvm::sys::fs::equivalent(path, input))
      return false;
  return true;
}

bool Artifacts::makeDirectories() const {
  for (const std::string &path : paths)
    if (!makeDirectoryOf(path))
      return false;
  return true;
}

void Artifacts::arm() {
  for (const std::string &path : paths)
    removers.push_back(std::make_unique<llvm::FileRemover>(path));
}

void Artifacts::keep() {
  for (const std::unique_ptr<llvm::FileRemover> &remover : removers)
    remover->releaseFile();
}

bool idr::driver::makeDirectoryOf(llvm::StringRef path) {
  llvm::StringRef directory = llvm::sys::path::parent_path(path);
  if (directory.empty())
    return true;
  if (std::error_code error = llvm::sys::fs::create_directories(directory)) {
    cannotWrite(path, error);
    return false;
  }
  return true;
}

bool idr::driver::emit(llvm::Module &module, llvm::TargetMachine &machine, llvm::StringRef path) {
  std::error_code error;
  llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_None);
  if (error) {
    cannotWrite(path, error);
    return false;
  }
  llvm::legacy::PassManager codegen;
  if (machine.addPassesToEmitFile(codegen, file.os(), nullptr, llvm::CodeGenFileType::ObjectFile)) {
    Report() << "the target cannot emit object files";
    return false;
  }
  codegen.run(module);
  file.keep();
  return true;
}
