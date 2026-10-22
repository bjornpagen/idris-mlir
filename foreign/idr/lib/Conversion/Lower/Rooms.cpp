// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's lifetimes made ready before its ops are converted: each
// cursor parameter kept in a slot of the frame, which its uses read and
// every return gives back, and each room's puts laid out once, each at a
// static offset in its block, which a block opener allocates in the frame.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/Func.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Conversion/Words.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/MathExtras.h"

#include <algorithm>
#include <optional>

using namespace mlir;

namespace idr::conversion {

namespace {

// `value` of the room type `type` moved `offset` bytes into its block: a
// pointer at the offset, seen as the room again until the conversion folds
// the casts away.
Value offsetRoom(OpBuilder &b, Location loc, Value room, uint64_t offset) {
  Type ptr = ptrType(b.getContext());
  Value base = UnrealizedConversionCastOp::create(b, loc, ptr, room).getResult(0);
  Value moved = at(b, loc, base, static_cast<unsigned>(offset));
  return UnrealizedConversionCastOp::create(b, loc, room.getType(), moved).getResult(0);
}

// What a put into a room takes of it: a cell's or a reserved room's bytes,
// or what a callee given the room says it puts into it, its bound.
FailureOr<uint64_t> putBytes(Operation *op, OpOperand &use, const solver::ProgramGraph &graph,
                             const Layouts &layouts) {
  if (auto putter = dyn_cast<LifetimePutOpInterface>(op))
    return putter.getPutBytes(layouts);
  auto call = cast<CallOp>(op);
  FuncOp callee = graph.op(graph.id(call.getCalleeAttr()));
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

LogicalResult prepareLifetimes(FuncOp fn, const solver::ProgramGraph &graph,
                               const Layouts &layouts) {
  MLIRContext *ctx = fn.getContext();
  Type ptr = ptrType(ctx);
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
      FailureOr<uint64_t> bytes = putBytes(op, use, graph, layouts);
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
  // Rewriting the opener's block and its binder's uses mutates the IR the
  // room names, which MLIR's op and value handles allow only when non-const.
  for (Room &room : rooms) {
    if (!room.opener)
      continue;
    Location at = room.opener.getLoc();
    uint64_t size = std::max<uint64_t>(room.next, 1);
    Value one = LLVM::ConstantOp::create(b, at, b.getI64Type(), 1);
    Value block =
        LLVM::AllocaOp::create(b, at, ptr, LLVM::LLVMArrayType::get(b.getI8Type(), size), one,
                               cellAlignment());
    Value lifetime =
        UnrealizedConversionCastOp::create(b, at, room.binder.getType(), block).getResult(0);
    room.binder.replaceAllUsesWith(lifetime);
  }
  return success();
}


} // namespace idr::conversion
