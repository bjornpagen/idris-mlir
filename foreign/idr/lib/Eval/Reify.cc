// Results of compile-time evaluation as constant attributes.

#include "Eval/Reify.h"

#include "idris_rt.h"

#include <cstring>

using namespace mlir;

namespace idr::eval {

namespace {

uint64_t readWord(const char *at, Type type) {
  unsigned bytes = 8;
  if (auto integer = dyn_cast<IntegerType>(type))
    bytes = static_cast<unsigned>(llvm::PowerOf2Ceil((integer.getWidth() + 7) / 8));
  uint64_t word = 0;
  std::memcpy(&word, at, bytes);
  return word;
}

template <typename T> const T *pointer(uint64_t word) {
  return reinterpret_cast<const T *>(static_cast<uintptr_t>(word));
}

CtorOp withTag(DataOp data, uint64_t tag) {
  for (CtorOp ctor : data.getCtors())
    if (ctor.getTag() == tag)
      return ctor;
  return {};
}

} // namespace

SmallVector<uint64_t> Reifier::read(const char *cell, ArrayRef<lower::Slot> slots) {
  SmallVector<uint64_t> words;
  for (const lower::Slot &slot : slots)
    words.push_back(readWord(cell + slot.offset, slot.type));
  return words;
}

// #idr.con<@T::@C, [fields]>, each field from its components.
Attribute Reifier::constructor(DataOp data, CtorOp ctor,
                               function_ref<SmallVector<uint64_t>(unsigned)> fields) {
  MLIRContext *ctx = data.getContext();
  SmallVector<Attribute> values;
  for (unsigned i = 0, e = static_cast<unsigned>(ctor.getFieldTypes().size()); i < e; ++i) {
    SmallVector<uint64_t> words = fields(i);
    ArrayRef<uint64_t> rest = words;
    values.push_back(value(ctor.getFieldType(i), rest));
  }
  auto name = SymbolRefAttr::get(data.getSymNameAttr(),
                                 {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
  return ConAttr::get(ctx, name, ArrayAttr::get(ctx, values));
}

Attribute Reifier::value(Type type, ArrayRef<uint64_t> &words) {
  MLIRContext *ctx = type.getContext();
  // A linear field or capture holds its value as it is.
  if (auto lin = dyn_cast<LinType>(type))
    return value(lin.getValue(), words);
  if (isa<ErasedType>(type))
    return ErasedAttr::get(ctx);
  if (auto data = dyn_cast<DataType>(type)) {
    const lower::SumLayout &layout = layouts.sum(data.getName().getAttr());
    size_t n = layout.types().size();
    ArrayRef<uint64_t> mine = words.take_front(n);
    words = words.drop_front(n);
    DataOp decl = lookupData(layouts.getModule(), type);
    CtorOp ctor = layout.tag ? withTag(decl, mine.front()) : decl.getCtors().front();
    return constructor(decl, ctor, [&](unsigned field) {
      SmallVector<uint64_t> out;
      for (unsigned slot : layout.fields.find(ctor.getSymName())->second[field])
        out.push_back(mine[layout.offset() + slot]);
      return out;
    });
  }
  uint64_t word = words.front();
  words = words.drop_front();
  if (auto integer = dyn_cast<IntegerType>(type))
    return IntegerAttr::get(type, APInt(integer.getWidth(), word, /*isSigned=*/false,
                                        /*implicitTrunc=*/true));
  if (isa<Float64Type>(type))
    return FloatAttr::get(type, llvm::bit_cast<double>(word));
  if (isa<StrType>(type)) {
    const auto *s = pointer<idris_rt_str>(word);
    return StringAttr::get(ctx, StringRef(idris_rt_str_bytes(s), s->bytes));
  }
  if (isa<BigType>(type)) {
    const idris_rt_str *text = idris_rt_big_show(static_cast<idris_rt_big>(word));
    return BigAttr::get(ctx, StringRef(idris_rt_str_bytes(text), text->bytes));
  }
  const char *cell = pointer<char>(word);
  const auto *header = pointer<idris_rt_header>(word);
  // The low 16 bits of the info word are a box's tag or a closure's label.
  uint32_t tag = header->info & lower::tagMask;
  if (isa<BoxType>(type)) {
    DataOp decl = lookupData(layouts.getModule(), type);
    CtorOp ctor = withTag(decl, tag);
    return constructor(decl, ctor,
                       [&](unsigned field) { return read(cell, layouts.box(ctor).fields[field]); });
  }
  const lower::Label &label = layouts.label(tag);
  const lower::Cell &layout = layouts.closure(label);
  SmallVector<Attribute> captures;
  for (auto [slots, captureType] :
       llvm::zip_equal(ArrayRef(layout.fields).drop_front(), label.captureTypes())) {
    SmallVector<uint64_t> components = read(cell, slots);
    ArrayRef<uint64_t> rest = components;
    captures.push_back(value(captureType, rest));
  }
  return ClosureAttr::get(ctx, label.callee, ArrayAttr::get(ctx, captures));
}

} // namespace idr::eval
