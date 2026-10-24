// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A lifetime at run time. What its value is, is its type's kind, which the
// one fold over the dialect's types gives every type's components by: a
// view and a home are no value; a room is the pointer to its block of
// static size; a cursor is a pointer that goes into each call that puts
// into it and comes back out. Where its memory comes from is the op that
// opens it, one lowering each: a view's nothing, a block in the opener's
// frame, the chain a cursor bumps, the stack of its base cursor, a home of
// the thread. What puts into a lifetime, opens one on it or packs it reads
// its value; the lifetime an op states of a value it makes is read by none.
//
// Inside a function a cursor lives in a slot of the frame, since every put
// moves it: its value is the slot's address, which a put reads and writes,
// a call loads into its argument and stores its result back into, and a
// return reads. A lifetime on a stack keeps its mark in the word after its
// cursor's, where its pack reads it.
//
// The runtime owns a chain's memory: arenaChunk gives the room of a cell,
// in the cursor's chunk or a new one; arenaOpen begins a chain; arenaClose
// gives a chain's chunks back; stackReset gives back a stack's chunks past
// a mark. Each call is its runtime function's, which the program's link
// inlines where it pays.

#include "idr/Conversion/Lower/Lifetimes.h"

#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/SCF/IR/SCF.h"

using namespace mlir;

namespace idr::conversion {

Value frameSlot(OpBuilder &b, Location loc, Operation *inside, SlotWords words) {
  OpBuilder::InsertionGuard guard(b);
  Operation *scope = inside->getParentWithTrait<mlir::OpTrait::AutomaticAllocationScope>();
  b.setInsertionPointToStart(&scope->getRegion(0).front());
  Type ptr = ptrType(b.getContext());
  Value count = LLVM::ConstantOp::create(b, loc, b.getI64Type(), static_cast<int64_t>(words));
  return LLVM::AllocaOp::create(b, loc, ptr, ptr, count, cellAlignment());
}

Value markOf(OpBuilder &b, Location loc, Value slot) {
  Type ptr = ptrType(b.getContext());
  return LLVM::GEPOp::create(b, loc, ptr, ptr, slot, ArrayRef<LLVM::GEPArg>{1});
}

Value bump(OpBuilder &b, Location loc, const Runtime &runtime, Value slot, uint64_t bytes) {
  Type ptr = ptrType(b.getContext());
  Value cursor = LLVM::LoadOp::create(b, loc, ptr, slot);
  Value room = runtime
                   .call(b, loc, idr::runtime::helper::arenaChunk,
                         ValueRange{cursor, i64Constant(b, loc, static_cast<int64_t>(bytes))})
                   .getResult();
  LLVM::StoreOp::create(b, loc, at(b, loc, room, static_cast<unsigned>(bytes)), slot);
  return room;
}

Value stackSlot(OpBuilder &b, Location loc, Operation *op, Value cursor, Value mark) {
  Value slot = frameSlot(b, loc, op, SlotWords::CursorAndMark);
  LLVM::StoreOp::create(b, loc, cursor, slot);
  LLVM::StoreOp::create(b, loc, mark, markOf(b, loc, slot));
  return slot;
}

RegionEnd regionEndOf(Region &body) {
  Operation *last = body.front().getTerminator()->getPrevNode();
  return isa_and_nonnull<LifetimePackOp>(last) ? RegionEnd::Packs : RegionEnd::Closes;
}

void endChain(OpBuilder &b, Location loc, const Runtime &runtime, RegionEnd end, Value slot) {
  switch (end) {
  case RegionEnd::Closes:
    runtime.call(b, loc, idr::runtime::helper::arenaClose,
                 LLVM::LoadOp::create(b, loc, ptrType(b.getContext()), slot).getResult());
    return;
  case RegionEnd::Packs:
    return;
  }
}

void endStack(OpBuilder &b, Location loc, const Runtime &runtime, RegionEnd end, Value base,
              Value slot, Value mark) {
  switch (end) {
  case RegionEnd::Closes:
    runtime.call(b, loc, idr::runtime::helper::stackReset, mark);
    LLVM::StoreOp::create(b, loc, mark, base);
    return;
  case RegionEnd::Packs: {
    Value past = LLVM::LoadOp::create(b, loc, ptrType(b.getContext()), slot);
    LLVM::StoreOp::create(b, loc, past, base);
    return;
  }
  }
}

namespace {

// The slot of the home of site `site`: its entry in the thread's array of
// home cursors, a static datum.
Value homeSlot(OpBuilder &b, Location loc, const Runtime &runtime, uint32_t site) {
  Value homes = staticAddress(b, loc, runtime.statics().homes());
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), ptrType(b.getContext()), homes,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(site)});
}

