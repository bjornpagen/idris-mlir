// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Releases, and what may touch a released buffer after one.
//
// A release hands a buffer to a place One-Shot does not see: a cell
// (bufferization.to_buffer before idr.data.con, a memo cell's forced
// value) or a callee, which may keep it in one. The analysis sees the release read and
// write the buffer, so a later read of it makes the release copy. It sees
// no read after a later write that does not read: such a write would
// overwrite a buffer something else now holds, and nothing would conflict.
// So before any analysis, the program is made such that no such write
// exists: each tensor.empty is one buffer with one use, where common
// subexpression elimination would have shared one between two writes, and
// a write-only use of a released buffer after its release writes a
// tensor.empty of its own. Its contents were never read, so only its shape
// is the program's.
//
// Which buffers may be one is every aliasing relation the models declare,
// followed both ways, before the analysis decides any of them: a partition
// of the program's tensor values made once. When one value may run after
// another is by position, through loops, and through the region graph of
// the branch that holds both, which orders two regions one way where
// One-Shot's own conflict check asks only whether they exclude each other.
//
// A buffer allocated for elements that hold references has nothing in its
// slots, so the program is also made such that its first writer places
// every slot: a fresh array of such elements is a generating op's
// destination, an allocation of its own, and an insert of such elements
// over the whole of its destination is its source, which a copy places
// where a buffer must be made for it.
#include "idr/Transforms/BufferizeModels.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Arrays.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Utils/ReshapeOpsUtils.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/DestinationStyleOpInterface.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// Whether `region` runs again after each run of it, by its op's model.
bool isRepetitive(Region *region, const BufferizationOptions &options) {
  BufferizableOpInterface op = options.dynCastBufferizableOp(region->getParentOp());
  return op && op.isRepetitiveRegion(region->getRegionNumber());
}

// The uses of `value`, taken before any of them changes.
SmallVector<OpOperand *> takeUses(Value value) {
  return llvm::map_to_vector(value.getUses(), [](OpOperand &use) { return &use; });
}

// `use` writes a tensor.empty of its own, of the shape of the value it wrote.
void writeOwn(RewriterBase &rewriter, OpOperand &use) {
  Operation *writer = use.getOwner();
  Value old = use.get();
  auto type = cast<RankedTensorType>(old.getType());
  rewriter.setInsertionPoint(writer);
  SmallVector<OpFoldResult> sizes = tensor::getMixedSizes(rewriter, writer->getLoc(), old);
  Value own = tensor::EmptyOp::create(rewriter, writer->getLoc(), sizes, type.getElementType(),
                                      type.getEncoding());
  rewriter.modifyOpInPlace(writer, [&] { use.set(own); });
}

// The dimensions of a whole insert's destination each dimension of its
// source expands to: a dimension the insert drops, of extent 1, joins the
// kept one after it, or the last kept one where none follows; a source of
// no dimension expands to unit dimensions alone, in no group.
SmallVector<ReassociationIndices> expansionOf(tensor::InsertSliceOp insert) {
  llvm::SmallBitVector dropped = insert.getDroppedDims();
  SmallVector<ReassociationIndices> groups;
  ReassociationIndices pending;
  for (int64_t d = 0, e = insert.getType().getRank(); d < e; ++d) {
    pending.push_back(d);
    if (dropped.test(static_cast<unsigned>(d)))
      continue;
    groups.push_back(std::move(pending));
    pending.clear();
  }
  if (!groups.empty())
    llvm::append_range(groups.back(), pending);
  return groups;
}

} // namespace

idr::bufferize::AliasClasses::AliasClasses(Operation *program,
                                           const BufferizationOptions &options)
    : classes(components(related(program, options))) {}

// Each tensor value is numbered, with each value an aliasing relation names
// beside it, and the relations are kept as pairs of numbers until the walk
// has numbered every value; the values of the program are finitely many. A
// release's value is a tensor operand, numbered as the walk meets it.
idr::Csr<idr::bufferize::AliasedValue>
idr::bufferize::AliasClasses::related(Operation *program, const BufferizationOptions &options) {
  AnalysisState state(options);
  footprint::DenseMap<Value, std::uint32_t> number;
  auto numberOf = [&](Value value) {
    auto [at, made] = number.try_emplace(value, static_cast<std::uint32_t>(values.size()));
    if (made)
      values.push_back(value);
    return at->second;
  };
  footprint::Vector<std::pair<std::uint32_t, std::uint32_t>> relations;
  auto join = [&](Value value) {
    if (!isa<TensorLikeType>(value.getType()))
      return;
    std::uint32_t at = numberOf(value);
    for (AliasingOpOperand alias : state.getAliasingOpOperands(value))
      relations.emplace_back(at, numberOf(alias.opOperand->get()));
  };
  program->walk([&](Operation *op) {
    for (Value result : op->getResults())
      join(result);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          join(arg);
    for (OpOperand &operand : op->getOpOperands()) {
      if (!isa<TensorLikeType>(operand.get().getType()))
        continue;
      for (AliasingValue alias : state.getAliasingValues(operand))
        relations.emplace_back(numberOf(operand.get()), numberOf(alias.value));
      if (isRelease(operand, state))
        released.push_back({&operand, Node(numberOf(operand.get()))});
    }
  });
  CsrBuilder<AliasedValue> graph(Count<Node>(static_cast<std::uint32_t>(values.size())));
  for (auto [from, to] : relations) {
    graph.edge(Node(from), Node(to));
    graph.edge(Node(to), Node(from));
  }
  return std::move(graph).finish();
}

SmallVector<Value> idr::bufferize::AliasClasses::sharers(Node value) const {
  return llvm::map_to_vector(classes.members(classes.componentOf(value)),
                             [&](Node member) { return values[member.index()]; });
}

