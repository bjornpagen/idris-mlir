// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an array of records is held as: which records split, into which
// leaves, and how a record is read from its columns, written into them,
// built and taken apart; the type conversion, and the gather and the
// scatter where an array of records meets what holds it whole.

#include "idr/Transforms/Columns.h"

#include "idr/IR/Grades.h"
#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::columns {

namespace {

// Whether the record `data` splits: one plain constructor of at least
// one field, each an element an array holds whole (no grade, so no linear
// field and no world, and no array a world orders) or an array of a static
// shape whose element is no record that splits. A field that is a record
// that splits is its leaves in turn: a record never holds itself but
// through a box, so the leaves are found by structure.
bool splits(DataType data) {
  if (data.getKind() != SumKind::Plain || data.getCtors().size() != 1)
    return false;
  const Ctor &ctor = data.getCtor(0);
  if (ctor.role != CtorRole::Plain || ctor.fields.empty())
    return false;
  return llvm::all_of(ctor.fields, [](Type field) {
    if (!gradeOf(field).plain() || isa<BaseMemRefType>(field))
      return false;
    if (auto array = dyn_cast<RankedTensorType>(field))
      return array.hasStaticShape() && !recordOf(array.getElementType());
    return !isa<ShapedType>(field);
  });
}

// An array of the dimensions `dims` holding `leaf` at each index: its
// dimensions, then the leaf's own where it is an array.
RankedTensorType columnOf(ArrayRef<int64_t> dims, Type leaf) {
  if (auto array = dyn_cast<RankedTensorType>(leaf))
    return RankedTensorType::get(
        llvm::to_vector(llvm::concat<const int64_t>(dims, array.getShape())),
        array.getElementType());
  return RankedTensorType::get(dims, leaf);
}

} // namespace

DataType recordOf(Type type) {
  auto data = dyn_cast<DataType>(type);
  return data && splits(data) ? data : DataType();
}

void leavesOf(Type type, SmallVectorImpl<Type> &leaves) {
  DataType record = recordOf(type);
  if (!record) {
    leaves.push_back(type);
    return;
  }
  for (Type field : record.getCtor(0).fields)
    leavesOf(field, leaves);
}

void columnsOf(RankedTensorType array, SmallVectorImpl<Type> &columns) {
  if (!recordOf(array.getElementType())) {
    columns.push_back(array);
    return;
  }
  SmallVector<Type> leaves;
  leavesOf(array.getElementType(), leaves);
  for (Type leaf : leaves)
    columns.push_back(columnOf(array.getShape(), leaf));
}

SmallVector<Value> takeApart(OpBuilder &b, Location loc, Value record) {
  DataType data = recordOf(record.getType());
  auto con = record.getDefiningOp<ConOp>();
  SmallVector<Value> leaves;
  for (auto [index, field] : llvm::enumerate(data.getCtor(0).fields)) {
    auto at = static_cast<unsigned>(index);
    Value value = con ? con.getField(at) : Value();
    if (!value)
      value = FieldOp::create(b, loc, record, 0u, at).getResult();
    if (recordOf(field))
      llvm::append_range(leaves, takeApart(b, loc, value));
    else
      leaves.push_back(value);
  }
  return leaves;
}

Value build(OpBuilder &b, Location loc, Type type, ValueRange &leaves) {
  DataType data = recordOf(type);
  SmallVector<Value> fields;
  for (Type field : data.getCtor(0).fields) {
    if (recordOf(field)) {
      fields.push_back(build(b, loc, field, leaves));
      continue;
    }
    fields.push_back(leaves.front());
    leaves = leaves.drop_front();
  }
  return ConOp::create(b, loc, type, 0u, fields).getResult();
}

Value readRecord(OpBuilder &b, Location loc, Type element, ValueRange columns, ValueRange indices) {
  SmallVector<Type> leaves;
  leavesOf(element, leaves);
  SmallVector<Value> values;
  for (auto [column, leaf] : llvm::zip_equal(columns, leaves))
    values.push_back(structure::readCell(b, loc, column, indices, leaf));
  ValueRange rest = values;
  return build(b, loc, element, rest);
}

SmallVector<Value> writeRecord(OpBuilder &b, Location loc, Value record, ValueRange columns,
                               ValueRange indices) {
  SmallVector<Value> written;
  for (auto [leaf, column] : llvm::zip_equal(takeApart(b, loc, record), columns))
    written.push_back(structure::writeCell(b, loc, leaf, column, indices));
  return written;
}

