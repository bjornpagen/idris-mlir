// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.join and idr.loop, the one family of join points: their regions'
// shape, the edges upstream's control-flow interfaces read off them, and
// the lifetimes they state. Their syntax is JoinsSyntax.cpp; idr.jump,
// which transfers control to one of their join regions, is Jump.cpp.
//
// A join point is a continuation local to its function, entered only by a
// jump in tail position, never an allocated closure. Its op's region 0 is
// the body, entered once from the op; each later region is one join point,
// whose parameters are its entry block's arguments after its tokens. A
// join region ends by yielding the op's results, by jumping, or by never
// ending, as a match's regions do.
//
// A target is upstream's builtin token, which only a token producer may
// define and only a token consumer may use: the core verifier refuses any
// other definer or user, so a continuation that has become a join point
// cannot be stored, passed, returned, yielded or captured, and no walk of
// ours looks for an escape. Token i, an entry argument of one of the op's
// regions, designates join region i + 1, read off the argument's number.
//
// The two members differ in where their tokens are, which is what their
// regions may do. idr.join defines its tokens in the body alone, so no join
// region can name its own op's targets: none repeats, and none diverges.
// idr.loop begins every region with the same N tokens, so a join region may
// jump to itself or to a sibling: its regions repeat, as a loop's do, and
// where Idris did not prove they end each begins with idr.may_loop, the
// divergence of the repetition, an op of the loop's own that goes wherever
// the loop does.
//
// A jump nested in a match reaches its join point through upstream's early
// exit: every op between the jump and its target lets it through
// (PropagateControlFlowBreak), and each such op forwards it to the target
// in its own successors, so upstream's dataflow, dead code and liveness read
// the edge from the jump to the join region with no reading of ours.
//
// Each scoped value a member makes, a result or a join region's parameter,
// lives in the lifetime its own entry of `outers` states (Control/Stated.h).

#include "idr/IR/Control/Family.h"
#include "idr/IR/Control/Stated.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/RegionKindInterface.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/LoopLikeInterface.h"

