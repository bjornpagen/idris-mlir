// idr.ops:constants: the check of every symbol a constant names, through
// its fields and captures.
export module idr.ops:constants;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// The constants and types already checked: a constant that compile-time
// evaluation made shares its parts, and each is checked once.
using Checked = llvm::DenseSet<std::pair<Attribute, Type>>;

// That `value` is a constant of `type`, recursively through fields and
// captures, with every symbol resolved.
LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols,
                             Attribute value, Type type, Checked &checked);

} // namespace idr::ops

namespace {

LogicalResult verifyConstants(Operation *op, SymbolTableCollection &symbols,
                              ArrayAttr values, TypeRange types, ops::Checked &checked) {
  if (values.size() != types.size())
    return op->emitOpError("has a constant with ")
           << values.size() << " fields or captures where " << types.size()
           << " are expected";
  // A constant fills a linear field or capture as its plain value.
  for (auto [value, type] : llvm::zip(values, types))
    if (failed(ops::verifyConstant(op, symbols, value, unrestricted(type), checked)))
      return failure();
  return success();
}

// That `value`, a constant of `type` other than a constructor, names
// functions that take its captures.
LogicalResult verifyClosure(Operation *op, SymbolTableCollection &symbols, Attribute value,
                            Type type, ops::Checked &checked) {
  auto closure = dyn_cast<ClosureAttr>(value);
  if (!closure)
    return success();
  auto fn = symbols.lookupNearestSymbolFrom<func::FuncOp>(op, closure.getCallee());
  if (!fn)
    return op->emitOpError("has a closure of an unknown function ") << closure.getCallee();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  size_t captures = closure.getCaptures().size();
  if (captures > inputs.size())
    return op->emitOpError("has a closure with more captures than ")
           << closure.getCallee() << " has parameters";
  // A suspension's function has no arguments past its captures: the cell
  // is the whole value, and forcing it passes nothing more.
  if (auto lazy = dyn_cast<LazyType>(type)) {
    // idr-rc grades the function's return; the constant stays a plain
    // cell, and the carrier is what the two still share.
    if (captures != inputs.size() || fn.getNumResults() != 1 ||
        unrestricted(fn.getResultTypes()[0]) != unrestricted(lazy.getValue()) ||
        llvm::any_of(inputs, isWorld))
      return op->emitOpError("has a suspension of ")
             << closure.getCallee() << ", where " << type << " is expected";
    return verifyConstants(op, symbols, closure.getCaptures(), inputs, checked);
  }
  // The function's signature carries the grades reference counting added.
  // The constant names the same carriers at the quantities Idris proved.
  auto actual = dyn_cast<FnType>(unrestricted(type));
  if (!actual || !sameCarriers(inputs.drop_front(captures), actual.getInputs()) ||
      !sameCarriers(fn.getResultTypes(), actual.getResults()))
    return op->emitOpError("has a closure of ")
           << closure.getCallee() << ", of type "
           << FnType::get(op->getContext(), inputs.drop_front(captures), fn.getResultTypes())
           << ", where " << type << " is expected";
  return verifyConstants(op, symbols, closure.getCaptures(), inputs.take_front(captures),
                         checked);
}

} // namespace

// A run's tail is the next value of the loop, after its cells: a list is
// checked a cell at a time however long it is, and never through the
// suffix that reading the field along its spine would build.
LogicalResult idr::ops::verifyConstant(Operation *op, SymbolTableCollection &symbols,
                                       Attribute value, Type type, Checked &checked) {
  while (checked.insert({value, type}).second) {
    if (auto scalar = dyn_cast<TypedAttr>(value);
        scalar && isa<IntegerAttr, FloatAttr>(value) && scalar.getType() == type &&
        isFieldType(type))
      return success();
    if (!ConstantOp::isBuildableWith(value, type))
      return op->emitOpError("has a constant ") << value << " where " << type << " is expected";
    auto con = dyn_cast<ConAttr>(value);
    if (!con)
      return verifyClosure(op, symbols, value, type, checked);
    auto data = symbols.lookupNearestSymbolFrom<DataOp>(
        op, FlatSymbolRefAttr::get(con.getCtor().getRootReference()));
    if (!data || data.getValueType() != type)
      return op->emitOpError("has a constant of an undeclared type ") << type;
    CtorOp ctor = lookupCtor(data, con.getCtor().getLeafReference());
    if (!ctor)
      return op->emitOpError("has a constant of an unknown constructor ") << con.getCtor();
    SmallVector<Type> fields(ctor.getFieldTypes().getAsValueRange<TypeAttr>());
    if (!con.isRun())
      return verifyConstants(op, symbols, con.getFields(), fields, checked);
    // Each cell after the first is the field along the spine of the one
    // before, so that field holds the constructor's own type.
    unsigned spine = con.getSpine();
    if (spine >= fields.size() || unrestricted(fields[spine]) != type)
      return op->emitOpError("has a run of ")
             << con.getCtor() << " along field " << spine << ", which does not hold " << type;
    fields.erase(fields.begin() + spine);
    for (ArrayAttr cell : con.getRunCells())
      if (failed(verifyConstants(op, symbols, cell, fields, checked)))
        return failure();
    value = con.getTail();
  }
  return success();
}
