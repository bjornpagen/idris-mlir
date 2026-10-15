// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// #idr.con: a constant constructor, its data type and its tag in it, held
// plain or, for a list or any other chain of one constructor through one
// field, as a flat run of its cells, so that a constant as long as the data
// it is stays one level deep to MLIR's printer, parser, bytecode and walks.
// It is written as it is held, the constructor by its name: `<!T, @C,
// [fields]>`, or `<!T, @C, [a], [b] tail t along 1>`. A constructor is its
// type and its tag together: two types' constructors are two constructors.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/DialectImplementation.h"

using namespace mlir;
using namespace idr;

namespace {

// A constructor: a data type and its tag in it.
struct Which {
  DataType data;
  Tag tag;
  bool operator==(const Which &) const = default;
};

Which whichOf(ConAttr con) { return {con.getData(), con.getTag()}; }

// `value` as a constructor of `ctor`, or null.
ConAttr conOf(Attribute value, Which ctor) {
  auto con = dyn_cast_if_present<ConAttr>(value);
  return con && whichOf(con) == ctor ? con : ConAttr();
}

bool holdsConOf(ArrayAttr fields, Which ctor) {
  return llvm::any_of(fields,
                      [&](Attribute field) { return static_cast<bool>(conOf(field, ctor)); });
}

ArrayAttr dropField(ArrayAttr fields, unsigned index) {
  SmallVector<Attribute> rest(fields.getValue());
  rest.erase(rest.begin() + index);
  return ArrayAttr::get(fields.getContext(), rest);
}

ArrayAttr insertField(ArrayAttr cell, unsigned index, Attribute field) {
  SmallVector<Attribute> fields(cell.getValue());
  fields.insert(fields.begin() + index, field);
  return ArrayAttr::get(cell.getContext(), fields);
}

// Whether `next`, field `at` of a cell of its own constructor with `width`
// other fields, continues that cell as a run: it is a run along the same
// field, or a plain con that holds no constructor of its own, which becomes
// the run's last cell. A con of another width is not the same constructor's
// cell, and stays a field.
bool continues(ConAttr next, unsigned at, size_t width) {
  ArrayAttr first = next.getCells().front();
  if (next.isRun())
    return next.getSpine() == at && first.size() == width;
  return first.size() == width + 1 && !holdsConOf(first, whichOf(next));
}

// The field `get` makes the spine of a run: the one field that is a
// constructor of `ctor`, where it continues the cell. A cell with two such
// fields is a node of a tree, and one whose such field runs along another
// field is a zig-zag; both stay plain, which leaves one attribute per value.
std::optional<unsigned> joinedAt(Which ctor, ArrayAttr fields) {
  std::optional<unsigned> at;
  for (auto [index, field] : llvm::enumerate(fields)) {
    if (!conOf(field, ctor))
      continue;
    if (at)
      return std::nullopt;
    at = static_cast<unsigned>(index);
  }
  if (at && continues(cast<ConAttr>(fields[*at]), *at, fields.size() - 1))
    return at;
  return std::nullopt;
}

// Appends the cells `next` brings to a run along `at`, and returns what
// follows them.
Attribute takeCells(ConAttr next, unsigned at, SmallVectorImpl<ArrayAttr> &cells) {
  if (next.isRun()) {
    llvm::append_range(cells, next.getCells());
    return next.getTail();
  }
  ArrayAttr last = next.getCells().front();
  cells.push_back(dropField(last, at));
  return last[at];
}

// The stored parameters of `ctor` over `fields`, in the one form `get`
// gives them.
struct Parts {
  SmallVector<ArrayAttr> cells;
  Attribute tail;
  unsigned spine = 0;
};

Parts canonical(Which ctor, ArrayAttr fields) {
  Parts parts;
  std::optional<unsigned> at = joinedAt(ctor, fields);
  if (!at) {
    parts.cells.push_back(fields);
    return parts;
  }
  parts.cells.push_back(dropField(fields, *at));
  parts.tail = takeCells(cast<ConAttr>(fields[*at]), *at, parts.cells);
  parts.spine = *at;
  return parts;
}

// That `cells` can be linked through field `spine`: each holds the same
// fields but the spine, which goes among them.
LogicalResult verifyCells(function_ref<InFlightDiagnostic()> emitError, unsigned spine,
                          ArrayRef<ArrayAttr> cells) {
  if (cells.empty())
    return emitError() << "expects a run of at least one cell";
  size_t width = cells.front().size();
  if (llvm::any_of(cells, [&](ArrayAttr cell) { return cell.size() != width; }))
    return emitError() << "expects the cells of a run to have one width";
  if (spine > width)
    return emitError() << "expects a run's spine to be at most its cells' width " << width
                       << ", got " << spine;
  return success();
}

} // namespace

