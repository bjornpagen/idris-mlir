// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.join and idr.loop, the one family of join points, and idr.jump,
// which transfers control to one of their join regions.
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
// jump to itself or to a sibling: its regions repeat, as a loop's do.
//
// A jump nested in a match reaches its join point through upstream's early
// exit: every op between the jump and its target lets it through
// (PropagateControlFlowBreak), and each such op forwards it to the target
// in its own successors, so upstream's dataflow, dead code and liveness read
// the edge from the jump to the join region with no reading of ours.

#include "idr/IR/Control/Family.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/RegionKindInterface.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/LoopLikeInterface.h"

using namespace mlir;
using namespace idr;

namespace {

// The members of the family are monomorphic: one instantiation of each
// template below per member, chosen by the member's constant, which the
// generator writes into the family's carrier.
template <typename Group>
concept JoinFamily = requires { JoinPointsFamily<Group>::tokens; };

template <typename Group>
inline constexpr TokenScope tokensAt = JoinPointsFamily<Group>::tokens;

template <JoinFamily Group>
unsigned targetsOf(Group op) {
  return static_cast<unsigned>(op.getJoinRegions().size());
}

// The tokens `region` of `op` begins with: in an idr.join the body's
// arguments, and none in a join region; in an idr.loop the first N
// arguments of every region.
template <JoinFamily Group>
Block::BlockArgListType tokensOf(Group op, Region &region) {
  Block::BlockArgListType args = region.front().getArguments();
  if constexpr (tokensAt<Group> == TokenScope::InBody)
    return &region == &op.getBody() ? args : args.take_front(0);
  else
    return args.take_front(std::min<size_t>(targetsOf(op), args.size()));
}

// A join region's parameters: its arguments after its tokens. The body
// takes none.
template <JoinFamily Group>
Block::BlockArgListType parametersOf(Group op, Region &region) {
  return region.front().getArguments().drop_front(tokensOf(op, region).size());
}

// The join region `token` designates, if it is a token of `op`: an
// argument among the tokens one of its regions begins with.
template <JoinFamily Group>
Region *targetOf(Group op, BlockArgument token) {
  Region *region = token.getOwner()->getParent();
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
LogicalResult verifyGroup(Group op) {
  unsigned targets = targetsOf(op);
  if (targets == 0)
    return op.emitOpError("expects at least one join region");
  if (op.getBinders().size() != targets)
    return op.emitOpError("expects the erased binders of each of its ") << targets
                                                                         << " join regions";
  for (Region &region : op->getRegions()) {
    Block::BlockArgListType tokens = tokensOf(op, region);
    bool leads = &region == &op.getBody() || tokensAt<Group> == TokenScope::InEveryRegion;
    if (leads && tokens.size() != targets)
      return op.emitOpError("region #") << region.getRegionNumber() << " must begin with "
                                        << targets << " tokens, one per join region";
    if (!llvm::all_of(tokens.getTypes(), llvm::IsaPred<TokenType>))
      return op.emitOpError("region #")
             << region.getRegionNumber() << " must begin with one token per join region";
    if (llvm::any_of(parametersOf(op, region).getTypes(), llvm::IsaPred<TokenType>))
      return op.emitOpError("region #") << region.getRegionNumber()
                                        << " takes a token as a parameter, which no jump passes";
  }
  if (!parametersOf(op, op.getBody()).empty())
    return op.emitOpError("expects a body that binds its tokens alone");
  return success();
}

// Entered at the body; from a yield, the op's results; from a jump to one
// of its own join regions, that region; from a jump to an enclosing join
// point, what that point's op says, as every op the jump crosses does.
template <JoinFamily Group>
void successorsOf(Group op, RegionBranchPoint point, SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent()) {
    regions.emplace_back(&op.getBody());
    return;
  }
  RegionBranchTerminatorOpInterface terminator = point.getTerminatorPredecessorOrNull();
  if (terminatorPropagatesThrough(terminator, op)) {
    appendPropagatedTerminatorSuccessors(terminator, op, regions);
    return;
  }
  if (auto jump = dyn_cast<JumpOp>(terminator.getOperation())) {
    regions.emplace_back(targetOf(op, cast<BlockArgument>(jump.getTarget())));
    return;
  }
  regions.push_back(RegionSuccessor(op.getOperation()));
}

template <JoinFamily Group>
ValueRange inputsOf(Group op, RegionSuccessor successor) {
  if (successor.isOperation())
    return op->getResults();
  return parametersOf(op, *successor.getSuccessor());
}

// The body once; a join region of an idr.join at most once, as only the
// body or another op's region may jump to it; a join region of an idr.loop
// any number of times.
template <JoinFamily Group>
void boundsOf(Group op, SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
  for (unsigned i = 0, n = targetsOf(op); i < n; ++i) {
    if constexpr (tokensAt<Group> == TokenScope::InBody)
      bounds.emplace_back(0, 1);
    else
      bounds.push_back(InvocationBounds::getUnknown());
  }
}

// What enters a region, read off the tokens' uses instead of every branch
// point under the op: the op itself enters the body; the jumps that use
// token i enter join region i + 1; the yields that end the op's own regions
// give its results.
template <JoinFamily Group>
void predecessorsOf(Group op, RegionSuccessor successor,
                    SmallVectorImpl<RegionBranchPoint> &predecessors) {
  if (successor.isOperation()) {
    for (Region &region : op->getRegions())
      if (auto yield = dyn_cast<YieldOp>(region.front().getTerminator()))
        predecessors.emplace_back(cast<RegionBranchTerminatorOpInterface>(yield.getOperation()));
    return;
  }
  Region *target = successor.getSuccessor();
  if (target == &op.getBody()) {
    predecessors.push_back(RegionBranchPoint::parent());
    return;
  }
  unsigned index = target->getRegionNumber() - 1;
  for (Region &region : op->getRegions()) {
    Block::BlockArgListType tokens = tokensOf(op, region);
    if (index >= tokens.size())
      continue;
    for (Operation *user : tokens[index].getUsers())
      predecessors.emplace_back(cast<RegionBranchTerminatorOpInterface>(user));
  }
}

// `(%k0, %k1)`, a region's tokens, given the token type.
ParseResult parseTokens(OpAsmParser &parser, SmallVectorImpl<OpAsmParser::Argument> &args) {
  Type token = parser.getBuilder().getType<TokenType>();
  return parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, [&] {
    if (parser.parseArgument(args.emplace_back()))
      return failure();
    args.back().type = token;
    return success();
  });
}

