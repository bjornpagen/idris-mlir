// idr.simplify:structural: what a module is, hashed so that a round of the
// simplify loop that changed nothing hashes the same.
//
// PIN(simplify-structural-fixpoint) — see PINS.md
// "Unchanged" is structural(), not OperationFingerPrint. The fingerprint
// hashes the addresses of ops and values. sccp keeps the constants the
// module already holds, so a round of it alone keeps the fingerprint.
// remove-dead-values does not: erasing no result of a call still builds a
// new call in its place, and the new call has a new address. A round at
// this fixpoint therefore still has a new fingerprint. Nor is "unchanged"
// the module's text: constants materialized at the start of a block come
// out in another order on every round. structural() hashes what an op is,
// not where it lives: constants are hashed as their values at each use,
// and other values by their position in the walk.
export module idr.simplify:structural;

import idr.mlir;

using namespace mlir;

namespace idr::simplify {

// The hash of the module's ops, their attributes, properties and types,
// their regions, and where each operand comes from. Attributes, types and
// op names are uniqued, so their addresses stand for their contents.
export std::array<uint8_t, 20> structural(ModuleOp module) {
  llvm::SHA1 hasher;
  auto add = [&](const void *data) {
    hasher.update(ArrayRef(reinterpret_cast<const uint8_t *>(&data), sizeof(data)));
  };
  auto addNumber = [&](uint64_t n) {
    hasher.update(ArrayRef(reinterpret_cast<const uint8_t *>(&n), sizeof(n)));
  };
  llvm::DenseMap<Value, uint64_t> numbers;
  auto number = [&](Value value) { numbers.try_emplace(value, numbers.size()); };
  module->walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (op->hasTrait<OpTrait::ConstantLike>())
      return;
    add(op->getName().getAsOpaquePointer());
    add(op->getRawDictionaryAttrs().getAsOpaquePointer());
    addNumber(op->hashProperties());
    for (Value operand : op->getOperands()) {
      Attribute constant;
      if (matchPattern(operand, m_Constant(&constant))) {
        add(constant.getAsOpaquePointer());
        add(operand.getType().getAsOpaquePointer());
      } else {
        addNumber(numbers.lookup(operand));
      }
    }
    for (Value result : op->getResults()) {
      number(result);
      add(result.getType().getAsOpaquePointer());
    }
    for (Region &region : op->getRegions()) {
      addNumber(region.getBlocks().size());
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments()) {
          number(arg);
          add(arg.getType().getAsOpaquePointer());
        }
    }
  });
  return hasher.result();
}

} // namespace idr::simplify
