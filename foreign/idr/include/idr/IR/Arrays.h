// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules the ops on arrays share, each said once: what an array holds at
// an index, where an element moves, where a generating op's destinations
// go, what memory an element's update may not touch, what a region of the
// generating set must end in and bind, and the bounds of the indices it
// binds (lib/IR/OpsArrayRules.cpp defines them);
// how a step of a generating op on buffers moves what it reads and gives
// (lib/IR/OpsArrayMovements.cpp); and two accesses of one element made one:
// a read and a write made its update, the skeleton rule on mutable memory
// and the step on a value array's buffers, and, on mutable memory, a read
// of a write the value written and a write overwritten gone
// (lib/IR/OpsArrayFusion.cpp).
#ifndef IDR_IR_ARRAYS_H
#define IDR_IR_ARRAYS_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Effects/Classify.h"
#include "idr/Transforms/EGraph.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StructuredOpsUtils.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/DestinationStyleOpInterface.h"
#include "mlir/Interfaces/TilingInterface.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cstdint>
#include <optional>
#include <type_traits>

namespace idr::arrays {

// Whether `op` is of the generating set: an op that writes destinations
// (DestinationStyleOpInterface) through a region that yields into them
// (YieldTargetsOpInterface), which linalg's ops and a memo cell's force
// are not both.
inline bool isGenerating(mlir::Operation *op) {
  return llvm::isa<mlir::DestinationStyleOpInterface>(op) &&
         llvm::isa<YieldTargetsOpInterface>(op);
}

// What an array of `array`'s shape holds at an index of its `lead` leading
// dimensions: its element when they are all of them, else the cell of the
// dimensions after them. A tensor's cell is a tensor and a buffer's a
// buffer of the identity layout, the one a cell crosses a step in.
mlir::Type cellOf(mlir::ShapedType array, unsigned lead);

// Whether two arrays agree on their `lead` leading dimensions: the same
// size where both are static, both dynamic otherwise.
bool sameLead(mlir::ShapedType a, mlir::ShapedType b, unsigned lead);

// The part of `array` that holds its elements.
FlowAnchor elementsOf(mlir::Value array);

// What a value at an index of an array is: an element, or the elements of
// a cell, a part of the cell. An operand's is where it moves from, a value
// the op or its region makes where it moves to.
FlowSource atIndex(mlir::OpOperand &use);
FlowPlace atIndex(mlir::Value value);

// What a generating op does with its destinations: on tensors each result
// is its destination written, which the op takes over with its reference;
// on buffers it gives nothing and writes each destination in place, whose
// holder keeps it. Upstream's tie of a result to its destination says both,
// a result per destination on tensors and none on buffers, so no edge
// names a result bufferization left empty.
void destinationEdges(mlir::DestinationStyleOpInterface op, FlowEdges &edges);

// Whether an effect may reach memory written in place: a read, a write or
// a release on contents or on a state above it. An allocation names a
// fresh value, which nothing else reaches.
bool onContents(const effects::Effect &each);

// Whether `op`, with everything in it, may read or write the contents or a
// state above them, or does what MLIR cannot say: what no op inside an
// update's region may do, since the element's place is empty while it
// runs. Any other effect passes: a free or an allocation on the heap, a
// count, a fresh value's identity, memo state, a cell being filled.
bool touchesInPlace(mlir::Operation *op);

// A region of the generating set is entered from the op and from its own
// end, each time it ends for an index, and left from the op when the
// domain is empty and from its end after the last index. Nothing is
// forwarded: what the region gives goes into memory.
void generatingSuccessors(mlir::Operation *op,
                          llvm::SmallVectorImpl<mlir::RegionSuccessor> &regions);

// The rule every region of the generating set keeps: it ends in
// idr.array.yield of `types`, or in a terminator that never returns. Every
// other terminator that returns is confined to the parents it serves, so
// one that is not the yield is one that ends the run.
mlir::LogicalResult verifyEnd(mlir::Operation *op, mlir::TypeRange types);

// The indices a region binds first: `rank` of them, each an index.
mlir::LogicalResult verifyIndices(mlir::Operation *op, unsigned rank);

// The rule of a generating op that writes its destinations and never reads
// them: each destination of elements that hold references is fresh, a
// tensor.empty or an alloc_tensor of no copy, and on buffers the
// allocation bufferization made of one. Its slots hold nothing, so placing
// them releases nothing, and the op, its first writer, places every one
// before anything reads or releases it.
mlir::LogicalResult verifyFresh(mlir::DestinationStyleOpInterface op);

// The allocation `buffer` is, where it is one: a memref.alloc, or the one
// counting took over (idr.own.adopt) where bufferization made it, as it
// does every buffer of elements that hold references, there and only there.
mlir::memref::AllocOp allocationOf(mlir::Value buffer);

// An index of the domain of `op`, a generating op, is at least 0 and below
// its dimension's size (extentOf). `indices` are the indices its region
// binds first, one per dimension of the domain.
void boundIndex(mlir::DestinationStyleOpInterface op, mlir::Value value,
                mlir::Block::BlockArgListType indices, mlir::ValueBoundsConstraintSet &cstr);

// The size of dimension `dim` of `array`, a tensor or a buffer: its static
// size, or its dimension read where the builder stands.
mlir::OpFoldResult sizeOf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value array,
                          unsigned dim);

