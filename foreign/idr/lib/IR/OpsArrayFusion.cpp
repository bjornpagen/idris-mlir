// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Two accesses of one element made one (idr/IR/Arrays.h): a read and a
// write made its update, on a value array's buffer One-Shot's write and the
// read before it, on mutable memory the skeleton rule MoveOut; and, on
// mutable memory, the skeleton rules ForwardWritten, a read of a write the
// value written, and DeleteOverwritten, a write that the next write of its
// element overwrites unread gone. What each asks is effects alone.

#include "idr/IR/Arrays.h"
#include "idr/IR/Effects/Classify.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

#include <limits>
#include <optional>

// What each stage of a program implies: whether its references are counted.
#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

namespace {

// A write of one element and the read it pairs with, read through the same
// questions: ours on mutable memory, upstream's on a value array's buffer.
template <class Write>
struct ElementAccess;

template <>
struct ElementAccess<ArraySetOp> {
  using Read = ArrayGetOp;
  static Value array(ArrayGetOp read) { return read.getArray(); }
  static Value array(ArraySetOp write) { return write.getArray(); }
  static Value element(ArrayGetOp read) { return read.getValue(); }
  static Value written(ArraySetOp write) { return write.getValue(); }
};

template <>
struct ElementAccess<memref::StoreOp> {
  using Read = memref::LoadOp;
  static Value array(memref::LoadOp read) { return read.getMemref(); }
  static Value array(memref::StoreOp write) { return write.getMemref(); }
  static Value element(memref::LoadOp read) { return read.getResult(); }
  static Value written(memref::StoreOp write) { return write.getValueToStore(); }
};

template <class Write>
concept ElementWrite = requires { typename ElementAccess<Write>::Read; };

// What a write and the read of its element become: the read, the ops
// between that rebuild the element from it, in order, and the values still
// read after the write, the element's or the rebuilding's.
template <ElementWrite Write>
struct Fusion {
  typename ElementAccess<Write>::Read read;
  SmallVector<Operation *> rebuilding;
  SmallVector<Value> leaving;
};

// An index as the value it was checked from: a guard gives its operand.
Value unguarded(Value index) {
  return definitionChain(index, [](Value value) -> std::optional<Value> {
           if (auto guard = value.getDefiningOp<GuardOpInterface>())
             return guard.getGuarded();
           return std::nullopt;
         }).back();
}

// Whether two indices are one: the same value or the same constant,
// whichever guard checked it.
bool sameIndex(Value a, Value b) { return isEqualConstantIntOrValue(unguarded(a), unguarded(b)); }

// Whether two accesses reach one element: the same array, through whatever
// view of it each was given, at the same indices.
bool sameElement(Value array, ValueRange indices, Value other, ValueRange otherIndices) {
  return arrayRoot(array) == arrayRoot(other) && llvm::equal(indices, otherIndices, sameIndex);
}

// Whether an effect may reach memory of an array: a buffer of its element
// in its memory space, whatever its shape, layout or grade, as a view of it
// is. An effect that names no value is on a state as a whole, which holds
// every buffer.
struct OnMemoryOf {
  MemRefType array;
  bool operator()(const effects::Effect &each) const {
    if (!onContents(each))
      return false;
    if (!each.value)
      return true;
    auto buffer = dyn_cast<BaseMemRefType>(unrestricted(each.value.getType()));
    return buffer && buffer.getElementType() == array.getElementType() &&
           buffer.getMemorySpace() == array.getMemorySpace();
  }
};

// What an effect on memory of an array may change of it: anything but a
// read, which leaves what each element holds as it was.
struct ChangesMemoryOf {
  OnMemoryOf memory;
  bool operator()(const effects::Effect &each) const {
    return each.kind != effects::Kind::Read && memory(each);
  }
};

// What fusion keeps out of the update it makes: an effect that may reach
// memory written in place, a release on the heap among them, or a cell
// filled beneath it. Stricter than the update's region, which lets a free
// on the heap and a cell filled through.
bool keptOut(const effects::Effect &each) {
  return onContents(each) ||
         effects::atOrBelow[effects::ResourceId::Contents].contains(each.resource);
}

// The last op before `op` in its block that does what `touches` asks about;
// null where none does.
template <effects::Question Q>
Operation *lastBefore(Operation *op, const Q &touches) {
  Operation *last = op->getPrevNode();
  while (last && effects::classify(last, touches) != effects::Does::Touches)
    last = last->getPrevNode();
  return last;
}

// The array an access of mutable memory reaches, its grade aside.
MemRefType memoryOf(Value array) { return cast<MemRefType>(unrestricted(array.getType())); }

// Whether the program `op` stands in counts no reference yet, as its stage
// says. The stage is the program's, which a pass at any stage meets only as
// it runs.
bool uncounted(Operation *op) {
  ProgramOp program = op->getParentOfType<FuncOp>().getProgram();
  return countingAt[program.getStage()] == StageCounting::Uncounted;
}

// The fusion of `write` with the read of its element, or nothing.
template <ElementWrite Write>
std::optional<Fusion<Write>> fusionOf(Write write) {
  using Access = ElementAccess<Write>;
  MemRefType array = memoryOf(Access::array(write));
  // An element that holds no reference has none to give up.
  if (!holdsReferences(array.getElementType()) || !uncounted(write))
    return std::nullopt;
  // The read is the last op before the write that may touch memory of the
  // array, so nothing between does.
  auto read = dyn_cast_or_null<typename Access::Read>(lastBefore(write, OnMemoryOf{array}));
  if (!read || !sameElement(Access::array(read), read.getIndices(), Access::array(write),
                            write.getIndices()))
    return std::nullopt;
  // `between` holds the ops between, in the block's order, each numbered by
  // its place there. A place indexes LLVM's bit vector, which marks the
  // rebuilding; it holds every place, since the vector of ops keeps its
  // length in no more bits.
  using Place = llvm::BitVector::size_type;
  static_assert(std::numeric_limits<llvm::SmallVectorSizeType<Operation *>>::max() <=
                    std::numeric_limits<Place>::max(),
                "every op between has a place");
  SmallVector<Operation *> between;
  for (Operation *op = read->getNextNode(); op != write.getOperation(); op = op->getNextNode())
    between.push_back(op);
  const auto places = static_cast<Place>(between.size());
  Block *block = write->getBlock();
  // The place among `between` of `op`, an op of the block strictly between
  // the read and the write, found by the block's own order; none for any
  // other op.
  auto placeOf = [&](Operation *op) -> std::optional<Place> {
    if (!op || op->getBlock() != block || !read->isBeforeInBlock(op) ||
        !op->isBeforeInBlock(write))
      return std::nullopt;
    auto at = llvm::lower_bound(between, op, [](Operation *a, Operation *b) {
      return a->isBeforeInBlock(b);
    });
    return static_cast<Place>(at - between.begin());
  };

  // The rebuilding, in order: each op between that reads the element, or a
  // value of the rebuilding, anywhere in it. It moves into the update's
  // region, where the element's place is empty. Which ops rebuild is a bit
  // per place.
  Fusion<Write> fusion{read, {}, {}};
  Value element = Access::element(read);
  llvm::BitVector rebuilds(places);
  auto rebuilt = [&](Operation *op) {
    std::optional<Place> at = placeOf(op);
    return at && rebuilds.test(*at);
  };
  auto readsRebuilt = [&](Operation *op) {
    return op
        ->walk([&](Operation *inner) {
          bool reads = llvm::any_of(inner->getOperands(), [&](Value operand) {
            return operand == element || rebuilt(operand.getDefiningOp());
          });
          return reads ? WalkResult::interrupt() : WalkResult::advance();
        })
        .wasInterrupted();
  };
  for (Place at = 0; at < places; ++at) {
    Operation *op = between[at];
    if (!readsRebuilt(op))
      continue;
    if (effects::classify(op, keptOut) == effects::Does::Touches)
      return std::nullopt;
    rebuilds.set(at);
    fusion.rebuilding.push_back(op);
  }

  // Each op of the rebuilding moves to the write past the ops between after
  // it that stay, which neither may tell: read from the write back.
  effects::EffectSet staying;
  for (Place at = places; at-- > 0;) {
    effects::EffectSet does = effects::whole(between[at]);
    if (!rebuilds.test(at))
      staying = staying | does;
    else if (does.conflicts(staying))
      return std::nullopt;
  }

  // What leaves the update: the element and the rebuilding's values that an
  // op after the write reads, the write itself aside.
  auto readAfter = [&](Value value) {
    return llvm::any_of(value.getUses(), [&](OpOperand &use) {
      Operation *at = block->findAncestorOpInBlock(*use.getOwner());
      return at != write.getOperation() && !rebuilt(at);
    });
  };
  if (readAfter(element))
    fusion.leaving.push_back(element);
  for (Operation *op : fusion.rebuilding)
    for (Value result : op->getResults())
      if (readAfter(result))
        fusion.leaving.push_back(result);
  return fusion;
}

// The update in the write's place: the rebuilding moved into its region in
// order, the element its region's argument there, the value written given
// back into the element's place, and every value that leaves read from the
// update's results after it.
template <ElementWrite Write>
void fuse(RewriterBase &rewriter, Write write, const Fusion<Write> &fusion) {
  using Access = ElementAccess<Write>;
  Value element = Access::element(fusion.read);
  Location loc = rewriter.getFusedLoc({fusion.read->getLoc(), write.getLoc()});
  rewriter.setInsertionPoint(write);
  auto update = ArrayUpdateOp::create(rewriter, loc, ValueRange(fusion.leaving).getTypes(),
                                      Access::array(write), write.getIndices());
  Block *body =
      rewriter.createBlock(&update.getRegion(), {}, {element.getType()}, {fusion.read->getLoc()});
  for (Operation *op : fusion.rebuilding)
    rewriter.moveOpBefore(op, body, body->end());
  Value moving = body->getArgument(0);
  rewriter.replaceUsesWithIf(element, moving, [&](OpOperand &use) {
    return update->isProperAncestor(use.getOwner());
  });
  auto inside = [&](Value value) { return value == element ? moving : value; };
  rewriter.setInsertionPointToEnd(body);
  ArrayUpdateYieldOp::create(rewriter, loc, inside(Access::written(write)),
                             llvm::map_to_vector(fusion.leaving, inside));
  for (auto [value, out] : llvm::zip_equal(fusion.leaving, update.getOuts()))
    rewriter.replaceUsesWithIf(value, out, [&](OpOperand &use) {
      return use.getOwner() != write.getOperation() && !update->isAncestor(use.getOwner());
    });
  rewriter.eraseOp(write);
  rewriter.eraseOp(fusion.read);
}

// The write whose value `read` reads: the last op before it that may
// change memory of its array, where that op is a write of the same element,
// or nothing. The read borrows the element and the write moved it in, so
// the value written read again is the read only while no reference is
// counted: a counted program has moved that value's reference into the
// array. The value gains a use where the read's were, so it is forwarded
// only where it may be used again and stands at the read's grade.
std::optional<ArraySetOp> writeRead(ArrayGetOp read) {
  if (!uncounted(read))
    return std::nullopt;
  auto write = dyn_cast_or_null<ArraySetOp>(
      lastBefore(read, ChangesMemoryOf{OnMemoryOf{memoryOf(read.getArray())}}));
  if (!write ||
      !sameElement(write.getArray(), write.getIndices(), read.getArray(), read.getIndices()))
    return std::nullopt;
  Type written = write.getValue().getType();
  if (isLinear(written) || !forgets(written, read.getValue().getType()))
    return std::nullopt;
  return write;
}

// The write `write` overwrites unread: the last op before it that may touch
// memory of its array, where that op is a write of the same element, or
// nothing. What that write moved in this one releases, and nothing read it
// between, so the earlier write does nothing the program can see; a crash
// between ends the run before anything could. Its value, moved in no
// longer, is released at its last use, which counting places only where no
// reference is counted yet. A value used once by its grade has that write
// as its one use, which cannot go.
std::optional<ArraySetOp> overwritten(ArraySetOp write) {
  if (!uncounted(write))
    return std::nullopt;
  auto earlier =
      dyn_cast_or_null<ArraySetOp>(lastBefore(write, OnMemoryOf{memoryOf(write.getArray())}));
  if (!earlier ||
      !sameElement(earlier.getArray(), earlier.getIndices(), write.getArray(), write.getIndices()) ||
      isLinear(earlier.getValue().getType()))
    return std::nullopt;
  return earlier;
}

} // namespace

