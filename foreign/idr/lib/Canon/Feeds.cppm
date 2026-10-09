// idr.canon:feeds: the values a consumer moved into a match's regions meets
// there: the profit of case-of-case and of moving a value into regions. A
// consumer meets a value where it folds or canonicalizes against it: a match
// takes the case of a known constructor or literal, a field or tag of a
// known constructor is read off it, a known closure applied is a call, a
// suspension forced where nothing else uses it is the call too, output
// takes a string as it is built (a list packed only to be written, as it is
// walked) and a constant list as the string it folds to, and any other op
// but a box constructor folds with constants.
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
export module idr.canon:feeds;

import idr.mlir;
import idr.dialect;

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
// fold: an op with regions is not tried, and the op is put back as it was
// whatever the fold returned, since the constant is not what the op holds
// and a folder may change its op in place and still return a result. The
// operands are set again only if the fold changed them, since setting them
// relinks their uses. The properties are copied whole and copied back, as
// the conversion driver rolls back an op it modified: set again from their
// attribute form, a property the fold set where the op had none would stay.
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
  DictionaryAttr attributes = op->getDiscardableAttrDictionary();
  OperationName name = op->getName();
  void *properties = nullptr;
  if (PropertyRef storage = op->getPropertiesStorage()) {
    properties = operator new(static_cast<size_t>(op->getPropertiesStorageSize()));
    name.initOpProperties(PropertyRef(name.getOpPropertiesTypeID(), properties), storage);
  }
  SmallVector<OpFoldResult> results;
  bool folded = succeeded(op->fold(operands, results)) && !results.empty();
  if (!llvm::equal(op->getOperands(), original))
    op->setOperands(original);
  op->setDiscardableAttrs(attributes);
  if (properties) {
    PropertyRef saved(name.getOpPropertiesTypeID(), properties);
    op->copyProperties(saved);
    name.destroyOpProperties(saved);
    operator delete(properties);
  }
  return folded;
}

} // namespace

export namespace idr::canon {

// Whether the consumer holding `use` folds or canonicalizes, or is raised
// or specialized, once the operand it holds there is `value`; not whether
// it merely holds it.
//
// A call's result meets the elimination that raising moves into a clone of
// the callee once the two meet. A string builder meets output that writes
// it in pieces (writtenInPieces) and the first character, which reads the
// string through the guard that it is not empty: the guard folds away on a
// string built with a character or a number in it, and the head after it.
// Output meets the empty string, which it does not write. Output of a list
// meets a constant list, which it writes as its string; not a cell, though
// it writes one a step at a time where it finds one: moved into the regions
// of a match for a cell, it would follow a chain of choices, each consing
// onto the list the one before built, into every region of each. A
// constant, a constructor or a closure meets what reads it and a call it
// is passed to as a function; a constant also meets what folds with it,
// and a call it closes.
//
// A suspension, built there or constant, meets a force when nothing else
// uses it, as a closure meets its apply: the force is then the call. A
// shared suspension does not: the force reads its cell. Nor does a memo
// box, which a force takes once suspensions are memo sums: its force reads
// the cell whatever built it. An `if` takes its branches as suspensions and
// forces after its match the one the match chose; moved into the match, the
// force is a call in each region.
//
// A box constructor of constants folds into static data, which every
// holder shares: no take gets its cell as a token, so a consumer that
// rebuilds it in place copies it, and every cell built on it is shared too.
// Built after the match, it is one fresh cell, exclusive to whoever takes
// it apart: it meets nothing in the regions.
bool feeds(Value value, OpOperand &use) {
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
  if (isa_and_nonnull<ClosureOp>(def) && holdsLinear(value) &&
      isa<LinEnterOp, ApplyOp>(use.getOwner()))
    return true;
  OpOperand &read = reader(use);
  Operation *consumer = read.getOwner();
  Attribute constant;
  matchPattern(value, m_Constant(&constant));
  if (isa<PutStrOp>(consumer)) {
    auto text = dyn_cast_or_null<StringAttr>(constant);
    return writtenInPieces(value) || (text && text.getValue().empty());
  }
  if (isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(def)) {
    if (auto guard = dyn_cast<CheckNonemptyOp>(consumer))
      return llvm::any_of(guard->getUsers(), llvm::IsaPred<StrHeadOp>);
    return isa<StrHeadOp>(consumer);
  }
  if (isa<PutListOp>(consumer))
    return static_cast<bool>(constant);
  if (isa<ForceOp>(consumer))
    return isa<LazyType>(unrestricted(value.getType())) &&
           (constant || isa_and_nonnull<SuspendOp>(def)) && value.hasOneUse();
  if (!constant && !isa_and_nonnull<ConOp, ClosureOp>(def))
    return false;
  if (eliminationAt(use) || isa<MatchOp, MatchLitOp, FieldOp, TagOp>(consumer))
    return true;
  if (isa<func::CallOp>(consumer))
    return isa<FnType>(unrestricted(value.getType())) || (constant && closedWith(read));
  if (auto con = dyn_cast<ConOp>(consumer); con && isa<BoxType>(unrestricted(con.getType())))
    return false;
  return constant && foldsWith(read, constant);
}

} // namespace idr::canon
