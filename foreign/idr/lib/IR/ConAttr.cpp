// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// #idr.con: a constant constructor, its data type and its tag in it, held
// as a run of its cells, so that a constant as long as the data it is stays
// one level deep to MLIR's printer, parser, bytecode and walks. A plain
// constructor is the run of one cell; a list, or any other chain of one
// constructor through one field, the run of its cells, every one but the
// last without the field the next one is. It is written as it is held, the
// constructor by its name: `<!T, @C, [fields]>`, or `<!T, @C, [a], [b, t]
// along 1>`. A constructor is its type and its tag together: two types'
// constructors are two constructors.

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

// Whether `next`, field `at` of a cell of its own constructor, continues
// that cell as a run: it holds no constructor of its own, and it runs along
// `at` or is one cell, which runs along any field. A run's cells never hold
// one, by its form, so of a run only its last cell is asked, as of one cell.
bool continues(ConAttr next, unsigned at) {
  return (next.getRunLength() == 1 || next.getSpine() == at) &&
         !holdsConOf(next.getCells().back(), whichOf(next));
}

// The field `get` makes the spine of a run: the one field that is a
// constructor of `ctor`, where it continues the cell. A cell with two such
// fields is a node of a tree, and one whose such field runs along another
// field is a zig-zag; both stay one cell, which leaves one attribute per
// value.
std::optional<unsigned> joinedAt(Which ctor, ArrayAttr fields) {
  std::optional<unsigned> at;
  for (auto [index, field] : llvm::enumerate(fields)) {
    if (!conOf(field, ctor))
      continue;
    if (at)
      return std::nullopt;
    at = static_cast<unsigned>(index);
  }
  if (at && continues(cast<ConAttr>(fields[*at]), *at))
    return at;
  return std::nullopt;
}

// The cells of `ctor` over `fields` and their spine, in the one form `get`
// gives them: the fields as one cell, or, where a field continues them, the
// fields but that one and then the cells of the run it is.
struct Run {
  SmallVector<ArrayAttr> cells;
  unsigned spine = 0;
};

Run canonical(Which ctor, ArrayAttr fields) {
  std::optional<unsigned> at = joinedAt(ctor, fields);
  if (!at)
    return {{fields}, 0};
  Run run{{dropField(fields, *at)}, *at};
  llvm::append_range(run.cells, cast<ConAttr>(fields[*at]).getCells());
  return run;
}

// That `cells`, linked through field `spine`, are cells of the constructor
// `tag` of `data`: one or more, the last holding every field and every
// other every field but the spine, which is one of them. One cell runs
// along no field, which is spine 0.
LogicalResult verifyShape(function_ref<InFlightDiagnostic()> emitError, DataType data, Tag tag,
                          ArrayRef<ArrayAttr> cells, unsigned spine) {
  if (static_cast<uint32_t>(tag) >= data.getCtors().size())
    return emitError() << "expects a constructor of \"" << data.getName() << "\", which has "
                       << data.getCtors().size() << ", got the tag "
                       << static_cast<uint32_t>(tag);
  const Ctor &ctor = data.getCtor(tag);
  StringRef spelled = ctor.name.getValue();
  size_t width = ctor.fields.size();
  if (cells.empty())
    return emitError() << "expects @" << spelled << " to be at least one cell";
  if (cells.back().size() != width)
    return emitError() << "expects the last cell of @" << spelled << " to hold its " << width
                       << " fields";
  if (cells.size() == 1) {
    if (spine != 0)
      return emitError() << "expects @" << spelled
                         << " of one cell to run along no field, got field " << spine;
    return success();
  }
  if (spine >= width)
    return emitError() << "expects a run of @" << spelled << " along one of its " << width
                       << " fields, got field " << spine;
  if (llvm::any_of(cells.drop_back(), [&](ArrayAttr cell) { return cell.size() + 1 != width; }))
    return emitError() << "expects each cell of @" << spelled << " but the last to hold its "
                       << width << " fields but the spine";
  return success();
}

} // namespace

ConAttr ConAttr::get(MLIRContext *context, DataType data, Tag tag, ArrayAttr fields) {
  Run run = canonical({data, tag}, fields);
  return getStored(context, data, tag, run.cells, run.spine);
}

ConAttr ConAttr::getChecked(function_ref<InFlightDiagnostic()> emitError, MLIRContext *context,
                            DataType data, Tag tag, ArrayAttr fields) {
  if (failed(verifyShape(emitError, data, tag, {fields}, 0)))
    return {};
  return get(context, data, tag, fields);
}

