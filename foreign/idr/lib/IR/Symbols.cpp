// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a data type's body says, read from a value's type; the elimination
// of a value at one of its uses; the data types a pass remakes where a body
// would change, since a body is set once; and the names generated from
// content.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/xxhash.h"

using namespace mlir;
using namespace idr;

DataType idr::dataTypeOf(Type type) {
  return TypeSwitch<Type, DataType>(unrestricted(type))
      .Case([](DataType data) { return data; })
      .Case([](BoxType box) { return box.getData(); })
      .Default([](Type) { return DataType(); });
}

bool idr::isBoxed(Type type) { return isa<BoxType>(unrestricted(type)); }

namespace {

// `visited`: the unboxed sums already asked about. Containment through
// them is acyclic, so one met again is one the verifier has yet to reject,
// or one whose answer is no (a yes ends the walk).
bool holds(Type type, llvm::SmallPtrSetImpl<const void *> &visited) {
  // A linear value holds what the value it is holds: its quantity decides
  // only how it is used.
  type = unrestricted(type);
  if (isa<StrType, BigType, NatType, BoxType, FnType, LazyType, idr::TokenType, ShapedType>(type))
    return true;
  auto data = dyn_cast<DataType>(type);
  if (!data || !visited.insert(data.getAsOpaquePointer()).second)
    return false;
  for (const Ctor &ctor : data.getCtors())
    for (Type field : ctor.fields)
      if (holds(field, visited))
        return true;
  return false;
}

} // namespace

bool idr::holdsReferences(Type type) {
  llvm::SmallPtrSet<const void *, 4> visited;
  return holds(type, visited);
}

std::optional<idr::Elimination> idr::eliminationAt(OpOperand &use) {
  // The only user of `v`, if it has one.
  auto next = [](Value v) { return v.hasOneUse() ? *v.user_begin() : nullptr; };
  Elimination e;
  Value value = use.get();
  Operation *user = use.getOwner();
  if ((e.enter = dyn_cast<LinEnterOp>(user))) {
    e.exit = dyn_cast_or_null<LinUseOp>(next(e.enter.getResult()));
    if (!e.exit)
      return std::nullopt;
    user = next(value = e.exit.getResult());
  }
  if ((e.field = dyn_cast_or_null<FieldOp>(user)))
    user = next(value = e.field.getResult());
  if ((e.use = dyn_cast_or_null<LinUseOp>(user)))
    user = next(value = e.use.getResult());
  e.dispatch = dyn_cast_or_null<MatchOp>(user);
  if (!e.dispatch || e.dispatch.getScrutinee() != value || !e.dispatch.getDataType().isClosures())
    return std::nullopt;
  return e;
}

//===----------------------------------------------------------------------===//
// Remaking data types
//===----------------------------------------------------------------------===//

namespace {

// A type written for a key: as MLIR writes it, but every data type by its
// name alone, which is what identifies it, so a key is short and needs no
// name that is still to be made.
void describe(Type type, raw_ostream &os) {
  auto list = [&](TypeRange types) {
    os << '(';
    llvm::interleaveComma(types, os, [&](Type t) { describe(t, os); });
    os << ')';
  };
  TypeSwitch<Type>(type)
      .Case([&](DataType data) { os << "!idr.data<\"" << data.getName() << "\">"; })
      .Case([&](BoxType box) {
        os << "!idr.box<";
        describe(box.getData(), os);
        os << '>';
      })
      .Case([&](QType q) {
        os << "!idr.q<" << stringifyQuantity(q.getQuantity()) << ", "
           << stringifyPermission(q.getPermission()) << ", ";
        describe(q.getValue(), os);
        os << '>';
      })
      .Case([&](FnType fn) {
        os << "!idr.fn<";
        list(fn.getInputs());
        os << " -> ";
        list(fn.getResults());
        os << '>';
      })
      .Case([&](LazyType lazy) {
        os << "!idr.lazy<";
        describe(lazy.getValue(), os);
        os << '>';
      })
      .Case([&](DestType dest) {
        os << "!idr.dest<";
        describe(dest.getValue(), os);
        os << '>';
      })
      .Case([&](FunctionType fn) {
        list(fn.getInputs());
        os << " -> ";
        list(fn.getResults());
      })
      .Case([&](ShapedType shaped) {
        os << (isa<MemRefType>(shaped) ? "memref<" : "tensor<");
        for (int64_t extent : shaped.getShape())
          os << (ShapedType::isDynamic(extent) ? std::string("?") : std::to_string(extent)) << 'x';
        describe(shaped.getElementType(), os);
        if (auto memref = dyn_cast<MemRefType>(shaped)) {
          if (!memref.getLayout().isIdentity())
            os << ", " << memref.getLayout();
          if (Attribute space = memref.getMemorySpace())
            os << ", " << space;
        }
        os << '>';
      })
      .Default([&](Type other) { os << other; });
}

} // namespace

