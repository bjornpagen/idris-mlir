// idr.layout:layouts: the layouts of the values of a module. idr-lower
// builds values in these layouts, idr-eval's child reads its results back
// through them, and the owned stage and idr-stack size cells by them.
module;
// The runtime's C ABI: the size of a word and of a cell's header.
#include "idris_rt.h"

export module idr.layout:layouts;

import idr.mlir;
import idr.dialect;

import :cellinfo;
import :cells;
import :labels;
import :sums;

export namespace idr::layout {

class Layouts {
public:
  // The layouts of the values of `m`, for the target its data layout
  // describes (dlti.dl_spec; MLIR's defaults without one). Every cell's
  // header is decided here, once: when a box type or a cell has more than
  // its header can describe, each such one gets an `unsupported (layout)`
  // error and the result is a failure. A target whose pointers are not the
  // runtime's words is an internal error.
  static mlir::FailureOr<Layouts> of(mlir::ModuleOp m);

  // The bytes a component of type `component` takes in a cell, and the
  // alignment it is placed at, as the target lays it out.
  unsigned sizeOf(mlir::Type component) const;
  unsigned alignmentOf(mlir::Type component) const;

  // The runtime components of a value type: none for !idr.erased and
  // !idr.world, the slots of an unboxed sum, one pointer for strings, boxes,
  // closures and reuse tokens, one i64 for bigs, the type itself for
  // scalars.
  llvm::SmallVector<mlir::Type> components(mlir::Type type);
  // For each of those components, whether it is counted: a pointer to a
  // cell, a big's word, or a counted slot of a sum.
  llvm::SmallVector<bool> counted(mlir::Type type);

  // The layout of the unboxed sum named `name`, computed once.
  const SumLayout &sum(mlir::StringAttr name);

  // The element layout of an array of `element`, or why it has none: more
  // counted components than a cell's header counts, or a size its tag
  // cannot hold.
  std::expected<Element, std::string> element(mlir::Type element);

  // The cell of a boxed constructor, and of a closure of `label`.
  const Cell &box(CtorOp ctor) const;
  const Cell &closure(const Label &label) const;
  // The cell a forced suspension of label `id` reads: the code pointer and
  // the value. Null when the label is not a suspension.
  const Cell *forced(unsigned id) const;

  // The labels closures of this module use (idr.closure ops and
  // #idr.closure constants, nested ones included), numbered in the order a
  // walk of the module meets them: idr-lower and idr-eval compute the same
  // numbers from the same module. A closure of a function the module lacks
  // names no label; the verifier rejects it.
  unsigned labelId(mlir::FlatSymbolRefAttr callee, unsigned captures) const;
  unsigned labelId(const Label &label) const;
  const Label &label(unsigned id) const;
  unsigned numLabels() const;

  mlir::ModuleOp getModule() const;

private:
  explicit Layouts(mlir::ModuleOp m);

  // A cell whose first `leading` fields come first, before the object
  // slots, with the header `info` gives for its number of object slots.
  std::expected<Cell, std::string>
  cellOf(llvm::ArrayRef<mlir::Type> fieldTypes, unsigned leading,
         llvm::function_ref<std::expected<CellInfo, std::string>(unsigned objs)> info);

  // Capture cells, and a second cell of a suspension's stored value.
  bool placeClosures(mlir::Type pointer);

  mlir::ModuleOp module;
  mlir::DataLayout target;
  // Each layout has its own allocation, so that a reference to one stays
  // valid while others are computed.
  llvm::DenseMap<mlir::StringAttr, std::unique_ptr<SumLayout>> sums;
  llvm::DenseMap<mlir::Operation *, std::unique_ptr<Cell>> boxes;
  llvm::SmallVector<Label> labels;
  llvm::DenseMap<std::pair<mlir::Attribute, unsigned>, unsigned> labelIds;
  llvm::DenseMap<unsigned, std::unique_ptr<Cell>> closures;
  llvm::DenseMap<unsigned, std::unique_ptr<Cell>> forcedCells;
};

} // namespace idr::layout

using namespace mlir;

