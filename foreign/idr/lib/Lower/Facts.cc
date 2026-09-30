// The facts idr-lower hands LLVM at function boundaries (Lower/Facts.h).

#include "Lower/Facts.h"

using namespace mlir;

namespace idr::lower {

namespace {

// Whether a value of `type` is one pointer to a cell: a box, a closure or a
// string. Static data and live cells alike are 8-aligned and start with an
// 8-byte header.
bool isCell(Type type) { return isa<BoxType, FnType, StrType>(unrestricted(type)); }

// The attributes of a pointer to a cell.
SmallVector<NamedAttribute> cellFacts(Builder &b) {
  return {b.getNamedAttr(LLVM::LLVMDialect::getNonNullAttrName(), b.getUnitAttr()),
          b.getNamedAttr(LLVM::LLVMDialect::getAlignAttrName(), b.getI64IntegerAttr(8)),
          b.getNamedAttr(LLVM::LLVMDialect::getDereferenceableAttrName(), b.getI64IntegerAttr(8))};
}

// The facts of each component of a value of `type`, in order: a cell's
// pointer, and an unboxed sum's tag, which is below its number of
// constructors.
SmallVector<SmallVector<NamedAttribute>> componentFacts(Type type, bool mayBeNull,
                                                        Layouts &layouts, Builder &b) {
  SmallVector<SmallVector<NamedAttribute>> facts(layouts.components(type).size());
  if (isCell(type)) {
    if (!mayBeNull)
      facts.front() = cellFacts(b);
    return facts;
  }
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data)
    return facts;
  const SumLayout &layout = layouts.sum(data.getName().getAttr());
  if (!layout.tag)
    return facts;
  unsigned width = layout.tag.getIntOrFloatBitWidth();
  auto count = static_cast<uint64_t>(
      layouts.getModule().lookupSymbol<DataOp>(data.getName().getAttr()).getCtors().size());
  // A tag type that the constructors fill has no range to state.
  if (count < (uint64_t{1} << width))
    facts.front().push_back(b.getNamedAttr(
        LLVM::LLVMDialect::getRangeAttrName(),
        LLVM::ConstantRangeAttr::get(b.getContext(), width, 0, static_cast<int64_t>(count))));
  return facts;
}

} // namespace

Facts::Facts(ModuleOp m) : module(m) {
  for (auto fn : module.getOps<func::FuncOp>())
    signatures[fn] = fn.getFunctionType();
  SymbolTable symbols(module);
  module.walk([&](func::CallOp call) {
    auto callee = symbols.lookup<func::FuncOp>(call.getCallee());
    if (!callee)
      return;
    for (OpOperand &operand : call->getOpOperands())
      if (operand.get().getDefiningOp<ub::PoisonOp>())
        poisoned.insert({callee, operand.getOperandNumber()});
  });
}

void Facts::apply(Layouts &layouts) {
  Builder b(module.getContext());
  for (auto fn : module.getOps<func::FuncOp>()) {
    auto it = signatures.find(fn);
    if (it == signatures.end())
      continue;
    FunctionType before = it->second;
    unsigned at = 0;
    for (auto [index, type] : llvm::enumerate(before.getInputs())) {
      bool mayBeNull = poisoned.contains({fn, static_cast<unsigned>(index)});
      for (const SmallVector<NamedAttribute> &facts :
           componentFacts(type, mayBeNull, layouts, b)) {
        for (const NamedAttribute &fact : facts)
          fn.setArgAttr(at, fact.getName(), fact.getValue());
        ++at;
      }
    }
    assert(at == fn.getNumArguments() && "the conversion made one parameter per component");
    // A result of several components becomes one struct in LLVM, which
    // takes no such facts.
    if (before.getNumResults() == 1 && fn.getNumResults() == 1 && isCell(before.getResult(0)))
      for (const NamedAttribute &fact : cellFacts(b))
        fn.setResultAttr(0, fact.getName(), fact.getValue());
  }
}

} // namespace idr::lower
