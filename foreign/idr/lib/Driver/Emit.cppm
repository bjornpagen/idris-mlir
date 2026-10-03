// idr.driver:emit: machine code for a module, into the output file.
export module idr.driver:emit;

import idr.mlir;

import :writeoutput;

export namespace idr::driver {

// Machine code for the module, of the kind --emit asks, into the output file.
bool emit(llvm::Module &module, llvm::TargetMachine &machine, llvm::CodeGenFileType fileType) {
  return writeOutput([&](llvm::raw_ostream &os) {
    auto *pwrite = static_cast<llvm::raw_pwrite_stream *>(&os);
    llvm::legacy::PassManager codegen;
    if (machine.addPassesToEmitFile(codegen, *pwrite, nullptr, fileType)) {
      llvm::errs() << "idris-mlir-cc: the target cannot emit object files\n";
      return false;
    }
    codegen.run(module);
    return true;
  });
}

} // namespace idr::driver
