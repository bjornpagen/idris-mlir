// Data declarations: idr.data and its constructors, idr.ctor.

#include "idr/Idr.h"

#include "llvm/ADT/DenseSet.h"

using namespace mlir;
using namespace idr;

SmallVector<CtorOp> DataOp::getCtors() {
  return llvm::to_vector(getBody().front().getOps<CtorOp>());
}

Type DataOp::getValueType() {
  auto name = FlatSymbolRefAttr::get(getSymNameAttr());
  if (getBox())
    return BoxType::get(getContext(), name);
  return DataType::get(getContext(), name);
}

bool idr::isMemo(DataOp data) { return data.getMemo(); }

namespace {

// A memo sum is a box, so that every reference sees one memo. Its
// constructors are its labels, each named after its function, which
// `labels` names, and the two states a force writes a cell into: `running`,
// with no field, and `forced`, with the value. Only a label runs at a
// force, so only a label is `by_name`.
LogicalResult verifyMemo(DataOp data) {
  if (!data.getBox())
    return data.emitOpError("is a memo sum, which must be a box: a cell has one memo, "
                            "which every reference to it sees");
  llvm::SmallDenseSet<StringAttr> labels;
  if (ArrayAttr named = data.getLabelsAttr())
    for (auto label : named.getAsRange<FlatSymbolRefAttr>())
      labels.insert(label.getAttr());
  bool running = false, forced = false;
  size_t ctors = 0;
  for (CtorOp ctor : data.getCtors()) {
    StringRef name = ctor.getSymName();
    if (name == memoRunning || name == memoForced) {
      if (ctor.getByName())
        return ctor.emitOpError("is a state of a memo sum, which is never by_name: only a label "
                                "runs at a force");
      if (name == memoRunning) {
        if (!ctor.getFieldTypes().empty())
          return ctor.emitOpError("is a memo sum's running state, which has no field");
        running = true;
      } else {
        if (ctor.getFieldTypes().size() != 1)
          return ctor.emitOpError("is a memo sum's forced state, whose one field is the value");
        forced = true;
      }
      continue;
    }
    if (!labels.contains(ctor.getSymNameAttr()))
      return ctor.emitOpError("is a constructor of a memo sum that is neither a state nor one of "
                              "its labels");
    ++ctors;
  }
  if (!running || !forced)
    return data.emitOpError("is a memo sum without its state @")
           << StringRef(running ? memoForced : memoRunning);
  if (ctors != labels.size())
    return data.emitOpError("names labels that are not its constructors");
  return success();
}

} // namespace

LogicalResult DataOp::verify() {
  for (Operation &op : getBody().front())
    if (!isa<CtorOp>(op))
      return op.emitOpError("is not allowed inside idr.data");
  if (getMemo())
    return verifyMemo(*this);
  if (getLabels())
    return emitOpError("names labels, which only a memo sum has");
  for (CtorOp ctor : getCtors())
    if (ctor.getByName())
      return ctor.emitOpError("is by_name, which only a label of a memo sum is");
  return success();
}

Type CtorOp::getFieldType(unsigned index) {
  return cast<TypeAttr>(getFieldTypes()[index]).getValue();
}

unsigned CtorOp::getTag() {
  Block *body = (*this)->getBlock();
  return static_cast<unsigned>(std::distance(body->begin(), (*this)->getIterator()));
}

LogicalResult CtorOp::verify() {
  for (Type type : getFieldTypes().getAsValueRange<TypeAttr>())
    if (!isFieldType(type))
      return emitOpError("has a field of unsupported type ") << type;
  return success();
}
