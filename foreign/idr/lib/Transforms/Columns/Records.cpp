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
#include "llvm/ADT/SmallVectorExtras.h"

#include <type_traits>

using namespace mlir;

namespace idr::columns {

namespace {

// An array of the dimensions `dims` holding `leaf` at each index. A leaf
// is never an array: a field holds an array's buffer, and a record with
// one is kept whole.
RankedTensorType columnOf(ArrayRef<int64_t> dims, Type leaf) {
  return RankedTensorType::get(dims, leaf);
}

// Every data type a type reaches, through grades, arrays and the fields of
// data types, each once.
void reach(Type type, llvm::DenseSet<Type> &seen, SmallVectorImpl<DataType> &found) {
  type = unrestricted(type);
  if (auto array = dyn_cast<ShapedType>(type))
    return reach(array.getElementType(), seen, found);
  auto data = dyn_cast<DataType>(type);
  if (!data || !seen.insert(data).second)
    return;
  found.push_back(data);
  for (Tag tag : data.possibleTags())
    for (Type field : data.ctor(tag).fields)
      reach(field, seen, found);
}

} // namespace

Records::Records(ProgramOp program) {
  llvm::DenseSet<Type> seen;
  SmallVector<DataType> found;
  program->walk([&](Operation *op) {
    for (Type type : op->getResultTypes())
      reach(type, seen, found);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          reach(arg.getType(), seen, found);
  });
  for (DataType data : found)
    for (Tag tag : data.possibleTags())
      for (Type field : data.ctor(tag).fields)
        if (auto array = dyn_cast<ShapedType>(unrestricted(field)))
          if (isa<DataType>(array.getElementType()))
            held.insert(array.getElementType());
}

// Whether the record `data` splits: no data type of the program holds an
// array of it, and it is data (no closure or memo sum) of one constructor
// of at least one field, each an element an array holds whole: used any
// number of times (a linear field is used once, and its column would be
// used as the array is), and no buffer (an array a field holds is its
// buffer, of mutable memory or a value array's, which a column cannot
// hold). A field that is a record that splits is its leaves in turn: a
// record never holds itself but through a cell, so the leaves are found by
// structure.
bool Records::splits(DataType data) const {
  if (held.contains(data) || data.memo() || data.closures() || data.declaredCount() != 1)
    return false;
  ArrayRef<Type> fields = data.ctor(Record::tag).fields;
  if (fields.empty())
    return false;
  return llvm::all_of(fields, [&](Type field) {
    return !isLinear(field) && !isa<ShapedType>(unrestricted(field));
  });
}

std::optional<Record> Records::recordOf(Type type) const {
  auto data = dyn_cast<DataType>(type);
  if (!data || !splits(data))
    return std::nullopt;
  return Record{data};
}

void Records::leavesOf(Type type, SmallVectorImpl<Type> &leaves) const {
  std::optional<Record> record = recordOf(type);
  if (!record) {
    leaves.push_back(type);
    return;
  }
  for (Type field : record->fields())
    leavesOf(field, leaves);
}

void Records::columnsOf(RankedTensorType array, SmallVectorImpl<Type> &columns) const {
  if (!recordOf(array.getElementType())) {
    columns.push_back(array);
    return;
  }
  SmallVector<Type> leaves;
  leavesOf(array.getElementType(), leaves);
  for (Type leaf : leaves)
    columns.push_back(columnOf(array.getShape(), leaf));
}

SmallVector<Value> Records::takeApart(OpBuilder &b, Location loc, Value value,
                                      Record record) const {
  auto con = value.getDefiningOp<DataConOp>();
  SmallVector<Value> leaves;
  for (auto [index, field] : llvm::enumerate(record.fields())) {
    auto at = static_cast<unsigned>(index);
    Type read = fieldType(value.getType(), unrestricted(field), usesOf(field), Recursion::Other);
    Value given =
        con ? con.getFields()[at] : DataFieldOp::create(b, loc, read, value, at).getResult();
    if (std::optional<Record> inner = recordOf(field))
      llvm::append_range(leaves, takeApart(b, loc, given, *inner));
    else
      leaves.push_back(given);
  }
  return leaves;
}

Value Records::build(OpBuilder &b, Location loc, Record record, ValueRange &leaves) const {
  SmallVector<Value> fields;
  for (Type field : record.fields()) {
    if (std::optional<Record> inner = recordOf(field)) {
      fields.push_back(build(b, loc, *inner, leaves));
      continue;
    }
    fields.push_back(leaves.front());
    leaves = leaves.drop_front();
  }
  return DataConOp::create(b, loc, record.data, fields).getResult();
}

Value Records::readRecord(OpBuilder &b, Location loc, Record element, ValueRange columns,
                          ValueRange indices) const {
  SmallVector<Type> leaves;
  leavesOf(element.data, leaves);
  SmallVector<Value> values;
  for (auto [column, leaf] : llvm::zip_equal(columns, leaves))
    values.push_back(structure::readCell(b, loc, column, indices, leaf));
  ValueRange rest = values;
  return build(b, loc, element, rest);
}

SmallVector<Value> Records::writeRecord(OpBuilder &b, Location loc, Value value, Record element,
                                        ValueRange columns, ValueRange indices) const {
  SmallVector<Value> written;
  for (auto [leaf, column] : llvm::zip_equal(takeApart(b, loc, value, element), columns))
    written.push_back(structure::writeCell(b, loc, leaf, column, indices));
  return written;
}

namespace {

// A tabulation over the dimensions of `shape`, whose sizes `source`'s
// dimensions give, writing fresh arrays of `types`, its region given its
// indices. Each destination has the domain's dimensions, then its leaf's
// own, which its type fixes.
template <typename BodyFn>
  requires std::is_invocable_r_v<SmallVector<Value>, BodyFn, ValueRange>
ArrayTabulateOp tabulation(OpBuilder &b, Location loc, RankedTensorType shape, Value source,
                      TypeRange types, BodyFn &&body) {
  SmallVector<Value> sizes;
  for (unsigned d = 0, e = static_cast<unsigned>(shape.getRank()); d < e; ++d)
    if (shape.isDynamicDim(d))
      sizes.push_back(tensor::DimOp::create(b, loc, source, d));
  SmallVector<Value> outs = llvm::map_to_vector(types, [&](Type type) -> Value {
    return tensor::EmptyOp::create(b, loc, cast<RankedTensorType>(type), sizes);
  });
  auto made = ArrayTabulateOp::create(b, loc, types, outs);
  OpBuilder::InsertionGuard guard(b);
  SmallVector<Type> indices(static_cast<size_t>(shape.getRank()), b.getIndexType());
  Block *region = b.createBlock(&made.getRegion(), {}, indices,
                                SmallVector<Location>(indices.size(), loc));
  ArrayYieldOp::create(b, loc, body(region->getArguments()));
  return made;
}

} // namespace

Value Records::gather(OpBuilder &b, Location loc, RankedTensorType type, Record element,
                      ValueRange columns) const {
  ArrayTabulateOp made =
      tabulation(b, loc, type, columns.front(), TypeRange{type}, [&](ValueRange at) {
        return SmallVector<Value>{readRecord(b, loc, element, columns, at)};
      });
  return made.getArrays().front();
}

SmallVector<Value> Records::scatter(OpBuilder &b, Location loc, Value array, Record element,
                                    TypeRange types) const {
  auto type = cast<RankedTensorType>(array.getType());
  ArrayTabulateOp made = tabulation(b, loc, type, array, types, [&](ValueRange at) {
    return takeApart(b, loc, tensor::ExtractOp::create(b, loc, array, at), element);
  });
  return SmallVector<Value>(made.getArrays());
}

ColumnConverter::ColumnConverter(const Records &records) : split(records) {
  addConversion([](Type type) { return type; });
  // An array of records at any grade: its columns at that grade.
  addConversion([&records](Type type,
                           SmallVectorImpl<Type> &columns) -> std::optional<LogicalResult> {
    auto array = dyn_cast<RankedTensorType>(unrestricted(type));
    if (!array || !records.recordOf(array.getElementType()).has_value())
      return std::nullopt;
    SmallVector<Type> plain;
    records.columnsOf(array, plain);
    for (Type column : plain)
      columns.push_back(graded(gradeOf(type), column));
    return success();
  });
  // Back to what an op the conversion does not take holds: an array of
  // records gathered from its columns, or a record built of its leaves.
  addSourceMaterialization([&records](OpBuilder &b, Type type, ValueRange inputs,
                                      Location loc) -> Value {
    if (std::optional<Record> record = records.recordOf(type)) {
      ValueRange leaves = inputs;
      return records.build(b, loc, *record, leaves);
    }
    auto array = dyn_cast<RankedTensorType>(unrestricted(type));
    if (!array)
      return Value();
    std::optional<Record> element = records.recordOf(array.getElementType());
    if (!element)
      return Value();
    SmallVector<Value> plain;
    for (Value column : inputs)
      plain.push_back(heldAs(b, loc, column, unrestricted(column.getType())));
    return heldAs(b, loc, records.gather(b, loc, array, *element, plain), type);
  });
  // An array of records from an op the conversion does not take: its
  // columns taken apart from it.
  addTargetMaterialization([&records](OpBuilder &b, TypeRange types, ValueRange inputs,
                                      Location loc, Type) -> SmallVector<Value> {
    if (inputs.size() != 1)
      return {};
    Value whole = inputs.front();
    auto array = dyn_cast<RankedTensorType>(unrestricted(whole.getType()));
    if (!array)
      return {};
    std::optional<Record> element = records.recordOf(array.getElementType());
    if (!element)
      return {};
    SmallVector<Type> plain = llvm::map_to_vector(types, unrestricted);
    SmallVector<Value> columns;
    for (auto [column, type] : llvm::zip_equal(
             records.scatter(b, loc, heldAs(b, loc, whole, array), *element, plain), types))
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
