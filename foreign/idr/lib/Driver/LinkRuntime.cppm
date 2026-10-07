// idr.driver:linkruntime: the program and the runtime, joined.
export module idr.driver:linkruntime;

import idr.mlir;

import :namesapart;
import :nativeruns;
import :options;
import :readruntime;
import :report;

export namespace idr::driver {

// The program and the runtime become one module, linked once with
// LinkOnlyNeeded: only what the program reaches joins it. From the prepared
// runtime, when its native half runs on the program's CPU, the bodies join
// as they are, available_externally: the optimizer inlines what pays and
// drops the rest, which the link line resolves in the native half, where
// every piece of runtime state has its one definition. Otherwise (the
// archive, or a program for a smaller CPU) every body the program reaches
// becomes a definition of its own and compiles with the program, so that its
// object is the whole program and the link line's runtime goes unused.
bool linkRuntime(llvm::Module &program, const llvm::Target &target, const llvm::Triple &triple,
                 const llvm::TargetMachine &machine) {
  if (runtimePath.empty())
    return true;
  std::unique_ptr<llvm::Module> runtime =
      readRuntime(program.getContext(), program.getTargetTriple(), program.getDataLayout());
  if (!runtime || !namesApart(program, *runtime))
    return false;
  if (!nativeRuns(*runtime, target, triple, machine))
    for (llvm::GlobalValue &value : runtime->global_values())
      if (value.hasAvailableExternallyLinkage())
        value.setLinkage(llvm::GlobalValue::ExternalLinkage);
  if (llvm::Linker::linkModules(program, std::move(runtime), llvm::Linker::LinkOnlyNeeded)) {
    Report() << "internal error: linking the runtime into the program failed";
    return false;
  }
  return true;
}

} // namespace idr::driver
