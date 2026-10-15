// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Record eta: a constructor rebuilt from the fields of a value of that
// constructor, which is the value. ConOp's folder asks it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Grades.h"

using namespace mlir;
using namespace idr;

namespace {

// The value `field` reads field `index` of, when it reads one of `ctor`,
// and, for a linear field, the constructor is its one reader. A case
// region's argument is such a read of the match's scrutinee, unless the
// match took a linear scrutinee apart: that value is used, and the
// constructor rebuilt from its fields is a new one (in its cell, once the
// owned stage reuses it).
Value readOf(Value field, FlatSymbolRefAttr ctor, unsigned index) {
  if (quantityOf(field.getType()) == Quantity::One && !field.hasOneUse())
    return {};
  if (auto read = field.getDefiningOp<FieldOp>())
    return read.getCtorAttr() == ctor && read.getIndex() == index ? read.getValue() : Value();
  auto arg = dyn_cast<BlockArgument>(field);
  auto match = arg ? dyn_cast_or_null<MatchOp>(arg.getOwner()->getParentOp()) : MatchOp();
  if (!match || arg.getArgNumber() != index ||
      quantityOf(match.getScrutinee().getType()) == Quantity::One)
    return {};
  unsigned region = arg.getOwner()->getParent()->getRegionNumber();
  if (region >= match.getCases().size() || match.getCases()[region] != ctor)
    return {};
  return match.getScrutinee();
}

// Whether `value` is known to be built by the constructor `ctor` names
// where `at` is, because `at` is in the case of a match on the value that
// `ctor` takes.
bool knownFromMatch(Value value, FlatSymbolRefAttr ctor, Operation *at) {
  for (Region *region = at->getParentRegion(); region; region = region->getParentRegion()) {
    auto match = dyn_cast<MatchOp>(region->getParentOp());
    if (!match || throughLinear(match.getScrutinee()) != throughLinear(value))
      continue;
    unsigned index = region->getRegionNumber();
    if (index < match.getCases().size() && match.getCases()[index] == ctor)
      return true;
  }
  return false;
}

} // namespace

namespace idr::canon {

// `con C(field x[C, 0], ..., field x[C, k])` is x, when x is known to be C
// and the constructor is the one reader of each linear field. Those reads
// then die with it, so each linear field of x is still taken once: by what
// takes x in the constructor's place. Any other field is a value, which
// other readers may share with x. x is known to be C where its type has no
// other constructor, or where an enclosing match took x apart in C's case.
Value eta(ConOp con) {
  auto fields = con.getFields();
  FlatSymbolRefAttr name = con.getCtorAttr();
  Value source;
  for (auto [index, field] : llvm::enumerate(fields)) {
    Value read = readOf(field, name, static_cast<unsigned>(index));
    if (!read || (source && read != source))
      return {};
    source = read;
  }
  if (!source || source.getType() != con.getType())
    return {};
  if (con.getDataType().getCtors().size() != 1 && !knownFromMatch(source, name, con))
    return {};
  return source;
}

} // namespace idr::canon
