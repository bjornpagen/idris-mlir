// idr.graph:moduloat: the tail modulo constructor of a block, where what a
// self call computes is a field of the constructor the function returns.
export module idr.graph:moduloat;

import idr.mlir;
import idr.dialect;

import :fieldsof;
import :isselfcall;
import :passesonprevious;

using namespace mlir;

namespace {

// Whether `op` is the constructor of a box: an idr.con or idr.reuse.
bool buildsBox(Operation *op) {
  return isa_and_nonnull<idr::ConOp, idr::ReuseOp>(op) && isa<idr::BoxType>(idr::unrestricted(op->getResult(0).getType()));
}

} // namespace

export namespace idr::graph {

// A tail modulo constructor: the self call whose result is field `index`
// of the constructor `built`, which the block's terminator passes on. The
// result may enter or leave a grade on its way to the field (`grades`,
// nearest the field first): a grade has no runtime form, and goes with
// the call.
struct Modulo {
  mlir::func::CallOp call;
  mlir::Operation *built;
  unsigned index;
  llvm::SmallVector<mlir::Operation *, 2> grades;
};

// The tail modulo constructor of `block` in `fn`: the constructor right
// before its terminator, and a self call in the block, with only ops between
// them that neither touch memory nor can fail, which the call then moves
// past, whose one result reaches a field of the constructor.
std::optional<Modulo> moduloAt(Block &block, func::FuncOp fn) {
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

} // namespace idr::graph
