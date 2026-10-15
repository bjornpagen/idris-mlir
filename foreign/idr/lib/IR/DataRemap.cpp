// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The data types a pass remakes where a body would change, since a body is
// set once (DataRemap, Symbols.h): which types change, the names their new
// bodies give them from content, and the bodies, made when the remap is.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Scc.h"
#include "idr/Support/Worklist.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <vector>

using namespace mlir;
using namespace idr;

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
// and its cells are values met anywhere but in a body. A reference to a
// renamed function names the new one; a data type is never entered, so a
// label is renamed only by remaking its type.
void DataRemap::addReplacements(AttrTypeReplacer &into, std::optional<FieldPlace> place) {
  into.addReplacement([this](SymbolRefAttr ref) -> std::optional<std::pair<Attribute, WalkResult>> {
    StringAttr renamed = renames.lookup(ref.getRootReference());
    if (!renamed)
      return std::make_pair(Attribute(ref), WalkResult::skip());
    return std::make_pair(Attribute(SymbolRefAttr::get(renamed, ref.getNestedReferences())),
                          WalkResult::skip());
  });
  into.addReplacement([this](ConAttr con) -> std::optional<std::pair<Attribute, WalkResult>> {
    SmallVector<ArrayAttr> cells;
    for (ArrayAttr cell : con.getCells())
      cells.push_back(cast<ArrayAttr>(replacer.replace(cell)));
    DataType data = mapData(con.getData());
    Attribute rebuilt =
        con.isRun() ? Attribute(ConAttr::getRun(context, data, con.getTag(), con.getSpine(),
                                                cells, replacer.replace(con.getTail())))
                    : Attribute(ConAttr::get(context, data, con.getTag(), cells.front()));
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

FailureOr<std::unique_ptr<DataRemap>> DataRemap::create(Operation *root, StringRef kind,
                                                        Leaf leaf, ArrayRef<DataType> boxed,
                                                        Renames renames) {
  std::unique_ptr<DataRemap> remap(
      new DataRemap(root, std::move(leaf), boxed, std::move(renames)));
  remap->remakeAll(root, kind);
  if (failed(remap->made))
    return failure();
  return remap;
}

DataRemap::DataRemap(Operation *root, Leaf leafFn, ArrayRef<DataType> boxedTypes,
                     Renames renamed)
    : context(root->getContext()), leaf(std::move(leafFn)), renames(std::move(renamed)),
      boxed(boxedTypes.begin(), boxedTypes.end()), at(root->getLoc()) {
  addReplacements(replacer, std::nullopt);
}

void DataRemap::remakeAll(Operation *root, StringRef kind) {
  // Every data type the root's values can be of, and each one's bodies':
  // each type enters once, so the walk ends with the types they reach.
  llvm::SetVector<DataType> types;
  AttrTypeWalker walker;
  walker.addWalk([&](DataType data) {
    types.insert(data);
    return WalkResult::skip();
  });
  root->walk([&](Operation *op) {
    walker.walk(op->getAttrDictionary());
    for (Type type : op->getResultTypes())
      walker.walk(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          walker.walk(type);
  });
  for (size_t index = 0; index < types.size(); ++index)
    for (const Ctor &ctor : types[index].getCtors())
      for (Type field : ctor.fields)
        walker.walk(field);

  // A type changes where a field does (a leaf replaced at the field, a type
  // of `boxed` held outside a box, a data type that changes) or where a
  // label's function is renamed. `holders` is the reverse of "a body
  // names", along which a change spreads; `held` is "a body names" itself.
  llvm::DenseMap<DataType, SmallVector<DataType>> holders, held;
  idr::OnceWorklist<DataType> spreading;
  for (DataType data : types) {
    bool direct = llvm::any_of(data.getCtors(), [&](const Ctor &ctor) {
      return ctor.fn && renames.contains(ctor.fn.getAttr());
    });
    for (Tag tag : data.getTags())
      for (auto [index, field] : llvm::enumerate(data.getCtor(tag).fields)) {
        FieldPlace place{data, tag, static_cast<unsigned>(index)};
        AttrTypeWalker fields;
        fields.addWalk([&](Type part) -> WalkResult {
          if (auto box = dyn_cast<BoxType>(part)) {
            holders[box.getData()].push_back(data);
            held[data].push_back(box.getData());
            return WalkResult::skip();
          }
          if (auto inner = dyn_cast<DataType>(part)) {
            holders[inner].push_back(data);
            held[data].push_back(inner);
            direct |= boxed.contains(inner);
            return WalkResult::skip();
          }
          // What a leaf gives is looked inside: the data types it names
          // are named by the body too.
          if (std::optional<Type> replaced = leafAt(part, place)) {
            direct = true;
            AttrTypeWalker inside;
            inside.addWalk([&](DataType inner) {
              holders[inner].push_back(data);
              held[data].push_back(inner);
              return WalkResult::skip();
            });
            inside.walk(*replaced);
            return WalkResult::skip();
          }
          return WalkResult::advance();
        });
        fields.walk<WalkOrder::PreOrder>(field);
      }
    if (direct)
      spreading.push(data);
  }
  // Each changing type enters once, so the spread ends with the types that
  // hold a changing one.
  SmallVector<DataType> changing;
  while (std::optional<DataType> data = spreading.pop()) {
    changing.push_back(*data);
    for (DataType holder : holders.lookup(*data))
      spreading.push(holder);
  }
  llvm::sort(changing, [](DataType a, DataType b) { return a.getName() < b.getName(); });

  // Each type's own key: its new body, every data type in it by its old
  // name, so a cycle of new types needs no name first.
  llvm::DenseMap<DataType, std::string> own;
  for (DataType data : changing) {
    std::string &key = own[data];
    llvm::raw_string_ostream os(key);
    for (Tag tag : data.getTags()) {
      const Ctor &ctor = data.getCtor(tag);
      os << '@' << ctor.name.getValue() << '(';
      for (auto [index, field] : llvm::enumerate(ctor.fields)) {
        if (index != 0)
          os << ", ";
        FieldPlace place{data, tag, static_cast<unsigned>(index)};
        auto inner = dyn_cast<DataType>(unrestricted(field));
        bool boxes = inner && boxed.contains(inner);
        std::optional<Type> replaced = leafAt(field, place);
        os << (boxes ? "!idr.box<" : "");
        describe(replaced ? *replaced : field, os);
        os << (boxes ? ">" : "");
      }
      os << ')';
      if (ctor.fn) {
        StringAttr renamedFn = renames.lookup(ctor.fn.getAttr());
        os << " @" << (renamedFn ? renamedFn : ctor.fn.getAttr()).getValue();
      }
    }
  }
  // And what every remade type it reaches becomes, which its own key names
  // only by the old name: the digest of each component of remade types,
  // callees first, over its members' own keys and its successors' digests.
  // Two remaps of one kind that remake anything below a type differently
  // name it differently, whatever cycles the types make.
  SmallVector<SmallVector<DataType>> components = idr::stronglyConnected<DataType>(
      changing, [&](DataType data) { return held.lookup(data); });
  llvm::DenseMap<DataType, Digest> below;
  for (const SmallVector<DataType> &component : components) {
    SmallVector<DataType> members(component);
    llvm::sort(members, [](DataType a, DataType b) { return a.getName() < b.getName(); });
    std::string text;
    llvm::raw_string_ostream os(text);
    for (DataType member : members)
      os << member.getName() << '\0' << digestOf(own[member]) << '\0';
    llvm::DenseSet<DataType> inside(members.begin(), members.end());
    SmallVector<std::pair<StringRef, Digest>> successors;
    for (DataType member : members)
      for (DataType inner : held.lookup(member))
        if (!inside.contains(inner) && below.contains(inner))
          successors.push_back({inner.getName(), below.lookup(inner)});
    llvm::sort(successors, [](const auto &a, const auto &b) { return a.first < b.first; });
    successors.erase(std::unique(successors.begin(), successors.end()), successors.end());
    for (auto [name, digest] : successors)
      os << name << '\0' << digest << '\0';
    Digest digest = digestOf(text);
    for (DataType member : members)
      below[member] = digest;
  }
  for (DataType data : changing) {
    std::string key = own[data];
    llvm::raw_string_ostream(key) << '\0' << below.lookup(data);
    names[data] = contentName(data.getName(), kind, key);
  }

  for (DataType data : changing)
    (void)remake(data);
}

// The type a remade body holds is made the first time a body or the remap
// asks for it, so a type made inside another's body may hold the one still
// being made, as define allows.
DataType DataRemap::remake(DataType old) {
  if (DataType known = next.lookup(old))
    return known;
  // The new fields of each constructor, which the body views until define
  // sets it.
  std::vector<SmallVector<Type>> fields(old.getCtors().size());
  FailureOr<DataType> remade = DataType::define(context, names.lookup(old), [&](DataType self) {
    next[old] = self;
    DataType::Body body{old.getKind(), {}, old.getInstance()};
    for (Tag tag : old.getTags()) {
      const Ctor &ctor = old.getCtor(tag);
      SmallVector<Type> &newFields = fields[static_cast<uint32_t>(tag)];
      for (auto [index, field] : llvm::enumerate(ctor.fields)) {
        // A field's leaves are keyed by the field, so each field has a
        // replacer of its own.
        AttrTypeReplacer atField;
        addReplacements(atField, FieldPlace{old, tag, static_cast<unsigned>(index)});
        newFields.push_back(atField.replace(field));
      }
      FlatSymbolRefAttr fn = ctor.fn;
      if (StringAttr renamedFn = fn ? renames.lookup(fn.getAttr()) : StringAttr())
        fn = FlatSymbolRefAttr::get(renamedFn);
      body.ctors.push_back({ctor.name, newFields, ctor.byName, ctor.role, fn});
    }
    return body;
  });
  if (succeeded(remade))
    return *remade;
  emitError(at) << "internal error: remaking the data type \"" << old.getName() << "\"";
  made = failure();
  return next.lookup(old);
}

// Each type's leaf is asked once at each place.
std::optional<Type> DataRemap::leafAt(Type type, std::optional<FieldPlace> place) {
  auto ask = [&](auto inserted) {
    auto [it, fresh] = inserted;
    if (fresh)
      it->second = leaf(type, place);
    return it->second;
  };
  if (!place)
    return ask(leavesElsewhere.try_emplace(type));
  return ask(leavesInBodies.try_emplace(
      {type, place->owner, static_cast<uint32_t>(place->tag), place->field}));
}

DataType DataRemap::mapData(DataType type) {
  if (!names.contains(type))
    return type;
  return remake(type);
}

void DataRemap::retype(Operation *root) {
  replacer.recursivelyReplaceElementsIn(root, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                        /*replaceTypes=*/true);
}
