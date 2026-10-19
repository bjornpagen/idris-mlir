// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The files of one compilation, named from one base, each output written
// whole or not at all into directories made for it; and the object code of
// the optimized program, one object per bin, generated on the driver's pool.

#include "idr/Driver/Artifacts.h"

#include "idr/Support/Profile.h"
#include "idr/Target/Target.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"

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

Plan::Plan(std::string base, Source source, Product product, std::optional<std::string> report)
    : base(std::move(base)), source(std::move(source)), product(std::move(product)),
      report(std::move(report)) {}

std::optional<Plan> Plan::of(llvm::StringRef input, Product product,
                             std::optional<std::string> report, FrontendArgs frontend) {
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
                      : Source(FromIdris{input.str(), base + ".core", base + ".mlirbc",
                                         std::move(frontend)});
  Plan plan(std::move(base), std::move(source), std::move(product), std::move(report));
  llvm::StringSet<> seen;
  for (const std::string &path : plan.written())
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

std::optional<std::string> Plan::objectsDirectory() const {
  return std::visit(llvm::makeVisitor(
                        [&](const Executable &) { return std::optional(base + ".objects"); },
                        [](const Archive &) { return std::optional<std::string>(); }),
                    product);
}

std::vector<std::string> Plan::written() const {
  std::vector<std::string> paths = outputs();
  if (report)
    paths.push_back(*report);
  return paths;
}

const std::string &Plan::modulePath() const {
  return std::visit([](const auto &from) -> const std::string & { return from.modulePath; },
                    source);
}

mlir::LogicalResult Plan::makeDirectories(mlir::MLIRContext &context) const {
  for (const std::string &path : written())
    if (mlir::failed(makeDirectoryOf(path, context)))
      return mlir::failure();
  return mlir::success();
}

Artifacts::Artifacts(Plan plan) : Plan(std::move(plan)) {
  for (const std::string &path : outputs())
    removers.push_back(std::make_unique<llvm::FileRemover>(path));
  if (std::optional<std::string> directory = objectsDirectory())
    (void)llvm::sys::fs::remove_directories(*directory);
}

Artifacts::~Artifacts() {
  if (std::optional<std::string> directory = objectsDirectory(); directory && !kept)
    (void)llvm::sys::fs::remove_directories(*directory);
}

void Artifacts::keep() {
  for (const std::unique_ptr<llvm::FileRemover> &remover : removers)
    remover->releaseFile();
  kept = true;
}

const std::string &Artifacts::addObject(llvm::StringRef bin) {
  llvm::SmallString<256> path(*objectsDirectory());
  (void)llvm::sys::fs::create_directories(path);
  llvm::sys::path::append(path, bin + ".o");
  objects.push_back(path.str().str());
  return objects.back();
}

mlir::InFlightDiagnostic idr::driver::cannotWrite(mlir::MLIRContext &context, llvm::StringRef path,
                                                  const std::error_code &error) {
  return mlir::emitError(mlir::UnknownLoc::get(&context))
         << "cannot write " << path << ": " << error.message();
}

mlir::LogicalResult idr::driver::makeDirectoryOf(llvm::StringRef path, mlir::MLIRContext &context) {
  // The working directory, which exists.
  llvm::StringRef directory = llvm::sys::path::parent_path(path);
  if (directory.empty())
    return mlir::success();
  if (std::error_code error = llvm::sys::fs::create_directories(directory))
    return cannotWrite(context, path, error);
  return mlir::success();
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

mlir::LogicalResult idr::driver::emit(llvm::Module &module, llvm::TargetMachine &machine,
                                      llvm::StringRef path, mlir::MLIRContext &context) {
  std::error_code error;
  llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_None);
  if (error)
    return cannotWrite(context, path, error);
  if (!objectCode(module, machine, file.os()))
    return mlir::emitError(mlir::UnknownLoc::get(&context))
           << "the target cannot emit object files";
  file.keep();
  return mlir::success();
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
    return Failed{"bin " + name + ": " + llvm::toString(module.takeError())};
  if (llvm::Error error = partition.extract(bin, **module))
    return Failed{llvm::toString(std::move(error))};
  llvm::Expected<std::unique_ptr<llvm::TargetMachine>> machine =
      idr::target::machine(target, triple, cpu, features);
  if (!machine)
    return Failed{"bin " + name + ": " + llvm::toString(machine.takeError())};
  Object object;
  llvm::raw_svector_ostream os(object.bytes);
  if (!objectCode(**module, **machine, os))
    return Failed{"bin " + name + ": the target cannot emit object files"};
  return object;
}

llvm::StringRef bytesOf(const Object &object) {
  return llvm::StringRef(object.bytes.data(), object.bytes.size());
}

// Each bin's object, in bin order, written whole at its artifacts.addObject.
mlir::LogicalResult writeEach(llvm::ArrayRef<idr::target::Bin> bins, llvm::ArrayRef<Object> objects,
                              Artifacts &artifacts, mlir::MLIRContext &context) {
  IDR_ZONE_IN("objects", LLVM);
  for (auto [bin, object] : llvm::zip_equal(bins, objects)) {
    const std::string &path = artifacts.addObject(bin.name);
    std::error_code error;
    llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_None);
    if (error)
      return cannotWrite(context, path, error);
    file.os() << bytesOf(object);
    file.keep();
  }
  return mlir::success();
}

// The objects as one archive, in the order of their names, which a link
// takes whole: every definition is reached from main.
mlir::LogicalResult writeAsArchive(llvm::ArrayRef<idr::target::Bin> bins,
                                   llvm::ArrayRef<Object> objects, const llvm::Triple &triple,
                                   const Archive &archive, mlir::MLIRContext &context) {
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
                                             /*Deterministic=*/true, /*Thin=*/false))
    return mlir::emitError(mlir::UnknownLoc::get(&context))
           << "cannot write " << archive.path << ": " << llvm::toString(std::move(error));
  return mlir::success();
}

} // namespace

mlir::LogicalResult idr::driver::writeObjects(llvm::Module &optimized, const llvm::Target &target,
                                              const llvm::Triple &triple, llvm::StringRef cpu,
                                              llvm::StringRef features,
                                              llvm::ThreadPoolInterface &pool,
                                              Artifacts &artifacts, mlir::MLIRContext &context) {
  mlir::Location unknown = mlir::UnknownLoc::get(&context);
  std::optional<idr::target::Partition> partition;
  {
    IDR_ZONE_IN("partition", LLVM);
    llvm::Expected<idr::target::Partition> made = idr::target::Partition::of(optimized);
    if (!made)
      return mlir::emitError(unknown) << llvm::toString(made.takeError());
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
  // Every failure is an error, in bin order; the objects are written only
  // when there is one for every bin.
  std::vector<Object> objects;
  for (Compiled &one : compiled)
    std::visit(llvm::makeVisitor(
                   [&](Object &object) { objects.push_back(std::move(object)); },
                   [&](const Failed &failed) { mlir::emitError(unknown) << failed.why; }),
               one);
  if (objects.size() != bins.size())
    return mlir::failure();
  return std::visit(llvm::makeVisitor(
                        [&](const Executable &) {
                          return writeEach(bins, objects, artifacts, context);
                        },
                        [&](const Archive &archive) {
                          return writeAsArchive(bins, objects, triple, archive, context);
                        }),
                    artifacts.product);
}
