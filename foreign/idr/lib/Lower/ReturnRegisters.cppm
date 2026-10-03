// idr.lower:returnRegisters: whether a result of a `tailcc` function comes
// back in registers, as the target's lowering of calls decides.

export module idr.lower:returnRegisters;

import idr.mlir;

using namespace mlir;

namespace idr::lower {

// Whether a result of a `tailcc` function comes back in registers: what the
// target's lowering of calls decides (TargetLowering::CanLowerReturn), asked
// through the code generator's view of a function that returns the type, of
// a machine for the #llvm.target of the module or of the first module around
// it that has one, the program's. A module with none (a test's) is asked of
// this machine's triple and the generic CPU, which the JIT compiles it for.
class ReturnRegisters {
public:
  explicit ReturnRegisters(Operation *module) : scope(module) {}

  // None when there is no machine for the target.
  std::optional<bool> fit(Type type) {
    if (isa<LLVM::LLVMVoidType>(type))
      return true;
    if (auto it = answers.find(type); it != answers.end())
      return it->second;
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
    bool fits =
        lowering.CanLowerReturn(llvm::CallingConv::Tail, mf, /*isVarArg=*/false, outs, context,
                                translated);
    info->deleteMachineFunctionFor(*fn);
    fn->eraseFromParent();
    answers[type] = fits;
    return fits;
  }

private:
  LogicalResult prepare() {
    MLIRContext *ctx = scope->getContext();
    LLVM::TargetAttr target;
    for (Operation *op = scope; op && !target; op = op->getParentOp())
      target = op->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
    if (!target)
      target = LLVM::TargetAttr::get(ctx, StringAttr::get(ctx, llvm::sys::getProcessTriple()),
                                     StringAttr::get(ctx, "generic"), LLVM::TargetFeaturesAttr());
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

  Operation *scope;
  llvm::LLVMContext context;
  std::unique_ptr<llvm::TargetMachine> machine;
  std::unique_ptr<llvm::Module> probe;
  std::unique_ptr<llvm::MachineModuleInfo> info;
  std::unique_ptr<LLVM::TypeToLLVMIRTranslator> types;
  DenseMap<Type, bool> answers;
};

} // namespace idr::lower
