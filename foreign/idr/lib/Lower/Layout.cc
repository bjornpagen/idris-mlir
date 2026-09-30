// Runtime layouts of idr values.

#include "Lower/Layout.h"

using namespace mlir;

namespace idr::lower {

std::expected<CellInfo, std::string> CellInfo::box(uint64_t tag, uint64_t objs) noexcept {
  if (tag >= IDRIS_RT_TAG_LIMIT)
    return std::unexpected(("its tag is " + Twine(tag) + ", and a cell's tag is below " +
                            Twine(IDRIS_RT_TAG_LIMIT))
                               .str());
  if (objs >= IDRIS_RT_OBJS_LIMIT)
    return std::unexpected(("it holds " + Twine(objs) +
                            " counted references (strings, boxed values, closures, "
                            "Integers, Nats), and a cell holds at most " +
                            Twine(IDRIS_RT_OBJS_LIMIT - 1))
                               .str());
  return CellInfo(idris_rt_info(static_cast<uint32_t>(tag), static_cast<uint32_t>(objs),
                                IDRIS_RT_KIND_BOX));
}

std::expected<CellInfo, std::string> CellInfo::closure(uint64_t objs) noexcept {
  if (objs >= IDRIS_RT_OBJS_LIMIT)
    return std::unexpected(("its captures hold " + Twine(objs) +
                            " counted references, and a cell holds at most " +
                            Twine(IDRIS_RT_OBJS_LIMIT - 1))
                               .str());
  return CellInfo(idris_rt_info(0, static_cast<uint32_t>(objs), IDRIS_RT_KIND_CLOSURE));
}

SmallVector<Type> SumLayout::types() const {
  SmallVector<Type> all;
  if (tag)
    all.push_back(tag);
  all.append(slots.begin(), slots.end());
  return all;
}

unsigned Layouts::sizeOf(Type component) const {
  return static_cast<unsigned>(target.getTypeSize(component).getFixedValue());
}

unsigned Layouts::alignmentOf(Type component) const {
  return static_cast<unsigned>(target.getTypeABIAlignment(component));
}

Layouts::Layouts(ModuleOp m) : module(m), target(m) {
  SymbolTable symbols(module);
  auto note = [&](FlatSymbolRefAttr callee, unsigned captures) {
    auto key = std::make_pair(Attribute(callee), captures);
    auto fn = symbols.lookup<func::FuncOp>(callee.getAttr());
    if (fn && labelIds.try_emplace(key, static_cast<unsigned>(labels.size())).second)
      labels.push_back({callee, captures, fn.getFunctionType()});
  };
  module.walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (auto closure = dyn_cast<ClosureOp>(op))
      note(closure.getCalleeAttr(), static_cast<unsigned>(closure.getCaptures().size()));
    op->getAttrDictionary().walk([&](ClosureAttr closure) {
      note(closure.getCallee(), static_cast<unsigned>(closure.getCaptures().size()));
    });
  });
}

FailureOr<Layouts> Layouts::of(ModuleOp m) {
  Layouts layouts(m);
  // The runtime frees a cell by its object slots, which it reads as
  // pointers of the target it is compiled for, one word each; the layouts
  // must place them as it reads them.
  Type pointer = LLVM::LLVMPointerType::get(m.getContext());
  if (layouts.sizeOf(pointer) != IDRIS_RT_WORD_BYTES ||
      layouts.alignmentOf(pointer) != IDRIS_RT_WORD_BYTES)
    return m.emitError() << "unsupported (target): its pointers take " << layouts.sizeOf(pointer)
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
  SymbolTable symbols(m);
  for (auto [id, label] : llvm::enumerate(layouts.labels)) {
    SmallVector<Type> fields{LLVM::LLVMPointerType::get(m.getContext())};
    llvm::append_range(fields, label.captureTypes());
    std::expected<Cell, std::string> cell =
        layouts.cellOf(fields, 1, [](unsigned objs) { return CellInfo::closure(objs); });
    if (!cell) {
      symbols.lookup(label.callee.getAttr())->emitError()
          << "unsupported (layout): a closure of @" << label.callee.getValue() << " with "
          << label.captures << " captures cannot be built: " << cell.error();
      fits = false;
      continue;
    }
    layouts.closures[static_cast<unsigned>(id)] = std::make_unique<Cell>(std::move(*cell));
  }
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
  type = unrestricted(type);
  if (isa<ErasedType, WorldType>(type))
    return {};
  // A destination is the address of a field's word.
  if (isa<StrType, BoxType, FnType, TokenType, DestType>(type))
    return {LLVM::LLVMPointerType::get(ctx)};
  if (isa<BigType, NatType>(type))
    return {IntegerType::get(ctx, 64)};
  if (auto data = dyn_cast<DataType>(type))
    return sum(data.getName().getAttr()).types();
  return {type};
}

SmallVector<bool> Layouts::counted(Type type) {
  type = unrestricted(type);
  if (isa<ErasedType, WorldType>(type))
    return {};
  if (isa<StrType, BoxType, FnType, TokenType, BigType, NatType>(type))
    return {true};
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

} // namespace idr::lower