void printValues(OpAsmPrinter &printer, ValueRange values) {
  printer << '(';
  llvm::interleaveComma(values, printer, [&](Value value) { printer.printOperand(value); });
  printer << ')';
}

// `idr.join tokens(%k0, ...) -> (T, ...) attr-dict {body} join(%p: A, ...) {region} ...`;
// an idr.loop's join regions also print their own tokens:
// `join tokens(%a0, ...)(%p: A, ...) {region}`. The erased binders are a
// property, printed in the attribute dictionary.
template <JoinFamily Group>
ParseResult parseGroup(OpAsmParser &parser, OperationState &state) {
  SmallVector<OpAsmParser::Argument> body;
  SmallVector<Type> results;
  if (parser.parseKeyword("tokens") || parseTokens(parser, body) || parser.parseArrow() ||
      parser.parseLParen())
    return failure();
  if (failed(parser.parseOptionalRParen())) {
    if (parser.parseTypeList(results) || parser.parseRParen())
      return failure();
  }
  state.addTypes(results);
  if (parser.parseOptionalAttrDictWithKeyword(state.attributes) ||
      parser.parseRegion(*state.addRegion(), body))
    return failure();
  while (succeeded(parser.parseOptionalKeyword("join"))) {
    SmallVector<OpAsmParser::Argument> args;
    if constexpr (tokensAt<Group> == TokenScope::InEveryRegion) {
      if (parser.parseKeyword("tokens") || parseTokens(parser, args))
        return failure();
    }
    if (parser.parseArgumentList(args, OpAsmParser::Delimiter::Paren, /*allowType=*/true) ||
        parser.parseRegion(*state.addRegion(), args))
      return failure();
  }
  return success();
}

template <JoinFamily Group>
void printGroup(Group op, OpAsmPrinter &printer) {
  printer << " tokens";
  printValues(printer, tokensOf(op, op.getBody()));
  printer << " -> (";
  llvm::interleaveComma(op->getResultTypes(), printer);
  printer << ')';
  printer.printOptionalAttrDictWithKeyword(op->getAttrs());
  printer << ' ';
  printer.printRegion(op.getBody(), /*printEntryBlockArgs=*/false);
  for (Region &region : op.getJoinRegions()) {
    printer << " join";
    if constexpr (tokensAt<Group> == TokenScope::InEveryRegion) {
      printer << " tokens";
      printValues(printer, tokensOf(op, region));
    }
    printer << '(';
    llvm::interleaveComma(parametersOf(op, region), printer,
                          [&](BlockArgument arg) { printer.printRegionArgument(arg); });
    printer << ") ";
    printer.printRegion(region, /*printEntryBlockArgs=*/false);
  }
}

} // namespace

//===----------------------------------------------------------------------===//
// idr.join
//===----------------------------------------------------------------------===//

LogicalResult JoinOp::verifyRegions() { return verifyGroup(*this); }

void JoinOp::getSuccessorRegions(RegionBranchPoint point,
                                 SmallVectorImpl<RegionSuccessor> &regions) {
  successorsOf(*this, point, regions);
}

ValueRange JoinOp::getSuccessorInputs(RegionSuccessor successor) {
  return inputsOf(*this, successor);
}

void JoinOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                       SmallVectorImpl<InvocationBounds> &bounds) {
  boundsOf(*this, bounds);
}

void JoinOp::getPredecessors(RegionSuccessor successor,
                             SmallVectorImpl<RegionBranchPoint> &predecessors) {
  predecessorsOf(*this, successor, predecessors);
}