void idr::arrays::moveOut(RewriterBase &rewriter, memref::StoreOp write) {
  if (std::optional<Fusion<memref::StoreOp>> fusion = fusionOf(write))
    fuse(rewriter, write, *fusion);
}

namespace idr::egraph {

// The fusion is the IR's, read off effects; the e-graph's facts add
// nothing to it.
std::optional<Edit> MoveOut::decide(ArraySetOp write, const OperandFacts &) {
  if (!fusionOf(write))
    return std::nullopt;
  return Rewrite{};
}

// The fusion found again on the input as it now is, since an earlier
// rewrite may have changed what stands before the write.
void MoveOut::rewrite(ArraySetOp write, const Rewrite &, RewriterBase &rewriter) {
  if (std::optional<Fusion<ArraySetOp>> fusion = fusionOf(write))
    fuse(rewriter, write, *fusion);
}

// The write is the IR's, read off effects, and the value it gives is no
// operand of the read, which a Forward could name: the rule's own rewrite
// replaces the read.
std::optional<Edit> ForwardWritten::decide(ArrayGetOp read, const OperandFacts &) {
  if (!writeRead(read))
    return std::nullopt;
  return Rewrite{};
}

// The write found again on the input as it now is, since an earlier rewrite
// may have changed what stands before the read.
void ForwardWritten::rewrite(ArrayGetOp read, const Rewrite &, RewriterBase &rewriter) {
  if (std::optional<ArraySetOp> write = writeRead(read))
    rewriter.replaceOp(read, write->getValue());
}

std::optional<Edit> DeleteOverwritten::decide(ArraySetOp write, const OperandFacts &) {
  if (!overwritten(write))
    return std::nullopt;
  return Rewrite{};
}

// The earlier write found again on the input as it now is, since an earlier
// rewrite may have changed what stands before this one.
void DeleteOverwritten::rewrite(ArraySetOp write, const Rewrite &, RewriterBase &rewriter) {
  if (std::optional<ArraySetOp> earlier = overwritten(write))
    rewriter.eraseOp(*earlier);
}

} // namespace idr::egraph
