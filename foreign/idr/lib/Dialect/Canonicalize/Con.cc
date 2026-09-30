// The folds of idr.con: a constructor of constants is a constant, and a
// constructor rebuilt from the fields of a value of that constructor is the
// value (record eta).

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

namespace {

// The value `field` reads field `index` of, when it reads one of `ctor` and
// the constructor is its one reader. A case region's argument is such a
// read of the match's scrutinee.
Value readOf(Value field, StringAttr ctor, unsigned index) {
  if (!field.hasOneUse())
    return {};
  if (auto read = field.getDefiningOp<FieldOp>())
    return read.getCtorAttr().getAttr() == ctor && read.getIndex() == index ? read.getValue()
                                                                           : Value();
  auto arg = dyn_cast<BlockArgument>(field);
  auto match = arg ? dyn_cast_or_null<MatchOp>(arg.getOwner()->getParentOp()) : MatchOp();
  if (!match || arg.getArgNumber() != index)
    return {};
  unsigned region = arg.getOwner()->getParent()->getRegionNumber();
  if (region >= match.getCases().size() ||
      cast<FlatSymbolRefAttr>(match.getCases()[region]).getAttr() != ctor)
    return {};
  return match.getScrutinee();
}

// Whether `value` is known to be built by `ctor` where `at` is: the type has
// no other constructor, or `at` is in the case of a match on the value that
// `ctor` takes.
bool knownCtor(Value value, CtorOp ctor, Operation *at) {
  if (cast<DataOp>(ctor->getParentOp()).getCtors().size() == 1)
    return true;
  for (Region *region = at->getParentRegion(); region; region = region->getParentRegion()) {
    auto match = dyn_cast<MatchOp>(region->getParentOp());
    if (!match || throughLinear(match.getScrutinee()) != throughLinear(value))
      continue;
    unsigned index = region->getRegionNumber();
    if (index < match.getCases().size() &&
        cast<FlatSymbolRefAttr>(match.getCases()[index]).getAttr() == ctor.getSymNameAttr())
      return true;
  }
  return false;
}

// `con C(field x[C, 0], ..., field x[C, k])` is x, when x is known to be C
// and the constructor is the one reader of each field. The reads then die
// with it, so each field of x, linear ones included, is still taken once:
// by what takes x in the constructor's place.
Value eta(ConOp con) {
  auto fields = con.getFields();
  if (fields.empty())
    return {};
  StringAttr name = con.getCtor().getLeafReference();
  Value source;
  for (auto [index, field] : llvm::enumerate(fields)) {
    Value read = readOf(field, name, static_cast<unsigned>(index));
    if (!read || (source && read != source))
      return {};
    source = read;
  }
  if (source.getType() != con.getType())
    return {};
  CtorOp ctor = lookupCtor(con, con.getCtor());
  if (!ctor || !knownCtor(source, ctor, con))
    return {};
  return source;
}

} // namespace

OpFoldResult ConOp::fold(FoldAdaptor adaptor) {
  if (Value value = eta(*this))
    return value;
  if (llvm::is_contained(adaptor.getFields(), Attribute()))
    return {};
  return ConAttr::get(getContext(), getCtor(), ArrayAttr::get(getContext(), adaptor.getFields()));
}
