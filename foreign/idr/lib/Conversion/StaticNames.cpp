// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a static datum is named: the digest of its content, which names
// everything the datum points at by that thing's own name, so that two
// constants of one content are one global whatever wrote them, and no
// order of writing reaches a name. An attribute or a type is digested from
// its canonical text, which no printing flag reaches and which is printed
// once for each attribute and type, however many data hold it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/StaticData.h"

#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The prefix every name of static data starts with, which no C symbol
// takes, since C never names a symbol with a dot.
constexpr llvm::StringLiteral owner = "__idr";

// A digest as the words of a key.
std::string hex(Digest digest) {
  std::string text;
  llvm::raw_string_ostream(text) << digest;
  return text;
}

} // namespace

StaticData::Named StaticData::intern(Location loc, StringRef kind, Digest key) {
  FailureOr<StringAttr> name = names.intern(loc, owner, kind, key);
  collision = collision || failed(name);
  return {failed(name) ? contentName(owner, kind, key) : name->str(), key};
}

Digest StaticData::cellKey(Type type, const Ctor &ctor, ArrayRef<std::string> fields) {
  return digestOf(hex(canonicalHash(type)) + " " + ctor.name.getValue().str() + "(" +
                  llvm::join(fields, ", ") + ")");
}

std::string StaticData::fieldKey(Location loc, Attribute value, Type type) {
  if (isWorld(type))
    return "world";
  type = unrestricted(type);
  if (auto text = dyn_cast<StringAttr>(value))
    return "&" + intern(loc, "str", digestOf(text.getValue())).name;
  if (isa<BigAttr, IntegerAttr, FloatAttr>(value))
    return hex(canonicalHash(value));
  auto con = cast<ConAttr>(value);
  if (isa<DataType>(type)) {
    const Ctor &ctor = con.getCtor();
    SmallVector<std::string> fields;
    for (auto [i, field] : llvm::enumerate(con.getFields()))
      fields.push_back(fieldKey(loc, field, ctor.fields[i]));
    return hex(cellKey(type, ctor, fields));
  }
  return "&" + boxName(loc, con, type).name;
}

// A box is named from its content, which names everything it points at by
// that thing's own name: so the name of a run's cell is a function of the
// cells after it, written from the tail back, and a constant that names a
// run from one of its cells on finds that cell. A memo cell is then one per
// value, as a force needs: it would otherwise run and store the same value
// twice.
StaticData::Named StaticData::boxName(Location loc, ConAttr con, Type type) {
  auto cached = boxNames.find({con, type});
  if (cached != boxNames.end())
    return cached->second;
  Named named;
  if (con.isRun()) {
    named = runNames(loc, con, type).front();
  } else {
    const Ctor &ctor = con.getCtor();
    SmallVector<std::string> fields;
    for (auto [i, field] : llvm::enumerate(con.getFields()))
      fields.push_back(fieldKey(loc, field, ctor.fields[i]));
    named = intern(loc, kindOf(con.getData(), con.getTag()), cellKey(type, ctor, fields));
  }
  boxNames.try_emplace({con, type}, named);
  return named;
}

// The names of a run's cells, first to last, each from the cells after it.
SmallVector<StaticData::Named> StaticData::runNames(Location loc, ConAttr con, Type type) {
  DataType data = con.getData();
  unsigned tag = con.getTag();
  const Ctor &ctor = con.getCtor();
  unsigned spine = con.getSpine();
  Type spineType = unrestricted(ctor.fields[spine]);
  ArrayRef<ArrayAttr> cells = con.getRunCells();
  SmallVector<Named> named(cells.size());
  std::string next = boxName(loc, cast<ConAttr>(con.getTail()), spineType).name;
  for (size_t k = cells.size(); k-- > 0;) {
    SmallVector<std::string> fields;
    for (auto [index, fieldType] : llvm::enumerate(ctor.fields)) {
      auto i = static_cast<unsigned>(index);
      fields.push_back(i == spine ? "&" + next
                                  : fieldKey(loc, cells[k][i < spine ? i : i - 1], fieldType));
    }
    named[k] = intern(loc, kindOf(data, tag), cellKey(k == 0 ? type : spineType, ctor, fields));
    next = named[k].name;
  }
  return named;
}

// A static memo cell's kind, or a box's.
StringRef StaticData::kindOf(DataType data, unsigned tag) const {
  return isMemoCell(layouts.box(data, tag)) ? "caf" : "box";
}

} // namespace idr::conversion