namespace {

// A tabulation over the dimensions of `shape`, whose sizes `source`'s
// dimensions give, making arrays of `types`, its region given its indices.
template <typename BodyFn>
TabulateOp tabulation(OpBuilder &b, Location loc, RankedTensorType shape, Value source,
                      TypeRange types, BodyFn body) {
  SmallVector<Value> sizes;
  for (unsigned d = 0, e = static_cast<unsigned>(shape.getRank()); d < e; ++d)
    if (shape.isDynamicDim(d))
      sizes.push_back(tensor::DimOp::create(b, loc, source, d));
  auto made = TabulateOp::create(b, loc, types, sizes);
  OpBuilder::InsertionGuard guard(b);
  SmallVector<Type> indices(static_cast<size_t>(shape.getRank()), b.getIndexType());
  Block *region = b.createBlock(&made.getRegion(), {}, indices,
                                SmallVector<Location>(indices.size(), loc));
  ArrayYieldOp::create(b, loc, body(region->getArguments()));
  return made;
}

} // namespace

Value gather(OpBuilder &b, Location loc, RankedTensorType type, ValueRange columns) {
  TabulateOp made = tabulation(b, loc, type, columns.front(), TypeRange{type}, [&](ValueRange at) {
    return SmallVector<Value>{readRecord(b, loc, type.getElementType(), columns, at)};
  });
  return made.getArrays().front();
}

SmallVector<Value> scatter(OpBuilder &b, Location loc, Value array, TypeRange types) {
  auto type = cast<RankedTensorType>(array.getType());
  TabulateOp made = tabulation(b, loc, type, array, types, [&](ValueRange at) {
    return takeApart(b, loc, tensor::ExtractOp::create(b, loc, array, at));
  });
  return SmallVector<Value>(made.getArrays());
}

ColumnConverter::ColumnConverter() {
  addConversion([](Type type) { return type; });
  // An array of records at any grade: its columns at that grade.
  addConversion([](Type type, SmallVectorImpl<Type> &columns) -> std::optional<LogicalResult> {
    auto array = dyn_cast<RankedTensorType>(unrestricted(type));
    if (!array || !recordOf(array.getElementType()))
      return std::nullopt;
    SmallVector<Type> plain;
    columnsOf(array, plain);
    for (Type column : plain)
      columns.push_back(graded(gradeOf(type), column));
    return success();
  });
  // Back to what an op the conversion does not take holds: an array of
  // records gathered from its columns, or a record built of its leaves.
  addSourceMaterialization([](OpBuilder &b, Type type, ValueRange inputs, Location loc) -> Value {
    if (recordOf(type)) {
      ValueRange leaves = inputs;
      return build(b, loc, type, leaves);
    }
    auto array = dyn_cast<RankedTensorType>(unrestricted(type));
    if (!array || !recordOf(array.getElementType()))
      return Value();
    SmallVector<Value> plain;
    for (Value column : inputs)
      plain.push_back(heldAs(b, loc, column, unrestricted(column.getType())));
    return heldAs(b, loc, gather(b, loc, array, plain), type);
  });
  // An array of records from an op the conversion does not take: its
  // columns taken apart from it.
  addTargetMaterialization([](OpBuilder &b, TypeRange types, ValueRange inputs, Location loc,
                              Type) -> SmallVector<Value> {
    if (inputs.size() != 1)
      return {};
    Value whole = inputs.front();
    auto array = dyn_cast<RankedTensorType>(unrestricted(whole.getType()));
    if (!array || !recordOf(array.getElementType()))
      return {};
    SmallVector<Type> plain = llvm::map_to_vector(types, unrestricted);
    SmallVector<Value> columns;
    for (auto [column, type] :
         llvm::zip_equal(scatter(b, loc, heldAs(b, loc, whole, array), plain), types))
      columns.push_back(heldAs(b, loc, column, type));
    return columns;
  });
}


SmallVector<Value> flatten(ArrayRef<ValueRange> ranges) {
  SmallVector<Value> values;
  for (ValueRange range : ranges)
    llvm::append_range(values, range);
  return values;
}

LogicalResult convertEach(const TypeConverter &converter, TypeRange types,
                          SmallVectorImpl<Type> &converted, SmallVectorImpl<unsigned> &counts) {
  for (Type type : types) {
    size_t before = converted.size();
    if (failed(converter.convertType(type, converted)))
      return failure();
    counts.push_back(static_cast<unsigned>(converted.size() - before));
  }
  return success();
}

SmallVector<SmallVector<Value>> runs(ValueRange values, ArrayRef<unsigned> counts) {
  SmallVector<SmallVector<Value>> out;
  for (unsigned count : counts) {
    out.emplace_back(values.take_front(count));
    values = values.drop_front(count);
  }
  return out;
}

Operation *remake(ConversionPatternRewriter &rewriter, Operation *op, ValueRange operands,
                  TypeRange results) {
  OperationState state(op->getLoc(), op->getName());
  state.addOperands(operands);
  state.addTypes(results);
  state.addAttributes(op->getDiscardableAttrDictionary().getValue());
  state.propertiesAttr = op->getPropertiesAsAttribute();
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
    state.addRegion();
  Operation *made = rewriter.create(state);
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
    rewriter.inlineRegionBefore(op->getRegion(i), made->getRegion(i), made->getRegion(i).end());
  return made;
}

} // namespace idr::columns
