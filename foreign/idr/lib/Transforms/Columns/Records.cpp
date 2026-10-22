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
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <algorithm>
#include <functional>
#include <type_traits>
#include <utility>

using namespace mlir;

namespace idr::columns {

namespace {

// An array of the dimensions `dims` holding `leaf` at each index. A leaf
// is never an array: a field holds an array's buffer, and a record with
// one is kept whole.
RankedTensorType columnOf(ArrayRef<int64_t> dims, Type leaf) {
  return RankedTensorType::get(dims, leaf);
}

// Types in the order of their uniqued storage: a total order that says
// nothing of the program, by which a sorted list of types answers whether
// it holds one.
bool before(Type a, Type b) {
  return std::less<const void *>()(a.getAsOpaquePointer(), b.getAsOpaquePointer());
}

} // namespace

Records::Records(ProgramOp program) {
  // Every data type the program's values reach, through grades, arrays and
  // the fields of data types, each once. A chain of data types each holding
  // the next is as deep as the program's types, so the types still to
  // visit are a stack of their own, drained after each op.
  llvm::DenseSet<Type> seen;
  footprint::Vector<DataType> found;
  footprint::Vector<Type> pending;
  auto reach = [&] {
    while (!pending.empty()) {
      Type type = unrestricted(pending.back());
      pending.pop_back();
      if (auto array = dyn_cast<ShapedType>(type)) {
        pending.push_back(array.getElementType());
        continue;
      }
      auto data = dyn_cast<DataType>(type);
      if (!data || !seen.insert(data).second)
        continue;
      found.push_back(data);
      for (Tag tag : data.possibleTags())
        llvm::append_range(pending, data.ctor(tag).fields);
    }
  };
  program->walk([&](Operation *op) {
    llvm::append_range(pending, op->getResultTypes());
    for (Region &region : op->getRegions())
      for (Block &block : region)
        llvm::append_range(pending, block.getArgumentTypes());
    reach();
  });
  for (DataType data : found)
    for (Tag tag : data.possibleTags())
      for (Type field : data.ctor(tag).fields)
        if (auto array = dyn_cast<ShapedType>(unrestricted(field)))
          if (isa<DataType>(array.getElementType()))
            held.push_back(array.getElementType());
  llvm::sort(held, before);
  held.erase(std::unique(held.begin(), held.end()), held.end());
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
  if (std::binary_search(held.begin(), held.end(), Type(data), before) || data.memo() || data.closures() || data.declaredCount() != 1)
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

// A record nests records as deep as the program's types, so each walk of
// one below keeps the records it is inside on a stack of its own, each with
// the next of its fields, in field order.
void Records::leavesOf(Type type, SmallVectorImpl<Type> &leaves) const {
  std::optional<Record> record = recordOf(type);
  if (!record) {
    leaves.push_back(type);
    return;
  }
  SmallVector<std::pair<Record, unsigned>> inside{{*record, 0}};
  while (!inside.empty()) {
    auto &[at, next] = inside.back();
    if (next == at.fields().size()) {
      inside.pop_back();
      continue;
    }
    Type field = at.fields()[next++];
    if (std::optional<Record> inner = recordOf(field))
      inside.push_back({*inner, 0});
    else
      leaves.push_back(field);
  }
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
  // A value being taken apart: its record, the idr.data.con that built it,
  // if one did, whose fields it gives, and its next field.
  struct Apart {
    Record record;
    Value value;
    DataConOp con;
    unsigned next;
  };
  SmallVector<Value> leaves;
  SmallVector<Apart> inside{{record, value, value.getDefiningOp<DataConOp>(), 0}};
  while (!inside.empty()) {
    Apart &top = inside.back();
    if (top.next == top.record.fields().size()) {
      inside.pop_back();
      continue;
    }
    unsigned at = top.next++;
    Type field = top.record.fields()[at];
    Value given =
        top.con ? top.con.getFields()[at] : DataFieldOp::create(b, loc, top.value, at).getResult();
    if (std::optional<Record> inner = recordOf(field))
      inside.push_back({*inner, given, given.getDefiningOp<DataConOp>(), 0});
    else
      leaves.push_back(given);
  }
  return leaves;
}

Value Records::build(OpBuilder &b, Location loc, Record record, ValueRange &leaves) const {
  // A value being built: its record and the fields it has so far; an inner
  // record is built before the one that holds it.
  struct Building {
    Record record;
    SmallVector<Value> fields;
  };
  // Each round gives a record a field, opens the record of one, or builds
  // a record whose fields are all there, and a record's type holds
  // finitely many, so the rounds end with the outermost record built.
  SmallVector<Building> inside;
  inside.push_back({record, {}});
  Value whole;
  while (!whole) {
    Building &top = inside.back();
    ArrayRef<Type> fields = top.record.fields();
    if (top.fields.size() == fields.size()) {
      Value made = DataConOp::create(b, loc, top.record.data, top.fields).getResult();
      inside.pop_back();
      if (inside.empty())
        whole = made;
      else
        inside.back().fields.push_back(made);
      continue;
    }
    if (std::optional<Record> inner = recordOf(fields[top.fields.size()])) {
      inside.push_back({*inner, {}});
      continue;
    }
    top.fields.push_back(leaves.front());
    leaves = leaves.drop_front();
  }
  return whole;
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
