// idr.eval:reify: reading a result of compile-time evaluation back as a
// constant attribute, through the layouts idr-lower built it in.
// Runs in idr-eval's child, on the memory of the JITed code.
module;
// The runtime's C ABI: its cells, strings and bignums, as C structs and
// macros; assert, a macro. No import carries them.
#include "idris_rt.h"

#include <cassert>

export module idr.eval:reify;

import idr.mlir;
import idr.dialect;
import idr.layout;

using namespace mlir;

export namespace idr::eval {

// Why the results of a call were not read back.
struct Unread {
  enum class Why {
    // They take more static data than a result may.
    TooLarge,
    // A suspension already stored its value over the captures, so the thunk
    // cannot be rebuilt as a constant. The call stays for runtime.
    Memoized,
    // The memory holds what no layout describes: an internal error.
    Unreadable,
  };
  Why why;
  std::string message;
};

class Reifier {
public:
  // `codes` maps the address of the code of each label's closures to the
  // label's number; the results of one call may take `budget` bytes of
  // static data.
  Reifier(layout::Layouts &l, llvm::DenseMap<uint64_t, unsigned> codes, uint64_t budget)
      : layouts(l), codes(std::move(codes)), budget(budget) {}

  // The values of `types` whose components are the words of `slots`, one
  // 8-byte slot each, or why they are not read.
  std::expected<llvm::SmallVector<mlir::Attribute>, Unread>
  results(llvm::ArrayRef<mlir::Type> types, llvm::ArrayRef<uint64_t> slots);

private:
  // The value of type `type` whose components are the next words of
  // `words`; advances `words`. Null once `unread` says why not.
  mlir::Attribute value(mlir::Type type, llvm::ArrayRef<uint64_t> &words);
  // The value in the cell or string `word` points to (or, for a big, the
  // word itself), read once however many values share it.
  mlir::Attribute object(mlir::Type type, uint64_t word);
  // The components of `slots` in the cell at `cell`, one word each.
  llvm::SmallVector<uint64_t> read(const char *cell, llvm::ArrayRef<layout::Slot> slots);
  mlir::Attribute constructor(DataOp data, CtorOp ctor,
                              llvm::function_ref<llvm::SmallVector<uint64_t>(unsigned field)> fields);
  // Counts `bytes` more of static data against the budget.
  bool spend(uint64_t bytes);
  mlir::Attribute refuse(Unread::Why why, std::string message);

  layout::Layouts &layouts;
  llvm::DenseMap<uint64_t, unsigned> codes;
  uint64_t budget;
  uint64_t spent = 0;
  std::optional<Unread> unread;
  // The values read, by address and type: the results of a round share
  // cells, and so do the constants read from them.
  llvm::DenseMap<std::pair<uint64_t, mlir::Type>, mlir::Attribute> seen;
};

} // namespace idr::eval

