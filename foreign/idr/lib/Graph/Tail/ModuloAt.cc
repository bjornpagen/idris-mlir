// The tail modulo constructor of a block.
module idr.graph;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace {

// Whether `op` is the constructor of a box: an idr.con or idr.reuse.
bool buildsBox(Operation *op) {
  return isa_and_nonnull<idr::ConOp, idr::ReuseOp>(op) && isa<idr::BoxType>(idr::unrestricted(op->getResult(0).getType()));
}

} // namespace

std::optional<idr::graph::Modulo> idr::graph::moduloAt(Block &block, func::FuncOp fn) {
  Operation *terminator = block.getTerminator();
  Operation *built = terminator->getPrevNode();
  if (!passesOnPrevious(terminator) || !buildsBox(built))
    return std::nullopt;
  for (auto [index, field] : llvm::enumerate(fieldsOf(built))) {
    SmallVector<Operation *, 2> grades;
    Value source = field;
    while (Operation *def = source.getDefiningOp()) {
      if (!isa<idr::LinEnterOp, idr::LinUseOp>(def) || !def->hasOneUse())
        break;
      grades.push_back(def);
      source = def->getOperand(0);
    }
    auto call = source.getDefiningOp<func::CallOp>();
    if (!call || !isSelfCall(call, fn) || call->getBlock() != &block || !call->hasOneUse() ||
        call->getNumResults() != 1)
      continue;
    bool movable = true;
    for (Operation *op = call->getNextNode(); op != built; op = op->getNextNode())
      movable = movable &&
                (llvm::is_contained(grades, op) || (isMemoryEffectFree(op) && isSpeculatable(op)));
    if (movable)
      return Modulo{call, built, static_cast<unsigned>(index), std::move(grades)};
  }
  return std::nullopt;
}