// The cursor's slot that a put into `lifetime`, converted to `converted`,
// bumps: a cursor's own, or a home's, which has no value of its own.
Value cursorSlot(OpBuilder &b, Location loc, const Runtime &runtime,
                 TypedValue<LifetimeType> lifetime, ValueRange converted) {
  return lifetimes::kindOf(lifetime).fold(
      [&]() -> Value { return {}; }, [&]() -> Value { return {}; },
      [&]() -> Value { return converted.front(); },
      [&](uint32_t site) -> Value { return homeSlot(b, loc, runtime, site); });
}

//===----------------------------------------------------------------------===//
// Puts
//===----------------------------------------------------------------------===//

// A cell put into a lifetime, its header count 0, the runtime's mark of a
// cell no count frees, written at each run: in a room, at the offset laid
// out before (the room's pointer is the cell); in a cursor or a home, at
// the place the bump gives. The address may be one a cell of an earlier run
// had, so loads through it see only what this run writes.
struct LowerCellArena : IdrPattern<CellArenaOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CellArenaOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const layout::Cell &cell = cellLayoutOf(layouts, cast<CellType>(op.getCell().getType()));
    TypedValue<LifetimeType> lifetime = op.getLifetime();
    Value place = lifetimes::kindOf(lifetime).isRoom()
                      ? adaptor.getLifetime().front()
                      : bump(rewriter, loc, runtime,
                             cursorSlot(rewriter, loc, runtime, lifetime, adaptor.getLifetime()),
                             cell.size);
    Value address = runtime.launder(rewriter, loc, place);
    runtime.storeUncountedHeader(rewriter, loc, address, cell);
    rewriter.replaceOp(op, address);
    return success();
  }
};

// A cell in the frame: a slot in the entry block of the function that
// holds it, one per op, allocated once per frame however often the op runs,
// so LLVM may keep it in registers when it stays in the function. Its
// header is written where the op runs, count 0: its lifetime frees it, never
// a count. The slot is written again at each run, so loads through it see
// only what this run writes.
struct LowerCellStack : IdrPattern<CellStackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CellStackOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const layout::Cell &cell = cellLayoutOf(layouts, cast<CellType>(op.getCell().getType()));
    Value slot;
    {
      OpBuilder::InsertionGuard guard(rewriter);
      Operation *scope = op->getParentWithTrait<mlir::OpTrait::AutomaticAllocationScope>();
      rewriter.setInsertionPointToStart(&scope->getRegion(0).front());
      slot = LLVM::AllocaOp::create(rewriter, loc, ptrType(getContext()),
                                    LLVM::LLVMArrayType::get(rewriter.getI8Type(), cell.size),
                                    i64Constant(rewriter, loc, 1), cellAlignment());
    }
    Value address = runtime.launder(rewriter, loc, slot);
    runtime.storeUncountedHeader(rewriter, loc, address, cell);
    rewriter.replaceOp(op, address);
    return success();
  }
};

// A room reserved in a cursor for a callee compiled for a room: one bump of
// its bytes.
struct LowerReserve : IdrPattern<LifetimeReserveOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeReserveOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value slot = cursorSlot(rewriter, loc, runtime, op.getLifetime(), adaptor.getLifetime());
    rewriter.replaceOp(op,
                       bump(rewriter, loc, runtime, slot, static_cast<uint64_t>(op.getBytes())));
    return success();
  }
};

// The ops whose result is a view: no value at run time.
template <typename OpT>
struct LowerToView : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Openers
//===----------------------------------------------------------------------===//