// The replacement of every type at a place: a box of its data's new type,
// a data type's new type (a box of it where it is held outside one), a
// leaf's at that place; the parts of anything else. What a leaf gives is
// looked inside, so a data type a leaf's replacement holds is remade too. A
// constant constructor names its data type as its identity, never boxed,
// and its cells are values met anywhere but in a body.
void DataRemap::addReplacements(AttrTypeReplacer &into, Place place) {
  into.addReplacement([this](ConAttr con) -> std::optional<std::pair<Attribute, WalkResult>> {
    MLIRContext *context = con.getContext();
    SmallVector<ArrayAttr> cells;
    for (ArrayAttr cell : con.getCells())
      cells.push_back(cast<ArrayAttr>(replacer.replace(cell)));
    DataType data = mapData(con.getData());
    Attribute rebuilt =
        con.isRun() ? Attribute(ConAttr::getRun(context, data, con.getCtor(), con.getSpine(),
                                                cells, replacer.replace(con.getTail())))
                    : Attribute(ConAttr::get(context, data, con.getCtor(), cells.front()));
    return std::make_pair(rebuilt, WalkResult::skip());
  });
  into.addReplacement([this, place](Type type) -> std::optional<std::pair<Type, WalkResult>> {
    if (auto box = dyn_cast<BoxType>(type))
      return std::make_pair(Type(BoxType::get(mapData(box.getData()))), WalkResult::skip());
    if (auto data = dyn_cast<DataType>(type)) {
      DataType mapped = mapData(data);
      if (boxed.contains(data))
        return std::make_pair(Type(BoxType::get(mapped)), WalkResult::skip());
      return std::make_pair(Type(mapped), WalkResult::skip());
    }
    if (std::optional<Type> replaced = leafAt(type, place))
      return std::make_pair(*replaced, WalkResult::advance());
    return std::nullopt;
  });
}

