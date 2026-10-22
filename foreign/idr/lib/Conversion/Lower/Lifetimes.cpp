// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A lifetime at run time. What its value is, is its type's kind, one
// context-free rule each: a view and a home are no value; a room is the
// pointer to its block of static size; a cursor is a pointer that goes into
// each call that puts into it and comes back out. Where its memory comes
// from is the op that opens it, one lowering each: a view's nothing, a
// block in the opener's frame, the chain a cursor bumps, the stack of its
// base cursor, a home of the thread.
//
// Inside a function a cursor lives in a slot of the frame, since every put
// moves it: its value is the slot's address, which a put reads and writes,
// a call loads into its argument and stores its result back into, and a
// return reads. A lifetime on a stack keeps its mark in the word after its
// cursor's, where its pack reads it. A room's puts are laid out once,
// before the function is converted, each at a static offset in its block.
//
// A lifetime of one recursion level, on a stack or in a chain, may end its
// region by packing it before a frame is pushed: the mark of a stack and
// the values living in it go into a record bumped in its own memory, whose
// address is the package the frame holds, and its opener then frees
// nothing. The resume's unpack reads the record back and reopens the
// lifetime past it, its end the one its source's opener would have run.
//
// The runtime owns a chain's memory: arenaChunk gives the room of a cell,
// in the cursor's chunk or a new one; arenaOpen begins a chain; arenaClose
// gives a chain's chunks back; stackReset gives back a stack's chunks past
// a mark. Each call is its runtime function's, which the program's link
// inlines where it pays.

#include "Lower.h"

#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/MathExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

Type pointer(MLIRContext *ctx) { return LLVM::LLVMPointerType::get(ctx); }

LifetimeKind kindOf(Type type) { return cast<LifetimeType>(type).getKind(); }

// What a lifetime's slot in the frame holds, a word each: its cursor, and
// for a lifetime on a stack the mark its end resets the stack to.
enum class SlotWords : std::uint8_t { Cursor = 1, CursorAndMark = 2 };

// A slot of the frame, at the start of the entry block of the function
// `inside` is in, so it is one per frame however often what needs it runs.
Value frameSlot(OpBuilder &b, Location loc, Operation *inside, SlotWords words) {
  OpBuilder::InsertionGuard guard(b);
  Operation *scope = inside->getParentWithTrait<mlir::OpTrait::AutomaticAllocationScope>();
  b.setInsertionPointToStart(&scope->getRegion(0).front());
  Type ptr = pointer(b.getContext());
  Value count = LLVM::ConstantOp::create(b, loc, b.getI64Type(), static_cast<int64_t>(words));
  return LLVM::AllocaOp::create(b, loc, ptr, ptr, count, cellAlignment());
}

// The address of the mark of a lifetime on a stack, the word after its
// cursor's in its slot.
Value markOf(OpBuilder &b, Location loc, Value slot) {
  Type ptr = pointer(b.getContext());
  return LLVM::GEPOp::create(b, loc, ptr, ptr, slot, ArrayRef<LLVM::GEPArg>{1});
}

// A room of `bytes` bytes in the cursor whose slot is `slot`: the place the
// runtime gives (the cursor itself where its chunk has room), and the
// cursor moved past it.
Value bump(OpBuilder &b, Location loc, const Runtime &runtime, Value slot, uint64_t bytes) {
  Type ptr = pointer(b.getContext());
  Value cursor = LLVM::LoadOp::create(b, loc, ptr, slot);
  Value room = runtime
                   .call(b, loc, idr::runtime::helper::arenaChunk,
                         ValueRange{cursor, i64Constant(b, loc, static_cast<int64_t>(bytes))})
                   .getResult();
  LLVM::StoreOp::create(b, loc, at(b, loc, room, static_cast<unsigned>(bytes)), slot);
  return room;
}

// The slot of the home of site `site`: its entry in the thread's array of
// home cursors, a static datum.
Value homeSlot(OpBuilder &b, Location loc, uint32_t site) {
  Value homes = staticAddress(b, loc, StaticNames::homes());
  return LLVM::GEPOp::create(b, loc, pointer(b.getContext()), pointer(b.getContext()), homes,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(site)});
}