// From the last cell back: `rest` is what the cells after this one make,
// and `pending` the cells before it, last first, that continue it as one
// run, unbuilt until the run ends, so that each cell costs its fields, not
// the run's length, as a `get` per cell would. A cell that holds a
// constructor of its own, or that `rest` does not continue along the spine,
// ends the run there, and `get` decides what it makes: one cell, since its
// constructor is held twice or does not continue.
ConAttr ConAttr::getRun(MLIRContext *context, DataType data, Tag tag, unsigned spine,
                        ArrayRef<ArrayAttr> cells) {
  assert(!cells.empty() && "a constructor is at least one cell");
  Which which{data, tag};
  ConAttr rest = get(context, data, tag, cells.back());
  SmallVector<ArrayAttr> pending;
  auto build = [&] {
    if (pending.empty())
      return;
    SmallVector<ArrayAttr> run(llvm::reverse(pending));
    llvm::append_range(run, rest.getCells());
    rest = getStored(context, data, tag, run, spine);
    pending.clear();
  };
  for (ArrayAttr cell : llvm::reverse(cells.drop_back())) {
    if (holdsConOf(cell, which) || (pending.empty() && !continues(rest, spine))) {
      build();
      rest = get(context, data, tag, insertField(cell, spine, rest));
      continue;
    }
    pending.push_back(cell);
  }
  build();
  return rest;
}

const Ctor &ConAttr::getCtor() const { return getData().getCtor(getTag()); }

void ConAttr::walkFields(function_ref<void(Attribute, unsigned)> each) const {
  for (auto [cell, fields] : llvm::enumerate(getCells()))
    for (auto [position, field] : llvm::enumerate(fields))
      each(field, fieldOfCell(static_cast<unsigned>(cell), static_cast<unsigned>(position)));
}

Attribute ConAttr::getField(unsigned index) const {
  ArrayRef<ArrayAttr> cells = getCells();
  unsigned spine = getSpine();
  if (cells.size() == 1)
    return cells.front()[index];
  if (index != spine)
    return cells.front()[index < spine ? index : index - 1];
  // The run from the second cell, canonical as this one is: two cells or
  // more stay a run, and the last cell alone is one cell, along no field.
  ArrayRef<ArrayAttr> rest = cells.drop_front();
  return getStored(getContext(), getData(), getTag(), rest, rest.size() == 1 ? 0 : spine);
}

ArrayAttr ConAttr::getFields() const {
  ArrayAttr first = getCells().front();
  if (getRunLength() == 1)
    return first;
  return insertField(first, getSpine(), getField(getSpine()));
}

// One value has one attribute, the one `get` and `getRun` build, so that
// equal constants are equal attributes. A replace of a sub-element rebuilds
// from the replaced parameters without canonicalizing, and is caught here.
LogicalResult ConAttr::verify(function_ref<InFlightDiagnostic()> emitError, DataType data,
                              Tag tag, ArrayRef<ArrayAttr> cells, unsigned spine) {
  if (failed(verifyShape(emitError, data, tag, cells, spine)))
    return failure();
  Which which{data, tag};
  StringRef spelled = data.getCtor(tag).name.getValue();
  // One cell is what `get` makes of its fields unless one of them continues
  // it; it may hold its own constructor where none does (a node of a tree).
  // The cells of a run hold none: one would be more of the run, which
  // `getRun` takes in, or a field that keeps its cell apart under `get`.
  if (cells.size() == 1) {
    if (std::optional<unsigned> at = joinedAt(which, cells.front()))
      return emitError() << "expects @" << spelled << " whose field " << *at
                         << " continues it as a run, not as one cell";
    return success();
  }
  if (llvm::any_of(cells, [&](ArrayAttr cell) { return holdsConOf(cell, which); }))
    return emitError() << "expects a run of @" << spelled << " whose cells hold no @" << spelled
                       << " of their own";
  return success();
}

// The stored parameters, as written: a constructor's cells and the field
// they run along. They are read into the one form `get` builds, so a value
// has one attribute however it is written: nested cells that form a run
// become one.
ConAttr ConAttr::getChecked(function_ref<InFlightDiagnostic()> emitError, MLIRContext *context,
                            DataType data, Tag tag, ArrayRef<ArrayAttr> cells, unsigned spine) {
  if (failed(verifyShape(emitError, data, tag, cells, spine)))
    return {};
  return getRun(context, data, tag, spine, cells);
}

// `<!T, @C, [fields]>`, or `<!T, @C, [a], [b, t] along 1>`: the data type,
// the constructor's name in it, the cells, and the field they run along,
// `along 0` left out. The cells, a list without brackets, end at the
// keyword or at `>`.
Attribute ConAttr::parse(AsmParser &parser, Type) {
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
  unsigned spine = 0;
  if (succeeded(parser.parseOptionalKeyword("along")) && parser.parseInteger(spine))
    return {};
  if (parser.parseGreater())
    return {};
  return getChecked([&] { return parser.emitError(loc); }, parser.getContext(), data,
                    Tag{static_cast<uint32_t>(tag.getInt())}, ArrayRef<ArrayAttr>(cells), spine);
}

void ConAttr::print(AsmPrinter &printer) const {
  printer << '<';
  printer.printType(getData());
  printer << ", ";
  printer.printSymbolName(getCtor().name.getValue());
  printer << ", ";
  llvm::interleaveComma(getCells(), printer, [&](ArrayAttr cell) { printer.printAttribute(cell); });
  if (unsigned spine = getSpine())
    printer << " along " << spine;
  printer << '>';
}
