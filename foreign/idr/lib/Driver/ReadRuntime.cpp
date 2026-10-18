// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime read from the file a compilation names, once, into the kind
// it is: the archive's members, each checked, stripped of what only
// separate compilation needs and marked with what it was compiled for,
// linked into one module; or prepared bitcode, with the CPU its native
// half is compiled for.

#include "idr/Driver/Options.h"
#include "idr/Driver/Runtime.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/BinaryFormat/Magic.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Linker/Linker.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/Error.h"
#include "llvm/Object/IRObjectFile.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/MemoryBufferRef.h"
#include "llvm/Support/Path.h"
#include "llvm/TargetParser/Triple.h"

#include <memory>
#include <string>
#include <utility>
#include <variant>
#include <vector>

using namespace idr::driver;

namespace {

// One member of the runtime archive, and its bitcode.
struct Member {
  std::string name;
  llvm::MemoryBufferRef bitcode;
};

} // namespace

// Every member of the runtime archive carries its bitcode as the target
// entry's flags compile it (a fat LTO object's section, say), where LLVM's
// object reader finds it whatever the object's format; this is the bitcode
// of each.
static mlir::FailureOr<std::vector<Member>>
readMembers(llvm::StringRef path, const llvm::MemoryBuffer &archiveBuffer, mlir::Location at) {
  auto archive = llvm::object::Archive::create(archiveBuffer.getMemBufferRef());
  if (!archive)
    return mlir::emitError(at) << "runtime " << path << ": " << llvm::toString(archive.takeError());
  std::vector<Member> members;
  llvm::Error error = llvm::Error::success();
  for (const llvm::object::Archive::Child &child : (*archive)->children(error)) {
    auto name = child.getName();
    auto buffer = child.getMemoryBufferRef();
    if (!name || !buffer) {
      llvm::consumeError(name.takeError());
      llvm::consumeError(buffer.takeError());
      llvm::consumeError(std::move(error));
      return mlir::emitError(at) << "runtime " << path << ": unreadable member";
    }
    auto bitcode = llvm::object::IRObjectFile::findBitcodeInMemBuffer(*buffer);
    if (!bitcode) {
      llvm::consumeError(std::move(error));
      return mlir::emitError(at)
             << "runtime member " << *name
             << " carries no bitcode, which every member of the runtime's archive must: "
             << llvm::toString(bitcode.takeError());
    }
    members.push_back({name->str(), *bitcode});
  }
  if (error)
    return mlir::emitError(at) << "runtime " << path << ": " << llvm::toString(std::move(error));
  return members;
}

// Whether code compiled for one triple runs where code for the other does:
// the same architecture, vendor, operating system and its version, and
// environment, however each is spelled. Clang writes the triple it was given
// in its normal form (arm64-apple-macosx14.0 becomes
// arm64-apple-macosx14.0.0), so the spelling is not compared.
static bool sameTarget(const llvm::Triple &a, const llvm::Triple &b) {
  return a.getArch() == b.getArch() && a.getSubArch() == b.getSubArch() &&
         a.getVendor() == b.getVendor() && a.getOS() == b.getOS() &&
         a.getOSVersion() == b.getOSVersion() && a.getEnvironment() == b.getEnvironment() &&
         a.getObjectFormat() == b.getObjectFormat();
}

// The runtime module `name` is compiled for the triple programs are.
static mlir::LogicalResult onProgramTriple(const llvm::Module &module, llvm::StringRef name,
                                             mlir::Location at) {
  if (!sameTarget(module.getTargetTriple(), llvm::Triple(targetTriple)))
    return mlir::emitError(at) << "runtime member " << name << " is compiled for "
                               << module.getTargetTriple().str() << ", and programs for "
                               << targetTriple;
  return mlir::success();
}

