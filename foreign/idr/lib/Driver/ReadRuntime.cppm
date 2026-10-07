// idr.driver:readruntime: the runtime as one module.
export module idr.driver:readruntime;

import idr.mlir;

import :members;
import :report;
import :options;
import :preparedbitcode;
import :preparemember;

export namespace idr::driver {

// The runtime as one module, for the program's triple and data layout: the
// bitcode of what --prepare-runtime wrote, or the members of the archive
// joined, where a symbol two members define is an error. Its debug info
// describes the runtime's C++ sources, not the program: it is most of the
// archive's bitcode, and every program would carry it, so it goes.
std::unique_ptr<llvm::Module> readRuntime(llvm::LLVMContext &context, const llvm::Triple &triple,
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

} // namespace idr::driver
