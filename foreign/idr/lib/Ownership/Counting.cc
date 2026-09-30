// Which values hold references, and what each use does with them.

#include "Ownership/Ownership.h"

using namespace mlir;

namespace idr::ownership {

bool Counting::counted(Type type) {
  // A linear value is counted as the value it is; its quantity decides
  // only how it is used.
  type = unrestricted(type);
  if (isa<StrType, BigType, NatType, BoxType, FnType, TokenType>(type))
    return true;
  auto data = dyn_cast<DataType>(type);
  if (!data)
    return false;
  if (datas.empty())
    for (Region &region : module->getRegions())
      for (Block &block : region)
        for (auto decl : block.getOps<DataOp>())
          datas[decl.getSymNameAttr()] = decl;
  Attribute name = data.getName().getAttr();
  auto known = sums.find(name);
  if (known != sums.end())
    return known->second;
  // Containment through unboxed sums is acyclic; the provisional answer
  // only guards a module the verifier has yet to reject.
  sums[name] = false;
  DataOp decl = datas.lookup(name);
  bool any = false;
  if (decl)
    for (CtorOp ctor : decl.getCtors())
      for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
        any = any || counted(field);
  sums[name] = any;
  return any;
}

Value readFrom(Value value) {
  if (auto field = value.getDefiningOp<FieldOp>())
    return field.getValue();
  auto arg = dyn_cast<BlockArgument>(value);
  if (!arg)
    return nullptr;
  if (auto match = dyn_cast_or_null<MatchOp>(arg.getOwner()->getParentOp()))
    return match.getScrutinee();
  return nullptr;
}

bool isStatic(Value value) {
  for (; value; value = readFrom(value)) {
    Operation *def = value.getDefiningOp();
    if (def && (def->hasTrait<OpTrait::ConstantLike>() || isa<ub::PoisonOp>(def)))
      return true;
  }
  return false;
}

bool usedAfter(Value value, Operation *op) {
  Block *home = value.getParentBlock();
  for (Operation *at = op; at; at = at->getParentOp()) {
    Block *block = at->getBlock();
    if (!block)
      return false;
    for (Operation *user : value.getUsers()) {
      Operation *top = block->findAncestorOpInBlock(*user);
      if (top && at->isBeforeInBlock(top))
        return true;
    }
    if (block == home || isa<func::FuncOp>(block->getParentOp()))
      return false;
  }
  return false;
}

bool isBorrowed(func::FuncOp fn, unsigned index) {
  return index < fn.getNumArguments() && fn.getArgAttr(index, borrowedAttr);
}

func::FuncOp callee(func::CallOp call, SymbolTableCollection &symbols) {
  return symbols.lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
}

Use useOf(OpOperand &operand, SymbolTableCollection &symbols) {
  Operation *op = operand.getOwner();
  if (auto call = dyn_cast<func::CallOp>(op)) {
    func::FuncOp fn = callee(call, symbols);
    return fn && isBorrowed(fn, operand.getOperandNumber()) ? Use::Borrow : Use::Consume;
  }
  if (auto apply = dyn_cast<ApplyOp>(op))
    return operand.get() == apply.getCallee() && operand.getOperandNumber() == 0 ? Use::Borrow
                                                                                : Use::Consume;
  // A linear value moves into its one use and out of it again, with its
  // reference; so does a natural into the Integer it is.
  if (isa<func::ReturnOp, YieldOp, ConOp, ClosureOp, ReuseOp, TakeOp, DecOp, LinEnterOp,
          LinUseOp, NatToBigOp, scf::ConditionOp, scf::YieldOp, scf::WhileOp>(op))
    return Use::Consume;
  return Use::Borrow;
}

} // namespace idr::ownership