ConAttr ConAttr::get(MLIRContext *context, DataType data, Tag tag, ArrayAttr fields) {
  Parts parts = canonical({data, tag}, fields);
  return getStored(context, data, tag, parts.cells, parts.tail, parts.spine,
                   NoneType::get(context));
}

ConAttr ConAttr::getChecked(function_ref<InFlightDiagnostic()> emitError, MLIRContext *context,
                            DataType data, Tag tag, ArrayAttr fields) {
  Parts parts = canonical({data, tag}, fields);
  return getStoredChecked(emitError, context, data, tag, parts.cells, parts.tail, parts.spine,
                          NoneType::get(context));
}

// From the last cell back, the cells that so far form one run with what
// follows them stay unbuilt, so that each cell costs its fields, not the
// run's length, as a `get` per cell would. A cell that holds a constructor
// of its own ends the run there, and `get` decides what it makes.
ConAttr ConAttr::getRun(MLIRContext *context, DataType data, Tag tag, unsigned spine,
                        ArrayRef<ArrayAttr> cells, Attribute tail) {
  Which which{data, tag};
  assert(!cells.empty() && tail && "a run is at least one cell and a tail");
  size_t width = cells.front().size();
  // The unbuilt cells, last first, and what follows them, which is never a
  // constructor of `ctor` while there are any.
  SmallVector<ArrayAttr> pending;
  Attribute rest = tail;
  auto build = [&] {
    if (pending.empty())
      return;
    if (pending.size() == 1) {
      rest = get(context, data, tag, insertField(pending.front(), spine, rest));
    } else {
      SmallVector<ArrayAttr> run(llvm::reverse(pending));
      rest = getStored(context, data, tag, run, rest, spine, NoneType::get(context));
    }
    pending.clear();
  };
  for (ArrayAttr cell : llvm::reverse(cells)) {
    assert(cell.size() == width && "the cells of a run have one width");
    ConAttr next = pending.empty() ? conOf(rest, which) : ConAttr();
    if (holdsConOf(cell, which) || (next && !continues(next, spine, width))) {
      build();
      rest = get(context, data, tag, insertField(cell, spine, rest));
      continue;
    }
    if (next) {
      SmallVector<ArrayAttr> taken;
      rest = takeCells(next, spine, taken);
      pending.append(taken.rbegin(), taken.rend());
    }
    pending.push_back(cell);
  }
  build();
  return cast<ConAttr>(rest);
}

const Ctor &ConAttr::getCtor() const { return getData().getCtor(getTag()); }

Attribute ConAttr::getField(unsigned index) const {
  ArrayAttr first = getCells().front();
  unsigned spine = getSpine();
  if (!isRun() || index < spine)
    return first[index];
  if (index > spine)
    return first[index - 1];
  // The run from the second cell, canonical as this one is: two cells or
  // more stay a run, and the last cell alone is a plain con.
  MLIRContext *ctx = getContext();
  ArrayRef<ArrayAttr> rest = getCells().drop_front();
  if (rest.size() > 1)
    return getStored(ctx, getData(), getTag(), rest, getTail(), spine, NoneType::get(ctx));
  ArrayAttr last = insertField(rest.front(), spine, getTail());
  return getStored(ctx, getData(), getTag(), last, Attribute(), 0, NoneType::get(ctx));
}

ArrayAttr ConAttr::getFields() const {
  ArrayAttr first = getCells().front();
  if (!isRun())
    return first;
  return insertField(first, getSpine(), getField(getSpine()));
}

