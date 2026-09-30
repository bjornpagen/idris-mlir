// Results of compile-time evaluation as constant attributes.

#include "Eval/Reify.h"

#include "idris_rt.h"

#include "mlir/Bytecode/BytecodeReader.h"
#include "mlir/Bytecode/BytecodeWriter.h"
#include "mlir/IR/BuiltinOps.h"

#include "llvm/Support/MemoryBufferRef.h"

#include <bit>
#include <cstring>

using namespace mlir;

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

SmallVector<uint64_t> Reifier::read(const char *cell, ArrayRef<lower::Slot> slots) {
  SmallVector<uint64_t> words;
  for (const lower::Slot &slot : slots) {
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
    const lower::Cell &layout = layouts.box(ctor);
    if (!spend(layout.size))
      return {};
    return constructor(decl, ctor, [&](unsigned field) { return read(cell, layout.fields[field]); });
  }
  // A closure: its code says which label it is of. Every closure keeps its
  // code in the same place, right after the header.
  uint64_t code = 0;
  std::memcpy(&code, cell + sizeof(idris_rt_header), sizeof(void *));
  auto found = codes.find(code);
  if (found == codes.end())
    return refuse(Unread::Why::Unreadable, "the code of a closure is no label's");
  const lower::Label &label = layouts.label(found->second);
  const lower::Cell &layout = layouts.closure(label);
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

namespace {

constexpr llvm::StringLiteral partsName = "eval.parts";
constexpr llvm::StringLiteral resultsName = "eval.results";

// The fields of a constructor or the captures of a closure; null for any
// other constant, which holds no parts.
ArrayAttr partsOf(Attribute value) {
  if (auto con = dyn_cast<ConAttr>(value))
    return con.getFields();
  if (auto closure = dyn_cast<ClosureAttr>(value))
    return closure.getCaptures();
  return {};
}

} // namespace

std::expected<std::string, std::string> encodeResults(ArrayRef<Attribute> values,
                                                     MLIRContext *ctx) {
  llvm::DenseMap<Attribute, int64_t> position;
  SmallVector<Attribute> table;
  // Each part after its own parts, by a walk with an explicit stack, since
  // a result is as deep as the data it is (a list of a million elements).
  struct Visit {
    Attribute value;
    bool expanded;
  };
  SmallVector<Visit> stack;
  for (Attribute root : values) {
    stack.push_back({root, false});
    while (!stack.empty()) {
      Visit visit = stack.back();
      if (position.contains(visit.value)) {
        stack.pop_back();
        continue;
      }
      ArrayAttr parts = partsOf(visit.value);
      if (parts && !visit.expanded) {
        stack.back().expanded = true;
        for (Attribute part : llvm::reverse(parts))
          if (!position.contains(part))
            stack.push_back({part, false});
        continue;
      }
      stack.pop_back();
      Attribute entry = visit.value;
      if (parts) {
        auto positions = llvm::map_to_vector(parts, [&](Attribute part) { return position.at(part); });
        Attribute head = isa<ConAttr>(visit.value)
                             ? Attribute(cast<ConAttr>(visit.value).getCtor())
                             : Attribute(cast<ClosureAttr>(visit.value).getCallee());
        entry = ArrayAttr::get(ctx, {head, DenseI64ArrayAttr::get(ctx, positions)});
      }
      position[visit.value] = static_cast<int64_t>(table.size());
      table.push_back(entry);
    }
  }
  OwningOpRef<ModuleOp> holder = ModuleOp::create(UnknownLoc::get(ctx));
  (*holder)->setAttr(partsName, ArrayAttr::get(ctx, table));
  (*holder)->setAttr(resultsName,
                     DenseI64ArrayAttr::get(ctx, llvm::map_to_vector(values, [&](Attribute value) {
                                              return position.at(value);
                                            })));
  std::string bytes;
  llvm::raw_string_ostream os(bytes);
  if (failed(writeBytecodeToFile(*holder, os)))
    return std::unexpected(std::string("the results have no bytecode"));
  return bytes;
}

std::expected<SmallVector<Attribute>, std::string> decodeResults(StringRef bytes,
                                                                 MLIRContext *ctx) {
  Block holder;
  if (failed(readBytecodeFile(llvm::MemoryBufferRef(bytes, "idr-eval results"), &holder,
                              ParserConfig(ctx, /*verifyAfterParse=*/false))) ||
      holder.empty())
    return std::unexpected(std::string("the results' bytecode does not read"));
  Operation &module = holder.front();
  auto table = module.getAttrOfType<ArrayAttr>(partsName);
  auto roots = module.getAttrOfType<DenseI64ArrayAttr>(resultsName);
  if (!table || !roots)
    return std::unexpected(std::string("the results' bytecode holds no table"));
  SmallVector<Attribute> built;
  built.reserve(table.size());
  for (Attribute entry : table) {
    auto node = dyn_cast<ArrayAttr>(entry);
    if (!node) {
      built.push_back(entry);
      continue;
    }
    auto head = node.size() == 2 ? dyn_cast<SymbolRefAttr>(node[0]) : SymbolRefAttr();
    auto positions = node.size() == 2 ? dyn_cast<DenseI64ArrayAttr>(node[1]) : DenseI64ArrayAttr();
    if (!head || !positions)
      return std::unexpected(std::string("a part of the results is malformed"));
    SmallVector<Attribute> parts;
    for (int64_t at : positions.asArrayRef()) {
      if (at < 0 || static_cast<size_t>(at) >= built.size())
        return std::unexpected(std::string("a part of the results holds one not before it"));
      parts.push_back(built[static_cast<size_t>(at)]);
    }
    // A constructor is named in its type (@T::@C), a function alone (@f).
    auto flat = dyn_cast<FlatSymbolRefAttr>(head);
    built.push_back(flat ? Attribute(ClosureAttr::get(ctx, flat, ArrayAttr::get(ctx, parts)))
                         : Attribute(ConAttr::get(ctx, head, ArrayAttr::get(ctx, parts))));
  }
  SmallVector<Attribute> values;
  for (int64_t at : roots.asArrayRef()) {
    if (at < 0 || static_cast<size_t>(at) >= built.size())
      return std::unexpected(std::string("a result is not in the table"));
    values.push_back(built[static_cast<size_t>(at)]);
  }
  return values;
}

} // namespace idr::eval
