// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's two readers, one per action, each of the one kind of file
// its action takes. --prepare-runtime reads an archive: its members, each
// checked, stripped of what only separate compilation needs and compiled
// for the program's CPU, linked into one module, with the archive's digest.
// A compilation reads what --prepare-runtime wrote: its bitcode, with the
// identity it recorded. The archive is the build's runtime as clang
// compiled it, the one input of preparing; the prepared runtime is the
// output, optimized once, whose native half every executable links. So no
// compilation reads an archive: that would compile the runtime again for
// every program, a second way to the program the prepared runtime makes.

#include "idr/Driver/Options.h"
#include "idr/Driver/Runtime.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Target/Target.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"
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
#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/Attributes.h"
#include "llvm/Linker/Linker.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/IRObjectFile.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/MemoryBufferRef.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/SHA256.h"
#include "llvm/Target/TargetMachine.h"
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
  if (!sameTarget(module.getTargetTriple(), llvm::Triple(idr::target::triple)))
    return mlir::emitError(at) << "runtime member " << name << " is compiled for "
                               << module.getTargetTriple().str() << ", and programs for "
                               << idr::target::triple;
  return mlir::success();
}

// Turns the runtime's annotations of a member's functions, which
// llvm.global.annotations lists, into marks: the baseline's, and the fault
// handler's, whose code runs on the signal stack.
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
    if (mark == baselineMark || mark == handlerMark)
      function->addFnAttr(mark);
  }
}

// A list of features as LLVM writes one ("+a,+b,-c"), each once, in order.
static llvm::SmallVector<llvm::StringRef> featureList(llvm::StringRef features) {
  llvm::SmallVector<llvm::StringRef> list;
  llvm::SplitString(features, list, ",");
  return list;
}

// Every function the member defines, compiled for the program's CPU (see
// Archived, idr/Driver/Runtime.h): the target attributes its unit's flags
// gave it go, so that it takes the program's machine's, as a program
// function does, and it inlines into one, as the inliner judges it (the
// predicates the inliner asks: the target's, the attributes', the library
// calls'), asked of `program`, a function of the module with no
// attributes, which is what the lowering writes of each one these
// predicates read. Of a function compiled for more than the baseline, the
// more is kept on top of the program's features; such a function is called
// where the processor has it, and inlines where the program's CPU has it
// too. A baseline function keeps what it was compiled for.
static mlir::LogicalResult forProgramCpu(llvm::Module &member, llvm::StringRef name,
                                         const llvm::TargetMachine &machine, mlir::Location at) {
  llvm::SmallVector<llvm::StringRef> baseline = featureList(idr::target::baselineCpu.features);
  llvm::Function *program = llvm::Function::Create(
      llvm::FunctionType::get(llvm::Type::getVoidTy(member.getContext()), false),
      llvm::GlobalValue::ExternalLinkage, "", member);
  llvm::TargetLibraryInfoImpl libraries(machine.getTargetTriple());
  llvm::TargetLibraryInfo programLibraries(libraries, program);
  auto refused = [&](llvm::Function &function) {
    program->eraseFromParent();
    return idr::refuse(at, idr::Rule::Runtime)
           << "runtime member " << name << " defines " << function.getName() << ", ";
  };
  for (llvm::Function &function : member) {
    if (function.isDeclaration() || function.hasFnAttribute(baselineMark))
      continue;
    llvm::SmallVector<llvm::StringRef> features =
        featureList(function.getFnAttribute("target-features").getValueAsString());
    llvm::SmallVector<llvm::StringRef> missing = llvm::filter_to_vector(
        baseline, [&](llvm::StringRef feature) { return !llvm::is_contained(features, feature); });
    if (!missing.empty())
      return refused(function) << "which is compiled without the baseline CPU's features "
                               << llvm::join(missing, ",")
                               << ", which the runtime's flags give every function";
    llvm::SmallVector<llvm::StringRef> beyond = llvm::filter_to_vector(
        features, [&](llvm::StringRef feature) { return !llvm::is_contained(baseline, feature); });
    function.removeFnAttr("target-cpu");
    function.removeFnAttr("tune-cpu");
    function.removeFnAttr("target-features");
    if (!beyond.empty()) {
      function.addFnAttr(
          "target-features",
          (idr::target::programCpu.features + llvm::Twine(",") + llvm::join(beyond, ",")).str());
      continue;
    }
    if (!machine.getTargetTransformInfo(function).areInlineCompatible(program, &function))
      return refused(function) << "which does not inline into a program function: their target "
                                  "features conflict";
    if (!llvm::AttributeFuncs::areInlineCompatible(*program, function))
      return refused(function) << "which does not inline into a program function: its attributes "
                                  "conflict with a program function's";
    if (!programLibraries.areInlineCompatible(llvm::TargetLibraryInfo(libraries, &function),
                                              /*AllowCallerSuperset=*/false))
      return refused(function) << "which does not inline into a program function: its library "
                                  "calls (no-builtin) differ from a program function's";
  }
  program->eraseFromParent();
  return mlir::success();
}