DataRemap::DataRemap(ModuleOp module, StringRef kind, Leaf leafFn, ArrayRef<DataType> boxedTypes)
    : leaf(std::move(leafFn)), boxed(boxedTypes.begin(), boxedTypes.end()) {
  // Every data type the module's values can be of, and each one's bodies'.
  llvm::SetVector<DataType> types;
  AttrTypeWalker walker;
  walker.addWalk([&](DataType data) { types.insert(data); });
  module.walk([&](Operation *op) {
    walker.walk(op->getAttrDictionary());
    for (Type type : op->getResultTypes())
      walker.walk(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          walker.walk(type);
  });
  for (size_t at = 0; at < types.size(); ++at)
    for (const Ctor &ctor : types[at].getCtors())
      for (Type field : ctor.fields)
        walker.walk(field);

  // A type changes where a field does: a leaf replaced at the field, a type
  // of `boxed` held outside a box, or a data type that changes. `holders`
  // is the reverse of "a body holds", along which a change spreads.
  llvm::DenseMap<DataType, SmallVector<DataType>> holders;
  SmallVector<DataType> changing;
  llvm::DenseSet<DataType> changed;
  for (DataType data : types) {
    bool direct = false;
    for (auto [tag, ctor] : llvm::enumerate(data.getCtors()))
      for (auto [index, field] : llvm::enumerate(ctor.fields)) {
        Place place{data, static_cast<unsigned>(tag), static_cast<unsigned>(index)};
        AttrTypeWalker fields;
        fields.addWalk([&](Type part) -> WalkResult {
          if (auto box = dyn_cast<BoxType>(part)) {
            holders[box.getData()].push_back(data);
            return WalkResult::skip();
          }
          if (auto inner = dyn_cast<DataType>(part)) {
            holders[inner].push_back(data);
            direct |= boxed.contains(inner);
            return WalkResult::skip();
          }
          if (leafAt(part, place)) {
            direct = true;
            return WalkResult::skip();
          }
          return WalkResult::advance();
        });
        fields.walk<WalkOrder::PreOrder>(field);
      }
    if (direct && changed.insert(data).second)
      changing.push_back(data);
  }
  for (size_t at = 0; at < changing.size(); ++at)
    for (DataType holder : holders.lookup(changing[at]))
      if (changed.insert(holder).second)
        changing.push_back(holder);
  llvm::sort(changing, [](DataType a, DataType b) { return a.getName() < b.getName(); });

  addReplacements(replacer, Place{});

  // Every new type is named before any body is set, each from its new body
  // with the old names, so a cycle of new types needs no name first.
  MLIRContext *context = module.getContext();
  for (DataType data : changing) {
    std::string key;
    llvm::raw_string_ostream os(key);
    for (auto [tag, ctor] : llvm::enumerate(data.getCtors())) {
      os << '@' << ctor.name.getValue() << '(';
      for (auto [index, field] : llvm::enumerate(ctor.fields)) {
        if (index != 0)
          os << ", ";
        Place place{data, static_cast<unsigned>(tag), static_cast<unsigned>(index)};
        auto inner = dyn_cast<DataType>(unrestricted(field));
        bool boxes = inner && boxed.contains(inner);
        std::optional<Type> replaced = leafAt(field, place);
        os << (boxes ? "!idr.box<" : "");
        describe(replaced ? *replaced : field, os);
        os << (boxes ? ">" : "");
      }
      os << ')';
    }
    DataType made = DataType::get(context, contentName(data.getName(), kind, key));
    next[data] = made;
    pairs.push_back({data, made});
  }
  for (auto [old, made] : pairs) {
    SmallVector<SmallVector<Type>> fields;
    for (auto [tag, ctor] : llvm::enumerate(old.getCtors())) {
      SmallVector<Type> mapped;
      for (auto [index, field] : llvm::enumerate(ctor.fields)) {
        // A field's leaves are keyed by the field, so each field has a
        // replacer of its own.
        AttrTypeReplacer atField;
        addReplacements(atField, Place{old, static_cast<unsigned>(tag), static_cast<unsigned>(index)});
        mapped.push_back(atField.replace(field));
      }
      fields.push_back(std::move(mapped));
    }
    SmallVector<Ctor> ctors;
    for (auto [ctor, mapped] : llvm::zip_equal(old.getCtors(), fields))
      ctors.push_back({ctor.name, mapped, ctor.byName});
    if (mlir::failed(made.setBody(
            [&] {
              return module.emitError()
                     << "internal error: remaking the data type \"" << old.getName() << "\": ";
            },
            old.getKind(), ctors, old.getInstance())))
      broken = true;
  }
}

// Each type's leaf is asked once at each place.
std::optional<Type> DataRemap::leafAt(Type type, Place place) {
  auto [it, fresh] = leaves.try_emplace({type, place.owner, place.tag, place.field});
  if (fresh)
    it->second = leaf(type, place.owner, place.tag, place.field);
  return it->second;
}

DataType DataRemap::mapData(DataType type) {
  DataType made = next.lookup(type);
  return made ? made : type;
}

Type DataRemap::map(Type type) { return replacer.replace(type); }

void DataRemap::retype(Operation *root) {
  replacer.recursivelyReplaceElementsIn(root, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                        /*replaceTypes=*/true);
}

//===----------------------------------------------------------------------===//
// Names from content
//===----------------------------------------------------------------------===//

std::string idr::contentHash(StringRef key) {
  llvm::XXH128_hash_t hash = llvm::xxh3_128bits(llvm::arrayRefFromStringRef(key));
  std::string text;
  llvm::raw_string_ostream os(text);
  os << llvm::format_hex_no_prefix(hash.low64, 16, /*Upper=*/false);
  return text;
}

std::string idr::contentName(StringRef owner, StringRef kind, StringRef key) {
  return (owner + "." + kind + "." + contentHash(key)).str();
}

FailureOr<StringAttr> ContentNames::intern(Location at, StringRef owner, StringRef kind,
                                           StringRef key) {
  std::string name = contentName(owner, kind, key);
  auto [it, fresh] = keys.try_emplace(name, key.str());
  if (!fresh && it->second != key)
    return emitError(at) << "internal error: two keys name " << name << ": " << it->second
                         << " and " << key;
  return StringAttr::get(at->getContext(), name);
}
