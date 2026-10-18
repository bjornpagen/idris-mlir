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
// field; no field used once by its type, as the world is; and no array a
// world orders) or an array of a static shape whose element is no record
// that splits. A field that is a record that splits is its leaves in turn:
// a record never holds itself but through a box, so the leaves are found
// by structure.
bool splits(DataType data) {
  if (data.getKind() != SumKind::Plain || data.getCtors().size() != 1)
    return false;
  const Ctor &ctor = data.getCtor(Record::tag);
  if (ctor.fields.empty())
    return false;
  return llvm::all_of(ctor.fields, [](Type field) {
    if (!gradeOf(field).plain() || isLinearByType(field) || isa<BaseMemRefType>(field))
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

std::optional<Record> recordOf(Type type) {
  auto data = dyn_cast<DataType>(type);
  if (!data || !splits(data))
    return std::nullopt;
  return Record{data};
}

void leavesOf(Type type, SmallVectorImpl<Type> &leaves) {
  std::optional<Record> record = recordOf(type);
  if (!record) {
    leaves.push_back(type);
    return;
  }
  for (Type field : record->fields())
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

SmallVector<Value> takeApart(OpBuilder &b, Location loc, Value value, Record record) {
  auto con = value.getDefiningOp<ConOp>();
  SmallVector<Value> leaves;
  for (auto [index, field] : llvm::enumerate(record.fields())) {
    auto at = static_cast<unsigned>(index);
    Value given =
        con ? con.getFields()[at] : FieldOp::create(b, loc, value, Record::tag, at).getResult();
    if (std::optional<Record> inner = recordOf(field))
      llvm::append_range(leaves, takeApart(b, loc, given, *inner));
    else
      leaves.push_back(given);
  }
  return leaves;
}

Value build(OpBuilder &b, Location loc, Record record, ValueRange &leaves) {
  SmallVector<Value> fields;
  for (Type field : record.fields()) {
    if (std::optional<Record> inner = recordOf(field)) {
      fields.push_back(build(b, loc, *inner, leaves));
      continue;
    }
    fields.push_back(leaves.front());
    leaves = leaves.drop_front();
  }
  return ConOp::create(b, loc, record.data, Record::tag, fields).getResult();
}

Value readRecord(OpBuilder &b, Location loc, Record element, ValueRange columns,
                 ValueRange indices) {
  SmallVector<Type> leaves;
  leavesOf(element.data, leaves);
  SmallVector<Value> values;
  for (auto [column, leaf] : llvm::zip_equal(columns, leaves))
    values.push_back(structure::readCell(b, loc, column, indices, leaf));
  ValueRange rest = values;
  return build(b, loc, element, rest);
}

SmallVector<Value> writeRecord(OpBuilder &b, Location loc, Value value, Record element,
                               ValueRange columns, ValueRange indices) {
  SmallVector<Value> written;
  for (auto [leaf, column] : llvm::zip_equal(takeApart(b, loc, value, element), columns))
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

Value gather(OpBuilder &b, Location loc, RankedTensorType type, Record element,
             ValueRange columns) {
  TabulateOp made = tabulation(b, loc, type, columns.front(), TypeRange{type}, [&](ValueRange at) {
    return SmallVector<Value>{readRecord(b, loc, element, columns, at)};
  });
  return made.getArrays().front();
}

SmallVector<Value> scatter(OpBuilder &b, Location loc, Value array, Record element,
                           TypeRange types) {
  auto type = cast<RankedTensorType>(array.getType());
  TabulateOp made = tabulation(b, loc, type, array, types, [&](ValueRange at) {
    return takeApart(b, loc, tensor::ExtractOp::create(b, loc, array, at), element);
  });
  return SmallVector<Value>(made.getArrays());
}

ColumnConverter::ColumnConverter() {
  addConversion([](Type type) { return type; });
  // An array of records at any grade: its columns at that grade.
  addConversion([](Type type, SmallVectorImpl<Type> &columns) -> std::optional<LogicalResult> {
    auto array = dyn_cast<RankedTensorType>(unrestricted(type));
    if (!array || !recordOf(array.getElementType()).has_value())
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
    if (std::optional<Record> record = recordOf(type)) {
      ValueRange leaves = inputs;
      return build(b, loc, *record, leaves);
    }
    auto array = dyn_cast<RankedTensorType>(unrestricted(type));
    if (!array)
      return Value();
    std::optional<Record> element = recordOf(array.getElementType());
    if (!element)
      return Value();
    SmallVector<Value> plain;
    for (Value column : inputs)
      plain.push_back(heldAs(b, loc, column, unrestricted(column.getType())));
    return heldAs(b, loc, gather(b, loc, array, *element, plain), type);
  });
  // An array of records from an op the conversion does not take: its
  // columns taken apart from it.
  addTargetMaterialization([](OpBuilder &b, TypeRange types, ValueRange inputs, Location loc,
                              Type) -> SmallVector<Value> {
    if (inputs.size() != 1)
      return {};
    Value whole = inputs.front();
    auto array = dyn_cast<RankedTensorType>(unrestricted(whole.getType()));
    if (!array)
      return {};
    std::optional<Record> element = recordOf(array.getElementType());
    if (!element)
      return {};
    SmallVector<Type> plain = llvm::map_to_vector(types, unrestricted);
    SmallVector<Value> columns;
    for (auto [column, type] :
         llvm::zip_equal(scatter(b, loc, heldAs(b, loc, whole, array), *element, plain), types))
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

} // namespace idr::columns