// Turns the runtime's annotations of a member's functions, which
// llvm.global.annotations lists, into marks.
static void markAnnotated(llvm::Module &member) {
  const llvm::GlobalVariable *annotations = member.getNamedGlobal("llvm.global.annotations");
  auto *entries = annotations && annotations->hasInitializer()
                      ? llvm::dyn_cast<llvm::ConstantArray>(annotations->getInitializer())
                      : nullptr;
  if (!entries)
    return;
  for (const llvm::Use &entry : entries->operands()) {
    auto *fields = llvm::dyn_cast<llvm::ConstantStruct>(entry.get());
    if (!fields || fields->getNumOperands() < 2)
      continue;
    auto *function = llvm::dyn_cast<llvm::Function>(fields->getOperand(0)->stripPointerCasts());
    auto *text = llvm::dyn_cast<llvm::GlobalVariable>(fields->getOperand(1)->stripPointerCasts());
    auto *data = text && text->hasInitializer()
                     ? llvm::dyn_cast<llvm::ConstantDataArray>(text->getInitializer())
                     : nullptr;
    if (!function || !data || !data->isCString())
      continue;
    llvm::StringRef mark = data->getAsCString();
    if (mark == baselineMark)
      function->addFnAttr(mark);
  }
}

// The runtime is constant-initialized, and its `used` markers exist for
// separate compilation only. LinkOnlyNeeded always links appending globals,
// so constructors would run in every program, and `used` would keep dead
// runtime code (and its libc calls) in every executable: constructors are
// rejected, `used` markers dropped. Annotations become marks, then are
// dropped too. Each definition is marked with what it was compiled for,
// before anything raises it.
static mlir::LogicalResult prepareMember(llvm::Module &member, llvm::StringRef name,
                                         mlir::Location at) {
  if (mlir::failed(onProgramTriple(member, name, at)))
    return mlir::failure();
  markAnnotated(member);
  if (llvm::GlobalVariable *annotations = member.getNamedGlobal("llvm.global.annotations"))
    annotations->eraseFromParent();
  // An empty list of constructors, which clang writes for some translation
  // units, lists none.
  for (llvm::StringRef array : {"llvm.global_ctors", "llvm.global_dtors"})
    if (llvm::GlobalVariable *global = member.getNamedGlobal(array)) {
      if (llvm::cast<llvm::ArrayType>(global->getValueType())->getNumElements() != 0)
        return mlir::emitError(at) << "runtime member " << name
                                   << " has static constructors or destructors; the runtime "
                                      "must be constant-initialized";
      global->eraseFromParent();
    }
  for (llvm::StringRef array : {"llvm.used", "llvm.compiler.used"})
    if (llvm::GlobalVariable *global = member.getNamedGlobal(array))
      global->eraseFromParent();
  for (const llvm::GlobalVariable &global : member.globals())
    if (global.hasAppendingLinkage())
      return idr::refuse(at, idr::Rule::Runtime)
             << "runtime member " << name << " defines the appending global " << global.getName();
  for (llvm::Function &function : member)
    if (!function.isDeclaration()) {
      function.addFnAttr(cpuMark, function.getFnAttribute("target-cpu").getValueAsString());
      function.addFnAttr(featuresMark,
                         function.getFnAttribute("target-features").getValueAsString());
    }
  return mlir::success();
}

// The prepared runtime's bitcode: the file itself when it is bitcode, else
// its object's bitcode section, where LLVM's object reader finds it
// (.llvm.lto on ELF), or the file beside the object exactly when the object
// has none, which `beside` then holds.
static llvm::Expected<llvm::MemoryBufferRef>
preparedBitcode(llvm::MemoryBufferRef file, llvm::StringRef path,
                std::unique_ptr<llvm::MemoryBuffer> &beside) {
  return llvm::handleExpected(
      llvm::object::IRObjectFile::findBitcodeInMemBuffer(file),
      [&]() -> llvm::Expected<llvm::MemoryBufferRef> {
        std::string besidePath = besideObject(path);
        auto read = llvm::MemoryBuffer::getFile(besidePath, /*IsText=*/false,
                                                /*RequiresNullTerminator=*/false);
        if (!read)
          return llvm::createStringError(read.getError(), "cannot read " + besidePath);
        beside = std::move(*read);
        return beside->getMemBufferRef();
      },
      [](const llvm::ECError &error) -> llvm::Error {
        std::error_code code = error.convertToErrorCode();
        if (code == llvm::object::object_error::bitcode_section_not_found)
          return llvm::Error::success();
        return llvm::errorCodeToError(code);
      });
}

std::string idr::driver::besideObject(llvm::StringRef object) {
  llvm::SmallString<128> path(object);
  llvm::sys::path::replace_extension(path, "bc");
  return path.str().str();
}