// A lifetime nothing allocates into: its region, and nothing besides.
struct LowerViewOpener : IdrPattern<LifetimeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    return runRegion(op, rewriter, *getTypeConverter(), {}, {}, {}, [] {});
  }
};

// A block in the opener's frame: laid out and allocated before the function
// was converted, its lifetime's uses reading the block; the region runs in
// place and nothing is given back.
struct LowerBlockOpener : IdrPattern<LifetimeBlockOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeBlockOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    return runRegion(op, rewriter, *getTypeConverter(), {}, {}, {}, [] {});
  }
};

// A chain of its own: its cursor in a slot of the frame, the chain begun
// empty, each put bumping it.
struct LowerChainOpener : IdrPattern<LifetimeChainOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeChainOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    RegionEnd end = regionEndOf(op.getBody());
    Value slot = frameSlot(rewriter, loc, op, SlotWords::Cursor);
    Value begun = runtime.call(rewriter, loc, idr::runtime::helper::arenaOpen,
                               i64Constant(rewriter, loc, 0))
                      .getResult();
    LLVM::StoreOp::create(rewriter, loc, begun, slot);
    return runRegion(op, rewriter, *getTypeConverter(), {slot}, {}, {}, [&] {
      endChain(rewriter, loc, runtime, end, slot);
    });
  }
};

// A lifetime on its base cursor's stack, its cursor and its mark in a slot
// of its own, both the base's cursor at the open. The base's chain takes
// its first chunk there if it has none, since a stack is reset to a mark
// in a chunk, and a chain takes its first chunk at its first put, which
// only the run knows; the base then holds it.
struct LowerStackOpener : IdrPattern<LifetimeStackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeStackOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type ptr = ptrType(getContext());
    RegionEnd end = regionEndOf(op.getBody());
    Value base = adaptor.getBase().front();
    Value top = LLVM::LoadOp::create(rewriter, loc, ptr, base);
    Value mark = runtime
                     .call(rewriter, loc, idr::runtime::helper::arenaChunk,
                           ValueRange{top, i64Constant(rewriter, loc, 0)})
                     .getResult();
    LLVM::StoreOp::create(rewriter, loc, mark, base);
    Value slot = stackSlot(rewriter, loc, op, mark, mark);
    return runRegion(op, rewriter, *getTypeConverter(), {slot}, {}, {}, [&] {
      endStack(rewriter, loc, runtime, end, base, slot, mark);
    });
  }
};

// The per-thread home of its site: nothing at the open (its first put takes
// its first chunk); at the end its chunks given back and its cursor empty.
struct LowerHomeOpener : IdrPattern<LifetimeHomeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeHomeOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    uint32_t site = lifetimes::kindOf(op.getOpened())
                        .fold([] { return 0u; }, [] { return 0u; }, [] { return 0u; },
                              [](uint32_t k) { return k; });
    return runRegion(op, rewriter, *getTypeConverter(), {}, {}, {}, [&] {
      Value slot = homeSlot(rewriter, loc, runtime, site);
      Type ptr = ptrType(getContext());
      Value cursor = LLVM::LoadOp::create(rewriter, loc, ptr, slot);
      runtime.call(rewriter, loc, idr::runtime::helper::arenaClose, cursor);
      LLVM::StoreOp::create(rewriter, loc, LLVM::ZeroOp::create(rewriter, loc, ptr), slot);
    });
  }
};

// A loan: its region in place, its lifetime a view, the view of the owner
// the owner's own words; the owner comes back as the first result, the
// same words.
struct LowerLend : IdrPattern<LendOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LendOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> owner(adaptor.getOwner());
    return runRegion(op, rewriter, *getTypeConverter(), {}, {owner}, {owner}, [] {});
  }
};

} // namespace

void populateLifetimePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCellArena, LowerCellStack, LowerReserve, LowerToView<ActivationOp>,
               LowerToView<LifetimeForgetOp>, LowerViewOpener, LowerBlockOpener, LowerChainOpener,
               LowerStackOpener, LowerHomeOpener, LowerLend>(converter, patterns.getContext(),
                                                             layouts, runtime);
}

} // namespace idr::conversion
