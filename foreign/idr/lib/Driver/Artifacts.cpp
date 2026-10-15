// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The files of one compilation, named from one base, each output written
// whole or not at all into directories made for it; and the object code of
// the optimized program, one object per bin, generated on the driver's pool.

#include "idr/Driver/Artifacts.h"

#include "idr/Driver/Report.h"
#include "idr/Support/Profile.h"
#include "idr/Target/Target.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/ArchiveWriter.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/FileUtilities.h"
#include "llvm/Support/MemoryBufferRef.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/ThreadPool.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Triple.h"

#include <algorithm>
#include <memory>
#include <numeric>
#include <optional>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

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
      modulePath(kind == Input::Idris ? base + ".mlirbc" : input.str()),
      archivePath(objectOnly ? output.str() : ""), executablePath(objectOnly ? "" : output.str()) {
  if (kind == Input::Idris) {
    paths.push_back(corePath);
    paths.push_back(modulePath);
  }
  paths.push_back(objectOnly ? archivePath : executablePath);
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
  armed = true;
  for (const std::string &path : paths)
    removers.push_back(std::make_unique<llvm::FileRemover>(path));
}

void Artifacts::keep() {
  for (const std::unique_ptr<llvm::FileRemover> &remover : removers)
    remover->releaseFile();
}

const std::string &Artifacts::addObject(llvm::StringRef bin) {
  std::string path = base + "." + bin.str() + ".o";
  if (armed)
    removers.push_back(std::make_unique<llvm::FileRemover>(path));
  paths.push_back(path);
  objects.push_back(std::move(path));
  return objects.back();
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

// The machine's object code for the module, into `os`; false when the
// target has no object emitter.
static bool objectCode(llvm::Module &module, llvm::TargetMachine &machine,
                       llvm::raw_pwrite_stream &os) {
  llvm::legacy::PassManager codegen;
  if (machine.addPassesToEmitFile(codegen, os, nullptr, llvm::CodeGenFileType::ObjectFile))
    return false;
  codegen.run(module);
  return true;
}

bool idr::driver::emit(llvm::Module &module, llvm::TargetMachine &machine, llvm::StringRef path) {
  std::error_code error;
  llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_None);
  if (error) {
    cannotWrite(path, error);
    return false;
  }
  if (!objectCode(module, machine, file.os())) {
    Report() << "the target cannot emit object files";
    return false;
  }
  file.keep();
  return true;
}

namespace {

// What one bin's task leaves in its own slot: its object, or why there is
// none, which the calling thread reports.
struct Compiled {
  llvm::SmallVector<char, 0> object;
  std::string failure;
};

// One bin: the optimized module read lazily from its bitcode in a context of
// its own, cut down to the bin, compiled by a machine of its own. Nothing is
// shared with another task but the bitcode and the partition, both read.
Compiled compileBin(const idr::target::Partition &partition, unsigned bin, llvm::StringRef bitcode,
                    const llvm::Target &target, const llvm::Triple &triple, llvm::StringRef cpu,
                    llvm::StringRef features) {
  idr::profile::ThreadTrace thread;
  const std::string &name = partition.bins()[bin].name;
  IDR_ZONE_IN(name, LLVM);
  Compiled compiled;
  llvm::LLVMContext context;
  llvm::Expected<std::unique_ptr<llvm::Module>> module =
      llvm::getLazyBitcodeModule(llvm::MemoryBufferRef(bitcode, "optimized"), context);
  if (!module) {
    compiled.failure = "internal error: bin " + name + ": " + llvm::toString(module.takeError());
    return compiled;
  }
  if (llvm::Error error = partition.extract(bin, **module)) {
    compiled.failure = llvm::toString(std::move(error));
    return compiled;
  }
  std::unique_ptr<llvm::TargetMachine> machine = idr::target::machine(target, triple, cpu, features);
  llvm::raw_svector_ostream os(compiled.object);
  if (!machine || !objectCode(**module, *machine, os))
    compiled.failure = "internal error: bin " + name + ": the target cannot emit object files";
  return compiled;
}

} // namespace

bool idr::driver::writeObjects(llvm::Module &optimized, const llvm::Target &target,
                               const llvm::Triple &triple, llvm::StringRef cpu,
                               llvm::StringRef features, llvm::ThreadPoolInterface &pool,
                               Artifacts &artifacts) {
  std::optional<idr::target::Partition> partition;
  {
    IDR_ZONE_IN("partition", LLVM);
    llvm::Expected<idr::target::Partition> made = idr::target::Partition::of(optimized);
    if (!made) {
      Report() << llvm::toString(made.takeError());
      return false;
    }
    partition.emplace(std::move(*made));
  }
  // The module once, as bitcode, on this thread: the one serial step.
  std::string bitcode;
  {
    IDR_ZONE_IN("write bitcode", LLVM);
    llvm::raw_string_ostream os(bitcode);
    llvm::WriteBitcodeToFile(optimized, os);
  }
  llvm::ArrayRef<idr::target::Bin> bins = partition->bins();
  std::vector<Compiled> compiled(bins.size());
  // The largest bins first, so that the last task to finish is a small one.
  std::vector<unsigned> order(bins.size());
  std::iota(order.begin(), order.end(), 0u);
  std::stable_sort(order.begin(), order.end(), [&](unsigned a, unsigned b) {
    return bins[a].instructions > bins[b].instructions;
  });
  {
    llvm::ThreadPoolTaskGroup tasks(pool);
    for (unsigned bin : order)
      tasks.async([&, bin] {
        compiled[bin] = compileBin(*partition, bin, bitcode, target, triple, cpu, features);
      });
    tasks.wait();
  }
  bool written = true;
  for (const Compiled &one : compiled)
    if (!one.failure.empty()) {
      Report() << one.failure;
      written = false;
    }
  if (!written)
    return false;

  if (artifacts.archivePath.empty()) {
    IDR_ZONE_IN("objects", LLVM);
    for (unsigned bin = 0; bin < bins.size(); ++bin) {
      const std::string &path = artifacts.addObject(bins[bin].name);
      std::error_code error;
      llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_None);
      if (error) {
        cannotWrite(path, error);
        return false;
      }
      file.os() << llvm::StringRef(compiled[bin].object.data(), compiled[bin].object.size());
      file.keep();
    }
    return true;
  }
  // With -c, the objects as one archive, in the order of their names, which
  // a link takes whole: every definition is reached from main.
  IDR_ZONE_IN("archive", LLVM);
  std::vector<std::string> names;
  std::vector<llvm::NewArchiveMember> members;
  names.reserve(bins.size());
  for (unsigned bin = 0; bin < bins.size(); ++bin) {
    names.push_back(bins[bin].name + ".o");
    members.emplace_back(llvm::MemoryBufferRef(
        llvm::StringRef(compiled[bin].object.data(), compiled[bin].object.size()), names.back()));
  }
  if (llvm::Error error = llvm::writeArchive(artifacts.archivePath, members,
                                             llvm::SymtabWritingMode::NormalSymtab,
                                             llvm::object::Archive::getDefaultKindForTriple(triple),
                                             /*Deterministic=*/true, /*Thin=*/false)) {
    Report() << "cannot write " << artifacts.archivePath << ": " << llvm::toString(std::move(error));
    return false;
  }
  return true;
}
