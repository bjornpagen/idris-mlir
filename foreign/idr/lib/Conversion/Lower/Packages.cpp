// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A lifetime split around a framed call. A lifetime of one recursion
// level, on a stack or in a chain, may end its region by packing it before
// a frame is pushed: the mark of a stack and the values living in it go
// into a record bumped in its own memory, whose address is the package the
// frame holds, and its opener then frees nothing. The resume's unpack
// reads the record back and reopens the lifetime, a chain past the record
// and a stack on the base it names, its end the one its source's opener
// would have run.

#include "idr/Conversion/Lower/Lifetimes.h"

#include "idr/IR/Lifetimes.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Words.h"

#include "llvm/Support/MathExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A package's record, laid out once for its pack and its unpack: a stack's
// mark, then the components of the values it holds, each at its alignment,
// the whole a multiple of a cell's alignment, so the cursor past it is where
// a cell may start.
struct Record {
  SmallVector<layout::Slot> slots;
  unsigned bytes = 0;
};

Record recordOf(const Layouts &layouts, LifetimePackageType package) {
  Record record;
  auto place = [&](const layout::Component &component) {
    unsigned offset = static_cast<unsigned>(
        llvm::alignTo(record.bytes, layouts.alignmentOf(component.type)));
    record.slots.push_back(layout::Slot{component, offset});
    record.bytes = offset + layouts.sizeOf(component.type);
  };
  switch (package.getPacked()) {
  case Packed::FromStack:
    place(layout::Component{ptrType(package.getContext()), layout::Word::Uncounted});
    break;
  case Packed::FromChain:
    break;
  }
  for (Type held : package.getHeld())
    for (const layout::Component &component : layouts.components(held))
      place(component);
  record.bytes = static_cast<unsigned>(llvm::alignTo(record.bytes, cellAlignment()));
  return record;
}

// The end of a lifetime's region before a frame's push: the record bumped
// in the lifetime's own memory, the cursor past it, and the package its
// address; nothing is freed, which the opener's end then keeps so. A record
// of no bytes, a chain's that holds nothing, is where the cursor is, with
// no bump.
struct LowerLifetimePack : IdrPattern<LifetimePackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimePackOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type ptr = ptrType(getContext());
    auto package = cast<LifetimePackageType>(op.getPackage().getType());
    Record record = recordOf(layouts, package);
    Value slot = adaptor.getLifetime().front();
    SmallVector<Value> values;
    switch (package.getPacked()) {
    case Packed::FromStack:
      values.push_back(LLVM::LoadOp::create(rewriter, loc, ptr, markOf(rewriter, loc, slot)));
      break;
    case Packed::FromChain:
      break;
    }
    for (ValueRange held : adaptor.getHeld())
      llvm::append_range(values, held);
    Value place = record.bytes == 0 ? Value(LLVM::LoadOp::create(rewriter, loc, ptr, slot))
                                    : bump(rewriter, loc, runtime, slot, record.bytes);
    runtime.store(rewriter, loc, place, cellAlignment(), record.slots, values);
    rewriter.replaceOp(op, place);
    return success();
  }
};

// The resume's reopening of a packed lifetime: its record read, its cursor
// in a slot of the frame, its region run in place with the values it holds
// restated, and its end its source's, unless it packs again. A chain is
// the lifetime's alone, so it reopens past the record. A stack reopens on
// the base it names, a lifetime the resume takes, at the cursor the calls
// since the push gave back through it, since what the framed call put into
// the base lies past the record; its mark is the record's, which its end
// gives back to the base.
struct LowerLifetimeUnpack : IdrPattern<LifetimeUnpackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeUnpackOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto package = cast<LifetimePackageType>(op.getPackage().getType());
    Record record = recordOf(layouts, package);
    Value place = adaptor.getPackage().front();
    SmallVector<Value> read = runtime.load(rewriter, loc, place, cellAlignment(), record.slots);
    RegionEnd end = regionEndOf(op.getBody());
    // The values the record holds after what it keeps of the lifetime,
    // each its components.
    auto heldIn = [&](ArrayRef<Value> rest) {
      SmallVector<SmallVector<Value>> held;
      for (Type type : package.getHeld()) {
        size_t count = layouts.components(type).size();
        held.push_back(SmallVector<Value>(rest.take_front(count)));
        rest = rest.drop_front(count);
      }
      return held;
    };
    switch (package.getPacked()) {
    case Packed::FromStack: {
      Value mark = read.front();
      Value base = adaptor.getBase().front();
      Value top = LLVM::LoadOp::create(rewriter, loc, ptrType(getContext()), base);
      Value slot = stackSlot(rewriter, loc, op, top, mark);
      return runRegion(op, rewriter, *getTypeConverter(), {slot},
                       heldIn(ArrayRef(read).drop_front()), {},
                       [&] { endStack(rewriter, loc, runtime, end, base, slot, mark); });
    }
    case Packed::FromChain:
      break;
    }
    Value cursor = record.bytes == 0 ? place : at(rewriter, loc, place, record.bytes);
    Value slot = frameSlot(rewriter, loc, op, SlotWords::Cursor);
    LLVM::StoreOp::create(rewriter, loc, cursor, slot);
    return runRegion(op, rewriter, *getTypeConverter(), {slot}, heldIn(read), {},
                     [&] { endChain(rewriter, loc, runtime, end, slot); });
  }
};

} // namespace

void populatePackagePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                             const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerLifetimePack, LowerLifetimeUnpack>(converter, patterns.getContext(), layouts,
                                                      runtime);
}

} // namespace idr::conversion