// The size of a dimension of a generating op's domain as value bounds
// names it, making nothing: an index value, or a dimension of a shaped
// value, `dim` set exactly then. Upstream's constraint set makes no term of
// a variable, so the size is kept in the form it makes both from.
struct DomainSize {
  mlir::Value value;
  std::optional<int64_t> dim;

  mlir::ValueBoundsConstraintSet::Variable variable() const {
    return {mlir::OpFoldResult(value), dim};
  }
  mlir::AffineExpr term(mlir::ValueBoundsConstraintSet &cstr) const {
    return cstr.getExpr(value, dim);
  }
};

// The size of dimension `dim` of a generating op's domain: the first
// destination's dimension, every destination having the domain's
// dimensions first, but along a fold's last axis, which no destination of
// a fold has, its length.
DomainSize extentOf(mlir::DestinationStyleOpInterface op, unsigned dim);

// The domain of a generating op as upstream's tiling reads it: each of its
// first `rank` dimensions from 0 to its size, in steps of 1.
llvm::SmallVector<mlir::Range> domainOf(mlir::OpBuilder &b, mlir::DestinationStyleOpInterface op,
                                        unsigned rank);

// How a generating op visits the `rank` dimensions of its domain, as
// upstream's iterator types say it: its first `frame` in parallel when its
// region only computes, and every other in order, carried, which
// `reduction` is on an op that implements no partial reduction, so that no
// upstream transform reorders it. Whether a dimension is ordered is what
// the region does, not which op holds it.
llvm::SmallVector<mlir::utils::IteratorType> iteratorsOf(mlir::Operation *op, unsigned rank,
                                                         unsigned frame);

// Whether the region of `op` only computes, each op in it asked on its own:
// it ends in the yield, and every op before the yield, with everything in
// it, at most makes fresh values. A region that may crash or run on forever
// at an index keeps its indices in order: out of order, another index could
// end the run first, with its own crash, or with a crash where the program
// would have run on forever, and crashes keep their order among themselves.
// A region that ends in another terminator ends the run at every index.
bool computes(mlir::Operation *op);

// What one step of a generating op on buffers moves, each a movement the
// lowering writes once (lib/Conversion/Movements.cpp). A slot of a buffer
// holds an element; a cell's slots are the elements under its leading
// indices.
//
// The value of a step's region's argument, taken out of `buffer` at
// `indices` with what its slots held: their place is left to be put back
// into (putBackAt).
mlir::Value takeAt(mlir::OpBuilder &b, mlir::Location loc, mlir::Value buffer,
                   mlir::ValueRange indices);
// A copy of what `buffer` holds at `indices`, with references of its own:
// the slots keep theirs.
mlir::Value copyAt(mlir::OpBuilder &b, mlir::Location loc, mlir::Value buffer,
                   mlir::ValueRange indices);
