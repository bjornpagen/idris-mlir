// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules the ops on arrays share, each said once: what an array holds at
// an index, where an element moves, what a region of the generating set
// must end in and bind, the bounds of the indices it binds, and how a step
// of a generating op on buffers moves what it reads and gives.
// lib/IR/OpsGenerating.cpp defines them.
#ifndef IDR_IR_ARRAYS_H
#define IDR_IR_ARRAYS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StructuredOpsUtils.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/DestinationStyleOpInterface.h"
#include "mlir/Interfaces/TilingInterface.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "llvm/ADT/SmallVectorExtras.h"

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

// The elements of `array`, a part of it.
FlowPoint elementsOf(mlir::Value array);

// What a value at an index of an array is: an element, or the elements of
// a cell, a part of the cell.
FlowPoint atIndex(mlir::OpOperand &use);
FlowPoint atIndex(mlir::Value value);

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

// An index of the domain is at least 0 and below its dimension's size.
// `Extent` gives the size of a dimension as a term of `cstr`.
template <typename Extent>
  requires std::is_invocable_r_v<mlir::AffineExpr, Extent, unsigned>
void boundIndex(mlir::Value value, mlir::Block::BlockArgListType indices, Extent &&extent,
                mlir::ValueBoundsConstraintSet &cstr) {
  auto index = llvm::dyn_cast<mlir::BlockArgument>(value);
  if (!index || indices.empty() || index.getOwner() != indices.front().getOwner() ||
      index.getArgNumber() >= indices.size())
    return;
  cstr.bound(value) >= 0;
  cstr.bound(value) < extent(index.getArgNumber());
}

// The size of dimension `dim` of `array`, a tensor or a buffer: its static
// size, or its dimension read where the builder stands.
mlir::OpFoldResult sizeOf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value array,
                          unsigned dim);

// The size of dimension `dim` of a generating op's domain as value bounds
// names it, making nothing: the first destination's dimension, every
// destination having the domain's dimensions first, but along a fold's
// last axis, which no destination of a fold has, its length.
mlir::ValueBoundsConstraintSet::Variable extentOf(mlir::DestinationStyleOpInterface op,
                                                  unsigned dim);

// The domain of a generating op as upstream's tiling reads it: each of its
// first `rank` dimensions from 0 to its size, in steps of 1.
llvm::SmallVector<mlir::Range> domainOf(mlir::OpBuilder &b, mlir::DestinationStyleOpInterface op,
                                        unsigned rank);

// How a generating op visits the `rank` dimensions of its domain, as
// upstream's iterator types say it: its first `frame` in parallel when its
// region does no more than compute and crash, and every other in order,
// carried, which `reduction` is on an op that implements no partial
// reduction, so that no upstream transform reorders it. Whether a
// dimension is ordered is what the region does, not which op holds it.
llvm::SmallVector<mlir::utils::IteratorType> iteratorsOf(mlir::Operation *op, unsigned rank,
                                                         unsigned frame);

// Whether `op` does no more than compute and crash: every effect of its,
// its own and its regions', is a crash's or a divergence's, or acquires a
// result of the op that has it. An op whose effects MLIR does not know may
// do anything.
bool computesOnly(mlir::Operation *op);

// Whether the region of `op` does no more than compute and crash, each op
// in it asked on its own. Asked once per op.
bool computes(mlir::Operation *op);

// What one step of a generating op on buffers moves, each a movement the
// lowering writes once (lib/Conversion/Arrays.cpp). A slot of a buffer
// holds an element; a cell's slots are the elements under its leading
// indices.
//
// The value of a step's region's argument, taken out of `buffer` at
// `indices` with what its slots held: they hold nothing to release after
// it, until a value is placed back.
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

} // namespace idr::arrays

#endif // IDR_IR_ARRAYS_H
