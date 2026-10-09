// idr.layout:fit: the boxes that make cells fit their headers. A cell's
// header counts its object slots in a few bits, and an unboxed sum spreads
// its slots over every cell that holds it, so a record nested in a record
// can make a cell that no header counts. Boxing the record leaves one
// pointer in its place: the type decides how a value is flattened, so
// making a declaration a box and retyping its values is the whole change,
// which every later pass and the lowering follow as they follow any box.
module;
// The runtime's C ABI: how many constructors a box's tag tells apart.
#include "idris_rt.h"

export module idr.layout:fit;

import idr.mlir;
import idr.dialect;

import :cellinfo;
import :components;

using namespace mlir;

export namespace idr::layout {

// Whether `data` may become a box without changing what an op already in
// the module means. With one constructor, every idr.field of a value names
// the constructor it has, so the read stays within its own live cell
// wherever it runs. A closure sum is made by idr-defunctionalize, which
// reads it only through idr.match. A sum of several constructors may
// already be read where its constructor is unknown (a read of an unboxed
// sum may run anywhere), which a box would turn into a load past the end
// of a smaller cell.
bool boxable(DataOp data);

// The cells whose header counts the object slots of what they hold spread
// over their own: each constructor of a box (a memo sum's states among
// them), and each element of an array of an unboxed sum.
class Holders {
public:
  // The holders of `m`: its array element types are found once, here.
  explicit Holders(ModuleOp m);

  // Calls `each` with every holder whose cell counts more object slots
  // than a header can, as `parts` measures the declarations now: the
  // constructor or the element's declaration, what it holds, and how many
  // object slots that takes.
  void overflows(Components &parts,
                 function_ref<void(Operation *at, ArrayRef<Type> held, unsigned objects)> each);

private:
  ModuleOp module;
  // The declarations whose values are array elements.
  SetVector<DataOp> elements;
};

// Makes boxes of records and closure sums until no cell that holds one
// counts more object slots than its header can, the widest first (ties by
// name), and retypes their values in the module; returns how many it made.
// A cell that still overflows does so by fields no box can shrink, which
// Layouts::of reports.
unsigned fit(ModuleOp module);

} // namespace idr::layout

namespace idr::layout {

bool boxable(DataOp data) {
  if (data.getBox())
    return false;
  size_t ctors = data.getCtors().size();
  return ctors == 1 || (data.getClosures() && ctors <= IDRIS_RT_TAG_LIMIT);
}

Holders::Holders(ModuleOp m) : module(m) {
  Components parts(m);
  AttrTypeWalker walker;
  walker.addWalk([&](MemRefType array) {
    if (auto data = dyn_cast<DataType>(unrestricted(array.getElementType())))
      if (DataOp decl = parts.declaration(data.getName().getAttr()))
        elements.insert(decl);
  });
  m.walk([&](Operation *op) {
    walker.walk(op->getAttrDictionary());
    for (Type type : op->getResultTypes())
      walker.walk(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          walker.walk(type);
  });
}

void Holders::overflows(
    Components &parts,
    function_ref<void(Operation *at, ArrayRef<Type> held, unsigned objects)> each) {
  for (DataOp data : module.getOps<DataOp>()) {
    if (!data.getBox())
      continue;
    for (CtorOp ctor : data.getCtors()) {
      SmallVector<Type> fields = llvm::to_vector(ctor.getFieldTypes().getAsValueRange<TypeAttr>());
      if (unsigned n = parts.objects(fields); n > mostObjects)
        each(ctor, fields, n);
    }
  }
  // An element of a box is one pointer.
  for (DataOp decl : elements) {
    if (decl.getBox())
      continue;
    Type value = decl.getValueType();
    if (unsigned n = parts.objects(value); n > mostObjects)
      each(decl, value, n);
  }
}

namespace {

// The boxable declarations of two or more object slots that a holder
// holds by `type`, looking through the unboxed sums that are not boxable,
// whose slots it holds too. Boxing one of fewer slots shrinks no cell.
void candidates(Components &parts, Type type, MapVector<DataOp, unsigned> &out,
                DenseSet<DataOp> &seen) {
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data)
    return;
  DataOp decl = parts.declaration(data.getName().getAttr());
  if (!decl || !seen.insert(decl).second)
    return;
  if (boxable(decl)) {
    if (unsigned n = parts.objects(data); n >= 2)
      out.insert({decl, n});
    return;
  }
  for (CtorOp ctor : decl.getCtors())
    for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
      candidates(parts, field, out, seen);
}

// Retypes the values of the declarations `boxed` names to their boxes, in
// `roots` and everything nested in them: attributes (a function's type, a
// constructor's fields), results and block arguments. Only the carrier
// changes, so a grade around it stays. A replacer caches what it replaced,
// so each retype makes its own: an answer cached before a decision would
// be stale after it.
void retype(ArrayRef<Operation *> roots, const DenseSet<StringAttr> &boxed) {
  AttrTypeReplacer replacer;
  replacer.addReplacement([&](DataType data) -> std::optional<Type> {
    if (!boxed.contains(data.getName().getAttr()))
      return std::nullopt;
    return BoxType::get(data.getContext(), data.getName());
  });
  for (Operation *root : roots)
    replacer.recursivelyReplaceElementsIn(root, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                          /*replaceTypes=*/true);
}

} // namespace

unsigned fit(ModuleOp module) {
  Holders holders(module);
  DenseSet<StringAttr> boxed;
  while (true) {
    // Measured afresh: the last box changed the shapes.
    Components parts(module);
    MapVector<DataOp, unsigned> wide;
    DenseSet<DataOp> seen;
    holders.overflows(parts, [&](Operation *, ArrayRef<Type> held, unsigned) {
      for (Type type : held)
        candidates(parts, type, wide, seen);
    });
    // The widest takes the most object slots out of every cell that holds
    // it, so the fewest types become boxes; an outer record goes before
    // its parts, and a part only when the outer one's own cell then
    // overflows. Ties go to the smaller name, so the choice is the
    // module's alone.
    DataOp widest;
    unsigned most = 0;
    for (auto [decl, n] : wide)
      if (n > most || (n == most && decl.getSymName() < widest.getSymName())) {
        widest = decl;
        most = n;
      }
    if (!widest)
      break;
    widest.setBox(true);
    boxed.insert(widest.getSymNameAttr());
    // The declarations are what the next measure reads.
    retype(llvm::map_to_vector(module.getOps<DataOp>(),
                               [](DataOp data) { return data.getOperation(); }),
           boxed);
  }
  if (!boxed.empty())
    retype(module.getOperation(), boxed);
  return static_cast<unsigned>(boxed.size());
}

} // namespace idr::layout