// `value` moved into `buffer` at `indices`, whose slots hold nothing to
// release.
void placeAt(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value, mlir::Value buffer,
             mlir::ValueRange indices);
// `value` moved back into `buffer` at `indices`, the place a take left.
void putBackAt(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value, mlir::Value buffer,
               mlir::ValueRange indices);

// The body of a generating op's region cloned at `b` with its arguments
// standing for `args`, and what its yield gives, through `place`, which
// moves each yielded value where it goes. A region that never returns is
// cloned whole inside an scf.execute_region of no results, its terminator
// kept, so that the step ends there and places nothing: a crash ends the
// run before anything reads the slots the step did not write.
template <typename Place>
  requires std::is_invocable_v<Place, mlir::OpBuilder &, mlir::ValueRange>
void cloneStep(mlir::OpBuilder &b, mlir::Location loc, mlir::Region &region,
               mlir::ValueRange args, Place &&place) {
  mlir::Block &body = region.front();
  mlir::IRMapping mapping;
  mapping.map(body.getArguments(), args);
  auto yield = llvm::dyn_cast<ArrayYieldOp>(body.getTerminator());
  if (!yield) {
    auto never = mlir::scf::ExecuteRegionOp::create(b, loc, mlir::TypeRange{});
    mlir::OpBuilder::InsertionGuard guard(b);
    b.createBlock(&never.getRegion());
    for (mlir::Operation &inner : body)
      b.clone(inner, mapping);
    return;
  }
  for (mlir::Operation &inner : body.without_terminator())
    b.clone(inner, mapping);
  llvm::SmallVector<mlir::Value> given = llvm::map_to_vector(
      yield.getValues(), [&](mlir::Value value) { return mapping.lookupOrDefault(value); });
  place(b, mlir::ValueRange(given));
}

// A read of an element whose next access to memory of its array, in its
// block, is a write of the same element becomes the element's update
// (idr.array.update), which stands where the write was: the element moves
// out of its place with the reference the place held, the ops between that
// read it, directly or through one another, move into the update's region,
// and the value written moves back in; the element, or a value of theirs,
// still read after the write leaves the update as one of its results. So a
// value read only to be rebuilt and written back holds the one reference
// to its cell while it is rebuilt, and counting rebuilds it in that cell.
//
// The read borrows and the write releases what it replaces; the update
// moves out and back. The two agree only while no reference is counted,
// so it rewrites a program whose holds are not yet decided. Nothing between
// may touch memory of the array, nor anything the rebuilding moves into the
// region touch memory written in place; the rebuilding moves toward the
// write past the other ops between only where neither may tell, so every
// effect keeps its order. What it asks is effects alone: it names no
// definition.
//
// On a value array's buffer, One-Shot's write and the read before it, as
// idr-bufferize leaves them; on mutable memory, the skeleton rule below.
void moveOut(mlir::RewriterBase &rewriter, mlir::memref::StoreOp write);

} // namespace idr::arrays

namespace idr::egraph {

// moveOut's rule on mutable memory, idr.array.set and the idr.array.get
// before it, in the e-graph's skeleton, where both are ordered by their
// effects.
struct MoveOut {
  using Root = ArraySetOp;
  static std::optional<Edit> decide(Root write, const OperandFacts &facts);
  static void rewrite(Root write, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

// A read of an element of mutable memory whose last write before it, in
// its block, to memory of its array wrote the same element reads the value
// written: the read is that value, and goes. Reads of the array between
// the two change nothing, and nothing between writes it.
struct ForwardWritten {
  using Root = ArrayGetOp;
  static std::optional<Edit> decide(Root read, const OperandFacts &facts);
  static void rewrite(Root read, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

// A write of an element of mutable memory whose last access before it, in
// its block, to memory of its array was a write of the same element
// overwrites what nothing read: the earlier write goes.
struct DeleteOverwritten {
  using Root = ArraySetOp;
  static std::optional<Edit> decide(Root write, const OperandFacts &facts);
  static void rewrite(Root write, const Rewrite &choice, mlir::RewriterBase &rewriter);
};

} // namespace idr::egraph

#endif // IDR_IR_ARRAYS_H
