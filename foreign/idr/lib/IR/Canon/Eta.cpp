// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Record eta: a constructor rebuilt from the fields of a value of that
// constructor, which is the value. ConOp's folder asks it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"

using namespace mlir;
using namespace idr;

namespace {

// The value `field` reads field `index` of, when it reads one of `ctor`,
// and, for a linear field, the constructor is its one reader. A case
// region's argument is such a read of the match's scrutinee, unless the
// match took a linear scrutinee apart: that value is used, and the
// constructor rebuilt from its fields is a new one (in its cell, once the
// owned stage reuses it).
Value readOf(Value field, StringAttr ctor, unsigned index) {
  if (quantityOf(field.getType()) == Quantity::One && !field.hasOneUse())
    return {};
  if (auto read = field.getDefiningOp<FieldOp>())
    return read.getCtorAttr().getAttr() == ctor && read.getIndex() == index ? read.getValue()
                                                                           : Value();
  auto arg = dyn_cast<BlockArgument>(field);
  auto match = arg ? dyn_cast_or_null<MatchOp>(arg.getOwner()->getParentOp()) : MatchOp();
  if (!match || arg.getArgNumber() != index ||
      quantityOf(match.getScrutinee().getType()) == Quantity::One)
    return {};
  unsigned region = arg.getOwner()->getParent()->getRegionNumber();
  if (region >= match.getCases().size() ||
      cast<FlatSymbolRefAttr>(match.getCases()[region]).getAttr() != ctor)
    return {};
  return match.getScrutinee();
}

// Whether `value` is known to be built by the constructor `ctor` names
// where `at` is, because `at` is in the case of a match on the value that
// `ctor` takes: read from the match itself, with no declaration looked up.
bool knownFromMatch(Value value, StringAttr ctor, Operation *at) {
  for (Region *region = at->getParentRegion(); region; region = region->getParentRegion()) {
    auto match = dyn_cast<MatchOp>(region->getParentOp());
    if (!match || throughLinear(match.getScrutinee()) != throughLinear(value))
      continue;
    unsigned index = region->getRegionNumber();
    if (index < match.getCases().size() &&
        cast<FlatSymbolRefAttr>(match.getCases()[index]).getAttr() == ctor)
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
// other readers may share with x. An enclosing match that took x apart
// proves C on its own, as MatchOp::verifySymbolUses checked its cases, so
// the declaration is looked up, one scan of the module, only where no match
// proves it, and only to ask whether the type has another constructor at
// all: once every field reads the one source, either way.
Value eta(ConOp con) {
  auto fields = con.getFields();
  StringAttr name = con.getCtor().getLeafReference();
  Value source;
  for (auto [index, field] : llvm::enumerate(fields)) {
    Value read = readOf(field, name, static_cast<unsigned>(index));
    if (!read || (source && read != source))
      return {};
    source = read;
  }
  if (!source || source.getType() != con.getType())
    return {};
  if (knownFromMatch(source, name, con))
    return source;
  CtorOp ctor = constructorOf(con, con.getCtor());
  if (!ctor || cast<DataOp>(ctor->getParentOp()).getCtors().size() != 1)
    return {};
  return source;
}

} // namespace idr::canon