namespace idr::eval {

namespace {

// A component narrower than a word is read into the low bytes of one, which
// holds its value only on a little-endian machine; the JIT runs the code on
// this one.
static_assert(std::endian::native == std::endian::little);

template <typename T> const T *pointer(uint64_t word) {
  return reinterpret_cast<const T *>(static_cast<uintptr_t>(word));
}

} // namespace

std::expected<SmallVector<Attribute>, Unread> Reifier::results(ArrayRef<Type> types,
                                                               ArrayRef<uint64_t> slots) {
  spent = 0;
  unread.reset();
  SmallVector<Attribute> values;
  for (Type type : types) {
    Attribute value = this->value(type, slots);
    if (!value)
      return std::unexpected(std::move(*unread));
    values.push_back(value);
  }
  return values;
}

bool Reifier::spend(uint64_t bytes) {
  spent += bytes;
  if (spent <= budget)
    return true;
  refuse(Unread::Why::TooLarge,
         ("its results take more than " + Twine(budget) + " bytes of static data").str());
  return false;
}

Attribute Reifier::refuse(Unread::Why why, std::string message) {
  if (!unread)
    unread = Unread{why, std::move(message)};
  return {};
}

SmallVector<uint64_t> Reifier::read(const char *cell, ArrayRef<layout::Slot> slots) {
  SmallVector<uint64_t> words;
  for (const layout::Slot &slot : slots) {
    uint64_t word = 0;
    std::memcpy(&word, cell + slot.offset, layouts.sizeOf(slot.type));
    words.push_back(word);
  }
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
    Attribute value = this->value(ctor.getFieldType(i), rest);
    if (!value)
      return {};
    values.push_back(value);
  }
  auto name = SymbolRefAttr::get(data.getSymNameAttr(),
                                 {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
  return ConAttr::get(ctx, name, ArrayAttr::get(ctx, values));
}

Attribute Reifier::value(Type type, ArrayRef<uint64_t> &words) {
  MLIRContext *ctx = type.getContext();
  // A linear field or capture holds its value as it is.
  if (isErased(type))
    return ErasedAttr::get(ctx);
  if (auto q = dyn_cast<QType>(type))
    return value(q.getValue(), words);
  if (auto data = dyn_cast<DataType>(type)) {
    const layout::SumLayout &layout = layouts.sum(data.getName().getAttr());
    size_t n = layout.types().size();
    ArrayRef<uint64_t> mine = words.take_front(n);
    words = words.drop_front(n);
    DataOp decl = lookupData(layouts.getModule(), type);
    SmallVector<CtorOp> ctors = decl.getCtors();
    uint64_t tag = layout.tag ? mine.front() : 0;
    if (tag >= ctors.size())
      return refuse(Unread::Why::Unreadable,
                    ("a value of @" + decl.getSymName() + " has tag " + Twine(tag)).str());
    CtorOp ctor = ctors[tag];
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
  // A small big is its word, which nothing shares.
  if (isa<BigType, NatType>(type) && (word & 1) != 0)
    return object(type, word);
  auto key = std::make_pair(word, type);
  if (Attribute known = seen.lookup(key))
    return known;
  Attribute read = object(type, word);
  if (read)
    seen[key] = read;
  return read;
}

Attribute Reifier::object(Type type, uint64_t word) {
  MLIRContext *ctx = type.getContext();
  if (isa<StrType>(type)) {
    const auto *s = pointer<idris_rt_str>(word);
    if (!spend(sizeof(idris_rt_str) + s->bytes))
      return {};
    return StringAttr::get(ctx, StringRef(idris_rt_str_bytes(s), s->bytes));
  }
  if (isa<BigType, NatType>(type)) {
    if ((word & 1) == 0) {
      const auto *number = pointer<idris_rt_bignum>(word);
      int64_t size = number->size;
      if (!spend(sizeof(idris_rt_bignum) + 8 * static_cast<uint64_t>(size < 0 ? -size : size)))
        return {};
    }
    const idris_rt_str *text = idris_rt_big_show(static_cast<idris_rt_big>(word));
    return BigAttr::get(ctx, StringRef(idris_rt_str_bytes(text), text->bytes));
  }
  const char *cell = pointer<char>(word);
  const auto *header = pointer<idris_rt_header>(word);
  if (isa<BoxType>(type)) {
    DataOp decl = lookupData(layouts.getModule(), type);
    SmallVector<CtorOp> ctors = decl.getCtors();
    uint32_t tag = idris_rt_info_tag(header->info);
    if (tag >= ctors.size())
      return refuse(Unread::Why::Unreadable,
                    ("a cell of @" + decl.getSymName() + " has tag " + Twine(tag)).str());
    CtorOp ctor = ctors[tag];
    const layout::Cell &layout = layouts.box(ctor);
    if (!spend(layout.size))
      return {};
    return constructor(decl, ctor, [&](unsigned field) { return read(cell, layout.fields[field]); });
  }
  // A closure or a suspension: its code says which label it is of. Every
  // one keeps its code in the same place, right after the header. A
  // suspension that has run has replaced that code, and the captures with
  // the value, so there is no thunk to rebuild.
  uint64_t code = 0;
  std::memcpy(&code, cell + sizeof(idris_rt_header), sizeof(void *));
  auto found = codes.find(code);
  if (found == codes.end()) {
    if (isa<LazyType>(unrestricted(type)))
      return refuse(Unread::Why::Memoized, "a suspension has already stored its value");
    return refuse(Unread::Why::Unreadable, "the code of a closure is no label's");
  }
  const layout::Label &label = layouts.label(found->second);
  const layout::Cell &layout = layouts.closure(label);
  assert(layout.fields.front().front().offset == sizeof(idris_rt_header));
  if (!spend(layout.size))
    return {};
  SmallVector<Attribute> captures;
  for (auto [slots, captureType] :
       llvm::zip_equal(ArrayRef(layout.fields).drop_front(), label.captureTypes())) {
    SmallVector<uint64_t> components = read(cell, slots);
    ArrayRef<uint64_t> rest = components;
    Attribute capture = value(captureType, rest);
    if (!capture)
      return {};
    captures.push_back(capture);
  }
  return ClosureAttr::get(ctx, label.callee, ArrayAttr::get(ctx, captures));
}

} // namespace idr::eval
