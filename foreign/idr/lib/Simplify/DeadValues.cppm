// idr-dead-values: remove-dead-values, leaving a call it does not change
// where it is.
//
// remove-dead-values lists every call of a private function that returns a
// value and erases results from it. Erasing results builds a new call, and
// it builds one even when no result is dead: the module prints the same and
// the new call has a new address, so OperationFingerPrint changes. The pass
// runs on a copy. When the copy still hashes the same, nothing it did was a
// change, and the module keeps the calls it has.
export module idr.simplify:deadvalues;

import idr.mlir;

using namespace mlir;

namespace {

// What the module is, hashed so a copy on which remove-dead-values only
// rebuilt calls hashes the same. The copy's operations are new objects
// either way, so addresses never match. Constants are hashed as their
// values at each use, and other values by their position in the walk.
std::array<uint8_t, 20> structural(ModuleOp module) {
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

} // namespace

namespace idr::simplify {

// Runs remove-dead-values with its canonicalization off. Returns whether
// the module changed. A failure is the pass's.
export FailureOr<bool> removeDeadValues(ModuleOp module) {
  OwningOpRef<ModuleOp> copy = module.clone();
  std::array<uint8_t, 20> before = structural(*copy);
  PassManager passes(module.getContext());
  // Its own canonicalization folds region-branch patterns on the matches
  // alone: a field one of them folds leaves the constructor it read dead
  // but in place, still holding a world or a linear value that the fold's
  // user now holds too. The next round's canonicalization runs on
  // everything and erases what is dead.
  passes.addPass(createRemoveDeadValuesPass(RemoveDeadValuesPassOptions{.canonicalize = false}));
  if (failed(passes.run(*copy)))
    return failure();
  if (structural(*copy) == before)
    return false;
  module->getRegion(0).takeBody((*copy)->getRegion(0));
  return true;
}

} // namespace idr::simplify
