// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// #idr.con: a constant constructor value, its data type refined to its
// constructor, held as a run of its cells, so that a constant as long as the
// data it is stays one level deep to MLIR's printer, parser, bytecode and
// walks. A plain constructor is the run of one cell; a list, a vector, or
// any other chain of one constructor through one field, the run of its
// cells, every one but the last without the field the next one is. A run
// is cells of one constructor of one member, whatever its index: the type
// of each cell after the first is the spine field's at the one before, so
// a `Vect 1000` constant is one run though each cell's index differs. It is
// written as it is held: `<!idr.data<#List @Cons>, [fields]>`, or
// `<!T, [a], [b, t] along 1>`. A constant of a memo cell or of a family
// rebuilt in place cannot be written: something reads which value each is,
// so neither is one shared constant.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/FamilyStorage.h"

#include "mlir/IR/DialectImplementation.h"

using namespace mlir;
using namespace idr;

// The parameters, as the storage holds them (FamilyStorage.h): the cells
// are attributes, each an array of its fields, the verifier says, an array
// of arrays a bytecode reader can own as it reads.
DataType ConAttr::getData() const { return getImpl()->data; }
ArrayRef<Attribute> ConAttr::getCells() const { return getImpl()->cells; }
uint64_t ConAttr::getSpine() const { return getImpl()->spine; }

