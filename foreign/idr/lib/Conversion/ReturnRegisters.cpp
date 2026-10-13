// Whether a result of a `tailcc` function comes back in registers.

#include "idr/Conversion/ReturnRegisters.h"

#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Target/LLVMIR/Transforms/TargetUtils.h"
#include "mlir/Target/LLVMIR/TypeToLLVM.h"
#include "llvm/CodeGen/Analysis.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/TargetLowering.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Module.h"
#include "llvm/Target/TargetMachine.h"

using namespace mlir;

namespace idr::conversion {

ReturnRegisters::ReturnRegisters(Operation *module) : scope(module) {}

ReturnRegisters::~ReturnRegisters() = default;

std::optional<bool> ReturnRegisters::fit(Type type) {
  if (isa<LLVM::LLVMVoidType>(type))
    return true;
  if (!machine && failed(prepare()))
    return std::nullopt;
  llvm::Type *translated = types->translateType(type);
  auto *fn = llvm::Function::Create(llvm::FunctionType::get(translated, false),
                                    llvm::GlobalValue::InternalLinkage, "probe", *probe);
  fn->setCallingConv(llvm::CallingConv::Tail);
  llvm::MachineFunction &mf = info->getOrCreateMachineFunction(*fn);
  const llvm::TargetLowering &lowering = *mf.getSubtarget().getTargetLowering();
  SmallVector<llvm::ISD::OutputArg, 8> outs;
  llvm::GetReturnInfo(llvm::CallingConv::Tail, translated, llvm::AttributeList(), outs, lowering,
                      probe->getDataLayout());
  bool fits = lowering.CanLowerReturn(llvm::CallingConv::Tail, mf, /*isVarArg=*/false, outs,
                                      context, translated);
  info->deleteMachineFunctionFor(*fn);
  fn->eraseFromParent();
  return fits;
}

LogicalResult ReturnRegisters::prepare() {
  LLVM::TargetAttr target;
  for (Operation *op = scope; op && !target; op = op->getParentOp())
    target = op->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return scope->emitError("internal error: the module lost its #llvm.target"), failure();
  LLVM::detail::initializeBackendsOnce();
  machine = LLVM::detail::getTargetMachine(cast<LLVM::TargetAttrInterface>(target))
                .value_or(nullptr);
  if (!machine) {
    scope->emitError("internal error: idr-tail-calls: no target machine for ")
        << target.getTriple();
    return failure();
  }
  probe = std::make_unique<llvm::Module>("idr-tail-calls", context);
  probe->setTargetTriple(machine->getTargetTriple());
  probe->setDataLayout(machine->createDataLayout());
  info = std::make_unique<llvm::MachineModuleInfo>(machine.get());
  types = std::make_unique<LLVM::TypeToLLVMIRTranslator>(context);
  return success();
}

} // namespace idr::conversion