// The cursor's slot that a put into `lifetime`, converted to `converted`,
// bumps: a cursor's own, or a home's, which has no value of its own.
Value cursorSlot(OpBuilder &b, Location loc, Type lifetime, ValueRange converted) {
  return kindOf(lifetime).fold([&]() -> Value { return {}; }, [&]() -> Value { return {}; },
                               [&]() -> Value { return converted.front(); },
                               [&](uint32_t site) -> Value { return homeSlot(b, loc, site); });
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
    Type lifetime = op.getLifetime().getType();
    Value place = kindOf(lifetime).isRoom()
                      ? adaptor.getLifetime().front()
                      : bump(rewriter, loc, runtime,
                             cursorSlot(rewriter, loc, lifetime, adaptor.getLifetime()), cell.size);
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
    Value slot = cursorSlot(rewriter, loc, op.getLifetime().getType(), adaptor.getLifetime());
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

// An opener's region, run once in place as an scf.execute_region, its
// lifetime `lifetime` (none for a view or a home, whose value is no value),
// its results the region's: what every opener and the loan share. `close`
// runs after the region, with the results at hand.
template <typename OpT, typename Close>
LogicalResult runRegion(OpT op, ConversionPatternRewriter &rewriter, const TypeConverter &converter,
                        SmallVector<Value> lifetime, ArrayRef<SmallVector<Value>> others,
                        SmallVector<SmallVector<Value>> leading, Close &&close) {
  FailureOr<SmallVector<SmallVector<Type>>> converted = convertedResults(op, converter);
  if (failed(converted))
    return rewriter.notifyMatchFailure(op, "a result's type does not convert");
  ArrayRef<SmallVector<Type>> yielded = ArrayRef(*converted).drop_front(leading.size());
  SmallVector<Type> flat;
  for (ArrayRef<Type> components : yielded)
    llvm::append_range(flat, components);
  auto run = scf::ExecuteRegionOp::create(rewriter, op.getLoc(), flat);
  SmallVector<SmallVector<Value>> args{std::move(lifetime)};
  llvm::append_range(args, others);
  moveRegion(rewriter, converter, op.getBody(), args, run.getRegion());
  close();
  SmallVector<SmallVector<Value>> results = std::move(leading);
  llvm::append_range(results, groupResults(run.getResults(), yielded));
  rewriter.replaceOpWithMultiple(op, std::move(results));
  return success();
}

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

// How the region of a lifetime of one recursion level ends: at its end, or
// by packing the lifetime, the last op before its terminator, which the
// pack's verifier holds there. The two are the problem's: a lifetime that
// ends here, and one whose memory moves into a frame.
enum class End : std::uint8_t { Closes, Packs };

End endOf(Region &body) {
  Operation *last = body.front().getTerminator()->getPrevNode();
  return isa_and_nonnull<LifetimePackOp>(last) ? End::Packs : End::Closes;
}

// The end of a chain whose cursor is in `slot`: closed, its chunks given
// back; packed, nothing, since the chain is the package's.
void endChain(OpBuilder &b, Location loc, const Runtime &runtime, End end, Value slot) {
  switch (end) {
  case End::Closes:
    runtime.call(b, loc, idr::runtime::helper::arenaClose,
                 LLVM::LoadOp::create(b, loc, pointer(b.getContext()), slot).getResult());
    return;
  case End::Packs:
    return;
  }
}

// The end of a lifetime on the stack of the cursor in `base`, its own in
// `slot`: closed, the chunks past its mark given back and the base's cursor
// the mark again; packed, its cells kept and the base's cursor past them,
// where what the frame's call puts goes.
void endStack(OpBuilder &b, Location loc, const Runtime &runtime, End end, Value base, Value slot,
              Value mark) {
  switch (end) {
  case End::Closes:
    runtime.call(b, loc, idr::runtime::helper::stackReset, mark);
    LLVM::StoreOp::create(b, loc, mark, base);
    return;
  case End::Packs: {
    Value past = LLVM::LoadOp::create(b, loc, pointer(b.getContext()), slot);
    LLVM::StoreOp::create(b, loc, past, base);
    return;
  }
  }
}

// A chain of its own: its cursor in a slot of the frame, the chain begun
// empty, each put bumping it.
struct LowerChainOpener : IdrPattern<LifetimeChainOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeChainOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    End end = endOf(op.getBody());
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
    Type ptr = pointer(getContext());
    End end = endOf(op.getBody());
    Value base = adaptor.getBase().front();
    Value top = LLVM::LoadOp::create(rewriter, loc, ptr, base);
    Value mark = runtime
                     .call(rewriter, loc, idr::runtime::helper::arenaChunk,
                           ValueRange{top, i64Constant(rewriter, loc, 0)})
                     .getResult();
    LLVM::StoreOp::create(rewriter, loc, mark, base);
    Value slot = frameSlot(rewriter, loc, op, SlotWords::CursorAndMark);
    LLVM::StoreOp::create(rewriter, loc, mark, slot);
    LLVM::StoreOp::create(rewriter, loc, mark, markOf(rewriter, loc, slot));
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
    uint32_t site = kindOf(op.getBody().front().getArgument(0).getType())
                        .fold([] { return 0u; }, [] { return 0u; }, [] { return 0u; },
                              [](uint32_t k) { return k; });
    return runRegion(op, rewriter, *getTypeConverter(), {}, {}, {}, [&] {
      Value slot = homeSlot(rewriter, loc, site);
      Value cursor = LLVM::LoadOp::create(rewriter, loc, pointer(getContext()), slot);
      runtime.call(rewriter, loc, idr::runtime::helper::arenaClose, cursor);
      LLVM::StoreOp::create(rewriter, loc, LLVM::ZeroOp::create(rewriter, loc, pointer(getContext())),
                            slot);
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

//===----------------------------------------------------------------------===//
// A lifetime split around a framed call
//===----------------------------------------------------------------------===//

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
    place(layout::Component{pointer(package.getContext()), layout::Word::Uncounted});
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
    Type ptr = pointer(getContext());
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
// past the record in a slot of the frame, its region run in place with the
// values it holds restated, and its end its source's, unless it packs
// again. A chain reopens whole. A stack's mark is in the record, but its
// end gives its base the mark back, and the unpack names no base: that is
// the op's to say, so the lowering refuses it as the internal error it is.
struct LowerLifetimeUnpack : IdrPattern<LifetimeUnpackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(LifetimeUnpackOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto package = cast<LifetimePackageType>(op.getPackage().getType());
    switch (package.getPacked()) {
    case Packed::FromStack:
      return op.emitOpError("internal error: idr-lower: reopens a stack lifetime but names no "
                            "base cursor, to which its end gives the mark back");
    case Packed::FromChain:
      break;
    }
    Record record = recordOf(layouts, package);
    Value place = adaptor.getPackage().front();
    SmallVector<Value> read = runtime.load(rewriter, loc, place, cellAlignment(), record.slots);
    Value cursor = record.bytes == 0 ? place : at(rewriter, loc, place, record.bytes);
    End end = endOf(op.getBody());
    Value slot = frameSlot(rewriter, loc, op, SlotWords::Cursor);
    LLVM::StoreOp::create(rewriter, loc, cursor, slot);
    SmallVector<SmallVector<Value>> held;
    ArrayRef<Value> rest = read;
    for (Type type : package.getHeld()) {
      size_t count = layouts.components(type).size();
      held.push_back(SmallVector<Value>(rest.take_front(count)));
      rest = rest.drop_front(count);
    }
    return runRegion(op, rewriter, *getTypeConverter(), {slot}, held, {}, [&] {
      endChain(rewriter, loc, runtime, end, slot);
    });
  }
};

//===----------------------------------------------------------------------===//
// Before the conversion
//===----------------------------------------------------------------------===//

// `value` of the room type `type` moved `offset` bytes into its block: a
// pointer at the offset, seen as the room again until the conversion folds
// the casts away.
Value offsetRoom(OpBuilder &b, Location loc, Value room, uint64_t offset) {
  Type ptr = pointer(b.getContext());
  Value base = UnrealizedConversionCastOp::create(b, loc, ptr, room).getResult(0);
  Value moved = at(b, loc, base, static_cast<unsigned>(offset));
  return UnrealizedConversionCastOp::create(b, loc, room.getType(), moved).getResult(0);
}

// What a put into a room takes of it: a cell's or a reserved room's bytes,
// or what a callee given the room says it puts into it, its bound.
FailureOr<uint64_t> putBytes(Operation *op, OpOperand &use, const SymbolTable &program,
                             const Layouts &layouts) {
  if (auto putter = dyn_cast<LifetimePutOpInterface>(op))
    return putter.getPutBytes(layouts);
  auto call = cast<CallOp>(op);
  auto callee = program.lookup<FuncOp>(call.getCalleeAttr().getAttr());
  ParameterParts parts(callee.getArgumentTypes());
  unsigned index = use.getOperandNumber();
  std::optional<uint64_t> bound;
  idr::match(
      parts[index],
      [&](PutPart part) {
        if (PutBoundsAttr bounded = callee.getBoundedAttr())
          for (const PutBound &each : bounded.getBounds())
            if (each.parameter == part.position)
              bound = each.bytes;
      },
      [](WritePart) {}, [](NoPart) {});
  if (!bound)
    return call.emitError() << "internal error: idr-lower: @" << callee.getSymName()
                            << " bounds nothing it puts into the room it is given";
  return *bound;
}

// Whether `op` puts into the lifetime it takes as `use`: a cell or a room
// it makes there, or a call that gives it to its callee. A loan's or a
// slot's stated lifetime, a cast to a view, a stack's base, are no puts.
bool puts(Operation *op, OpOperand &use) {
  if (auto putter = dyn_cast<LifetimePutOpInterface>(op))
    return putter.getPutLifetime() == use.get();
  return isa<CallOp>(op);
}

} // namespace

void addLifetimeConversions(TypeConverter &converter) {
  converter.addConversion(
      [](LifetimeType type, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
        if (type.getKind().lowered() != Lowered::NoValue)
          out.push_back(pointer(type.getContext()));
        return success();
      });
}

LogicalResult prepareLifetimes(FuncOp fn, const SymbolTable &program, const Layouts &layouts) {
  MLIRContext *ctx = fn.getContext();
  Type ptr = pointer(ctx);
  Block &entry = fn.getBody().front();
  Location loc = fn.getLoc();
  OpBuilder b = OpBuilder::atBlockBegin(&entry);

  // Each cursor parameter in its slot, which its uses read; each return
  // gives the cursors back after its values, in the parameters' order.
  SmallVector<Value> slots;
  for (BlockArgument arg : entry.getArguments()) {
    if (!isCursorLifetime(arg.getType()))
      continue;
    auto in = UnrealizedConversionCastOp::create(b, loc, ptr, Value(arg));
    Value one = LLVM::ConstantOp::create(b, loc, b.getI64Type(), 1);
    Value slot = LLVM::AllocaOp::create(b, loc, ptr, ptr, one, cellAlignment());
    LLVM::StoreOp::create(b, loc, in.getResult(0), slot);
    Value held = UnrealizedConversionCastOp::create(b, loc, arg.getType(), slot).getResult(0);
    arg.replaceAllUsesExcept(held, in);
    slots.push_back(slot);
  }
  if (!slots.empty())
    for (Block &block : fn.getBody())
      if (auto ret = dyn_cast<ReturnOp>(block.getTerminator())) {
        OpBuilder at(ret);
        SmallVector<Value> cursors = llvm::map_to_vector(
            slots, [&](Value slot) -> Value { return LLVM::LoadOp::create(at, loc, ptr, slot); });
        ret->insertOperands(ret->getNumOperands(), cursors);
      }

  // Each room's puts at their offsets in its block, in program order: its
  // parameters' from the function's start, a block opener's from its own,
  // whose block is then allocated in the frame at the size laid out.
  struct Room {
    Value binder;
    uint64_t next;
    LifetimeBlockOp opener;
  };
  SmallVector<Room> rooms;
  for (BlockArgument arg : entry.getArguments())
    if (isRoomLifetime(arg.getType()))
      rooms.push_back({arg, 0, {}});
  LogicalResult laid = success();
  fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (auto opener = dyn_cast<LifetimeBlockOp>(op)) {
      rooms.push_back({opener.getBody().front().getArgument(0), 0, opener});
      return WalkResult::advance();
    }
    for (OpOperand &use : op->getOpOperands()) {
      auto room = llvm::find_if(rooms, [&](const Room &r) { return r.binder == use.get(); });
      if (room == rooms.end() || !puts(op, use))
        continue;
      FailureOr<uint64_t> bytes = putBytes(op, use, program, layouts);
      if (failed(bytes)) {
        laid = failure();
        return WalkResult::interrupt();
      }
      uint64_t offset = llvm::alignTo(room->next, cellAlignment());
      room->next = offset + *bytes;
      if (offset != 0) {
        OpBuilder before(op);
        use.set(offsetRoom(before, op->getLoc(), use.get(), offset));
      }
    }
    return WalkResult::advance();
  });
  if (failed(laid))
    return failure();
  for (const Room &room : rooms) {
    if (!room.opener)
      continue;
    Location at = room.opener.getLoc();
    uint64_t size = std::max<uint64_t>(room.next, 1);
    Value one = LLVM::ConstantOp::create(b, at, b.getI64Type(), 1);
    Value block = LLVM::AllocaOp::create(
        b, at, ptr, LLVM::LLVMArrayType::get(b.getI8Type(), static_cast<unsigned>(size)), one,
        cellAlignment());
    Value lifetime =
        UnrealizedConversionCastOp::create(b, at, room.binder.getType(), block).getResult(0);
    room.binder.replaceAllUsesWith(lifetime);
  }
  return success();
}

void populateLifetimePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCellArena, LowerCellStack, LowerReserve, LowerToView<ActivationOp>,
               LowerToView<LifetimeForgetOp>, LowerViewOpener, LowerBlockOpener, LowerChainOpener,
               LowerStackOpener, LowerHomeOpener, LowerLend, LowerLifetimePack,
               LowerLifetimeUnpack>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
