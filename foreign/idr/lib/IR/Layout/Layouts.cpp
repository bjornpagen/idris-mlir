// The layouts of the values of a module, computed whole when a pass first
// asks for them.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/MathExtras.h"

#include "idris_rt.h"

#include <algorithm>

using namespace mlir;

namespace idr {

namespace {

// The size and alignment of `component` as `target` lays it out.
std::pair<unsigned, unsigned> measure(const DataLayout &target, Type component) {
  return {static_cast<unsigned>(target.getTypeSize(component).getFixedValue()),
          static_cast<unsigned>(target.getTypeABIAlignment(component))};
}

} // namespace

Layouts::Layouts(Operation *op) : Components(cast<ModuleOp>(op)) {
  ModuleOp m = getModule();
  MLIRContext *ctx = m.getContext();
  DataLayout target(m);
  auto record = [&](Type component) {
    if (!measures.contains(component))
      measures.try_emplace(component, measure(target, component));
  };
  // The runtime frees a cell by its object slots, which it reads as
  // pointers of the target it is compiled for, one word each; the layouts
  // must place them as it reads them. The module's data layout is the
  // target entry's (idr-target), the one the runtime is built for, so a
  // mismatch is the compiler's error, never the program's.
  Type pointer = LLVM::LLVMPointerType::get(ctx);
  auto [pointerSize, pointerAlignment] = measure(target, pointer);
  if (pointerSize != IDRIS_RT_WORD_BYTES || pointerAlignment != IDRIS_RT_WORD_BYTES) {
    m.emitError() << "the module's target is not the runtime's: its pointers take "
                  << pointerSize << " bytes at an alignment of " << pointerAlignment
                  << ", and the runtime's object slots are words of " << IDRIS_RT_WORD_BYTES;
    fits = false;
    return;
  }
  // The scalars an element or a field may be, and every component a
  // declaration holds, so that no query after this one needs the data
  // layout's own memory.
  for (Type scalar : {pointer, Type(IntegerType::get(ctx, 1)), Type(IntegerType::get(ctx, 8)),
                      Type(IntegerType::get(ctx, 16)), Type(IntegerType::get(ctx, 32)),
                      Type(IntegerType::get(ctx, 64)), Type(Float32Type::get(ctx)),
                      Type(Float64Type::get(ctx))})
    record(scalar);
  SmallVector<DataOp> decls = llvm::to_vector(m.getOps<DataOp>());
  // Every unboxed sum, the only kind of declaration a value type names by
  // its data type: a box's values are pointers to its cells.
  for (DataOp data : decls)
    if (!data.getBox())
      for (Type component : Components::sum(data.getSymNameAttr()).types())
        record(component);
  for (DataOp data : decls)
    for (CtorOp ctor : data.getCtors())
      for (Attribute field : ctor.getFieldTypes())
        for (Type component : components(cast<TypeAttr>(field).getValue()))
          record(component);

  for (DataOp data : decls) {
    if (!data.getBox())
      continue;
    // A memo cell is allocated in one state and written into another, the
    // value a force stores over the captures it took, so every state's
    // cell is as large as the largest.
    bool memo = idr::isMemo(data);
    unsigned size = 0;
    SmallVector<CtorOp> ctors = data.getCtors();
    for (auto [tag, ctor] : llvm::enumerate(ctors)) {
      SmallVector<Type> fields;
      for (Attribute field : ctor.getFieldTypes())
        fields.push_back(cast<TypeAttr>(field).getValue());
      std::expected<layout::Cell, std::string> cell = cellOf(fields, [&](unsigned objs) {
        return memo ? layout::CellInfo::thunk(tag, objs) : layout::CellInfo::box(tag, objs);
      });
      if (!cell) {
        ctor.emitError() << "unsupported (layout): a cell of the constructor @" << ctor.getSymName()
                         << " cannot be built: " << cell.error();
        fits = false;
        continue;
      }
      size = std::max(size, cell->size);
      boxes.try_emplace(ctor, std::move(*cell));
    }
    if (memo)
      for (CtorOp ctor : ctors)
        if (auto it = boxes.find(ctor); it != boxes.end())
          it->second.size = size;
  }
}

LogicalResult Layouts::valid() const { return success(fits); }

SmallVector<Type> Layouts::components(Type type) const {
  return componentsWith(type, [&](StringAttr name) -> const layout::SumLayout & { return sum(name); });
}

SmallVector<bool> Layouts::counted(Type type) const {
  return countedWith(type, [&](StringAttr name) -> const layout::SumLayout & { return sum(name); });
}

unsigned Layouts::objects(Type type) const {
  return static_cast<unsigned>(llvm::count(counted(type), true));
}

unsigned Layouts::objects(ArrayRef<Type> types) const {
  unsigned all = 0;
  for (Type type : types)
    all += objects(type);
  return all;
}

const layout::SumLayout &Layouts::sum(StringAttr name) const {
  if (const layout::SumLayout *known = computed(name))
    return *known;
  llvm::reportFatalInternalError("no layout of the sum @" + name.getValue() +
                                 ", which the module did not declare when its layouts were "
                                 "computed");
}

unsigned Layouts::sizeOf(Type component) const {
  if (auto it = measures.find(component); it != measures.end())
    return it->second.first;
  return measure(DataLayout(getModule()), component).first;
}

unsigned Layouts::alignmentOf(Type component) const {
  if (auto it = measures.find(component); it != measures.end())
    return it->second.second;
  return measure(DataLayout(getModule()), component).second;
}

bool Layouts::isMemo(Type type) const {
  FlatSymbolRefAttr name = getSumName(type);
  DataOp data = name ? declaration(name.getAttr()) : DataOp();
  return data && idr::isMemo(data);
}

// An element is laid out as a cell of one field, less the header: the
// offsets start at the element, and the stride is the element's size at
// its own alignment, so that a byte element takes one byte and a buffer's
// bytes are contiguous; an element with an object slot takes whole words.
std::expected<layout::Element, std::string> Layouts::element(Type type) const {
  std::expected<layout::Cell, std::string> cell =
      cellOf(type, [](unsigned objs) { return layout::CellInfo::box(0, objs); });
  if (!cell)
    return std::unexpected(std::move(cell.error()));
  constexpr unsigned header = sizeof(idris_rt_header);
  SmallVector<layout::Slot> slots = std::move(cell->fields.front());
  unsigned end = 0, alignment = 1;
  for (layout::Slot &slot : slots) {
    slot.offset -= header;
    end = std::max(end, slot.offset + sizeOf(slot.type));
    alignment = std::max(alignment, alignmentOf(slot.type));
  }
  unsigned stride = static_cast<unsigned>(llvm::alignTo(end, alignment));
  std::expected<layout::CellInfo, std::string> info = layout::CellInfo::array(stride, cell->objs);
  if (!info)
    return std::unexpected(std::move(info.error()));
  return layout::Element{std::move(slots), stride, *info};
}

std::expected<layout::Cell, std::string>
Layouts::cellOf(ArrayRef<Type> fieldTypes,
                function_ref<std::expected<layout::CellInfo, std::string>(unsigned objs)> info)
    const {
  SmallVector<SmallVector<layout::Slot>> fields;
  SmallVector<SmallVector<bool>> countedness;
  for (Type field : fieldTypes) {
    SmallVector<layout::Slot> slots;
    for (Type component : components(field))
      slots.push_back({component, 0});
    fields.push_back(std::move(slots));
    countedness.push_back(counted(field));
  }
  SmallVector<std::pair<unsigned, unsigned>> order;
  unsigned objs = objects(fieldTypes);
  unsigned at = sizeof(idris_rt_header);
  auto place = [&](unsigned field, unsigned component) {
    layout::Slot &slot = fields[field][component];
    at = static_cast<unsigned>(llvm::alignTo(at, alignmentOf(slot.type)));
    slot.offset = at;
    at += sizeOf(slot.type);
    order.push_back({field, component});
  };
  auto count = static_cast<unsigned>(fieldTypes.size());
  // The object slots, each a word, so contiguous.
  for (unsigned f = 0; f < count; ++f)
    for (unsigned c = 0; c < fields[f].size(); ++c)
      if (countedness[f][c])
        place(f, c);
  // The other components, the most aligned first, so that the small ones
  // (the tags of unboxed sums, characters, booleans) share a word instead
  // of each taking one: the order of fields in the source is not a layout.
  SmallVector<std::pair<unsigned, unsigned>> others;
  for (unsigned f = 0; f < count; ++f)
    for (unsigned c = 0; c < fields[f].size(); ++c)
      if (!countedness[f][c])
        others.push_back({f, c});
  llvm::stable_sort(others, [&](std::pair<unsigned, unsigned> a, std::pair<unsigned, unsigned> b) {
    return alignmentOf(fields[a.first][a.second].type) > alignmentOf(fields[b.first][b.second].type);
  });
  for (auto [f, c] : others)
    place(f, c);
  std::expected<layout::CellInfo, std::string> header = info(objs);
  if (!header)
    return std::unexpected(std::move(header.error()));
  return layout::Cell{std::move(fields),
                      static_cast<unsigned>(llvm::alignTo(at, IDRIS_RT_WORD_BYTES)), objs,
                      std::move(order), *header};
}

const layout::Cell &Layouts::box(CtorOp ctor) const {
  if (auto it = boxes.find(ctor); it != boxes.end())
    return it->second;
  llvm::reportFatalInternalError("no cell of the constructor @" + ctor.getSymName() +
                                 ", which the module did not declare boxed when its layouts "
                                 "were computed");
}

arith::CmpIPredicate layout::signedPredicate(CmpPredicate predicate) {
  switch (predicate) {
  case CmpPredicate::eq:
    return arith::CmpIPredicate::eq;
  case CmpPredicate::lt:
    return arith::CmpIPredicate::slt;
  case CmpPredicate::lte:
    return arith::CmpIPredicate::sle;
  case CmpPredicate::gt:
    return arith::CmpIPredicate::sgt;
  case CmpPredicate::gte:
    return arith::CmpIPredicate::sge;
  }
  llvm_unreachable("a comparison predicate");
}

} // namespace idr
