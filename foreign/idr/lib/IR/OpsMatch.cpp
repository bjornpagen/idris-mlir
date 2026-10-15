// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.match and idr.match_lit: their rules, the region each takes for a
// known key, and their canonicalization. A case of idr.match is a
// constructor's tag, whose fields are checked against the scrutinee's data
// type, whose body is in the type.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

namespace {

// Every region ends in idr.yield, or in ub.unreachable after a crash. Each
// region is one block that is not empty (SingleBlock), so it has an op to
// end in. What a yield gives is the match's results, which
// RegionBranchOpInterface checks along the edge from the yield to the match.
LogicalResult verifyMatchRegions(Operation *op) {
  for (auto [index, region] : llvm::enumerate(op->getRegions()))
    if (!isa<YieldOp, ub::UnreachableOp>(region.front().back()))
      return op->emitOpError("region #")
             << index << " must end in idr.yield or ub.unreachable";
  return success();
}

// The region of `Match` taken for the key `key`: its case, else the default.
// A key is a literal of idr.match_lit, or a tag of idr.match.
template <typename Match, typename Key>
Region *takenRegion(Match op, Key key) {
  auto cases = op.getCases();
  const auto *it = llvm::find(cases, key);
  if (it != cases.end())
    return &op.getCaseRegion(static_cast<unsigned>(it - cases.begin()));
  return op.getDefaultRegion();
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
    unsigned index = region->getRegionNumber();
    if (index < outer.getCases().size())
      return takenRegion(op, outer.getCases()[index]);
    Region *fallback = op.getDefaultRegion();
    if (fallback && llvm::all_of(op.getCases(), [&](auto key) {
          return llvm::is_contained(outer.getCases(), key);
        }))
      return fallback;
  }
  return nullptr;
}

} // namespace

// Each case is a constructor of the scrutinee's data type, once, and its
// region's arguments are that constructor's fields at the scrutinee's
// grade: what the type's body says, read with the op and its regions'
// arguments alone.
LogicalResult MatchOp::verify() {
  size_t cases = getCases().size();
  if (getRegions().size() != cases && getRegions().size() != cases + 1)
    return emitOpError("expects one region per case and at most one default");
  llvm::SmallDenseSet<int32_t> seen;
  for (auto [index, tag] : llvm::enumerate(getCases())) {
    if (tag < 0)
      return emitOpError("has a case for constructor ") << tag;
    const Ctor *ctor =
        idr::detail::ctorAt(*this, getScrutinee().getType(), static_cast<unsigned>(tag));
    if (!ctor)
      return failure();
    if (!seen.insert(tag).second)
      return emitOpError("has two cases for constructor ") << tag;
    SmallVector<Type> expected;
    for (Type field : ctor->fields)
      expected.push_back(fieldType(getScrutinee().getType(), field));
    TypeRange args = getCaseRegion(static_cast<unsigned>(index)).getArgumentTypes();
    if (args != TypeRange(expected))
      return emitOpError("case @") << ctor->name.getValue()
                                   << " must take the constructor's fields at the "
                                   << "scrutinee's grade, " << expected;
  }
  if (Region *fallback = getDefaultRegion()) {
    TypeRange args = fallback->getArgumentTypes();
    if (args.size() > 1 || (args.size() == 1 && args.front() != getScrutinee().getType()))
      return emitOpError("expects a default region without arguments, or one that takes the "
                         "scrutinee back at its type");
  }
  return success();
}

LogicalResult MatchOp::verifyRegions() { return verifyMatchRegions(*this); }

DataType MatchOp::getDataType() { return dataTypeOf(getScrutinee().getType()); }

void MatchOp::build(OpBuilder &builder, OperationState &state, TypeRange results,
                    Value scrutinee, ArrayRef<unsigned> tags, unsigned regions) {
  SmallVector<int32_t> cases;
  for (unsigned tag : tags)
    cases.push_back(static_cast<int32_t>(tag));
  build(builder, state, results, scrutinee, ArrayRef<int32_t>(cases), regions);
}

// A constant constructor, or the constructor of the idr.con that built the
// scrutinee, also through a linear position; else what an enclosing match
// on the same value established.
Region *MatchOp::getTakenRegion(Attribute value) {
  std::optional<int32_t> tag;
  Value source = throughLinear(getScrutinee());
  ConAttr constant;
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

// Keys are distinct literals of the scrutinee's type, and a default is required.
LogicalResult MatchLitOp::verify() {
  if (getRegions().size() != getCases().size() + 1)
    return emitOpError("expects one region per case and a default");
  Type type = unrestricted(getScrutinee().getType());
  llvm::SmallDenseSet<Attribute> seen;
  for (Attribute key : getCases()) {
    bool typed = TypeSwitch<Type, bool>(type)
                     .Case([&](IntegerType) {
                       auto integer = dyn_cast<IntegerAttr>(key);
                       return integer && integer.getType() == type;
                     })
                     .Case([&](StrType) { return isa<StringAttr>(key); })
                     .Case([&](BigType) { return isa<BigAttr>(key); })
                     .Case([&](NatType) {
                       auto big = dyn_cast<BigAttr>(key);
                       return big && !big.getValue().isNegative();
                     })
                     .Default([](Type) { return false; });
    if (!typed)
      return emitOpError("has a key ") << key << " that is not a literal of " << type;
    if (!seen.insert(key).second)
      return emitOpError("has two cases for ") << key;
  }
  for (Region &region : getRegions())
    if (region.getNumArguments())
      return emitOpError("expects regions without arguments");
  return success();
}

LogicalResult MatchLitOp::verifyRegions() { return verifyMatchRegions(*this); }

// The literal itself, else what an enclosing match on the same value
// established.
Region *MatchLitOp::getTakenRegion(Attribute value) {
  if (!value)
    return takenFromEnclosing(*this);
  return takenRegion(*this, value);
}

// Upstream's region patterns, as scf.index_switch uses them, then the
// dialect's. Results no region needs drop, and a match whose taken region
// is known (a constant or an idr.con scrutinee, or one region left) is
// replaced by that region, whose arguments become idr.field reads that
// fold. Upstream's defaults for the region of a literal match, which binds
// nothing, are local to its header, so these hooks add the region patterns
// themselves.
void MatchOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  populateRegionBranchOpInterfaceCanonicalizationPatterns(results, getOperationName());
  populateRegionBranchOpInterfaceInliningPattern(results, getOperationName(), canon::readField,
                                                 canon::readsPlainValue);
  canon::addMatchPatterns(results, context);
}

void MatchLitOp::getCanonicalizationPatterns(RewritePatternSet &results,
                                             MLIRContext *context) {
  populateRegionBranchOpInterfaceCanonicalizationPatterns(results, getOperationName());
  populateRegionBranchOpInterfaceInliningPattern(results, getOperationName());
  canon::addMatchLitPatterns(results, context);
}
