// idr.driver:markannotated: the runtime's annotations, as marks on its
// functions.
export module idr.driver:markannotated;

import idr.mlir;

import :marks;

export namespace idr::driver {

// Turns the runtime's annotations of a member's functions into marks.
void markAnnotated(llvm::Module &member) {
  const llvm::GlobalVariable *annotations = member.getNamedGlobal("llvm.global.annotations");
  auto *entries = annotations && annotations->hasInitializer()
                      ? llvm::dyn_cast<llvm::ConstantArray>(annotations->getInitializer())
                      : nullptr;
  if (!entries)
    return;
  for (const llvm::Use &entry : entries->operands()) {
    auto *fields = llvm::dyn_cast<llvm::ConstantStruct>(entry.get());
    if (!fields || fields->getNumOperands() < 2)
      continue;
    auto *function = llvm::dyn_cast<llvm::Function>(fields->getOperand(0)->stripPointerCasts());
    auto *text = llvm::dyn_cast<llvm::GlobalVariable>(fields->getOperand(1)->stripPointerCasts());
    auto *data = text && text->hasInitializer()
                     ? llvm::dyn_cast<llvm::ConstantDataArray>(text->getInitializer())
                     : nullptr;
    if (!function || !data || !data->isCString())
      continue;
    llvm::StringRef mark = data->getAsCString();
    if (mark == baselineMark || mark == compilerMark)
      function->addFnAttr(mark);
  }
}

} // namespace idr::driver
