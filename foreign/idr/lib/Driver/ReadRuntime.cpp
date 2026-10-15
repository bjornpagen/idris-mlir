// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime read from what --runtime names: prepared bitcode, or the
// archive's members, each checked and stripped of what only separate
// compilation needs, linked into one module.

#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Runtime.h"
#include "idr/IR/IdrDialect.h"

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
#include "llvm/IR/Module.h"
#include "llvm/Linker/Linker.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/IRObjectFile.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/MemoryBufferRef.h"
#include "llvm/Support/Path.h"
#include "llvm/TargetParser/Triple.h"

#include <memory>
#include <string>
#include <utility>
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
static bool readMembers(const llvm::MemoryBuffer &archiveBuffer, std::vector<Member> &members) {
  auto archive = llvm::object::Archive::create(archiveBuffer.getMemBufferRef());
  if (!archive) {
    Report() << "runtime " << runtimePath << ": " << llvm::toString(archive.takeError());
    return false;
  }
  llvm::Error error = llvm::Error::success();
  for (const llvm::object::Archive::Child &child : (*archive)->children(error)) {
    auto name = child.getName();
    auto buffer = child.getMemoryBufferRef();
    if (!name || !buffer) {
      Report() << "runtime " << runtimePath << ": unreadable member";
      llvm::consumeError(name.takeError());
      llvm::consumeError(buffer.takeError());
      llvm::consumeError(std::move(error));
      return false;
    }
    auto bitcode = llvm::object::IRObjectFile::findBitcodeInMemBuffer(*buffer);
    if (!bitcode) {
      Report() << "runtime member " << *name
               << " carries no bitcode, which every member of the runtime's archive must: "
               << llvm::toString(bitcode.takeError());
      llvm::consumeError(std::move(error));
      return false;
    }
    members.push_back({name->str(), *bitcode});
  }
  if (error) {
    Report() << "runtime " << runtimePath << ": " << llvm::toString(std::move(error));
    return false;
  }
  return true;
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
// dropped too. Prepared bitcode passes through unchanged: it is a member
// that was prepared already.
static bool prepareMember(llvm::Module &member, llvm::StringRef name) {
  if (!sameTarget(member.getTargetTriple(), llvm::Triple(targetTriple))) {
    Report() << "runtime member " << name << " is compiled for " << member.getTargetTriple().str()
             << ", and programs for " << targetTriple;
    return false;
  }
  markAnnotated(member);
  if (llvm::GlobalVariable *annotations = member.getNamedGlobal("llvm.global.annotations"))
    annotations->eraseFromParent();
  // An empty list of constructors, which clang writes for some translation
  // units, lists none.
  for (llvm::StringRef array : {"llvm.global_ctors", "llvm.global_dtors"})
    if (llvm::GlobalVariable *global = member.getNamedGlobal(array)) {
      if (llvm::cast<llvm::ArrayType>(global->getValueType())->getNumElements() == 0) {
        global->eraseFromParent();
        continue;
      }
      Report() << "runtime member " << name
               << " has static constructors or destructors; the runtime must be "
                  "constant-initialized";
      return false;
    }
  for (llvm::StringRef array : {"llvm.used", "llvm.compiler.used"})
    if (llvm::GlobalVariable *global = member.getNamedGlobal(array))
      global->eraseFromParent();
  for (const llvm::GlobalVariable &global : member.globals())
    if (global.hasAppendingLinkage()) {
      Report() << idr::refusalHead(idr::Rule::Runtime) << ": runtime member " << name
               << " defines the appending global " << global.getName();
      return false;
    }
  return true;
}

// The prepared runtime's bitcode, where its container keeps it: a bitcode
// file is itself; an object, of any format LLVM's object reader knows,
// holds it in the section the container names, or, with none named, the
// file beside it does, which `beside` then holds.
static llvm::Expected<llvm::MemoryBufferRef>
preparedBitcode(llvm::MemoryBufferRef file, std::unique_ptr<llvm::MemoryBuffer> &beside) {
  if (llvm::identify_magic(file.getBuffer()) == llvm::file_magic::bitcode)
    return file;
  if (runtimeBitcodeSection.empty()) {
    std::string path = besideObject(runtimePath);
    auto read = llvm::MemoryBuffer::getFile(path, /*IsText=*/false,
                                            /*RequiresNullTerminator=*/false);
    if (!read)
      return llvm::createStringError(read.getError(), "cannot read " + path);
    beside = std::move(*read);
    return beside->getMemBufferRef();
  }
  auto object = llvm::object::ObjectFile::createObjectFile(file);
  if (!object)
    return object.takeError();
  for (const llvm::object::SectionRef &section : (*object)->sections()) {
    llvm::Expected<llvm::StringRef> name = section.getName();
    if (!name)
      return name.takeError();
    if (*name != runtimeBitcodeSection)
      continue;
    llvm::Expected<llvm::StringRef> contents = section.getContents();
    if (!contents)
      return contents.takeError();
    return llvm::MemoryBufferRef(*contents, file.getBufferIdentifier());
  }
  return llvm::createStringError("the object has no section " + runtimeBitcodeSection);
}

std::string idr::driver::besideObject(llvm::StringRef object) {
  llvm::SmallString<128> path(object);
  llvm::sys::path::replace_extension(path, "bc");
  return path.str().str();
}

std::unique_ptr<llvm::Module> idr::driver::readRuntime(llvm::LLVMContext &context,
                                                       const llvm::Triple &triple,
                                                       const llvm::DataLayout &layout) {
  auto buffer = llvm::MemoryBuffer::getFile(runtimePath, /*IsText=*/false,
                                            /*RequiresNullTerminator=*/false);
  if (!buffer) {
    Report() << "cannot read runtime " << runtimePath << ": " << buffer.getError().message();
    return nullptr;
  }
  std::unique_ptr<llvm::Module> runtime;
  if (llvm::identify_magic((*buffer)->getBuffer()) != llvm::file_magic::archive) {
    std::unique_ptr<llvm::MemoryBuffer> beside;
    auto bitcode = preparedBitcode((*buffer)->getMemBufferRef(), beside);
    if (!bitcode) {
      Report() << "runtime " << runtimePath
               << " carries no bitcode where its container keeps it; the runtime is what "
                  "--prepare-runtime wrote, or the archive it reads: "
               << llvm::toString(bitcode.takeError());
      return nullptr;
    }
    auto module = llvm::parseBitcodeFile(*bitcode, context);
    if (!module) {
      Report() << "runtime " << runtimePath << ": " << llvm::toString(module.takeError());
      return nullptr;
    }
    if (!prepareMember(**module, runtimePath))
      return nullptr;
    runtime = std::move(*module);
  } else {
    std::vector<Member> members;
    if (!readMembers(**buffer, members))
      return nullptr;
    runtime = std::make_unique<llvm::Module>("idris-mlir-runtime", context);
    runtime->setTargetTriple(triple);
    runtime->setDataLayout(layout);
    llvm::Linker runtimeLinker(*runtime);
    for (const Member &member : members) {
      auto module = llvm::parseBitcodeFile(member.bitcode, context);
      if (!module) {
        Report() << "runtime member " << member.name << ": " << llvm::toString(module.takeError());
        return nullptr;
      }
      if (!prepareMember(**module, member.name))
        return nullptr;
      if (runtimeLinker.linkInModule(std::move(*module))) {
        Report() << "runtime member " << member.name << " does not link with the members before it";
        return nullptr;
      }
    }
  }
  llvm::StripDebugInfo(*runtime);
  return runtime;
}