// The archive's members, each prepared, joined into one module.
static mlir::FailureOr<std::variant<Archived, Prepared>>
readArchive(llvm::StringRef path, const llvm::MemoryBuffer &buffer, llvm::LLVMContext &llvmContext,
            const llvm::Triple &triple, const llvm::DataLayout &layout, mlir::Location at) {
  mlir::FailureOr<std::vector<Member>> members = readMembers(path, buffer, at);
  if (mlir::failed(members))
    return mlir::failure();
  auto runtime = std::make_unique<llvm::Module>("idris-mlir-runtime", llvmContext);
  runtime->setTargetTriple(triple);
  runtime->setDataLayout(layout);
  llvm::Linker runtimeLinker(*runtime);
  for (const Member &member : *members) {
    auto module = llvm::parseBitcodeFile(member.bitcode, llvmContext);
    if (!module)
      return mlir::emitError(at) << "runtime member " << member.name << ": "
                                 << llvm::toString(module.takeError());
    if (mlir::failed(prepareMember(**module, member.name, at)))
      return mlir::failure();
    if (runtimeLinker.linkInModule(std::move(*module)))
      return mlir::emitError(at) << "runtime member " << member.name
                                 << " does not link with the members before it";
  }
  return std::variant<Archived, Prepared>(Archived{std::move(runtime)});
}

// What --prepare-runtime wrote: its bitcode, with the flags that say what
// its native half is compiled for; a file that holds no bitcode, or bitcode
// without both flags, is neither kind of runtime.
static mlir::FailureOr<std::variant<Archived, Prepared>>
readPrepared(llvm::StringRef path, const llvm::MemoryBuffer &buffer,
             llvm::LLVMContext &llvmContext, mlir::Location at) {
  auto neither = [&]() -> mlir::InFlightDiagnostic {
    mlir::InFlightDiagnostic diagnostic = mlir::emitError(at);
    diagnostic << "runtime " << path
               << " is neither the archive --prepare-runtime reads nor a runtime it wrote: ";
    return diagnostic;
  };
  std::unique_ptr<llvm::MemoryBuffer> beside;
  auto bitcode = preparedBitcode(buffer.getMemBufferRef(), path, beside);
  if (!bitcode)
    return neither() << llvm::toString(bitcode.takeError());
  auto module = llvm::parseBitcodeFile(*bitcode, llvmContext);
  if (!module)
    return mlir::emitError(at) << "runtime " << path << ": " << llvm::toString(module.takeError());
  if (mlir::failed(onProgramTriple(**module, path, at)))
    return mlir::failure();
  // The CPU and features --prepare-runtime records the native half is
  // compiled for, as the module's flags.
  auto *cpu = llvm::dyn_cast_or_null<llvm::MDString>((*module)->getModuleFlag(preparedCpuFlag));
  auto *features =
      llvm::dyn_cast_or_null<llvm::MDString>((*module)->getModuleFlag(preparedFeaturesFlag));
  if (!cpu || !features)
    return neither() << "its bitcode records no CPU it was prepared for";
  PreparedFor target{cpu->getString().str(), features->getString().str()};
  return std::variant<Archived, Prepared>(Prepared{std::move(*module), std::move(target)});
}

mlir::FailureOr<std::variant<Archived, Prepared>>
idr::driver::readRuntime(llvm::StringRef path, llvm::LLVMContext &llvmContext,
                         const llvm::Triple &triple, const llvm::DataLayout &layout,
                         mlir::MLIRContext &context) {
  mlir::Location at = mlir::UnknownLoc::get(&context);
  auto buffer = llvm::MemoryBuffer::getFile(path, /*IsText=*/false,
                                            /*RequiresNullTerminator=*/false);
  if (!buffer)
    return mlir::emitError(at) << "cannot read runtime " << path << ": "
                               << buffer.getError().message();
  // The file's kind, read off it once: an archive, or what
  // --prepare-runtime wrote.
  mlir::FailureOr<std::variant<Archived, Prepared>> runtime =
      llvm::identify_magic((*buffer)->getBuffer()) == llvm::file_magic::archive
          ? readArchive(path, **buffer, llvmContext, triple, layout, at)
          : readPrepared(path, **buffer, llvmContext, at);
  if (mlir::failed(runtime))
    return mlir::failure();
  std::visit([](auto &read) { llvm::StripDebugInfo(*read.module); }, *runtime);
  return runtime;
}