namespace idr::layout {

unsigned Layouts::sizeOf(Type component) const {
  return static_cast<unsigned>(target.getTypeSize(component).getFixedValue());
}

unsigned Layouts::alignmentOf(Type component) const {
  return static_cast<unsigned>(target.getTypeABIAlignment(component));
}

FailureOr<Layouts> Layouts::of(ModuleOp m) {
  Layouts layouts(m);
  // The runtime frees a cell by its object slots, which it reads as
  // pointers of the target it is compiled for, one word each; the layouts
  // must place them as it reads them. The module's data layout is the
  // target entry's (idr-target), the one the runtime is built for, so a
  // mismatch is the compiler's error, never the program's.
  Type pointer = LLVM::LLVMPointerType::get(m.getContext());
  if (layouts.sizeOf(pointer) != IDRIS_RT_WORD_BYTES ||
      layouts.alignmentOf(pointer) != IDRIS_RT_WORD_BYTES)
    return m.emitError() << "the module's target is not the runtime's: its pointers take "
                         << layouts.sizeOf(pointer)
                         << " bytes at an alignment of " << layouts.alignmentOf(pointer)
                         << ", and the runtime's object slots are words of "
                         << IDRIS_RT_WORD_BYTES;
  bool fits = true;
  for (auto data : m.getOps<DataOp>()) {
    if (!data.getBox())
      continue;
    SmallVector<CtorOp> ctors = data.getCtors();
    // A box's tag is in its header, which has room for this many
    // constructors; an unboxed sum's tag slot is as wide as its count needs.
    if (ctors.size() > IDRIS_RT_TAG_LIMIT) {
      data.emitError() << "unsupported (layout): the boxed type @" << data.getSymName() << " has "
                       << ctors.size() << " constructors, and a boxed type has at most "
                       << IDRIS_RT_TAG_LIMIT;
      fits = false;
      continue;
    }
    for (auto [tag, ctor] : llvm::enumerate(ctors)) {
      SmallVector<Type> fields;
      for (Attribute field : ctor.getFieldTypes())
        fields.push_back(cast<TypeAttr>(field).getValue());
      std::expected<Cell, std::string> cell =
          layouts.cellOf(fields, 0, [&](unsigned objs) { return CellInfo::box(tag, objs); });
      if (!cell) {
        ctor.emitError() << "unsupported (layout): a cell of the constructor @" << ctor.getSymName()
                         << " cannot be built: " << cell.error();
        fits = false;
        continue;
      }
      layouts.boxes[ctor] = std::make_unique<Cell>(std::move(*cell));
    }
  }
  if (!layouts.placeClosures(pointer))
    fits = false;
  if (!fits)
    return failure();
  return layouts;
}

unsigned Layouts::labelId(FlatSymbolRefAttr callee, unsigned captures) const {
  return labelIds.lookup(std::make_pair(Attribute(callee), captures));
}

const SumLayout &Layouts::sum(StringAttr name) {
  auto it = sums.find(name);
  if (it != sums.end())
    return *it->second;
  auto data = module.lookupSymbol<DataOp>(name);
  SumLayout layout;
  auto ctors = data.getCtors();
  Builder b(module.getContext());
  if (ctors.size() >= 2) {
    unsigned width = ctors.size() <= 256 ? 8u : ctors.size() <= 65536 ? 16u : 32u;
    layout.tag = b.getIntegerType(width);
  }
  for (CtorOp ctor : ctors) {
    SmallVector<bool> used(layout.slots.size(), false);
    SmallVector<SmallVector<unsigned>> perField;
    for (Attribute field : ctor.getFieldTypes()) {
      Type fieldType = cast<TypeAttr>(field).getValue();
      SmallVector<unsigned> slots;
      for (auto [component, isCounted] :
           llvm::zip_equal(components(fieldType), counted(fieldType))) {
        auto chosen = static_cast<unsigned>(layout.slots.size());
        for (unsigned i = 0; i < layout.slots.size(); ++i)
          if (!used[i] && layout.slots[i] == component && layout.counted[i] == isCounted) {
            chosen = i;
            break;
          }
        if (chosen == layout.slots.size()) {
          layout.slots.push_back(component);
          layout.counted.push_back(isCounted);
          used.push_back(false);
        }
        used[chosen] = true;
        slots.push_back(chosen);
      }
      perField.push_back(std::move(slots));
    }
    layout.fields[ctor.getSymName()] = std::move(perField);
  }
  auto &slot = sums[name];
  slot = std::make_unique<SumLayout>(std::move(layout));
  return *slot;
}

SmallVector<Type> Layouts::components(Type type) {
  MLIRContext *ctx = module.getContext();
  // Linearity is a fact for the passes; at runtime the value is itself.
  if (isErased(type) || isWorld(type))
    return {};
  type = unrestricted(type);
  // A destination is the address of a field's word.
  if (isa<StrType, BoxType, FnType, LazyType, TokenType, DestType>(type))
    return {LLVM::LLVMPointerType::get(ctx)};
  // An array is its cell and its length, the memref's dimension: a bounds
  // check compares two registers, so the one a program's own test made
  // redundant folds away, where a load of the length from the cell, which
  // the stores into the cell may alias, would stay in every loop.
  if (isArray(type))
    return {LLVM::LLVMPointerType::get(ctx), IntegerType::get(ctx, 64)};
  if (isa<BigType, NatType>(type))
    return {IntegerType::get(ctx, 64)};
  if (auto data = dyn_cast<DataType>(type))
    return sum(data.getName().getAttr()).types();
  return {type};
}

SmallVector<bool> Layouts::counted(Type type) {
  if (isErased(type) || isWorld(type))
    return {};
  type = unrestricted(type);
  if (isa<StrType, BoxType, FnType, LazyType, TokenType, BigType, NatType>(type))
    return {true};
  if (isArray(type))
    return {true, false};
  if (isa<DestType>(type))
    return {false};
  if (auto data = dyn_cast<DataType>(type)) {
    const SumLayout &layout = sum(data.getName().getAttr());
    SmallVector<bool> all;
    if (layout.tag)
      all.push_back(false);
    all.append(layout.counted.begin(), layout.counted.end());
    return all;
  }
  return {false};
}

// An element is laid out as a cell of one field, less the header: the
// offsets start at the element, and the stride is the element's size at
// its own alignment, so that a byte element takes one byte and a buffer's
// bytes are contiguous; an element with an object slot takes whole words.
std::expected<Element, std::string> Layouts::element(Type type) {
  std::expected<Cell, std::string> cell =
      cellOf(type, 0, [](unsigned objs) { return CellInfo::box(0, objs); });
  if (!cell)
    return std::unexpected(std::move(cell.error()));
  constexpr unsigned header = sizeof(idris_rt_header);
  SmallVector<Slot> slots = std::move(cell->fields.front());
  unsigned end = 0, alignment = 1;
  for (Slot &slot : slots) {
    slot.offset -= header;
    end = std::max(end, slot.offset + sizeOf(slot.type));
    alignment = std::max(alignment, alignmentOf(slot.type));
  }
  unsigned stride = static_cast<unsigned>(llvm::alignTo(end, alignment));
  std::expected<CellInfo, std::string> info = CellInfo::array(stride, cell->objs);
  if (!info)
    return std::unexpected(std::move(info.error()));
  return Element{std::move(slots), stride, *info};
}

std::expected<Cell, std::string>
Layouts::cellOf(ArrayRef<Type> fieldTypes, unsigned leading,
                function_ref<std::expected<CellInfo, std::string>(unsigned objs)> info) {
  SmallVector<SmallVector<Slot>> fields;
  SmallVector<SmallVector<bool>> countedness;
  for (Type field : fieldTypes) {
    SmallVector<Slot> slots;
    for (Type component : components(field))
      slots.push_back({component, 0});
    fields.push_back(std::move(slots));
    countedness.push_back(counted(field));
  }
  SmallVector<std::pair<unsigned, unsigned>> order;
  unsigned objs = 0;
  unsigned at = sizeof(idris_rt_header);
  auto place = [&](unsigned field, unsigned component) {
    Slot &slot = fields[field][component];
    at = static_cast<unsigned>(llvm::alignTo(at, alignmentOf(slot.type)));
    slot.offset = at;
    at += sizeOf(slot.type);
    order.push_back({field, component});
  };
  auto count = static_cast<unsigned>(fieldTypes.size());
  for (unsigned f = 0; f < std::min(leading, count); ++f)
    for (unsigned c = 0; c < fields[f].size(); ++c)
      place(f, c);
  // The object slots, each a word, so contiguous.
  for (unsigned f = leading; f < count; ++f)
    for (unsigned c = 0; c < fields[f].size(); ++c)
      if (countedness[f][c]) {
        place(f, c);
        ++objs;
      }
  // The other components, the most aligned first, so that the small ones
  // (the tags of unboxed sums, characters, booleans) share a word instead
  // of each taking one: the order of fields in the source is not a layout.
  SmallVector<std::pair<unsigned, unsigned>> others;
  for (unsigned f = leading; f < count; ++f)
    for (unsigned c = 0; c < fields[f].size(); ++c)
      if (!countedness[f][c])
        others.push_back({f, c});
  llvm::stable_sort(others, [&](std::pair<unsigned, unsigned> a, std::pair<unsigned, unsigned> b) {
    return alignmentOf(fields[a.first][a.second].type) > alignmentOf(fields[b.first][b.second].type);
  });
  for (auto [f, c] : others)
    place(f, c);
  std::expected<CellInfo, std::string> header = info(objs);
  if (!header)
    return std::unexpected(std::move(header.error()));
  return Cell{std::move(fields), static_cast<unsigned>(llvm::alignTo(at, IDRIS_RT_WORD_BYTES)), objs,
              std::move(order), *header};
}

const Cell &Layouts::box(CtorOp ctor) const { return *boxes.find(ctor)->second; }

const Cell &Layouts::closure(const Label &label) const {
  return *closures.find(labelId(label))->second;
}

const Cell *Layouts::forced(unsigned id) const {
  auto it = forcedCells.find(id);
  return it == forcedCells.end() ? nullptr : it->second.get();
}

unsigned Layouts::labelId(const Label &label) const {
  return labelId(label.callee, label.captures);
}

const Label &Layouts::label(unsigned id) const { return labels[id]; }

unsigned Layouts::numLabels() const { return static_cast<unsigned>(labels.size()); }

ModuleOp Layouts::getModule() const { return module; }

} // namespace idr::layout