// The runtime is constant-initialized, and its `used` markers exist for
// separate compilation only. LinkOnlyNeeded always links appending globals,
// so constructors would run in every program, and `used` would keep dead
// runtime code (and its libc calls) in every executable: constructors are
// rejected, `used` markers dropped. Annotations become marks, then are
// dropped too. Every definition is then compiled for the program's CPU.
static mlir::LogicalResult prepareMember(llvm::Module &member, llvm::StringRef name,
                                         const llvm::TargetMachine &machine, mlir::Location at) {
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
  return forProgramCpu(member, name, machine, at);
}

std::string idr::driver::besideObject(llvm::StringRef object) {
  llvm::SmallString<128> path(object);
  llvm::sys::path::replace_extension(path, "bc");
  return path.str().str();
}

// The SHA-256 digest of `bytes`, in lowercase hex, as the build writes it.
static std::string digestOf(llvm::StringRef bytes) {
  return llvm::toHex(llvm::SHA256::hash(llvm::arrayRefFromStringRef(bytes)), /*LowerCase=*/true);
}

mlir::FailureOr<Archived> idr::driver::readArchive(llvm::StringRef path,
                                                  llvm::LLVMContext &llvmContext,
                                                  const llvm::TargetMachine &machine,
                                                  mlir::MLIRContext &context) {
  mlir::Location at = mlir::UnknownLoc::get(&context);
  auto buffer = llvm::MemoryBuffer::getFile(path, /*IsText=*/false,
                                            /*RequiresNullTerminator=*/false);
  if (!buffer)
    return mlir::emitError(at) << "cannot read runtime " << path << ": "
                               << buffer.getError().message();
  mlir::FailureOr<std::vector<Member>> members = readMembers(path, **buffer, at);
  if (mlir::failed(members))
    return mlir::failure();
  auto runtime = std::make_unique<llvm::Module>("idris-mlir-runtime", llvmContext);
  runtime->setTargetTriple(machine.getTargetTriple());
  runtime->setDataLayout(machine.createDataLayout());
  llvm::Linker runtimeLinker(*runtime);
  for (const Member &member : *members) {
    auto module = llvm::parseBitcodeFile(member.bitcode, llvmContext);
    if (!module)
      return mlir::emitError(at) << "runtime member " << member.name << ": "
                                 << llvm::toString(module.takeError());
    if (mlir::failed(prepareMember(**module, member.name, machine, at)))
      return mlir::failure();
    if (runtimeLinker.linkInModule(std::move(*module)))
      return mlir::emitError(at) << "runtime member " << member.name
                                 << " does not link with the members before it";
  }
  // The debug info of the runtime's C++ sources describes no program, and
  // is most of the members' bitcode: it goes here, before anything is
  // prepared, so the prepared runtime carries none for a program to join.
  llvm::StripDebugInfo(*runtime);
  return Archived{std::move(runtime),
                  Identity{digestOf((*buffer)->getBuffer()), idr::target::programCpu.name.str(),
                           idr::target::programCpu.features.str()}};
}

mlir::FailureOr<Prepared> idr::driver::readPrepared(llvm::StringRef path,
                                                    llvm::LLVMContext &llvmContext,
                                                    mlir::MLIRContext &context) {
  mlir::Location at = mlir::UnknownLoc::get(&context);
  auto notPrepared = [&]() -> mlir::InFlightDiagnostic {
    mlir::InFlightDiagnostic diagnostic = mlir::emitError(at);
    diagnostic << "runtime " << path << " is not one --prepare-runtime wrote: ";
    return diagnostic;
  };
  std::string besidePath = besideObject(path);
  auto beside = llvm::MemoryBuffer::getFile(besidePath, /*IsText=*/false,
                                            /*RequiresNullTerminator=*/false);
  if (!beside)
    return notPrepared() << "cannot read " << besidePath << ": " << beside.getError().message();
  auto module = llvm::parseBitcodeFile((*beside)->getMemBufferRef(), llvmContext);
  if (!module)
    return mlir::emitError(at) << "runtime " << path << ": " << llvm::toString(module.takeError());
  auto flag = [&](llvm::StringRef name) {
    return llvm::dyn_cast_or_null<llvm::MDString>((*module)->getModuleFlag(name));
  };
  llvm::MDString *archive = flag(preparedArchiveFlag), *cpu = flag(preparedCpuFlag),
                 *features = flag(preparedFeaturesFlag);
  if (!archive || !cpu || !features)
    return notPrepared() << "its bitcode records no identity";
  Identity identity{archive->getString().str(), cpu->getString().str(),
                    features->getString().str()};
  return Prepared{std::move(*module), std::move(identity)};
}
