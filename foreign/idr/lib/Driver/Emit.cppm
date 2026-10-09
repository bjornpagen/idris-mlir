// idr.driver:emit: object code for a module, into the output file.
export module idr.driver:emit;

import idr.mlir;

import :report;
import :writeoutput;

export namespace idr::driver {

// Object code for the module, into the output file.
bool emit(llvm::Module &module, llvm::TargetMachine &machine) {
  return writeOutput([&](llvm::raw_ostream &os) {
    auto *pwrite = static_cast<llvm::raw_pwrite_stream *>(&os);
    llvm::legacy::PassManager codegen;
    if (machine.addPassesToEmitFile(codegen, *pwrite, nullptr, llvm::CodeGenFileType::ObjectFile)) {
      Report() << "the target cannot emit object files";
      return false;
    }
    codegen.run(module);
    return true;
  });
}

} // namespace idr::driver
