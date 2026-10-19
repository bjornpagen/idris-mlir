// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.match and idr.match_lit: their rules, their builders, the region each
// takes for a known key, and their canonicalization. A case of idr.match is
// a constructor's tag, whose fields are checked against the scrutinee's
// data type, whose body is in the type; a key of idr.match_lit is a literal
// of the scrutinee's type, which the type says.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;
using namespace idr;

namespace {

// Every region that runs ends in idr.yield, or in ub.unreachable after a
// crash. Each is one block that is not empty (SingleBlock), so it has an op
// to end in; an exhaustive match's empty default has none, and never runs.
// What a yield gives is the match's results, which RegionBranchOpInterface
// checks along the edge from the yield to the match.
LogicalResult verifyMatchRegions(Operation *op) {
  for (Region &region : op->getRegions())
    if (!region.empty() && !isa<YieldOp, ub::UnreachableOp>(region.front().back()))
      return op->emitOpError("region #")
             << region.getRegionNumber() << " must end in idr.yield or ub.unreachable";
  return success();
}

// A default that runs binds the scrutinee back, at its type: the value no
// case took apart, which a linear scrutinee needs, since the match used it.
LogicalResult verifyDefault(MatchOpInterface match) {
  Region &fallback = match.getDefaultRegion();
  if (fallback.empty() ||
      (fallback.getNumArguments() == 1 &&
       fallback.getArgument(0).getType() == match.getScrutinee().getType()))
    return success();
  return match->emitOpError("expects a default region that takes the scrutinee back at its type");
}

// An empty default region and one per case, the default first.
void addRegions(OperationState &state, size_t cases) {
  for (size_t region = 0; region <= cases; ++region)
    state.addRegion();
}

// The region of `Match` taken for the key `key`: its case, else the
// default. A key is a literal of idr.match_lit, or a tag of idr.match: the
// two keys are different things, so this is written over the op. An empty
// default never runs: the key is then one the match has no region for,
// which nothing reaches.
template <typename Match, typename Key>
Region *takenRegion(Match op, Key key) {
  auto cases = op.getCases();
  const auto *it = llvm::find(cases, key);
  if (it != cases.end())
    return &op.getCaseRegion(static_cast<unsigned>(it - cases.begin()));
  Region &fallback = op.getDefaultRegion();
  return fallback.empty() ? nullptr : &fallback;
}

// The region a match takes because it sits in a region of another match on
// the same value: in a case of the enclosing match the value has that
// case's key, and in its default it has none of its keys, so a match whose
// keys are all among them takes its default. A match on a value no
// enclosing match took is known no better; the enclosing match's default
// says too little when this match has a key of its own, and the search
// goes on outward. Only the value matters, not the position it is held in:
// the same value in a linear position is still that value.
template <typename Match>
Region *takenFromEnclosing(Match op) {
  Value source = throughLinear(op.getScrutinee());
  for (Region *region = op->getParentRegion(); region; region = region->getParentRegion()) {
    auto outer = dyn_cast<Match>(region->getParentOp());
    if (!outer || throughLinear(outer.getScrutinee()) != source)
      continue;
    if (region != &outer.getDefaultRegion())
      return takenRegion(op, outer.getCases()[outer.caseOf(*region)]);
    Region &fallback = op.getDefaultRegion();
    if (!fallback.empty() && llvm::all_of(op.getCases(), [&](auto key) {
          return llvm::is_contained(outer.getCases(), key);
        }))
      return &fallback;
  }
  return nullptr;
}

} // namespace

//===----------------------------------------------------------------------===//
// idr.match
//===----------------------------------------------------------------------===//

// Each case is a constructor of the scrutinee's data type, once, and its
// region's arguments are that constructor's fields at the scrutinee's
// grade: what the type's body says, read with the op and its regions'
// arguments alone. ODS ties no key to a case region, so the two lists are
// held to one length here.
LogicalResult MatchOp::verify() {
  if (getCases().size() != getNumCases())
    return emitOpError("expects one key per case region");
  llvm::SmallDenseSet<int32_t> seen;
  for (unsigned index = 0, count = getNumCases(); index < count; ++index) {
    FailureOr<std::reference_wrapper<const Ctor>> found =
        idr::detail::ctorAt(*this, getScrutinee().getType(), getCaseTag(index));
    if (failed(found))
      return failure();
    const Ctor &ctor = *found;
    if (!seen.insert(getCases()[index]).second)
      return emitOpError("has two cases for @") << ctor.name.getValue();
    SmallVector<Type> expected;
    for (Type field : ctor.fields)
      expected.push_back(caseFieldType(getScrutinee().getType(), ctor, field));
    TypeRange args = getCaseRegion(index).getArgumentTypes();
    if (args != TypeRange(expected))
      return emitOpError("case @") << ctor.name.getValue()
                                   << " must take the constructor's fields at the "
                                   << "scrutinee's grade, " << expected;
  }
  return verifyDefault(*this);
}

