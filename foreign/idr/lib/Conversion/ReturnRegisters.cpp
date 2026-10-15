// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
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
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Target/TargetMachine.h"

using namespace mlir;

namespace idr::conversion {

FailureOr<ReturnRegisters> ReturnRegisters::of(Operation *module) {
  LLVM::TargetAttr target;
  for (Operation *op = module; op && !target; op = op->getParentOp())
    target = op->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return module->emitError("internal error: the module lost its #llvm.target");
  LLVM::detail::initializeBackendsOnce();
  FailureOr<std::unique_ptr<llvm::TargetMachine>> machine =
      LLVM::detail::getTargetMachine(cast<LLVM::TargetAttrInterface>(target));
  if (failed(machine) || !*machine)
    return module->emitError("internal error: idr-tail-calls: no target machine for ")
           << target.getTriple();
  return ReturnRegisters(std::make_unique<llvm::LLVMContext>(), std::move(*machine));
}

ReturnRegisters::ReturnRegisters(std::unique_ptr<llvm::LLVMContext> c,
                                 std::unique_ptr<llvm::TargetMachine> m)
    : context(std::move(c)), machine(std::move(m)),
      probe(std::make_unique<llvm::Module>("idr-tail-calls", *context)),
      info(std::make_unique<llvm::MachineModuleInfo>(machine.get())),
      types(std::make_unique<LLVM::TypeToLLVMIRTranslator>(*context)) {
  probe->setTargetTriple(machine->getTargetTriple());
  probe->setDataLayout(machine->createDataLayout());
}

ReturnRegisters::ReturnRegisters(ReturnRegisters &&) noexcept = default;
ReturnRegisters &ReturnRegisters::operator=(ReturnRegisters &&) noexcept = default;
ReturnRegisters::~ReturnRegisters() = default;

bool ReturnRegisters::fit(Type type) {
  if (isa<LLVM::LLVMVoidType>(type))
    return true;
  auto [answer, fresh] = answers.try_emplace(type, false);
  if (!fresh)
    return answer->second;
  llvm::Type *translated = types->translateType(type);
  auto *fn = llvm::Function::Create(llvm::FunctionType::get(translated, false),
                                    llvm::GlobalValue::InternalLinkage, "probe", *probe);
  fn->setCallingConv(llvm::CallingConv::Tail);
  llvm::MachineFunction &mf = info->getOrCreateMachineFunction(*fn);
  const llvm::TargetLowering &lowering = *mf.getSubtarget().getTargetLowering();
  SmallVector<llvm::ISD::OutputArg, 8> outs;
  llvm::GetReturnInfo(llvm::CallingConv::Tail, translated, llvm::AttributeList(), outs, lowering,
                      probe->getDataLayout());
  answer->second = lowering.CanLowerReturn(llvm::CallingConv::Tail, mf, /*isVarArg=*/false, outs,
                                           *context, translated);
  info->deleteMachineFunctionFor(*fn);
  fn->eraseFromParent();
  return answer->second;
}

} // namespace idr::conversion
