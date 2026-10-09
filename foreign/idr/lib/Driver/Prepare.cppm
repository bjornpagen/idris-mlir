// idr.driver:prepare: --prepare-runtime, the runtime optimized and compiled
// once for every program.
export module idr.driver:prepare;

import idr.mlir;
import idr.target;

import :besideobject;
import :emit;
import :externalize;
import :isprepared;
import :marks;
import :options;
import :report;
import :readruntime;
import :retarget;

export namespace idr::driver {

// --prepare-runtime: the archive's members, joined, raised to the target's
// CPU and optimized as a program is, with everything but the C ABI programs
// reach (idris_rt_*, less the compiler's own entries) internal. Each
// function first records what it was compiled for, so that retarget can
// raise it to any CPU from there; the optimization copies the marks into
// every function it makes from another (a clone, a thunk), and one without
// them could not be retargeted, so none may be left.
//
// The result is an object whose native code is what every executable's link
// line takes, and the same module as bitcode with every definition
// available_externally, which is what joins each program's module
// (linkRuntime), kept where the target entry's container says: in a section
// of the object that every link leaves out, as a fat LTO object keeps its
// bitcode, or in a file beside it. The two halves come from the one module,
// so they name the same symbols: a body the program's optimizer inlines
// becomes program code, one it does not is dropped and resolves to the
// native half, and runtime state (the allocator's thread-locals, the output
// buffer, the live-cell count) is defined once, in the native half,
// whichever bodies were inlined.
int prepare(const llvm::Target &target, const llvm::Triple &triple) {
  // Only these formats mark a section for every link to leave out
  // (embedBufferInModule's exclusion); in any other, the bitcode would ship
  // in every executable.
  if (!runtimeBitcodeSection.empty() && !triple.isOSBinFormatELF() && !triple.isOSBinFormatCOFF()) {
    Report() << "unsupported --runtime-bitcode-section=" << runtimeBitcodeSection << ": a "
             << triple.str()
             << " object has no section every link leaves out; the bitcode goes beside the "
                "object (--runtime-bitcode-section='')";
    return usage;
  }
  std::unique_ptr<llvm::TargetMachine> machine =
      idr::target::machine(target, triple, targetCpu, "");
  if (!machine) {
    Report() << "internal error: no target machine for " << targetTriple;
    return failure;
  }
  llvm::LLVMContext context;
  std::unique_ptr<llvm::Module> runtime = readRuntime(context, triple, machine->createDataLayout());
  if (!runtime)
    return failure;
  if (isPrepared(*runtime)) {
    Report() << "runtime " << runtimePath
             << " is prepared already; --prepare-runtime reads the archive";
    return usage;
  }
  llvm::StringMap<std::pair<std::string, std::string>> compiledFor;
  for (const llvm::Function &function : *runtime)
    if (!function.isDeclaration())
      compiledFor[function.getName()] = {
          function.getFnAttribute("target-cpu").getValueAsString().str(),
          function.getFnAttribute("target-features").getValueAsString().str()};
  retarget(*runtime, *machine);
  for (llvm::Function &function : *runtime)
    if (auto found = compiledFor.find(function.getName()); found != compiledFor.end()) {
      function.addFnAttr(cpuMark, found->second.first);
      function.addFnAttr(featuresMark, found->second.second);
    }
  // Programs reach the C ABI, but the compiler's part of it.
  llvm::internalizeModule(*runtime, [](const llvm::GlobalValue &value) {
    auto *function = llvm::dyn_cast<llvm::Function>(&value);
    return value.getName().starts_with("idris_rt_") &&
           !(function && function->hasFnAttribute(compilerMark));
  });
  idr::target::optimize(*runtime, *machine);
  for (const llvm::Function &function : *runtime)
    if (!function.isDeclaration() &&
        (!function.hasFnAttribute(cpuMark) || !function.hasFnAttribute(featuresMark))) {
      Report() << "internal error: the optimization made the runtime function " << function.getName()
               << " without the marks of what it was compiled for";
      return failure;
    }
  if (!externalize(*runtime))
    return failure;
  runtime->addModuleFlag(llvm::Module::Error, preparedCpuFlag,
                         llvm::MDString::get(context, machine->getTargetCPU()));
  runtime->addModuleFlag(llvm::Module::Error, preparedFeaturesFlag,
                         llvm::MDString::get(context, machine->getTargetFeatureString()));
  // The bitcode half: the same module, every definition available_externally.
  std::string bitcode;
  {
    for (llvm::GlobalValue &value : runtime->global_values())
      if (!value.isDeclaration())
        value.setLinkage(llvm::GlobalValue::AvailableExternallyLinkage);
    llvm::raw_string_ostream os(bitcode);
    llvm::WriteBitcodeToFile(*runtime, os);
    for (llvm::GlobalValue &value : runtime->global_values())
      if (value.hasAvailableExternallyLinkage())
        value.setLinkage(llvm::GlobalValue::ExternalLinkage);
  }
  // Kept only once the object is written too.
  std::unique_ptr<llvm::ToolOutputFile> beside;
  if (runtimeBitcodeSection.empty()) {
    std::error_code error;
    std::string path = besideObject(outputPath);
    beside = std::make_unique<llvm::ToolOutputFile>(path, error, llvm::sys::fs::OF_None);
    if (error) {
      cannotWrite(path, error);
      return failure;
    }
    beside->os() << bitcode;
  } else {
    llvm::embedBufferInModule(*runtime, llvm::MemoryBufferRef(bitcode, "idris_rt"),
                              runtimeBitcodeSection);
  }
  if (!emit(*runtime, *machine))
    return failure;
  if (beside)
    beside->keep();
  return ok;
}

} // namespace idr::driver