// A jump's arguments are typed in the jump's scope and a parameter in its
// join region's, whose erased binders the jump instantiates: an argument
// is an instance of its parameter's pattern. The jump's verifier and the
// function's scope walk check the exact instance.
bool JoinOp::areTypesCompatible(Type lhs, Type rhs) {
  return lhs == rhs || families::instanceOf(lhs, rhs);
}

Region *JoinOp::getTarget(BlockArgument token) { return targetOf(*this, token); }

Block::BlockArgListType JoinOp::getTokens(Region &region) { return tokensOf(*this, region); }

Block::BlockArgListType JoinOp::getParameters(Region &region) {
  return parametersOf(*this, region);
}

ArrayRef<families::Sort> JoinOp::getBoundSorts(Region &region) {
  if (&region == &getBody())
    return {};
  return cast<IndexBindersAttr>(getBinders()[region.getRegionNumber() - 1]).getSorts();
}

ParseResult JoinOp::parse(OpAsmParser &parser, OperationState &state) {
  return parseGroup<JoinOp>(parser, state);
}

void JoinOp::print(OpAsmPrinter &printer) { printGroup(*this, printer); }

//===----------------------------------------------------------------------===//
// idr.loop
//===----------------------------------------------------------------------===//

LogicalResult LoopOp::verifyRegions() { return verifyGroup(*this); }

void LoopOp::getSuccessorRegions(RegionBranchPoint point,
                                 SmallVectorImpl<RegionSuccessor> &regions) {
  successorsOf(*this, point, regions);
}

ValueRange LoopOp::getSuccessorInputs(RegionSuccessor successor) {
  return inputsOf(*this, successor);
}

void LoopOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                       SmallVectorImpl<InvocationBounds> &bounds) {
  boundsOf(*this, bounds);
}

void LoopOp::getPredecessors(RegionSuccessor successor,
                             SmallVectorImpl<RegionBranchPoint> &predecessors) {
  predecessorsOf(*this, successor, predecessors);
}

bool LoopOp::areTypesCompatible(Type lhs, Type rhs) {
  return lhs == rhs || families::instanceOf(lhs, rhs);
}

Region *LoopOp::getTarget(BlockArgument token) { return targetOf(*this, token); }

Block::BlockArgListType LoopOp::getTokens(Region &region) { return tokensOf(*this, region); }

Block::BlockArgListType LoopOp::getParameters(Region &region) {
  return parametersOf(*this, region);
}

ArrayRef<families::Sort> LoopOp::getBoundSorts(Region &region) {
  if (&region == &getBody())
    return {};
  return cast<IndexBindersAttr>(getBinders()[region.getRegionNumber() - 1]).getSorts();
}

// The loop's regions for upstream's loop utilities (LICM among them): its
// join regions, which repeat; the body runs once.
SmallVector<Region *> LoopOp::getLoopRegions() {
  return llvm::map_to_vector(getJoinRegions(), [](Region &region) { return &region; });
}

ParseResult LoopOp::parse(OpAsmParser &parser, OperationState &state) {
  return parseGroup<LoopOp>(parser, state);
}

void LoopOp::print(OpAsmPrinter &printer) { printGroup(*this, printer); }

//===----------------------------------------------------------------------===//
// idr.jump
//===----------------------------------------------------------------------===//

// Its target is the join region its token designates, read off the token's
// owner and number: the token is an entry argument of a region of a join
// point's op, so dominance already puts the jump inside that op. Every op
// between the jump and the owner must let a jump through. The arguments are
// the target's parameters: equal, where the target binds no index
// variable; an instance under the jump's terms otherwise, which the
// function's scope walk checks, since the substitution reads the depth of
// the scope.
LogicalResult JumpOp::verify() {
  // A token producer of another dialect may define its token as a result.
  auto token = dyn_cast<BlockArgument>(getTarget());
  Operation *owner = token ? token.getOwner()->getParentOp() : nullptr;
  auto points = dyn_cast_or_null<JoinPointsOpInterface>(owner);
  Region *target = points ? points.getTarget(token) : nullptr;
  if (!target)
    return emitOpError("expects a token that designates a join region");
  for (Operation *op = (*this)->getParentOp(); op != owner; op = op->getParentOp())
    if (!op->hasTrait<OpTrait::PropagateControlFlowBreak>())
      return emitOpError("crosses ") << op->getName() << ", which lets no jump through";
  Block::BlockArgListType parameters = points.getParameters(*target);
  if (getArgs().size() != parameters.size())
    return emitOpError("passes ") << getArgs().size() << " arguments to a join region of "
                                  << parameters.size() << " parameters";
  if (cast<ErasedBinderOpInterface>(owner).getBoundSorts(*target).empty() &&
      TypeRange(getArgs()) != TypeRange(parameters.getTypes()))
    return emitOpError("passes arguments of types ")
           << getArgs().getTypes() << " to parameters of types " << parameters.getTypes();
  return success();
}

// The values a jump passes become its target's parameters.
MutableOperandRange JumpOp::getMutableSuccessorOperands(RegionSuccessor) {
  return getArgsMutable();
}

// The op whose join region the token designates.
SmallVector<Operation *> JumpOp::getPotentialTargets() {
  return {cast<BlockArgument>(getTarget()).getOwner()->getParentOp()};
}
