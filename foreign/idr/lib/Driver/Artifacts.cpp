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
#include "llvm/ADT/STLExtras.h"
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
#include <variant>
#include <vector>

using namespace idr::driver;

Plan::Plan(std::string base, Source source, Product product)
    : base(std::move(base)), source(std::move(source)), product(std::move(product)) {}

std::optional<Plan> Plan::of(llvm::StringRef input, Product product) {
  std::string base = std::visit(llvm::makeVisitor(
                                    [](const Executable &executable) { return executable.path; },
                                    [](const Archive &archive) {
                                      llvm::SmallString<256> path(archive.path);
                                      llvm::sys::path::replace_extension(path, "");
                                      return path.str().str();
                                    }),
                                product);
  llvm::StringRef extension = llvm::sys::path::extension(input);
  Source source = extension == ".mlir" || extension == ".mlirbc"
                      ? Source(FromModule{input.str()})
                      : Source(FromIdris{input.str(), base + ".core", base + ".mlirbc"});
  Plan plan(std::move(base), std::move(source), std::move(product));
  llvm::StringSet<> seen;
  for (const std::string &path : plan.outputs())
    if (!seen.insert(path).second || path == input || llvm::sys::fs::equivalent(path, input))
      return std::nullopt;
  return plan;
}

std::vector<std::string> Plan::outputs() const {
  std::vector<std::string> paths;
  if (const auto *idris = std::get_if<FromIdris>(&source))
    paths = {idris->corePath, idris->modulePath};
  paths.push_back(std::visit([](const auto &made) { return made.path; }, product));
  return paths;
}

const std::string &Plan::modulePath() const {
  return std::visit([](const auto &from) -> const std::string & { return from.modulePath; },
                    source);
}

bool Plan::makeDirectories() const {
  for (const std::string &path : outputs())
    if (!makeDirectoryOf(path))
      return false;
  return true;
}

Artifacts::Artifacts(Plan plan) : Plan(std::move(plan)) {
  for (const std::string &path : outputs())
    removers.push_back(std::make_unique<llvm::FileRemover>(path));
}

void Artifacts::keep() {
  for (const std::unique_ptr<llvm::FileRemover> &remover : removers)
    remover->releaseFile();
}

const std::string &Artifacts::addObject(llvm::StringRef bin) {
  std::string path = base + "." + bin.str() + ".o";
  removers.push_back(std::make_unique<llvm::FileRemover>(path));
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
struct Object {
  llvm::SmallVector<char, 0> bytes;
};
struct Failed {
  std::string why;
};
using Compiled = std::variant<Object, Failed>;

// One bin: the optimized module read lazily from its bitcode in a context of
// its own, cut down to the bin, compiled by a machine of its own. Nothing is
// shared with another task but the bitcode and the partition, both read.
Compiled compileBin(const idr::target::Partition &partition, unsigned bin, llvm::StringRef bitcode,
                    const llvm::Target &target, const llvm::Triple &triple, llvm::StringRef cpu,
                    llvm::StringRef features) {
  idr::profile::ThreadTrace thread;
  const std::string &name = partition.bins()[bin].name;
  IDR_ZONE_IN(name, LLVM);
  llvm::LLVMContext context;
  llvm::Expected<std::unique_ptr<llvm::Module>> module =
      llvm::getLazyBitcodeModule(llvm::MemoryBufferRef(bitcode, "optimized"), context);
  if (!module)
    return Failed{"internal error: bin " + name + ": " + llvm::toString(module.takeError())};
  if (llvm::Error error = partition.extract(bin, **module))
    return Failed{llvm::toString(std::move(error))};
  llvm::Expected<std::unique_ptr<llvm::TargetMachine>> machine =
      idr::target::machine(target, triple, cpu, features);
  if (!machine)
    return Failed{"internal error: bin " + name + ": " + llvm::toString(machine.takeError())};
  Object object;
  llvm::raw_svector_ostream os(object.bytes);
  if (!objectCode(**module, **machine, os))
    return Failed{"internal error: bin " + name + ": the target cannot emit object files"};
  return object;
}

llvm::StringRef bytesOf(const Object &object) {
  return llvm::StringRef(object.bytes.data(), object.bytes.size());
}

// Each bin's object, in bin order, written whole at its artifacts.addObject.
bool writeEach(llvm::ArrayRef<idr::target::Bin> bins, llvm::ArrayRef<Object> objects,
               Artifacts &artifacts) {
  IDR_ZONE_IN("objects", LLVM);
  for (auto [bin, object] : llvm::zip_equal(bins, objects)) {
    const std::string &path = artifacts.addObject(bin.name);
    std::error_code error;
    llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_None);
    if (error) {
      cannotWrite(path, error);
      return false;
    }
    file.os() << bytesOf(object);
    file.keep();
  }
  return true;
}

// The objects as one archive, in the order of their names, which a link
// takes whole: every definition is reached from main.
bool writeAsArchive(llvm::ArrayRef<idr::target::Bin> bins, llvm::ArrayRef<Object> objects,
                    const llvm::Triple &triple, const Archive &archive) {
  IDR_ZONE_IN("archive", LLVM);
  std::vector<std::string> names;
  std::vector<llvm::NewArchiveMember> members;
  names.reserve(bins.size());
  for (auto [bin, object] : llvm::zip_equal(bins, objects)) {
    names.push_back(bin.name + ".o");
    members.emplace_back(llvm::MemoryBufferRef(bytesOf(object), names.back()));
  }
  if (llvm::Error error = llvm::writeArchive(archive.path, members,
                                             llvm::SymtabWritingMode::NormalSymtab,
                                             llvm::object::Archive::getDefaultKindForTriple(triple),
                                             /*Deterministic=*/true, /*Thin=*/false)) {
    Report() << "cannot write " << archive.path << ": " << llvm::toString(std::move(error));
    return false;
  }
  return true;
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
  // Every failure is reported; the objects are written only when there is
  // one for every bin.
  std::vector<Object> objects;
  bool whole = true;
  for (Compiled &one : compiled)
    std::visit(llvm::makeVisitor([&](Object &object) { objects.push_back(std::move(object)); },
                                 [&](const Failed &failed) {
                                   Report() << failed.why;
                                   whole = false;
                                 }),
               one);
  if (!whole)
    return false;
  return std::visit(
      llvm::makeVisitor(
          [&](const Executable &) { return writeEach(bins, objects, artifacts); },
          [&](const Archive &archive) { return writeAsArchive(bins, objects, triple, archive); }),
      artifacts.product);
}
