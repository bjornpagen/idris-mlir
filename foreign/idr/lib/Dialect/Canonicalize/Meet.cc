// The values a consumer moved into a match's regions meets there: the
// profit of case-of-case and of moving a value into regions. A consumer
// meets a value where it folds or canonicalizes against it: a match takes
// the case of a known constructor or literal, a field or tag of a known
// constructor is read off it, a known closure applied is a call, output
// takes a string as it is built, and any other op folds with constants.
// Each copy then shrinks to what its region knows. A consumer that only
// holds the value gains nothing there: a constructor holding it beside a
// field that is not constant, a closure capturing it, a call passing it on.
// Moved into every region anyway, it is copied, and so is whatever then
// meets the copies; each match of a chain of them multiplies the code after
// it by its regions. A call is specialized for an argument only where the
// argument is a function, which makes the callee's applications of it
// direct calls; for data it would only re-abstract what the regions know.
// A call whose every argument is then a constant is closed, and
// compile-time evaluation computes it.

#include "Dialect/Canonicalize/Matches.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

namespace {

// The use that reads the value `use` holds: past the linear positions it
// only passes, entered and used at once, each the one use of the last.
OpOperand &reader(OpOperand &use) {
  OpOperand *at = &use;
  while (isa<LinEnterOp, LinUseOp>(at->getOwner())) {
    Value held = at->getOwner()->getResult(0);
    if (!held.hasOneUse())
      break;
    at = &*held.getUses().begin();
  }
  return *at;
}

// Whether every operand of the op holding `use` but that one is a constant:
// with a constant there, a call is closed, and compile-time evaluation
// computes it.
bool closedWith(OpOperand &use) {
  return llvm::all_of(use.getOwner()->getOpOperands(), [&](OpOperand &operand) {
    return &operand == &use || matchPattern(operand.get(), m_Constant());
  });
}

// Whether the op holding `use` folds with `constant` there and the
// constants its other operands are, as constant propagation simulates a
// fold: an op with regions is not tried, and one that would fold in place
// is put back as it was, since the constant is not what the op holds.
bool foldsWith(OpOperand &use, Attribute constant) {
  Operation *op = use.getOwner();
  if (op->getNumRegions() != 0)
    return false;
  SmallVector<Attribute> operands;
  for (OpOperand &operand : op->getOpOperands()) {
    Attribute known;
    if (&operand == &use)
      known = constant;
    else
      matchPattern(operand.get(), m_Constant(&known));
    operands.push_back(known);
  }
  SmallVector<Value> original(op->getOperands());
  DictionaryAttr attributes = op->getAttrDictionary();
  SmallVector<OpFoldResult> results;
  if (failed(op->fold(operands, results)))
    return false;
  if (results.empty()) {
    op->setOperands(original);
    op->setAttrs(attributes);
    return false;
  }
  return true;
}

} // namespace

// A call's result meets the elimination that raising moves into a clone of
// the callee once the two meet. A string builder meets output and the
// first character, and output meets the empty string, which it does not
// write. A constant, a constructor or a closure meets what reads it and a
// call it is passed to as a function; a constant also meets what folds
// with it, and a call it closes.
bool canon::feeds(Value value, OpOperand &use) {
  if (isa_and_nonnull<func::CallOp>(value.getDefiningOp()))
    return eliminationAt(use).has_value();
  // A linear position the value only passes on the way changes nothing a
  // consumer folds against: the consumer of a linear value is its use, and
  // what reads the use sees through the pair.
  value = throughLinear(value);
  Operation *def = value.getDefiningOp();
  // A closure holding a linear value has one use, which applies it or
  // enters it into a linear type (its verifier's rule): moved to where the
  // closure is made, such a use is not a profit but its place.
  if (auto closure = dyn_cast_or_null<ClosureOp>(def);
      closure && isa<LinEnterOp, ApplyOp>(use.getOwner()) &&
      llvm::any_of(closure.getCaptures().getTypes(),
                   [](Type type) { return quantityOf(type) == Quantity::One; }))
    return true;
  OpOperand &read = reader(use);
  Operation *consumer = read.getOwner();
  if (isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(def))
    return isa<PutStrOp, StrHeadOp>(consumer);
  Attribute constant;
  matchPattern(value, m_Constant(&constant));
  if (isa<PutStrOp>(consumer)) {
    auto text = dyn_cast_or_null<StringAttr>(constant);
    return text && text.getValue().empty();
  }
  if (!constant && !isa_and_nonnull<ConOp, ClosureOp>(def))
    return false;
  if (eliminationAt(use) || isa<MatchOp, MatchLitOp, FieldOp, TagOp>(consumer))
    return true;
  if (isa<func::CallOp>(consumer))
    return isa<FnType>(unrestricted(value.getType())) || (constant && closedWith(read));
  return constant && foldsWith(read, constant);
}

bool canon::meetsInSomeRegion(OpResult result, Operation *consumer) {
  return llvm::any_of(consumer->getOpOperands(), [&](OpOperand &use) {
    if (use.get() != result)
      return false;
    return llvm::any_of(result.getOwner()->getRegions(), [&](Region &region) {
      auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
      return yield && feeds(yield.getOperand(result.getResultNumber()), use);
    });
  });
}
