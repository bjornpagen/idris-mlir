// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a result of a `tailcc` function comes back in registers, as the
// target's lowering of calls decides.

#ifndef IDR_CONVERSION_RETURNREGISTERS_H
#define IDR_CONVERSION_RETURNREGISTERS_H

#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/DenseMap.h"

#include <memory>

namespace llvm {
class LLVMContext;
class MachineModuleInfo;
class Module;
class TargetMachine;
} // namespace llvm

namespace mlir::LLVM {
class TypeToLLVMIRTranslator;
} // namespace mlir::LLVM

namespace idr::conversion {

// Whether a result of a `tailcc` function comes back in registers: what the
// target's lowering of calls decides (TargetLowering::CanLowerReturn), asked
// through the code generator's view of a function that returns the type, of
// a machine for the #llvm.target of the module or of the first module around
// it that has one, the program's. Each type is asked once.
class ReturnRegisters {
public:
  // The answers for the target `module` is in, or a failure, reported,
  // when it has none or LLVM has no machine for it.
  static mlir::FailureOr<ReturnRegisters> of(mlir::Operation *module);

  ReturnRegisters(ReturnRegisters &&) noexcept;
  ReturnRegisters &operator=(ReturnRegisters &&) noexcept;
  ~ReturnRegisters();

  bool fit(mlir::Type type);

private:
  ReturnRegisters(std::unique_ptr<llvm::LLVMContext> context,
                  std::unique_ptr<llvm::TargetMachine> machine);

  // Declared first, so that what refers to it goes before it.
  std::unique_ptr<llvm::LLVMContext> context;
  std::unique_ptr<llvm::TargetMachine> machine;
  std::unique_ptr<llvm::Module> probe;
  std::unique_ptr<llvm::MachineModuleInfo> info;
  std::unique_ptr<mlir::LLVM::TypeToLLVMIRTranslator> types;
  llvm::DenseMap<mlir::Type, bool> answers;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_RETURNREGISTERS_H
