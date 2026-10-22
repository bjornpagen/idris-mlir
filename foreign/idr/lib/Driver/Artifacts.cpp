// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The files of one compilation, named from one base, each output written
// whole or not at all into directories made for it; and the object code of
// the optimized program, one object per bin, generated on the driver's pool.

#include "idr/Driver/Artifacts.h"

#include "idr/Driver/Runtime.h"
#include "idr/Driver/StackBound.h"
#include "idr/Support/Match.h"
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
#include "llvm/IR/Constants.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/GlobalVariable.h"
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
                             std::optional<std::string> report,
                             std::optional<std::string> emitted, FrontendArgs frontend) {
  std::string base = idr::match(
      product, [](const Executable &executable) { return executable.path; },
      [](const Archive &archive) {
        llvm::SmallString<256> path(archive.path);
        llvm::sys::path::replace_extension(path, "");
        return path.str().str();
      });
  llvm::StringRef extension = llvm::sys::path::extension(input);
  Source source = extension == ".mlir" || extension == ".mlirbc"
                      ? Source(FromModule{input.str()})
                      : Source(FromIdris{input.str(), emitted.value_or(base + ".mlirbc"),
                                         emitted ? ModuleKept::Always : ModuleKept::WithProduct,
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
  idr::match(
      source, [](const FromModule &) {},
      [&](const FromIdris &idris) {
        if (idris.kept == ModuleKept::WithProduct)
          paths.push_back(idris.modulePath);
      });
  paths.push_back(idr::match(
      product, [](const idr::OneOf<Executable, Archive> auto &made) { return made.path; }));
  return paths;
}

std::optional<std::string> Plan::objectsDirectory() const {
  return idr::match(
      product, [&](const Executable &) { return std::optional(base + ".objects"); },
      [](const Archive &) { return std::optional<std::string>(); });
}

std::vector<std::string> Plan::written() const {
  std::vector<std::string> paths = outputs();
  if (report)
    paths.push_back(*report);
  idr::match(
      source, [](const FromModule &) {},
      [&](const FromIdris &idris) {
        if (idris.kept == ModuleKept::Always)
          paths.push_back(idris.modulePath);
      });
  return paths;
}

const std::string &Plan::modulePath() const {
  return idr::match(source, [](const idr::OneOf<FromIdris, FromModule> auto &from) -> auto & {
    return from.modulePath;
  });
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
// its own, cut down to the bin, compiled by a machine of its own, each frame
// code generation lays out gathered into `frames`, the bin's own. Nothing is
// shared with another task but the bitcode and the partition, both read.
Compiled compileBin(const idr::target::Partition &partition, unsigned bin, llvm::StringRef bitcode,
                    const llvm::Target &target, idr::driver::stack::Frames &frames) {
  idr::profile::ThreadTrace thread;
  const std::string &name = partition.bins()[bin].name;
  IDR_ZONE_IN(name, LLVM);
  llvm::LLVMContext context;
  context.setDiagnosticHandler(idr::driver::stack::gather(frames));
  llvm::Expected<std::unique_ptr<llvm::Module>> module =
      llvm::getLazyBitcodeModule(llvm::MemoryBufferRef(bitcode, "optimized"), context);
  if (!module)
    return Failed{"bin " + name + ": " + llvm::toString(module.takeError())};
  if (llvm::Error error = partition.extract(bin, **module))
    return Failed{llvm::toString(std::move(error))};
  llvm::Expected<std::unique_ptr<llvm::TargetMachine>> machine =
      idr::target::machine(target);
  if (!machine)
    return Failed{"bin " + name + ": " + llvm::toString(machine.takeError())};
  Object object;
  llvm::raw_svector_ostream os(object.bytes);
  if (!objectCode(**module, **machine, os))
    return Failed{"bin " + name + ": the target cannot emit object files"};
  return object;
}

// What only the whole program's code generation gives the runtime, as the
// one constant of an object of its own (idris_rt_built): the stack's need
// and the program's name, which every message begins with. It is data: the
// machine compiles it for no CPU of its own.
Compiled builtObject(const idr::driver::stack::Need &need, llvm::StringRef name,
                     llvm::TargetMachine &machine) {
  llvm::LLVMContext context;
  llvm::Module module("built", context);
  module.setTargetTriple(machine.getTargetTriple());
  module.setDataLayout(machine.createDataLayout());
  module.setPICLevel(llvm::PICLevel::BigPIC);
  module.setPIELevel(llvm::PIELevel::Large);
  llvm::Type *word = llvm::Type::getInt64Ty(context);
  auto *fields = llvm::StructType::get(
      context, {word, word, word, llvm::PointerType::getUnqual(context), word});
  llvm::Constant *bytes = llvm::ConstantDataArray::getString(context, name, /*AddNull=*/false);
  auto *text = new llvm::GlobalVariable(module, bytes->getType(), /*isConstant=*/true,
                                        llvm::GlobalValue::PrivateLinkage, bytes, "name");
  text->setUnnamedAddr(llvm::GlobalValue::UnnamedAddr::Global);
  auto *built = new llvm::GlobalVariable(
      module, fields, /*isConstant=*/true, llvm::GlobalValue::ExternalLinkage,
      llvm::ConstantStruct::get(fields, {llvm::ConstantInt::get(word, need.stack),
                                         llvm::ConstantInt::get(word, need.frame),
                                         llvm::ConstantInt::get(word, need.signal), text,
                                         llvm::ConstantInt::get(word, name.size())}),
      builtSymbol);
  built->setDSOLocal(true);
  Object object;
  llvm::raw_svector_ostream os(object.bytes);
  if (!objectCode(module, machine, os))
    return Failed{"the target cannot emit object files"};
  return object;
}

// The name of the object of what the driver knows, beside the bins', whose
// names are hex digits alone.
constexpr llvm::StringLiteral builtObjectName = "built";

llvm::StringRef bytesOf(const Object &object) {
  return llvm::StringRef(object.bytes.data(), object.bytes.size());
}

// Each object, in order, written whole at its artifacts.addObject.
mlir::LogicalResult writeEach(llvm::ArrayRef<std::string> names, llvm::ArrayRef<Object> objects,
                              Artifacts &artifacts, mlir::MLIRContext &context) {
  IDR_ZONE_IN("objects", LLVM);
  for (auto [name, object] : llvm::zip_equal(names, objects)) {
    const std::string &path = artifacts.addObject(name);
    std::error_code error;
    llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_None);
    if (error)
      return cannotWrite(context, path, error);
    file.os() << bytesOf(object);
    file.keep();
  }
  return mlir::success();
}

// The objects as one archive, in order, which a link takes whole: every
// definition is reached from main.
mlir::LogicalResult writeAsArchive(llvm::ArrayRef<std::string> names,
                                   llvm::ArrayRef<Object> objects, const llvm::Triple &triple,
                                   const Archive &archive, mlir::MLIRContext &context) {
  IDR_ZONE_IN("archive", LLVM);
  idr::footprint::Vector<std::string> files;
  idr::footprint::Vector<llvm::NewArchiveMember> members;
  files.reserve(names.size());
  for (auto [name, object] : llvm::zip_equal(names, objects)) {
    files.push_back(name + ".o");
    members.emplace_back(llvm::MemoryBufferRef(bytesOf(object), files.back()));
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
                                              const llvm::Triple &triple,
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
  // The calls of the module as the bins have them, read once, before any
  // code is generated: a call on a cycle that is no tail call fails the
  // build here. Code generation is asked for every frame.
  std::optional<stack::Graph> calls;
  {
    IDR_ZONE_IN("calls", LLVM);
    mlir::FailureOr<stack::Graph> read = stack::Graph::of(optimized, context);
    if (mlir::failed(read))
      return mlir::failure();
    calls.emplace(std::move(*read));
    stack::ask(optimized);
  }
  // The module once, as bitcode, on this thread: the one serial step.
  std::string bitcode;
  {
    IDR_ZONE_IN("write bitcode", LLVM);
    llvm::raw_string_ostream os(bitcode);
    llvm::WriteBitcodeToFile(optimized, os);
  }
  // Each bin's slot in every table, sized by the program, so their memory
  // is the footprint's.
  llvm::ArrayRef<idr::target::Bin> bins = partition->bins();
  idr::footprint::Vector<Compiled> compiled(bins.size());
  idr::footprint::Vector<stack::Frames> frames(bins.size());
  // The largest bins first, so that the last task to finish is a small one.
  idr::footprint::Vector<unsigned> order(bins.size());
  std::iota(order.begin(), order.end(), 0u);
  std::stable_sort(order.begin(), order.end(), [&](unsigned a, unsigned b) {
    return bins[a].instructions > bins[b].instructions;
  });
  {
    llvm::ThreadPoolTaskGroup tasks(pool);
    for (unsigned bin : order)
      tasks.async([&, bin] {
        compiled[bin] = compileBin(*partition, bin, bitcode, target, frames[bin]);
      });
    tasks.wait();
  }
  // What the runtime reads of the program, once every frame is laid out,
  // compiled last: its object follows the bins'.
  stack::Frames laid;
  for (const stack::Frames &bin : frames)
    laid.join(bin);
  llvm::Expected<std::unique_ptr<llvm::TargetMachine>> machine = idr::target::machine(target);
  if (!machine)
    return mlir::emitError(unknown) << llvm::toString(machine.takeError());
  compiled.push_back(builtObject(calls->need(laid, **machine),
                                 llvm::sys::path::filename(artifacts.base), **machine));
  idr::footprint::Vector<std::string> names;
  names.reserve(compiled.size());
  for (const idr::target::Bin &bin : bins)
    names.push_back(bin.name);
  names.push_back(builtObjectName.str());
  // Every failure is an error, in order; the objects are written only when
  // there is one for every name.
  idr::footprint::Vector<Object> objects;
  for (Compiled &one : compiled)
    idr::match(
        one, [&](Object &object) { objects.push_back(std::move(object)); },
        [&](const Failed &failed) { mlir::emitError(unknown) << failed.why; });
  if (objects.size() != names.size())
    return mlir::failure();
  return idr::match(
      artifacts.product,
      [&](const Executable &) { return writeEach(names, objects, artifacts, context); },
      [&](const Archive &archive) {
        return writeAsArchive(names, objects, triple, archive, context);
      });
}
