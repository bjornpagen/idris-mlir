// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Columns.h - An array of records as one array per field -------------===//
//
// idr-columns holds an array whose element is a record as one array per
// leaf of the record, by upstream's one-to-N type conversion: a record is
// a data type of one plain constructor, and its leaves are its fields, a
// field that is a record itself being its own leaves. Each array of the
// record's shape holds one leaf at each index; a leaf that is an array of
// a static shape adds its dimensions after the array's. Every signature,
// call, block argument, array op and tie that carries such an array
// carries its columns instead, a read of an element reads each column and
// builds the record, and a write takes the record apart.
//
// A record the conversion cannot hold so is kept whole, never refused: one
// whose field is graded (a linear field is used once, and its column would
// be used as the array is), an array a world orders, an array of a shape
// its type leaves dynamic (records of one array type may hold arrays of
// different lengths), or an array of records. Where an array of records
// meets an op the conversion does not take (a constructor's field holds
// one, say), it is gathered from its columns there, and taken apart into
// them again where it comes out: the program is the same, held in two
// ways at that boundary.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_COLUMNS_H
#define IDR_TRANSFORMS_COLUMNS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DECL_IDRCOLUMNS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::columns {

// A data type whose arrays are held as one array per leaf: a record, whose
// one constructor, the first of its body, every value is built with.
struct Record {
  static constexpr Tag tag{0};
  DataType data;
  llvm::ArrayRef<mlir::Type> fields() const { return data.getCtor(tag).fields; }
};

// The record a value of `type` is, when an array of it is held as one
// array per leaf; nothing for any other type.
std::optional<Record> recordOf(mlir::Type type);

// The leaves of a record of `type`, in field order, each record among its
// fields its own leaves in turn.
void leavesOf(mlir::Type type, llvm::SmallVectorImpl<mlir::Type> &leaves);

// The arrays an array of `array`'s type is held as: one per leaf of its
// record, or itself when its element is no record.
void columnsOf(mlir::RankedTensorType array, llvm::SmallVectorImpl<mlir::Type> &columns);

// The leaves of `value`, a value of `record`: the fields its idr.con was
// given, or its fields read.
llvm::SmallVector<mlir::Value> takeApart(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value,
                                         Record record);

// The value of `record` built of the leaves at the front of `leaves`, which
// it takes.
mlir::Value build(mlir::OpBuilder &b, mlir::Location loc, Record record, mlir::ValueRange &leaves);

// The value at `indices` of an array of `element` held as `columns`; the
// columns with `value`, of `element`, written at `indices`.
mlir::Value readRecord(mlir::OpBuilder &b, mlir::Location loc, Record element,
                       mlir::ValueRange columns, mlir::ValueRange indices);
llvm::SmallVector<mlir::Value> writeRecord(mlir::OpBuilder &b, mlir::Location loc,
                                           mlir::Value value, Record element,
                                           mlir::ValueRange columns, mlir::ValueRange indices);

// The array of `type`, whose element is `element`, gathered from its
// columns, and the columns of `array`, of `types`, taken apart from it:
// each an idr.tabulate, where an array of records meets what holds it whole.
mlir::Value gather(mlir::OpBuilder &b, mlir::Location loc, mlir::RankedTensorType type,
                   Record element, mlir::ValueRange columns);
llvm::SmallVector<mlir::Value> scatter(mlir::OpBuilder &b, mlir::Location loc, mlir::Value array,
                                       Record element, mlir::TypeRange types);

// The conversion: arrays of records, at any grade, to their columns, with
// the gather and the scatter at its boundary.
class ColumnConverter : public mlir::TypeConverter {
public:
  ColumnConverter();
};

// The patterns of each op that carries an array of records, and the
// legality that asks for them: those of what carries an array between
// functions and regions (lib/Transforms/Columns/Calls.cpp), of the tensor
// ops (Tensors.cpp) and of the array ops (ArrayOps.cpp).
void populateColumnPatterns(const mlir::TypeConverter &converter, mlir::RewritePatternSet &patterns,
                            mlir::ConversionTarget &target);
void populateCallColumnPatterns(const mlir::TypeConverter &converter,
                                mlir::RewritePatternSet &patterns);
void populateTensorColumnPatterns(const mlir::TypeConverter &converter,
                                  mlir::RewritePatternSet &patterns);
void populateArrayColumnPatterns(const mlir::TypeConverter &converter,
                                 mlir::RewritePatternSet &patterns);

// What the patterns share. The values of `ranges`, one after another; the
// types `types` become, and how many each becomes; `values` cut into
// consecutive runs of `counts`; and `op` made again with `operands` and
// `results`, its properties and discardable attributes kept, its regions
// moved into it.
llvm::SmallVector<mlir::Value> flatten(llvm::ArrayRef<mlir::ValueRange> ranges);
mlir::LogicalResult convertEach(const mlir::TypeConverter &converter, mlir::TypeRange types,
                                llvm::SmallVectorImpl<mlir::Type> &converted,
                                llvm::SmallVectorImpl<unsigned> &counts);
llvm::SmallVector<llvm::SmallVector<mlir::Value>> runs(mlir::ValueRange values,
                                                       llvm::ArrayRef<unsigned> counts);
mlir::Operation *remake(mlir::ConversionPatternRewriter &rewriter, mlir::Operation *op,
                        mlir::ValueRange operands, mlir::TypeRange results);

} // namespace idr::columns

#endif // IDR_TRANSFORMS_COLUMNS_H
