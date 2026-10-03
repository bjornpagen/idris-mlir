// idr.ownership:wheredies: where a value dies on each path of a block.
export module idr.ownership:wheredies;

import idr.mlir;

import :arrayloop;
import :useof;
import :usersin;

using namespace mlir;

namespace idr::ownership {

// Where `value`, which `block` holds a reference to, dies on each path of
// the block: at its start when nothing there uses it, after its last use,
// or inside each region of that use when it has regions (not the body of a
// loop over an array, which the value outlives). Nowhere on a path whose
// last use consumes it: the value moves on, its cell with it, and a take
// after that use would keep a second reference alive across it, so that
// whoever receives the value finds its cell shared and copies it. Calls
// `at` with each point.
export void whereDies(Value value, Block &block, SymbolTableCollection &symbols,
                      function_ref<void(Block &, Block::iterator)> at) {
  SmallVector<Operation *> users = usersIn(value, block, nullptr);
  if (users.empty()) {
    at(block, block.begin());
    return;
  }
  Operation *last = users.back();
  if (last->hasTrait<OpTrait::IsTerminator>())
    return;
  // Borrow inference may still be to come, so every call may consume its
  // arguments here.
  if (llvm::any_of(last->getOpOperands(), [&](OpOperand &operand) {
        return operand.get() == value && useOf(operand, symbols) == Use::Consume;
      }))
    return;
  // The body of a loop over an array runs once per element, and a value
  // from outside it is alive throughout: the value dies after the loop.
  if (last->getNumRegions() != 0 && !isArrayLoop(last)) {
    for (Region &region : last->getRegions())
      if (!region.empty())
        whereDies(value, region.front(), symbols, at);
    return;
  }
  at(block, std::next(last->getIterator()));
}

} // namespace idr::ownership
