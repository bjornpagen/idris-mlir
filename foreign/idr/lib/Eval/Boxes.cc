// Reading a box back from compile-time evaluation: the constructor its cell
// holds, a list built at once from its cells, or, in a sum
// idr-defunctionalize made, what the cell was made of: a closure, or a
// suspension.
module;
// The runtime's C ABI: a cell's header and its info word. No import carries
// them.
#include "idris_rt.h"

module idr.eval;

import idr.mlir;
import idr.dialect;
import idr.layout;

using namespace mlir;

namespace idr::eval {

namespace {

// The cell a word of a result points to, and the tag in its header.
const char *cellAt(uint64_t word) {
  return reinterpret_cast<const char *>(static_cast<uintptr_t>(word));
}

uint32_t tagAt(uint64_t word) {
  const auto *header = reinterpret_cast<const idris_rt_header *>(static_cast<uintptr_t>(word));
  return idris_rt_info_tag(header->info);
}

} // namespace

CtorOp Reifier::cellCtor(DataOp decl, uint64_t word) {
  SmallVector<CtorOp> ctors = decl.getCtors();
  uint32_t tag = tagAt(word);
  if (tag < ctors.size())
    return ctors[tag];
  refuse(Unread::Why::Unreadable,
         ("a cell of @" + decl.getSymName() + " has tag " + Twine(tag)).str());
  return {};
}

SmallVector<unsigned> Reifier::selfFields(Type type, CtorOp ctor, uint64_t word) {
  const layout::Cell &layout = layouts.box(ctor);
  SmallVector<unsigned> own;
  for (unsigned i = 0, e = static_cast<unsigned>(ctor.getFieldTypes().size()); i < e; ++i)
    if (unrestricted(ctor.getFieldType(i)) == type &&
        tagAt(read(cellAt(word), layout.fields[i]).front()) == tagAt(word))
      own.push_back(i);
  return own;
}

// A value of a box type. A sum of closures has no lists: a closure that
// captures one of its own label is a constructor like any other.
Attribute Reifier::box(Type type, uint64_t word) {
  DataOp decl = lookupData(layouts.getModule(), type);
  CtorOp ctor = cellCtor(decl, word);
  if (!ctor)
    return {};
  if (idr::isMemo(decl))
    return suspension(ctor, word);
  auto name =
      SymbolRefAttr::get(decl.getSymNameAttr(), {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
  if (!label(name)) {
    SmallVector<unsigned> own = selfFields(type, ctor, word);
    if (own.size() == 1)
      return run(type, name, ctor, own.front(), word);
  }
  std::optional<SmallVector<Attribute>> values = cellFields(ctor, word);
  if (!values)
    return {};
  return constructor(name, *values);
}

// A memo cell before its force is the suspension it was made of, its label's
// captures in its fields. After its force it holds the value instead, and
// while the force runs it holds nothing: neither is a thunk to rebuild.
Attribute Reifier::suspension(CtorOp ctor, uint64_t word) {
  if (ctor.getSymName() == idr::memoForced)
    return refuse(Unread::Why::Memoized, "a suspension has already stored its value");
  if (ctor.getSymName() == idr::memoRunning)
    return refuse(Unread::Why::Unreadable, "a suspension is still being forced");
  std::optional<SmallVector<Attribute>> captures = cellFields(ctor, word);
  if (!captures)
    return {};
  MLIRContext *ctx = ctor.getContext();
  return ClosureAttr::get(ctx, FlatSymbolRefAttr::get(ctor.getSymNameAttr()),
                          ArrayAttr::get(ctx, *captures));
}

// The list whose head is the cell of `ctor` at `word`, along its field
// `spine`. Its cells along that field are read in a loop, not by recursion,
// up to the tail: the first value the field holds that is no cell of
// `ctor`, or one read already. ConAttr::getRun then builds them at once into
// what ConAttr::get would build one cell at a time, a run or plain cells.
Attribute Reifier::run(Type type, SymbolRefAttr name, CtorOp ctor, unsigned spine,
                       uint64_t word) {
  MLIRContext *ctx = type.getContext();
  const layout::Cell &layout = layouts.box(ctor);
  SmallVector<ArrayAttr> cells;
  SmallVector<uint64_t> addresses;
  Attribute tail;
  for (uint64_t at = word;;) {
    std::optional<SmallVector<Attribute>> values = cellFields(ctor, at, spine);
    if (!values)
      return {};
    cells.push_back(ArrayAttr::get(ctx, *values));
    addresses.push_back(at);
    SmallVector<uint64_t> next = read(cellAt(at), layout.fields[spine]);
    if (tagAt(next.front()) != tagAt(word)) {
      ArrayRef<uint64_t> rest = next;
      if (!(tail = value(ctor.getFieldType(spine), rest)))
        return {};
      break;
    }
    at = next.front();
    if ((tail = known(type, at)))
      break;
  }
  // When the head is a run, the cells read here are its first ones, and each
  // is the rest of the run from there.
  ConAttr list = ConAttr::getRun(ctx, name, spine, cells, tail);
  if (list.isRun())
    for (auto [k, at] : llvm::enumerate(addresses))
      if (k > 0)
        suffixes[{at, type}] = {list, static_cast<unsigned>(k)};
  return list;
}

} // namespace idr::eval