namespace idr {

namespace {

template <JoinFamily Group>
unsigned targetsOf(Group op) {
  return static_cast<unsigned>(op.getJoinRegions().size());
}

// The tokens `region` of `op` begins with: in an idr.join the body's
// arguments, and none in a join region; in an idr.loop the first N
// arguments of every region.
template <JoinFamily Group>
mlir::Block::BlockArgListType tokensOf(Group op, mlir::Region &region) {
  mlir::Block::BlockArgListType args = region.front().getArguments();
  if constexpr (tokensAt<Group> == TokenScope::InBody)
    return &region == &op.getBody() ? args : args.take_front(0);
  else
    return args.take_front(std::min<size_t>(targetsOf(op), args.size()));
}

// A join region's parameters: its arguments after its tokens. The body
// takes none.
template <JoinFamily Group>
mlir::Block::BlockArgListType parametersOf(Group op, mlir::Region &region) {
  return region.front().getArguments().drop_front(tokensOf(op, region).size());
}

// The join region `token` designates, if it is a token of `op`: an
// argument among the tokens one of its regions begins with.
template <JoinFamily Group>
mlir::Region *targetOf(Group op, mlir::BlockArgument token) {
  mlir::Region *region = token.getOwner()->getParent();
  if (region->getParentOp() != op.getOperation() ||
      token.getArgNumber() >= tokensOf(op, *region).size())
    return nullptr;
  return &op.getJoinRegions()[token.getArgNumber()];
}

// The region signatures: the body binds exactly the N tokens of an
// idr.join, or begins with the N of an idr.loop and binds nothing else;
// every region of an idr.loop begins with them; no parameter is a token,
// since a jump passes none. Each join region has its erased binders, an
// empty list where it binds no index variable.
template <JoinFamily Group>
mlir::LogicalResult verifyGroup(Group op) {
  unsigned targets = targetsOf(op);
  if (targets == 0)
    return op.emitOpError("expects at least one join region");
  if (op.getBinders().size() != targets)
    return op.emitOpError("expects the erased binders of each of its ") << targets
                                                                         << " join regions";
  for (mlir::Region &region : op->getRegions()) {
    mlir::ValueRange tokens = tokensOf(op, region);
    bool leads = &region == &op.getBody() || tokensAt<Group> == TokenScope::InEveryRegion;
    if (leads && tokens.size() != targets)
      return op.emitOpError("region #") << region.getRegionNumber() << " must begin with "
                                        << targets << " tokens, one per join region";
    if (!llvm::all_of(tokens.getTypes(), llvm::IsaPred<mlir::TokenType>))
      return op.emitOpError("region #")
             << region.getRegionNumber() << " must begin with one token per join region";
    if (llvm::any_of(mlir::ValueRange(parametersOf(op, region)).getTypes(),
                     llvm::IsaPred<mlir::TokenType>))
      return op.emitOpError("region #") << region.getRegionNumber()
                                        << " takes a token as a parameter, which no jump passes";
  }
  if (!parametersOf(op, op.getBody()).empty())
    return op.emitOpError("expects a body that binds its tokens alone");
  return lifetimes::verifyOuters(op, 0);
}

// Entered at the body; from a yield, the op's results; from a jump to one
// of its own join regions, that region; from a jump to an enclosing join
// point, what that point's op says, as every op the jump crosses does.
template <JoinFamily Group>
void successorsOf(Group op, mlir::RegionBranchPoint point,
                  llvm::SmallVectorImpl<mlir::RegionSuccessor> &regions) {
  if (point.isParent()) {
    regions.emplace_back(&op.getBody());
    return;
  }
  mlir::RegionBranchTerminatorOpInterface terminator = point.getTerminatorPredecessorOrNull();
  if (mlir::terminatorPropagatesThrough(terminator, op)) {
    mlir::appendPropagatedTerminatorSuccessors(terminator, op, regions);
    return;
  }
  if (auto jump = llvm::dyn_cast<JumpOp>(terminator.getOperation())) {
    regions.emplace_back(targetOf(op, llvm::cast<mlir::BlockArgument>(jump.getTarget())));
    return;
  }
  regions.push_back(mlir::RegionSuccessor(op.getOperation()));
}

template <JoinFamily Group>
mlir::ValueRange inputsOf(Group op, mlir::RegionSuccessor successor) {
  if (successor.isOperation())
    return op->getResults();
  return parametersOf(op, *successor.getSuccessor());
}

// The body once; a join region of an idr.join at most once, as only the
// body or another op's region may jump to it; a join region of an idr.loop
// any number of times.
template <JoinFamily Group>
void boundsOf(Group op, llvm::SmallVectorImpl<mlir::InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
  for (unsigned i = 0, n = targetsOf(op); i < n; ++i) {
    if constexpr (tokensAt<Group> == TokenScope::InBody)
      bounds.emplace_back(0, 1);
    else
      bounds.push_back(mlir::InvocationBounds::getUnknown());
  }
}

// What enters a region, read off the tokens' uses instead of every branch
// point under the op: the op itself enters the body; the jumps that use
// token i enter join region i + 1; the yields that end the op's own regions
// give its results.
template <JoinFamily Group>
void predecessorsOf(Group op, mlir::RegionSuccessor successor,
                    llvm::SmallVectorImpl<mlir::RegionBranchPoint> &predecessors) {
  if (successor.isOperation()) {
    for (mlir::Region &region : op->getRegions())
      if (auto yield = llvm::dyn_cast<YieldOp>(region.front().getTerminator()))
        predecessors.emplace_back(
            llvm::cast<mlir::RegionBranchTerminatorOpInterface>(yield.getOperation()));
    return;
  }
  mlir::Region *target = successor.getSuccessor();
  if (target == &op.getBody()) {
    predecessors.push_back(mlir::RegionBranchPoint::parent());
    return;
  }
  unsigned index = target->getRegionNumber() - 1;
  for (mlir::Region &region : op->getRegions()) {
    mlir::Block::BlockArgListType tokens = tokensOf(op, region);
    if (index >= tokens.size())
      continue;
    for (mlir::Operation *user : tokens[index].getUsers())
      predecessors.emplace_back(llvm::cast<mlir::RegionBranchTerminatorOpInterface>(user));
  }
}

} // namespace

//===----------------------------------------------------------------------===//
// idr.join
//===----------------------------------------------------------------------===//

mlir::LogicalResult JoinOp::verifyRegions() { return verifyGroup(*this); }

void JoinOp::getSuccessorRegions(mlir::RegionBranchPoint point,
                                 llvm::SmallVectorImpl<mlir::RegionSuccessor> &regions) {
  successorsOf(*this, point, regions);
}

mlir::ValueRange JoinOp::getSuccessorInputs(mlir::RegionSuccessor successor) {
  return inputsOf(*this, successor);
}

void JoinOp::getRegionInvocationBounds(llvm::ArrayRef<mlir::Attribute>,
                                       llvm::SmallVectorImpl<mlir::InvocationBounds> &bounds) {
  boundsOf(*this, bounds);
}

void JoinOp::getPredecessors(mlir::RegionSuccessor successor,
                             llvm::SmallVectorImpl<mlir::RegionBranchPoint> &predecessors) {
  predecessorsOf(*this, successor, predecessors);
}

// A jump's arguments are typed in the jump's scope and a parameter in its
// join region's, whose erased binders the jump instantiates: an argument
// is an instance of its parameter's pattern. The jump's verifier and the
// function's scope walk check the exact instance. Each value crosses at
// the hold of the place it enters where the program's stage lets a hold
// that fits stand (crossedAs).
bool JoinOp::areTypesCompatible(mlir::Type lhs, mlir::Type rhs) {
  mlir::Type crossed = crossedAs(getOperation(), lhs, rhs);
  return crossed == rhs || families::instanceOf(crossed, rhs);
}

mlir::Region *JoinOp::getTarget(mlir::BlockArgument token) { return targetOf(*this, token); }

mlir::Block::BlockArgListType JoinOp::getTokens(mlir::Region &region) {
  return tokensOf(*this, region);
}

mlir::Block::BlockArgListType JoinOp::getParameters(mlir::Region &region) {
  return parametersOf(*this, region);
}

llvm::ArrayRef<families::Sort> JoinOp::getBoundSorts(mlir::Region &region) {
  if (&region == &getBody())
    return {};
  return llvm::cast<IndexBindersAttr>(getBinders()[region.getRegionNumber() - 1]).getSorts();
}

mlir::Value JoinOp::getStatedLifetime(mlir::Value made) {
  return lifetimes::statedOuter(*this, made, 0);
}

void JoinOp::setStatedLifetime(mlir::Value made, mlir::Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

unsigned JoinOp::getScopedBindings() { return control::scopedBindings(*this); }

std::optional<unsigned> JoinOp::getBindingEntry(mlir::Value made) {
  return control::bindingEntry(*this, made);
}


//===----------------------------------------------------------------------===//
// idr.loop
//===----------------------------------------------------------------------===//

mlir::LogicalResult LoopOp::verifyRegions() { return verifyGroup(*this); }

void LoopOp::getSuccessorRegions(mlir::RegionBranchPoint point,
                                 llvm::SmallVectorImpl<mlir::RegionSuccessor> &regions) {
  successorsOf(*this, point, regions);
}

mlir::ValueRange LoopOp::getSuccessorInputs(mlir::RegionSuccessor successor) {
  return inputsOf(*this, successor);
}

void LoopOp::getRegionInvocationBounds(llvm::ArrayRef<mlir::Attribute>,
                                       llvm::SmallVectorImpl<mlir::InvocationBounds> &bounds) {
  boundsOf(*this, bounds);
}

void LoopOp::getPredecessors(mlir::RegionSuccessor successor,
                             llvm::SmallVectorImpl<mlir::RegionBranchPoint> &predecessors) {
  predecessorsOf(*this, successor, predecessors);
}

bool LoopOp::areTypesCompatible(mlir::Type lhs, mlir::Type rhs) {
  mlir::Type crossed = crossedAs(getOperation(), lhs, rhs);
  return crossed == rhs || families::instanceOf(crossed, rhs);
}

mlir::Region *LoopOp::getTarget(mlir::BlockArgument token) { return targetOf(*this, token); }

mlir::Block::BlockArgListType LoopOp::getTokens(mlir::Region &region) {
  return tokensOf(*this, region);
}

mlir::Block::BlockArgListType LoopOp::getParameters(mlir::Region &region) {
  return parametersOf(*this, region);
}

llvm::ArrayRef<families::Sort> LoopOp::getBoundSorts(mlir::Region &region) {
  if (&region == &getBody())
    return {};
  return llvm::cast<IndexBindersAttr>(getBinders()[region.getRegionNumber() - 1]).getSorts();
}

// The loop's regions for upstream's loop utilities (LICM among them): its
// join regions, which repeat; the body runs once.
llvm::SmallVector<mlir::Region *> LoopOp::getLoopRegions() {
  return llvm::map_to_vector(getJoinRegions(), [](mlir::Region &region) { return &region; });
}

mlir::Value LoopOp::getStatedLifetime(mlir::Value made) {
  return lifetimes::statedOuter(*this, made, 0);
}

void LoopOp::setStatedLifetime(mlir::Value made, mlir::Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

unsigned LoopOp::getScopedBindings() { return control::scopedBindings(*this); }

std::optional<unsigned> LoopOp::getBindingEntry(mlir::Value made) {
  return control::bindingEntry(*this, made);
}

} // namespace idr
