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

// What a type becomes, decided once: its shape, the type with each box and
// leaf applied at `place` (a data type of `boxed` held outside a box
// becomes a box of it; any other type the leaf replaces becomes what it
// gives, which is looked inside in turn) and every data type still by its
// old name, which the key of a remade type writes; then, remadeOf, each
// data type in the shape its new type. A box is kept as it is: what it
// holds is boxed already. A replacer of its own per call, since its leaves
// are the place's and its cache would hold them.
Type DataRemap::shapeAt(Type type, std::optional<FieldPlace> place) {
  AttrTypeReplacer shape;
  shape.addReplacement([&](Type part) -> std::optional<std::pair<Type, WalkResult>> {
    if (isa<BoxType>(part))
      return std::make_pair(part, WalkResult::skip());
    if (auto data = dyn_cast<DataType>(part))
      return std::make_pair(boxed.contains(data) ? Type(BoxType::get(data)) : Type(data),
                            WalkResult::skip());
    if (std::optional<Type> replaced = leafAt(part, place))
      return std::make_pair(*replaced, WalkResult::advance());
    return std::nullopt;
  });
  return shape.replace(type);
}

// A replacer of its own per call too: remaking a data type remakes, inside
// it, the types its shapes hold, and a shared replacer would answer a shape
// still being remade with itself.
Type DataRemap::remadeOf(Type shape) {
  AttrTypeReplacer remade;
  remade.addReplacement([this](DataType data) -> std::optional<std::pair<Type, WalkResult>> {
    return std::make_pair(Type(mapData(data)), WalkResult::skip());
  });
  return remade.replace(shape);
}

FailureOr<std::unique_ptr<DataRemap>> DataRemap::create(ProgramOp root, StringRef kind,
                                                        Leaf leaf, ArrayRef<DataType> boxed,
                                                        Renames renames) {
  std::unique_ptr<DataRemap> remap(
      new DataRemap(root, std::move(leaf), boxed, std::move(renames)));
  remap->remakeAll(root, kind);
  if (failed(remap->made))
    return failure();
  return remap;
}

// The replacement of everything met anywhere but in a body, once every new
// body is made. A reference to a renamed function names the new one; a data
// type is never entered, so a label is renamed only by remaking its type. A
// constant constructor names its data type as its identity, never boxed,
// and its cells are values met anywhere but in a body. Every type is
// replaced whole, by its shape there remade.
DataRemap::DataRemap(ProgramOp root, Leaf leafFn, ArrayRef<DataType> boxedTypes,
                     Renames renamed)
    : context(root.getContext()), program(root), leaf(std::move(leafFn)),
      renames(std::move(renamed)),
      boxed(boxedTypes.begin(), boxedTypes.end()), at(root->getLoc()) {
  replacer.addReplacement(
      [this](SymbolRefAttr ref) -> std::optional<std::pair<Attribute, WalkResult>> {
        StringAttr renamedFn = renames.lookup(ref.getRootReference());
        if (!renamedFn)
          return std::make_pair(Attribute(ref), WalkResult::skip());
        return std::make_pair(Attribute(SymbolRefAttr::get(renamedFn, ref.getNestedReferences())),
                              WalkResult::skip());
      });
  replacer.addReplacement([this](ConAttr con) -> std::optional<std::pair<Attribute, WalkResult>> {
    SmallVector<ArrayAttr> cells;
    for (ArrayAttr cell : con.getCells())
      cells.push_back(cast<ArrayAttr>(replacer.replace(cell)));
    return std::make_pair(Attribute(ConAttr::getRun(context, mapData(con.getData()), con.getTag(),
                                                    con.getSpine(), cells)),
                          WalkResult::skip());
  });
  replacer.addReplacement([this](Type type) -> std::optional<std::pair<Type, WalkResult>> {
    return std::make_pair(remadeOf(shapeAt(type, std::nullopt)), WalkResult::skip());
  });
}

void DataRemap::remakeAll(ProgramOp root, StringRef kind) {
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

  // Each field's shape, decided once. A type changes where a shape is not
  // its field (a box or a leaf applied anywhere in it) or where a label's
  // function is renamed, and where a data type it holds changes. `holders`
  // is the reverse of "a body names", along which a change spreads; `held`
  // is "a body names" itself: the data types in its shapes.
  llvm::DenseMap<DataType, SmallVector<DataType>> holders, held;
  idr::OnceWorklist<DataType> spreading;
  for (DataType data : types) {
    bool direct = llvm::any_of(data.getCtors(), [&](const Ctor &ctor) {
      const auto *label = std::get_if<role::Label>(&ctor.role);
      return label && renames.contains(label->fn.getAttr());
    });
    std::vector<SmallVector<Type>> &bodyShapes = shapes[data];
    for (Tag tag : data.getTags()) {
      SmallVector<Type> &ctorShapes = bodyShapes.emplace_back();
      for (auto [index, field] : llvm::enumerate(data.getCtor(tag).fields)) {
        Type shape = shapeAt(field, FieldPlace{data, tag, static_cast<unsigned>(index)});
        direct |= shape != field;
        ctorShapes.push_back(shape);
        // Pre-order, so the skip keeps the walk out of each data type's
        // labels: a shape names the data types at its top, whatever they
        // hold.
        AttrTypeWalker named;
        named.addWalk([&](DataType inner) {
          holders[inner].push_back(data);
          held[data].push_back(inner);
          return WalkResult::skip();
        });
        named.walk<WalkOrder::PreOrder>(shape);
      }
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

  // Each type's own key: its new body, its shapes, every data type in them
  // by its old name, so a cycle of new types needs no name first.
  llvm::DenseMap<DataType, std::string> own;
  for (DataType data : changing) {
    std::string &key = own[data];
    llvm::raw_string_ostream os(key);
    const std::vector<SmallVector<Type>> &bodyShapes = shapes.at(data);
    for (Tag tag : data.getTags()) {
      const Ctor &ctor = data.getCtor(tag);
      os << '@' << ctor.name.getValue() << '(';
      llvm::interleaveComma(bodyShapes[static_cast<uint32_t>(tag)], os,
                            [&](Type shape) { describe(shape, os); });
      os << ')';
      if (const auto *label = std::get_if<role::Label>(&ctor.role)) {
        StringAttr renamedFn = renames.lookup(label->fn.getAttr());
        os << " @" << (renamedFn ? renamedFn : label->fn.getAttr()).getValue();
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
  // sets it: each field's shape with its data types remade.
  std::vector<SmallVector<Type>> fields(old.getCtors().size());
  const std::vector<SmallVector<Type>> &bodyShapes = shapes.at(old);
  FailureOr<DataType> remade = DataType::define(
      program, names.lookup(old), [&](DataType self) -> FailureOr<DataType::Body> {
        next[old] = self;
        DataType::Body body{old.getKind(), {}, old.getInstance()};
        for (Tag tag : old.getTags()) {
          const Ctor &ctor = old.getCtor(tag);
          SmallVector<Type> &newFields = fields[static_cast<uint32_t>(tag)];
          for (Type shape : bodyShapes[static_cast<uint32_t>(tag)])
            newFields.push_back(remadeOf(shape));
          // A label names its function's new name where it is renamed.
          Role played = ctor.role;
          if (auto *label = std::get_if<role::Label>(&played))
            if (StringAttr renamedFn = renames.lookup(label->fn.getAttr()))
              label->fn = FlatSymbolRefAttr::get(renamedFn);
          body.ctors.push_back({ctor.name, newFields, played});
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
