// idr.eval:reify: reading a result of compile-time evaluation back as a
// constant attribute, through the layouts idr-lower built it in, its boxes
// by Boxes.cc. Runs in idr-eval's child, on the memory of the JITed code.
module;
// The runtime's C ABI: its cells, strings and bignums, as C structs and
// macros. No import carries them.
#include "idris_rt.h"

export module idr.eval:reify;

import idr.mlir;
import idr.dialect;
import idr.facts;
import idr.layout;

using namespace mlir;

export namespace idr::eval {

// Why the results of a call were not read back.
struct Unread {
  enum class Why {
    // They take more static data than a result may.
    TooLarge,
    // A suspension was forced: its cell holds the value in place of its
    // label's captures, so the thunk cannot be rebuilt as a constant. The
    // call stays for runtime.
    Memoized,
    // The memory holds what no layout describes: an internal error.
    Unreadable,
  };
  Why why;
  std::string message;
};

class Reifier {
public:
  // The results of one call may take `budget` bytes of static data.
  Reifier(layout::Layouts &l, uint64_t budget) : layouts(l), budget(budget) {}

  // The values of `types` whose components are the words of `slots`, one
  // 8-byte slot each, or why they are not read.
  std::expected<llvm::SmallVector<mlir::Attribute>, Unread>
  results(llvm::ArrayRef<mlir::Type> types, llvm::ArrayRef<uint64_t> slots);

private:
  // The value of type `type` whose components are the next words of
  // `words`; advances `words`. Null once `unread` says why not.
  mlir::Attribute value(mlir::Type type, llvm::ArrayRef<uint64_t> &words);
  // The value in the cell or string `word` points to, read once however
  // many values share it.
  mlir::Attribute shared(mlir::Type type, uint64_t word);
  // The value read already at `word` as `type`, or null.
  mlir::Attribute known(mlir::Type type, uint64_t word);
  // The value in the cell or string `word` points to (or, for a big, the
  // word itself).
  mlir::Attribute object(mlir::Type type, uint64_t word);
  // A box, a list built by one ConAttr::getRun, and a memo cell, read by
  // Boxes.cc.
  mlir::Attribute box(mlir::Type type, uint64_t word);
  mlir::Attribute run(mlir::Type type, mlir::SymbolRefAttr name, CtorOp ctor, unsigned spine,
                      uint64_t word);
  mlir::Attribute suspension(CtorOp ctor, uint64_t word);
  // The constructor of the cell at `word`, a cell of `decl`; null once
  // `unread` says why not.
  CtorOp cellCtor(DataOp decl, uint64_t word);
  // The fields of the cell of `ctor` at `word` that hold another cell of
  // `ctor`, of type `type`: a list's spine, or a tree's branches.
  llvm::SmallVector<unsigned> selfFields(mlir::Type type, CtorOp ctor, uint64_t word);
  // The fields of the cell of `ctor` at `word` but `skip`, counted against
  // the budget.
  std::optional<llvm::SmallVector<mlir::Attribute>>
  cellFields(CtorOp ctor, uint64_t word, std::optional<unsigned> skip = std::nullopt);
  // The fields of `ctor` but `skip`, each from its components.
  std::optional<llvm::SmallVector<mlir::Attribute>>
  fields(CtorOp ctor, llvm::function_ref<llvm::SmallVector<uint64_t>(unsigned field)> components,
         std::optional<unsigned> skip = std::nullopt);
  // The constructor `name` of `fields`, or the closure a sum of closures
  // holds.
  mlir::Attribute constructor(mlir::SymbolRefAttr name, llvm::ArrayRef<mlir::Attribute> fields);
  // The label closureLabel names for the constructor `name`, asked once per
  // constructor.
  mlir::StringAttr label(mlir::SymbolRefAttr name);
  // The components of `slots` in the cell at `cell`, one word each.
  llvm::SmallVector<uint64_t> read(const char *cell, llvm::ArrayRef<layout::Slot> slots);
  // Counts `bytes` more of static data against the budget.
  bool spend(uint64_t bytes);
  mlir::Attribute refuse(Unread::Why why, std::string message);

