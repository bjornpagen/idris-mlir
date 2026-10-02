// Which values hold references, and what each use does with them.

#include "Ownership/Ownership.h"

using namespace mlir;

namespace idr::ownership {

bool Counting::counted(Type type) {
  // A linear value is counted as the value it is; its quantity decides
  // only how it is used.
  type = unrestricted(type);
  if (isa<StrType, BigType, NatType, BoxType, FnType, TokenType>(type) || isArray(type))
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
    if (def && (def->hasTrait<OpTrait::ConstantLike>() || isa<ub::PoisonOp, BigSmallOp, PendingOp>(def)))
      return true;
  }
  return false;
}

bool isArrayLoop(Operation *op) { return isa<ArrayGenerateOp, ArrayFoldOp>(op); }

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
    // The body of a loop runs again: the next iteration uses the value.
    if (isArrayLoop(block->getParentOp()))
      return true;
  }
  return false;
}

// Before the owned stage every parameter may still be owned: borrow
// inference has not decided.
bool isBorrowed(func::FuncOp fn, unsigned index) {
  auto module = fn->getParentOfType<ModuleOp>();
  return module && module->hasAttr(stageAttr) && index < fn.getNumArguments() &&
         !isOwned(fn.getArgument(index).getType());
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
  // reference; so does a natural into the Integer it is, and a value
  // written to a destination into the cell.
  if (isa<func::ReturnOp, YieldOp, ConOp, ClosureOp, ReuseOp, TakeOp, DropOp, LinEnterOp,
          LinUseOp, ShareOp, NatToBigOp, DestWriteOp, scf::ConditionOp, scf::YieldOp,
          scf::WhileOp>(op))
    return Use::Consume;
  // An element moves into the array's cell; the array itself is read. The
  // fill of a generated array moves in likewise, and a fold's init into
  // its body as the first accumulator.
  if (auto make = dyn_cast<ArrayNewOp>(op))
    return operand.get() == make.getFill() ? Use::Consume : Use::Borrow;
  if (auto set = dyn_cast<ArraySetOp>(op))
    return operand.get() == set.getValue() ? Use::Consume : Use::Borrow;
  if (auto generate = dyn_cast<ArrayGenerateOp>(op))
    return operand.get() == generate.getFill() ? Use::Consume : Use::Borrow;
  if (auto fold = dyn_cast<ArrayFoldOp>(op))
    return operand.get() == fold.getInit() ? Use::Consume : Use::Borrow;
  return Use::Borrow;
}

} // namespace idr::ownership