// One value has one attribute, the one `get` and `getRun` build, so that
// equal constants are equal attributes. A replace of a sub-element rebuilds
// from the replaced parameters without canonicalizing, and is caught here.
// The constructor is one of its type's, and every cell holds its fields.
LogicalResult ConAttr::verify(function_ref<InFlightDiagnostic()> emitError, DataType data,
                              Tag tag, ArrayRef<ArrayAttr> cells, Attribute tail,
                              unsigned spine, Type) {
  if (static_cast<uint32_t>(tag) >= data.getCtors().size())
    return emitError() << "expects a constructor of \"" << data.getName() << "\", which has "
                       << data.getCtors().size() << ", got the tag "
                       << static_cast<uint32_t>(tag);
  const Ctor &ctor = data.getCtor(tag);
  StringRef spelled = ctor.name.getValue();
  // A run's cells hold every field but the spine.
  size_t width = ctor.fields.size() - (tail ? 1 : 0);
  if ((tail && ctor.fields.empty()) ||
      llvm::any_of(cells, [&](ArrayAttr cell) { return cell.size() != width; }))
    return emitError() << "expects each cell of @" << spelled << " to hold its "
                       << ctor.fields.size() << " fields" << (tail ? " but the spine" : "");
  Which which{data, tag};
  if (!tail) {
    if (cells.size() != 1 || spine != 0)
      return emitError() << "expects a plain constructor to hold its fields as one cell, "
                            "along spine 0";
    if (std::optional<unsigned> at = joinedAt(which, cells.front()))
      return emitError() << "expects @" << spelled << " whose field " << *at
                         << " continues it as a run, not as a plain constructor";
    return success();
  }
  if (cells.size() < 2)
    return emitError() << "expects a run of at least two cells";
  if (failed(verifyCells(emitError, spine, cells)))
    return failure();
  // A constructor of the run's own in a cell or as its tail is either more
  // of the run, which `getRun` takes in, or a field that keeps a cell plain
  // under `get`.
  if (llvm::any_of(cells, [&](ArrayAttr cell) { return holdsConOf(cell, which); }) ||
      conOf(tail, which))
    return emitError() << "expects a run of @" << spelled << " whose cells and tail hold no @"
                       << spelled << " of their own";
  return success();
}

// The stored parameters, as written: a plain constructor's one cell, or a
// run's cells, its tail and the field it runs along. Either is read into the
// one form `get` builds, so a value has one attribute however it is
// written: nested plain constructors that form a run become one, and a run
// that is one cell is a plain constructor.
ConAttr ConAttr::getChecked(function_ref<InFlightDiagnostic()> emitError, MLIRContext *context,
                            DataType data, Tag tag, ArrayRef<ArrayAttr> cells,
                            Attribute tail, unsigned spine, Type type) {
  ConAttr con;
  if (tail) {
    if (failed(verifyCells(emitError, spine, cells)))
      return {};
    con = getRun(context, data, tag, spine, cells, tail);
  } else if (cells.size() != 1 || spine != 0) {
    emitError() << "expects a constructor without a tail to be one cell, along spine 0";
    return {};
  } else {
    con = getChecked(emitError, context, data, tag, cells.front());
  }
  // MLIR's parser hands the type after an attribute to the attribute; the
  // constant that holds it takes it from there.
  if (!con || !type || isa<NoneType>(type))
    return con;
  return getStoredChecked(emitError, context, con.getData(), con.getTag(), con.getCells(),
                          con.getTail(), con.getSpine(), type);
}

// `<!T, @C, [fields]>`, or `<!T, @C, [a], [b] tail t along 1>`: the data
// type, the constructor's name in it, the cells, and for a run its tail and
// the field it runs along, `along 0` left out. Each optional group starts
// with its keyword, so the cells, a list without brackets, end at it.
Attribute ConAttr::parse(AsmParser &parser, Type type) {
  SMLoc loc = parser.getCurrentLocation();
  Type written;
  IntegerAttr tag;
  if (parser.parseLess() || parser.parseType(written) || parser.parseComma())
    return {};
  auto data = dyn_cast<DataType>(written);
  if (!data) {
    parser.emitError(loc) << "expects the data type of a constructor, got " << written;
    return {};
  }
  SmallVector<ArrayAttr> cells;
  if (parseCtorRef(parser, data, tag) || parser.parseComma() ||
      parser.parseCommaSeparatedList([&]() { return parser.parseAttribute(cells.emplace_back()); }))
    return {};
  Attribute tail;
  unsigned spine = 0;
  if (succeeded(parser.parseOptionalKeyword("tail")) && parser.parseAttribute(tail))
    return {};
  if (succeeded(parser.parseOptionalKeyword("along")) && parser.parseInteger(spine))
    return {};
  if (parser.parseGreater())
    return {};
  return getChecked([&] { return parser.emitError(loc); }, parser.getContext(), data,
                    Tag{static_cast<uint32_t>(tag.getInt())}, ArrayRef<ArrayAttr>(cells), tail,
                    spine, type);
}

void ConAttr::print(AsmPrinter &printer) const {
  printer << '<';
  printer.printType(getData());
  printer << ", ";
  printer.printSymbolName(getCtor().name.getValue());
  printer << ", ";
  llvm::interleaveComma(getCells(), printer, [&](ArrayAttr cell) { printer.printAttribute(cell); });
  if (Attribute tail = getTail()) {
    printer << " tail ";
    printer.printAttribute(tail);
  }
  if (unsigned spine = getSpine())
    printer << " along " << spine;
  printer << '>';
}
