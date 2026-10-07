// idr.narrow:widths: what a vectorized loop computes on, and what it reads
// from outside.
export module idr.narrow:widths;

import idr.mlir;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

// Whether `loop` is vectorized, as its ops say: it computes on vectors, has
// no results (a loop over buffers), and holds nothing but vector ops, the
// loops of its tiles and ops with neither effects nor regions. A tile the
// vectorizer refused keeps its linalg.generic, and a branch or a call
// keeps its scalar code, so a loop holding one is not vectorized, nor is a
// loop around a vectorized one that stores: the tile loops are the
// outermost such loops.
bool isVectorized(scf::ForOp loop) {
  if (loop->getNumResults() != 0)
    return false;
  bool vectors = false;
  WalkResult walk = loop.walk([&](Operation *op) {
    if (isa_and_nonnull<vector::VectorDialect>(op->getDialect())) {
      vectors = true;
      return WalkResult::advance();
    }
    if (isa<scf::ForOp, scf::YieldOp>(op))
      return WalkResult::advance();
    if (op->getNumRegions() != 0 || !isMemoryEffectFree(op))
      return WalkResult::interrupt();
    return WalkResult::advance();
  });
  return vectors && !walk.wasInterrupted();
}

// The values `loop` reads from outside it, in the order of their first use.
SetVector<Value> inputsOf(scf::ForOp loop) {
  SetVector<Value> inputs;
  inputs.insert_range(loop->getOperands());
  getUsedValuesDefinedAbove(loop->getRegions(), inputs);
  return inputs;
}

// Whether `value` is one the version tests: an integer wider than 32 bits
// or an index, no constant, whose range the analysis cannot know.
bool testable(Value value) {
  Type type = value.getType();
  return (type.isIndex() || (type.isSignlessInteger() && type.getIntOrFloatBitWidth() > 32)) &&
         !matchPattern(value, m_Constant());
}

// Whether a word of `range` fits a signed 32-bit one.
bool fits32(const ConstantIntRanges &range) {
  return range.smin().getSignificantBits() <= 32 && range.smax().getSignificantBits() <= 32;
}

// The range `solver` gives `value`; none where it gives none, as in code
// the analysis never reached.
std::optional<ConstantIntRanges> rangeOf(DataFlowSolver &solver, Value value) {
  auto *state = solver.lookupState<IntegerValueRangeLattice>(value);
  if (!state || state->getValue().isUninitialized())
    return std::nullopt;
  return state->getValue().getValue();
}

// What `op` computes on: whether on integers wider than 32 bits (an
// elementwise op that is no cast, with such an operand or result), and
// whether on lanes of them.
struct Width {
  bool wide = false;
  bool lanes = false;
};
Width widthOf(Operation *op) {
  Width width;
  if (!op->hasTrait<OpTrait::Elementwise>() || isa<CastOpInterface>(op))
    return width;
  auto note = [&](Type type) {
    if (ConstantIntRanges::getStorageBitwidth(type) <= 32)
      return;
    width.wide = true;
    width.lanes |= isa<VectorType>(type);
  };
  for (Type type : op->getOperandTypes())
    note(type);
  for (Type type : op->getResultTypes())
    note(type);
  return width;
}

// Whether `loop` computes on lanes of integers wider than 32 bits, which is
// what the narrowing is for.
bool computesWideLanes(scf::ForOp loop) {
  return loop
      .walk([](Operation *op) { return widthOf(op).lanes ? WalkResult::interrupt() : WalkResult::advance(); })
      .wasInterrupted();
}

} // namespace idr::narrow
