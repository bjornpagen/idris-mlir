// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the lowering of a lifetime's openers and of its packages share: a
// lifetime's slot in the frame, the bump of a cursor, how the region of a
// lifetime of one recursion level ends, and an opener's region run in
// place.
#ifndef IDR_CONVERSION_LOWER_LIFETIMES_H
#define IDR_CONVERSION_LOWER_LIFETIMES_H

#include "idr/Conversion/Lower/Lower.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <utility>

namespace idr::conversion {

// What a lifetime's slot in the frame holds, a word each: its cursor, and
// for a lifetime on a stack the mark its end resets the stack to.
enum class SlotWords : std::uint8_t { Cursor = 1, CursorAndMark = 2 };

// A slot of the frame, at the start of the entry block of the function
// `inside` is in, so it is one per frame however often what needs it runs.
mlir::Value frameSlot(mlir::OpBuilder &b, mlir::Location loc, mlir::Operation *inside,
                      SlotWords words);

// The address of the mark of a lifetime on a stack, the word after its
// cursor's in its slot.
mlir::Value markOf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value slot);

// The slot of a lifetime on a stack, in the frame of the function `op` is
// in: its cursor `cursor`, where its first put goes, and the mark `mark`
// its end gives back to its base.
mlir::Value stackSlot(mlir::OpBuilder &b, mlir::Location loc, mlir::Operation *op,
                      mlir::Value cursor, mlir::Value mark);

// A room of `bytes` bytes in the cursor whose slot is `slot`: the place the
// runtime gives (the cursor itself where its chunk has room), and the
// cursor moved past it.
mlir::Value bump(mlir::OpBuilder &b, mlir::Location loc, const Runtime &runtime, mlir::Value slot,
                 uint64_t bytes);

// How the region of a lifetime of one recursion level ends: at its end, or
// by packing the lifetime, the last op before its terminator, which the
// pack's verifier holds there. The two are the problem's: a lifetime that
// ends here, and one whose memory moves into a frame.
enum class RegionEnd : std::uint8_t { Closes, Packs };
RegionEnd regionEndOf(mlir::Region &body);

// The end of a chain whose cursor is in `slot`: closed, its chunks given
// back; packed, nothing, since the chain is the package's.
void endChain(mlir::OpBuilder &b, mlir::Location loc, const Runtime &runtime, RegionEnd end,
              mlir::Value slot);

// The end of a lifetime on the stack of the cursor in `base`, its own in
// `slot`: closed, the chunks past its mark given back and the base's cursor
// the mark again; packed, its cells kept and the base's cursor past them,
// where what the frame's call puts goes.
void endStack(mlir::OpBuilder &b, mlir::Location loc, const Runtime &runtime, RegionEnd end,
              mlir::Value base, mlir::Value slot, mlir::Value mark);

// An opener's region, run once in place as an scf.execute_region, its
// lifetime `lifetime` (none for a view or a home, whose value is no value),
// its results the region's: what every opener, the loan and the unpack
// share. `close` runs after the region, with the results at hand.
template <typename OpT, typename Close>
mlir::LogicalResult runRegion(OpT op, mlir::ConversionPatternRewriter &rewriter,
                              const mlir::TypeConverter &converter,
                              llvm::SmallVector<mlir::Value> lifetime,
                              llvm::ArrayRef<llvm::SmallVector<mlir::Value>> others,
                              llvm::SmallVector<llvm::SmallVector<mlir::Value>> leading,
                              Close &&close) {
  mlir::FailureOr<llvm::SmallVector<llvm::SmallVector<mlir::Type>>> converted =
      convertedResults(op, converter);
  if (mlir::failed(converted))
    return rewriter.notifyMatchFailure(op, "a result's type does not convert");
  llvm::ArrayRef<llvm::SmallVector<mlir::Type>> yielded =
      llvm::ArrayRef(*converted).drop_front(leading.size());
  llvm::SmallVector<mlir::Type> flat;
  for (llvm::ArrayRef<mlir::Type> components : yielded)
    llvm::append_range(flat, components);
  auto run = mlir::scf::ExecuteRegionOp::create(rewriter, op.getLoc(), flat);
  llvm::SmallVector<llvm::SmallVector<mlir::Value>> args{std::move(lifetime)};
  llvm::append_range(args, others);
  moveRegion(rewriter, converter, op.getBody(), args, run.getRegion());
  close();
  llvm::SmallVector<llvm::SmallVector<mlir::Value>> results = std::move(leading);
  llvm::append_range(results, groupResults(run.getResults(), yielded));
  rewriter.replaceOpWithMultiple(op, std::move(results));
  return mlir::success();
}

} // namespace idr::conversion

#endif // IDR_CONVERSION_LOWER_LIFETIMES_H