bool idr::bufferize::mayRunAfter(Operation *later, Operation *earlier, Value value,
                                 const BufferizationOptions &options) {
  // A loop around both, inside the region that defines `value`, runs `later`
  // again after `earlier` on the same instance. A loop that holds the
  // definition defines it anew on each run.
  Region *defining = value.getParentRegion();
  for (Region *region = later->getParentRegion(); region && !region->isAncestor(defining);
       region = region->getParentRegion())
    if (isRepetitive(region, options) && region->isAncestor(earlier->getParentRegion()))
      return true;

  // Otherwise by position, in the closest region that holds both: one of
  // the regions around `earlier`, which are finitely many, and the body of
  // the function that holds both is one of them.
  Region *common = nullptr;
  for (Region *region = earlier->getParentRegion(); region && !common;
       region = region->getParentRegion())
    if (region->findAncestorOpInRegion(*later))
      common = region;
  Operation *first = common->findAncestorOpInRegion(*earlier);
  Operation *second = common->findAncestorOpInRegion(*later);
  if (first == second) {
    // `later` holds `earlier`, and its operands are read before its regions
    // run; or `earlier` holds `later`, which runs inside it after them.
    if (second == later)
      return false;
    if (first == earlier)
      return true;
    // The two are in two regions of one op: `later` may follow where the
    // op's region graph reaches the region that holds it from the one that
    // holds `earlier` (a join region after the body that jumps to it, never
    // the body after one of its join regions, nor one alternative after
    // another). An op that is no region branch says nothing of the order of
    // its regions, so either may follow the other.
    auto branch = dyn_cast<RegionBranchOpInterface>(first);
    if (!branch)
      return true;
    unsigned from = idr::ownership::regionHolding(first, earlier).getRegionNumber();
    unsigned to = idr::ownership::regionHolding(first, later).getRegionNumber();
    return branch.isRegionReachable(from, to);
  }

  // In the region's one block: a function's body is one block, and so is
  // every region of the ops counting meets in it.
  return first->isBeforeInBlock(second);
}

bool idr::bufferize::isRelease(OpOperand &operand, const AnalysisState &state) {
  if (!isa<TensorLikeType>(operand.get().getType()))
    return false;
  if (isa<CallOpInterface>(operand.getOwner()))
    return true;
  return state.bufferizesToMemoryWrite(operand) &&
         state.getAliasingValues(operand).getNumAliases() == 0;
}

void idr::bufferize::prepare(Operation *program, const BufferizationOptions &options) {
  IRRewriter rewriter(program->getContext());

  // An insert of elements that hold references over the whole of its
  // destination, which it does not read, is its source in the
  // destination's shape. Kept, it would be written, where the destination
  // is read after it, into a buffer allocated with nothing in it, through a
  // copy that releases what each slot held. Upstream's model says which
  // inserts read their destination.
  {
    AnalysisState state(options);
    footprint::Vector<tensor::InsertSliceOp> whole;
    program->walk([&](tensor::InsertSliceOp insert) {
      if (idr::holdsReferences(insert.getType().getElementType()) &&
          !state.bufferizesToMemoryRead(insert.getDestMutable()))
        whole.push_back(insert);
    });
    for (tensor::InsertSliceOp insert : whole) {
      rewriter.setInsertionPoint(insert);
      Value value = insert.getSource();
      // A source of the destination's rank is of its type; one the insert
      // drops unit dimensions of gains them back.
      if (value.getType() != insert.getType())
        value = tensor::ExpandShapeOp::create(rewriter, insert.getLoc(), insert.getType(), value,
                                              expansionOf(insert));
      rewriter.replaceOp(insert, value);
    }
  }

  program->walk([&](tensor::EmptyOp empty) {
    // The first use keeps the op; one nothing uses has no first.
    SmallVector<OpOperand *> uses = takeUses(empty.getResult());
    if (uses.empty())
      return;
    for (OpOperand *use : llvm::drop_begin(uses)) {
      rewriter.setInsertionPointAfter(empty);
      Operation *own = rewriter.clone(*empty);
      rewriter.modifyOpInPlace(use->getOwner(), [&] { use->set(own->getResult(0)); });
    }
  });

  AnalysisState state(options);
  AliasClasses aliases(program, options);
  for (const AliasClasses::Release &release : aliases.releases()) {
    Operation *releaser = release.operand->getOwner();
    // The sharers are read whole before any use changes: a write given an
    // empty tensor of its own leaves the partition the program had.
    for (Value sharer : aliases.sharers(release.value)) {
      if (!isa<RankedTensorType>(sharer.getType()))
        continue;
      for (OpOperand *use : takeUses(sharer))
        if (state.bufferizesToMemoryWrite(*use) && !state.bufferizesToMemoryRead(*use) &&
            mayRunAfter(use->getOwner(), releaser, sharer, options))
          writeOwn(rewriter, *use);
    }
  }

  // A generating op's fresh destination of elements that hold references,
  // a write-only use's own among them, is placed slot by slot, no slot
  // released: it is an allocation of its own, which empty-tensor
  // elimination never makes a slice of an array whose slots hold elements.
  footprint::Vector<tensor::EmptyOp> fresh;
  program->walk([&](Operation *op) {
    if (!idr::arrays::isGenerating(op))
      return;
    for (Value out : cast<DestinationStyleOpInterface>(op).getDpsInits())
      if (auto empty = out.getDefiningOp<tensor::EmptyOp>();
          empty && idr::holdsReferences(empty.getType().getElementType()))
        fresh.push_back(empty);
  });
  for (tensor::EmptyOp empty : fresh) {
    rewriter.setInsertionPoint(empty);
    rewriter.replaceOpWithNewOp<AllocTensorOp>(empty, empty.getType(), empty.getDynamicSizes());
  }
}
