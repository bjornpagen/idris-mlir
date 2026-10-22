// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A region op of ours that runs one region once (a lifetime's opener, a
// loan, a match on uniqueness) lowers to upstream's scf op of that shape,
// its region moved in, so the one conversion of scf to blocks makes every
// block the function has.

#include "idr/Conversion/Lower/Lower.h"

#include "mlir/Dialect/SCF/IR/SCF.h"

using namespace mlir;

namespace idr::conversion {

FailureOr<SmallVector<SmallVector<Type>>> convertedResults(Operation *op,
                                                           const TypeConverter &converter) {
  SmallVector<SmallVector<Type>> converted(op->getNumResults());
  for (auto [type, components] : llvm::zip_equal(op->getResultTypes(), converted))
    if (failed(converter.convertType(type, components)))
      return failure();
  return converted;
}

void moveRegion(ConversionPatternRewriter &rewriter, const TypeConverter &converter, Region &from,
                ArrayRef<SmallVector<Value>> args, Region &into) {
  Block &block = from.front();
  // An argument of no component is dropped, as the converter drops one it
  // converts to nothing: an empty replacement would read as a position
  // remapped.
  TypeConverter::SignatureConversion signature(block.getNumArguments());
  for (auto [index, values] : llvm::enumerate(args))
    if (!values.empty())
      signature.remapInput(static_cast<unsigned>(index), values);
  Block *converted = rewriter.applySignatureConversion(&block, signature, &converter);
  // A region that never ends keeps its terminator, which upstream's scf
  // ops hold; one that ends gives its values to the op's results.
  if (auto yield = dyn_cast<YieldOp>(converted->getTerminator())) {
    OpBuilder::InsertionGuard guard(rewriter);
    rewriter.setInsertionPoint(yield);
    rewriter.replaceOpWithNewOp<scf::YieldOp>(yield, yield->getOperands());
  }
  rewriter.inlineRegionBefore(from, into, into.end());
}

SmallVector<SmallVector<Value>> groupResults(ValueRange flat,
                                             ArrayRef<SmallVector<Type>> converted) {
  SmallVector<SmallVector<Value>> grouped;
  for (ArrayRef<Type> components : converted) {
    grouped.push_back(SmallVector<Value>(flat.take_front(components.size())));
    flat = flat.drop_front(components.size());
  }
  return grouped;
}

} // namespace idr::conversion
