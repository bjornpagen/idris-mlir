// Whether a result of a `tailcc` function comes back in registers, as the
// target's lowering of calls decides.

#ifndef IDR_CONVERSION_RETURNREGISTERS_H
#define IDR_CONVERSION_RETURNREGISTERS_H

#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "llvm/IR/LLVMContext.h"

#include <memory>
#include <optional>

namespace llvm {
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
// it that has one, the program's. A module with none (a test's) is asked of
// this machine's triple and the generic CPU. The machine is made when the
// first type is asked; each type is asked once.
class ReturnRegisters {
public:
  explicit ReturnRegisters(mlir::Operation *module);
  ~ReturnRegisters();

  // None when there is no machine for the target, which is reported.
  std::optional<bool> fit(mlir::Type type);

private:
  mlir::LogicalResult prepare();

  mlir::Operation *scope;
  llvm::LLVMContext context;
  std::unique_ptr<llvm::TargetMachine> machine;
  std::unique_ptr<llvm::Module> probe;
  std::unique_ptr<llvm::MachineModuleInfo> info;
  std::unique_ptr<mlir::LLVM::TypeToLLVMIRTranslator> types;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_RETURNREGISTERS_H