namespace {

// A constructor of a run: its member and tag, whatever its index.
struct Which {
  FamilyAttr group;
  uint32_t member;
  Tag tag;
  bool operator==(const Which &) const = default;
};

Which whichOf(ConAttr con) {
  return {con.getData().getGroup(), con.getData().getMember(), con.getTag()};
}

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
// `at` or is one cell, which runs along any field.
bool continues(ConAttr next, unsigned at) {
  return (next.getRunLength() == 1 || next.getSpine() == at) &&
         !holdsConOf(next.getCell(next.getRunLength() - 1), whichOf(next));
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

// The type of the run after a cell of `data` along `spine`: the spine
// field's type at this application, refined to the same constructor.
DataType restOf(DataType data, unsigned spine) {
  Tag tag = *data.singleTag();
  SmallVector<Type> fields = *data.determinedFields(tag);
  return cast<DataType>(unrestricted(fields[spine])).refined({tag});
}

// That `cells`, linked through field `spine`, are cells of the constructor
// `data` is refined to: one or more, the last holding every field and every
// other every field but the spine. A memo cell or a family rebuilt in place
// is no constant.
LogicalResult verifyShape(function_ref<InFlightDiagnostic()> emitError, DataType data,
                          ArrayRef<Attribute> written, uint64_t spine) {
  std::optional<Tag> tag = data.singleTag();
  if (!tag || !data.determinedFields(*tag))
    return emitError() << "expects a data type refined to one constructor whose binders it "
                       << "determines, got " << data;
  if (data.kind() == MemberKind::Memo || data.kind() == MemberKind::Frames ||
      data.promise() == Promise::InPlace)
    return emitError() << "expects a value no reader tells apart from an equal one, got "
                       << data;
  StringRef spelled = data.ctor(*tag).label;
  size_t width = data.ctor(*tag).fields.size();
  if (!llvm::all_of(written, [](Attribute cell) { return isa<ArrayAttr>(cell); }))
    return emitError() << "expects each cell of @" << spelled << " to be an array of its fields";
  auto cells = llvm::map_to_vector(written, [](Attribute cell) { return cast<ArrayAttr>(cell); });
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
  if (llvm::any_of(ArrayRef<ArrayAttr>(cells).drop_back(),
                   [&](ArrayAttr cell) { return cell.size() + 1 != width; }))
    return emitError() << "expects each cell of @" << spelled << " but the last to hold its "
                       << width << " fields but the spine";
  return success();
}

} // namespace

namespace {

ConAttr stored(MLIRContext *context, DataType data, ArrayRef<ArrayAttr> cells, unsigned spine) {
  SmallVector<Attribute> held(cells.begin(), cells.end());
  return ConAttr::get(context, data, ArrayRef<Attribute>(held), uint64_t{spine});
}

// The cells of `con`, as arrays.
SmallVector<ArrayAttr> cellsOf(ConAttr con) {
  return llvm::map_to_vector(con.getCells(), [](Attribute cell) { return cast<ArrayAttr>(cell); });
}

} // namespace

ArrayAttr ConAttr::getCell(unsigned cell) const { return cast<ArrayAttr>(getCells()[cell]); }

ConAttr ConAttr::get(MLIRContext *context, DataType data, ArrayAttr fields) {
  Which which{data.getGroup(), data.getMember(), *data.singleTag()};
  std::optional<unsigned> at = joinedAt(which, fields);
  if (!at)
    return stored(context, data, {fields}, 0);
  SmallVector<ArrayAttr> cells{dropField(fields, *at)};
  llvm::append_range(cells, cellsOf(cast<ConAttr>(fields[*at])));
  return stored(context, data, cells, *at);
}

// From the last cell back: `rest` is what the cells after this one make,
// each cell's type the spine field's of the one before, and `pending` the
// cells before it that continue it as one run, unbuilt until the run ends,
// so that each cell costs its fields, not the run's length.
ConAttr ConAttr::getRun(MLIRContext *context, DataType data, unsigned spine,
                        ArrayRef<ArrayAttr> cells) {
  SmallVector<DataType> types{data};
  for (size_t i = 1; i < cells.size(); ++i)
    types.push_back(restOf(types.back(), spine));
  Which which{data.getGroup(), data.getMember(), *data.singleTag()};
  ConAttr rest = get(context, types.back(), cells.back());
  SmallVector<ArrayAttr> pending;
  auto build = [&](DataType at) {
    if (pending.empty())
      return;
    SmallVector<ArrayAttr> run(llvm::reverse(pending));
    llvm::append_range(run, cellsOf(rest));
    rest = stored(context, at, run, spine);
    pending.clear();
  };
  for (size_t i = cells.size() - 1; i-- > 0;) {
    ArrayAttr cell = cells[i];
    if (holdsConOf(cell, which) || (pending.empty() && !continues(rest, spine))) {
      build(types[i + 1]);
      rest = get(context, types[i], insertField(cell, spine, rest));
      continue;
    }
    pending.push_back(cell);
  }
  build(types.front());
  return rest;
}

Tag ConAttr::getTag() const { return *getData().singleTag(); }
unsigned ConAttr::getRunLength() const { return static_cast<unsigned>(getCells().size()); }

unsigned ConAttr::fieldOfCell(unsigned cell, unsigned position) const {
  return cell + 1 == getRunLength() || position < getSpine() ? position : position + 1;
}

Attribute ConAttr::getField(unsigned index) const {
  auto spine = static_cast<unsigned>(getSpine());
  if (getRunLength() == 1)
    return getCell(0)[index];
  if (index != spine)
    return getCell(0)[index < spine ? index : index - 1];
  // The run from the second cell, canonical as this one is: its cells are
  // this one's, held already, so only the attribute is new.
  ArrayRef<Attribute> rest = getCells().drop_front();
  return get(getContext(), restOf(getData(), spine), rest, rest.size() == 1 ? 0 : uint64_t{spine});
}

ArrayAttr ConAttr::getFields() const {
  ArrayAttr first = getCell(0);
  if (getRunLength() == 1)
    return first;
  auto spine = static_cast<unsigned>(getSpine());
  return insertField(first, spine, getField(spine));
}

// One value has one attribute, the one `get` and `getRun` build. A replace
// of a sub-element rebuilds from the replaced parameters without
// canonicalizing, and is caught here.
LogicalResult ConAttr::verify(function_ref<InFlightDiagnostic()> emitError, DataType data,
                              ArrayRef<Attribute> written, uint64_t spine) {
  if (failed(verifyShape(emitError, data, written, spine)))
    return failure();
  auto cells = llvm::map_to_vector(written, [](Attribute cell) { return cast<ArrayAttr>(cell); });
  Which which{data.getGroup(), data.getMember(), *data.singleTag()};
  StringRef spelled = data.ctor(which.tag).label;
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

// The parser's and bytecode's builder: cells of the right shape, made into
// the one attribute `get` gives for the same value however they were linked.
// It takes its diagnostic callback in the form upstream's getChecked and
// verify do, since it runs the check `verify` runs.
ConAttr ConAttr::getNormalized(function_ref<InFlightDiagnostic()> emitError,
                               MLIRContext *context, DataType data, ArrayRef<Attribute> written,
                               uint64_t spine) {
  if (failed(verifyShape(emitError, data, written, spine)))
    return {};
  auto cells = llvm::map_to_vector(written, [](Attribute cell) { return cast<ArrayAttr>(cell); });
  return getRun(context, data, static_cast<unsigned>(spine), cells);
}

// The bytecode's builder: the cells as read, checked and made canonical as
// the parser's are.
ConAttr idr::readCon(DialectBytecodeReader &reader, MLIRContext *context, DataType data,
                     ArrayRef<Attribute> cells, uint64_t spine) {
  return ConAttr::getNormalized([&] { return reader.emitError(); }, context, data, cells, spine);
}

// `<!T, [fields]>`, or `<!T, [a], [b, t] along 1>`: the refined data type,
// the cells, and the field they run along, `along 0` left out.
Attribute ConAttr::parse(AsmParser &parser, Type) {
  SMLoc loc = parser.getCurrentLocation();
  Type written;
  if (parser.parseLess() || parser.parseType(written) || parser.parseComma())
    return {};
  auto data = dyn_cast<DataType>(written);
  if (!data) {
    parser.emitError(loc) << "expects the data type of a constructor, got " << written;
    return {};
  }
  SmallVector<Attribute> cells;
  if (parser.parseCommaSeparatedList([&]() { return parser.parseAttribute(cells.emplace_back()); }))
    return {};
  uint64_t spine = 0;
  if (succeeded(parser.parseOptionalKeyword("along")) && parser.parseInteger(spine))
    return {};
  if (parser.parseGreater())
    return {};
  return getNormalized([&] { return parser.emitError(loc); }, parser.getContext(), data, cells,
                       spine);
}

void ConAttr::print(AsmPrinter &printer) const {
  printer << '<';
  printer.printType(getData());
  printer << ", ";
  llvm::interleaveComma(getCells(), printer, [&](Attribute cell) { printer.printAttribute(cell); });
  if (uint64_t spine = getSpine())
    printer << " along " << spine;
  printer << '>';
}