LogicalResult MatchOp::verifyRegions() { return verifyMatchRegions(*this); }

DataType MatchOp::getDataType() { return dataTypeOf(getScrutinee().getType()); }

void MatchOp::build(OpBuilder &builder, OperationState &state, TypeRange results,
                    Value scrutinee, ArrayRef<Tag> tags) {
  state.addOperands(scrutinee);
  state.addTypes(results);
  state.getOrAddProperties<Properties>().cases = builder.getDenseI32ArrayAttr(
      llvm::map_to_vector(tags, [](Tag tag) { return static_cast<int32_t>(tag); }));
  addRegions(state, tags.size());
}

// A case region is entered at its constructor; the default at none, the
// scrutinee being none of the cases'.
std::optional<Tag> MatchOp::knownTag(Region &region) {
  if (&region == &getDefaultRegion())
    return std::nullopt;
  return getCaseTag(caseOf(region));
}

// A constant constructor, or the constructor of the idr.con that built the
// scrutinee, also through a linear position, where that still holds
// (builtStateHolds); else what an enclosing match on the same value
// established.
Region *MatchOp::getTakenRegion(Attribute value) {
  std::optional<int32_t> tag;
  Value source = throughLinear(getScrutinee());
  ConAttr constant;
  if (!builtStateHolds(source, getOperation()))
    return takenFromEnclosing(*this);
  if (auto con = dyn_cast_or_null<ConAttr>(value))
    tag = static_cast<int32_t>(con.getTag());
  else if (auto built = source.getDefiningOp<ConOp>())
    tag = static_cast<int32_t>(built.getTag());
  else if (matchPattern(source, m_Constant(&constant)))
    tag = static_cast<int32_t>(constant.getTag());
  if (!tag)
    return takenFromEnclosing(*this);
  return takenRegion(*this, *tag);
}

// Upstream's region patterns, as scf.index_switch uses them, then the
// dialect's. Results no region needs drop, and a match whose taken region
// is known (a constant or an idr.con scrutinee, or one region left) is
// replaced by that region, whose arguments are no successor inputs: a
// case's become idr.field reads that fold, and the default's the scrutinee
// (canon::readField). A match that takes a linear value apart stays
// (canon::readsPlainValue).
void MatchOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  populateRegionBranchOpInterfaceCanonicalizationPatterns(results, getOperationName());
  populateRegionBranchOpInterfaceInliningPattern(results, getOperationName(), canon::readField,
                                                 canon::readsPlainValue);
  canon::addMatchPatterns(results, context);
}

//===----------------------------------------------------------------------===//
// idr.match_lit
//===----------------------------------------------------------------------===//

// Keys are distinct literals of the scrutinee's type, as the type says, one
// per case region, which binds nothing.
LogicalResult MatchLitOp::verify() {
  if (getCases().size() != getNumCases())
    return emitOpError("expects one key per case region");
  Type type = unrestricted(getScrutinee().getType());
  auto literals = cast<LiteralTypeInterface>(type);
  llvm::SmallDenseSet<Attribute> seen;
  for (Attribute key : getCases()) {
    if (!literals.isLiteral(key))
      return emitOpError("has a key ") << key << " that is not a literal of " << type;
    if (!seen.insert(key).second)
      return emitOpError("has two cases for ") << key;
  }
  for (Region &region : getCaseRegions())
    if (region.getNumArguments())
      return emitOpError("expects case regions without arguments");
  return verifyDefault(*this);
}

LogicalResult MatchLitOp::verifyRegions() { return verifyMatchRegions(*this); }

void MatchLitOp::build(OpBuilder &, OperationState &state, TypeRange results, Value scrutinee,
                       ArrayAttr cases) {
  state.addOperands(scrutinee);
  state.addTypes(results);
  state.getOrAddProperties<Properties>().cases = cases;
  addRegions(state, cases.size());
}

// A literal match binds no fields: no region is entered at a constructor.
std::optional<Tag> MatchLitOp::knownTag(Region &) { return std::nullopt; }

// The literal itself, else what an enclosing match on the same value
// established.
Region *MatchLitOp::getTakenRegion(Attribute value) {
  if (!value)
    return takenFromEnclosing(*this);
  return takenRegion(*this, value);
}

// Upstream's region patterns, as for idr.match: the default's argument,
// the one value a literal match binds, is the scrutinee when its region
// replaces the match.
void MatchLitOp::getCanonicalizationPatterns(RewritePatternSet &results,
                                             MLIRContext *context) {
  populateRegionBranchOpInterfaceCanonicalizationPatterns(results, getOperationName());
  populateRegionBranchOpInterfaceInliningPattern(results, getOperationName(), canon::readField,
                                                 canon::readsPlainValue);
  canon::addMatchLitPatterns(results, context);
}
