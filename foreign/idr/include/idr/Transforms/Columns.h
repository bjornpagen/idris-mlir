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
// whose field is used once (its column would be used as the array is) or
// holds an array, which a field holds as its buffer; and one an array of
// which a data type of the program holds, as a constructor's field holds
// it whole (Records). Where an array of records meets another op the conversion
// does not take, it is gathered from its columns there, and taken apart
// into them again where it comes out: the program is the same, held in two
// ways at that boundary.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_COLUMNS_H
#define IDR_TRANSFORMS_COLUMNS_H

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Remake.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr {
#define GEN_PASS_DECL_IDRCOLUMNS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::columns {

// A data type whose arrays are held as one array per leaf: a record, whose
// one constructor, the first of its declaration, every value is built
// with, so its type fixes the constructor.
struct Record {
  static constexpr Tag tag{0};
  DataType data;
  llvm::ArrayRef<mlir::Type> fields() const { return data.ctor(tag).fields; }
};

// The records of a program whose arrays are held as their columns, and
// how a record is read from its columns, written into them, built and
// taken apart. A record splits when the conversion can hold its arrays so
// and no data type of the program holds an array of it: a constructor's
// field holds the array whole, so its columns would be gathered into a
// fresh array at every constructor and taken apart at every match, a copy
// of the array each time, and a linear array's columns would be used both
// by the gather and where the conversion reads them. The program decides
// it once, and every reading of a record below asks it.
class Records {
public:
  explicit Records(ProgramOp program);

  // The record a value of `type` is, when an array of it is held as one
  // array per leaf; nothing for any other type.
  std::optional<Record> recordOf(mlir::Type type) const;

  // The leaves of a record of `type`, in field order, each record among
  // its fields its own leaves in turn.
  void leavesOf(mlir::Type type, llvm::SmallVectorImpl<mlir::Type> &leaves) const;

  // The arrays an array of `array`'s type is held as: one per leaf of its
  // record, or itself when its element is no record.
  void columnsOf(mlir::RankedTensorType array, llvm::SmallVectorImpl<mlir::Type> &columns) const;

  // The leaves of `value`, a value of `record`: the fields its idr.con was
  // given, or its fields read.
  llvm::SmallVector<mlir::Value> takeApart(mlir::OpBuilder &b, mlir::Location loc,
                                           mlir::Value value, Record record) const;

  // The value of `record` built of the leaves at the front of `leaves`,
  // which it takes.
  mlir::Value build(mlir::OpBuilder &b, mlir::Location loc, Record record,
                    mlir::ValueRange &leaves) const;

  // The value at `indices` of an array of `element` held as `columns`; the
  // columns with `value`, of `element`, written at `indices`.
  mlir::Value readRecord(mlir::OpBuilder &b, mlir::Location loc, Record element,
                         mlir::ValueRange columns, mlir::ValueRange indices) const;
  llvm::SmallVector<mlir::Value> writeRecord(mlir::OpBuilder &b, mlir::Location loc,
                                             mlir::Value value, Record element,
                                             mlir::ValueRange columns,
                                             mlir::ValueRange indices) const;

  // The array of `type`, whose element is `element`, gathered from its
  // columns, and the columns of `array`, of `types`, taken apart from it:
  // each an idr.tabulate, where an array of records meets what holds it
  // whole.
  mlir::Value gather(mlir::OpBuilder &b, mlir::Location loc, mlir::RankedTensorType type,
                     Record element, mlir::ValueRange columns) const;
  llvm::SmallVector<mlir::Value> scatter(mlir::OpBuilder &b, mlir::Location loc,
                                         mlir::Value array, Record element,
                                         mlir::TypeRange types) const;

private:
  bool splits(DataType data) const;
  // The records an array of which some data type of the program holds.
  llvm::DenseSet<mlir::Type> held;
};

// The conversion: arrays of records, at any grade, to their columns, with
// the gather and the scatter at its boundary, as the program's records
// split.
class ColumnConverter : public mlir::TypeConverter {
public:
  explicit ColumnConverter(const Records &records);
  const Records &records() const { return split; }

private:
  const Records &split;
};

// The records of the conversion a pattern is given.
inline const Records &recordsOf(const mlir::TypeConverter &converter) {
  return static_cast<const ColumnConverter &>(converter).records();
}

// The patterns of each op that carries an array of records, each added with
// the legality that asks for it: those of what carries an array between
// functions and regions (lib/Transforms/Columns/Calls.cpp), of the tensor
// ops (Tensors.cpp) and of the array ops (ArrayOps.cpp). Every op none of
// them takes holds an array of records whole, legal as it is.
void populateColumnPatterns(const mlir::TypeConverter &converter, mlir::RewritePatternSet &patterns,
                            mlir::ConversionTarget &target);
void populateCallColumnPatterns(const mlir::TypeConverter &converter,
                                mlir::RewritePatternSet &patterns, mlir::ConversionTarget &target);
void populateTensorColumnPatterns(const mlir::TypeConverter &converter,
                                  mlir::RewritePatternSet &patterns,
                                  mlir::ConversionTarget &target);
void populateArrayColumnPatterns(const mlir::TypeConverter &converter,
                                 mlir::RewritePatternSet &patterns, mlir::ConversionTarget &target);

// The legality of an op the conversion takes, unless its pattern states
// another: legal once every type it carries is converted already.
inline mlir::ConversionTarget::DynamicLegalityCallbackFn
whole(const mlir::TypeConverter &converter) {
  return [&converter](mlir::Operation *op) -> std::optional<bool> { return converter.isLegal(op); };
}

// `Pattern`, and the legality `legal` of each op of `Ops` it converts: that
// the conversion takes an op is one registration, its pattern and its
// legality together, as upstream's populate...AndLegality helpers make it.
template <typename Pattern, typename... Ops>
void addColumns(const mlir::TypeConverter &converter, mlir::RewritePatternSet &patterns,
                mlir::ConversionTarget &target,
                const mlir::ConversionTarget::DynamicLegalityCallbackFn &legal) {
  patterns.add<Pattern>(converter, patterns.getContext());
  target.addDynamicallyLegalOp<Ops...>(legal);
}

// What the patterns share. The values of `ranges`, one after another; the
// types `types` become, and how many each becomes; `values` cut into
// consecutive runs of `counts`.
llvm::SmallVector<mlir::Value> flatten(llvm::ArrayRef<mlir::ValueRange> ranges);
mlir::LogicalResult convertEach(const mlir::TypeConverter &converter, mlir::TypeRange types,
                                llvm::SmallVectorImpl<mlir::Type> &converted,
                                llvm::SmallVectorImpl<unsigned> &counts);
llvm::SmallVector<llvm::SmallVector<mlir::Value>> runs(mlir::ValueRange values,
                                                       llvm::ArrayRef<unsigned> counts);

// An op that gives each array of records it makes as the columns its
// regions give: made again on its operands' columns, its regions moved in,
// each result the run of columns it became. A match, whose regions yield
// the columns (a yield moves on its operands' columns), and a tabulation,
// whose region yields the leaves of each record (an idr.array.yield takes
// each record apart).
template <typename OpT>
struct ResultColumns : mlir::OpConversionPattern<OpT> {
  using mlir::OpConversionPattern<OpT>::OpConversionPattern;
  mlir::LogicalResult
  matchAndRewrite(OpT op, typename mlir::OpConversionPattern<OpT>::OneToNOpAdaptor adaptor,
                  mlir::ConversionPatternRewriter &rewriter) const override {
    llvm::SmallVector<mlir::Type> results;
    llvm::SmallVector<unsigned> counts;
    if (mlir::failed(
            convertEach(*this->getTypeConverter(), op->getResultTypes(), results, counts)))
      return mlir::failure();
    mlir::Operation *made = remakeOp(rewriter, op, flatten(adaptor.getOperands()), results);
    rewriter.replaceOpWithMultiple(op, runs(made->getResults(), counts));
    return mlir::success();
  }
};

} // namespace idr::columns

#endif // IDR_TRANSFORMS_COLUMNS_H