  layout::Layouts &layouts;
  uint64_t budget;
  uint64_t spent = 0;
  std::optional<Unread> unread;
  // The values read, by address and type: the results of a round share
  // cells, and so do the constants read from them.
  llvm::DenseMap<std::pair<uint64_t, mlir::Type>, mlir::Attribute> seen;
  // The cells read inside a run, by address and type, with the run and
  // their place in it: each is the rest of the run from there, built only
  // when another value shares it.
  llvm::DenseMap<std::pair<uint64_t, mlir::Type>, std::pair<ConAttr, unsigned>> suffixes;
  llvm::DenseMap<mlir::SymbolRefAttr, mlir::StringAttr> labels;
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

StringAttr Reifier::label(SymbolRefAttr name) {
  auto [it, fresh] = labels.try_emplace(name);
  if (fresh)
    it->second = facts::closureLabel(layouts.getModule(), name);
  return it->second;
}

// #idr.con<@T::@C, [fields]>; for a sum of closures, the closure it was made
// of, #idr.closure<@C, [fields]>: its label is C, its captures the fields.
Attribute Reifier::constructor(SymbolRefAttr name, ArrayRef<Attribute> fields) {
  MLIRContext *ctx = name.getContext();
  if (StringAttr callee = label(name))
    return ClosureAttr::get(ctx, FlatSymbolRefAttr::get(callee), ArrayAttr::get(ctx, fields));
  return ConAttr::get(ctx, name, ArrayAttr::get(ctx, fields));
}

std::optional<SmallVector<Attribute>>
Reifier::fields(CtorOp ctor, function_ref<SmallVector<uint64_t>(unsigned)> components,
                std::optional<unsigned> skip) {
  SmallVector<Attribute> values;
  for (unsigned i = 0, e = static_cast<unsigned>(ctor.getFieldTypes().size()); i < e; ++i) {
    if (i == skip)
      continue;
    SmallVector<uint64_t> words = components(i);
    ArrayRef<uint64_t> rest = words;
    Attribute value = this->value(ctor.getFieldType(i), rest);
    if (!value)
      return std::nullopt;
    values.push_back(value);
  }
  return values;
}

std::optional<SmallVector<Attribute>> Reifier::cellFields(CtorOp ctor, uint64_t word,
                                                          std::optional<unsigned> skip) {
  const layout::Cell &layout = layouts.box(ctor);
  if (!spend(layout.size))
    return std::nullopt;
  return fields(
      ctor, [&](unsigned field) { return read(pointer<char>(word), layout.fields[field]); }, skip);
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
    std::optional<SmallVector<Attribute>> values = fields(ctor, [&](unsigned field) {
      SmallVector<uint64_t> out;
      for (unsigned slot : layout.fields.find(ctor.getSymName())->second[field])
        out.push_back(mine[layout.offset() + slot]);
      return out;
    });
    if (!values)
      return {};
    return constructor(SymbolRefAttr::get(decl.getSymNameAttr(),
                                          {FlatSymbolRefAttr::get(ctor.getSymNameAttr())}),
                       *values);
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
  return shared(type, word);
}

Attribute Reifier::shared(Type type, uint64_t word) {
  if (Attribute read = known(type, word))
    return read;
  Attribute read = object(type, word);
  if (read)
    seen[{word, type}] = read;
  return read;
}

Attribute Reifier::known(Type type, uint64_t word) {
  auto key = std::make_pair(word, type);
  if (Attribute read = seen.lookup(key))
    return read;
  auto inside = suffixes.find(key);
  if (inside == suffixes.end())
    return {};
  auto [list, from] = inside->second;
  Attribute rest = ConAttr::getRun(type.getContext(), list.getCtor(), list.getSpine(),
                                   list.getRunCells().drop_front(from), list.getTail());
  seen[key] = rest;
  return rest;
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
  if (isa<BoxType>(type))
    return box(type, word);
  // After idr-defunctionalize every closure and suspension is a sum, and
  // nothing else a call returns is in a cell.
  return refuse(Unread::Why::Unreadable, "a value has a type no cell layout describes");
}

} // namespace idr::eval
