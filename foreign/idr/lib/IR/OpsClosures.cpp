// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Closures and suspensions. idr.fn.closure captures a function's leading
// parameters, and idr.fn.apply runs one. idr.lazy.suspend builds a cell and
// does not run its function; idr.lazy.force reads that cell, and the first
// entry computes the value and leaves it there. After idr-defunctionalize
// the cell is a value of a memo family, a force is a call of the family's
// dispatch, and the dispatch exchanges the cell's state through
// idr.memo.run, which moves the captures out and the value in. A
// suspension of a value that already exists, idr.lazy.delay, is evaluated
// where it is built: forcing it computes nothing, and the force is the
// value.
//
// A suspension has no fold: the cell it builds is the one thing that
// changes while references to it live, so folding one into a constant
// would make every run share one cell whose forced value lives until the
// program ends, and a trusted library's effect inside it would run once
// instead of where its value is demanded. Nor do these ops carry rewrite
// patterns: defunctionalization replaces every one of them before any
// simplification runs, and what is left of a force after it (a call of a
// known label, a cell forced in one case) is the e-graph's.
//
// The exchange moves a memoized label's captures out of the cell's fields,
// so it takes the cell refined to the label's state, as its dispatch's case
// binds it: the captures are at the label's binders, the state the
// refinement's. Each capture leaves its field empty and holds the field's
// reference, so its hold is its own and never the cell's (Closures.h).
// Its steps, idr.memo.take and idr.memo.store, are the same exchange for a
// pass that cannot keep its region.

#include "idr/IR/Closures.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/PatternMatch.h"

#include <concepts>

using namespace mlir;
using namespace idr;

namespace {

// The signature of the function a closure or a suspension names, at the
// terms its index variables take there, one per binder, as a call's index
// arguments give them, read through the function's extents as a call reads
// its callee; failure, reported, where none fits.
FailureOr<FunctionType> calleeAt(Operation *op, FlatSymbolRefAttr callee, IndexArgsAttr args,
                                 SymbolTableCollection &symbols) {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(op, callee);
  if (!fn) {
    op->emitOpError("refers to an unknown function ") << callee;
    return failure();
  }
  std::size_t binding = fn.getBinders().getSorts().size();
  if (args.getCount() != binding) {
    op->emitOpError("gives ") << args.getCount() << " index terms to " << callee
                              << ", which binds " << binding;
    return failure();
  }
  return families::substitute(fn.getFunctionType(), fn.getExtentsAttr(), args);
}

// The cell is in the state of a label that memoizes: a label run by name
// leaves its cell as it is, so it has no exchange, and running and forced,
// the states past a memo family's labels, are none an exchange starts from.
LogicalResult memoizes(Operation *op, DataType cell) {
  ArrayRef<families::MemoLabelDecl> labels = cell.memo()->labels();
  auto state = static_cast<unsigned>(*cell.singleTag());
  if (state >= labels.size() || labels[state].mode != idr::Mode::Memoized)
    return op->emitOpError("exchanges the state ")
           << state << " of " << cell << ", which is no label of the cell that memoizes";
  return success();
}

// What the cell's forced state holds at the cell's indices: the value an
// exchange moves in.
Type forcedAt(DataType cell) {
  return cell.determinedFields(cell.memo()->forced())->front();
}

// Whether captures typed `bound` are the ones an exchange moves out as
// `made` (capturesMovedOut): one per field, each at its field's carrier and
// uses, at any hold. A capture holds the reference its field held, so its
// hold is what a pass proves of it (a claim exclusivity writes) or learns
// of where what it holds lives, never what the cell is held at: a view of
// the cell (borrowing's) or a claim on it says that of the cell alone.
bool standAsCaptures(TypeRange made, TypeRange bound) { return sameCarriers(made, bound); }

// What an exchange does with capture `index` of the cell it holds: the
// capture moves out of its field of the label's state into `capture`, with
// the reference the field held, and the field holds nothing from then on,
// the cell running until its value moves in; the cell itself is only read,
// its reference kept by whoever holds it. A part moved out of a value left
// alive is a part of a value read whose place the op empties, as an array's
// take moves an element out of its slot.
template <class Exchange>
  requires requires(Exchange op) {
    { op.getCell() } -> std::convertible_to<Value>;
    { op.getDataType() } -> std::same_as<DataType>;
    { op.getTag() } -> std::same_as<Tag>;
  }
void movedOut(Exchange op, unsigned index, Value capture, FlowEdges &edges) {
  Value cell = op.getCell();
  FlowAnchor field = FlowAnchor::fieldOf(op.getDataType(), op.getTag(), index);
  edges.flow(FlowSource::partOf(cell, field), FlowPlace::of(capture));
  edges.overwrite(cell, field);
}

} // namespace

// A memo family's cell in one known state, as a case of its dispatch binds
// it: what an exchange reads the captures of and writes the state of.
bool idr::isMemoState(Type type) {
  DataType data = dataTypeOf(type);
  return data && data.memo() && data.singleTag();
}

// Each field as the cell's memory holds it, re-packed as any read of it
// is: read from the cell's carrier at its bare grade, so counted and
// claiming nothing whatever the cell is held at, but its own cells
// unshared where the re-pack builds them; at the field's own uses.
std::optional<SmallVector<Type>> idr::capturesMovedOut(Type cell) {
  DataType data = dataTypeOf(cell);
  ArrayRef<Type> fields = data.ctor(*data.singleTag()).fields;
  SmallVector<Type> captures;
  for (auto [index, field] : llvm::enumerate(fields)) {
    std::optional<Type> read = fieldReadType(data, static_cast<unsigned>(index));
    if (!read)
      return std::nullopt;
    captures.push_back(atUses(*read, usesOf(field)));
  }
  return captures;
}

//===----------------------------------------------------------------------===//
// The carriers
//===----------------------------------------------------------------------===//

void FnType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("f"); }
void LazyType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("lazy"); }

//===----------------------------------------------------------------------===//
// #idr.closure
//===----------------------------------------------------------------------===//

// A constant closure's function and captures are upstream's attributes, and
// read and print as upstream's do: `@f`, then `[1 : i64, #idr.big<7>]`.
FailureOr<FlatSymbolRefAttr> idr::parseCalleeRef(AsmParser &parser) {
  FlatSymbolRefAttr callee;
  if (parser.parseAttribute(callee))
    return failure();
  return callee;
}

void idr::printCalleeRef(AsmPrinter &printer, FlatSymbolRefAttr value) {
  printer.printAttributeWithoutType(value);
}

FailureOr<ArrayAttr> idr::parseCaptures(AsmParser &parser) {
  ArrayAttr captures;
  if (parser.parseAttribute(captures))
    return failure();
  return captures;
}

void idr::printCaptures(AsmPrinter &printer, ArrayAttr value) {
  printer.printAttributeWithoutType(value);
}

//===----------------------------------------------------------------------===//
// idr.fn.closure
//===----------------------------------------------------------------------===//

// The callee's signature at the closure's index terms: its leading
// parameters are the captures, and the rest of it is the closure's carrier,
// whatever quantity the captures give it (ResultUsesMaxOf).
LogicalResult FnClosureOp::verifySymbolUses(SymbolTableCollection &symbols) {
  FailureOr<FunctionType> at = calleeAt(*this, getCalleeAttr(), getIndexArgs(), symbols);
  if (failed(at))
    return failure();
  ArrayRef<Type> inputs = at->getInputs();
  size_t captures = getCaptures().size();
  if (captures > inputs.size() ||
      !llvm::equal(getCaptures().getTypes(), inputs.take_front(captures)))
    return emitOpError("captures ")
           << getCaptures().getTypes() << ", which are not the leading parameters of "
           << getCalleeAttr();
  auto expected = FnType::get(getContext(), inputs.drop_front(captures), at->getResults());
  if (expected != unrestricted(getType()))
    return emitOpError("has type ") << getType() << ", but a closure of " << getCalleeAttr()
                                    << " with these captures is " << expected;
  return success();
}

// A closure of constants is an immutable value nothing reads the identity
// of, so it is the constant idr.constant holds at its type. A capture is a
// constant the dialect builds at its type, never a poison, the program's
// value where control never arrives, which no constant holds. Essential,
// two closures: a constant closure holds no index terms, so one at terms
// stays an op.
OpFoldResult FnClosureOp::fold(FoldAdaptor adaptor) {
  if (getIndexArgs().getCount() != 0)
    return {};
  for (auto [capture, operand] : llvm::zip_equal(adaptor.getCaptures(), getCaptures()))
    if (!capture || !fold::buildable(capture, operand.getType()))
      return {};
  auto captures = ArrayAttr::get(getContext(), adaptor.getCaptures());
  return fold::held(ClosureAttr::get(getContext(), getCalleeAttr(), captures), getType());
}

//===----------------------------------------------------------------------===//
// idr.lazy.suspend
//===----------------------------------------------------------------------===//

// The callee's signature at the suspension's index terms: every parameter
// is a capture, and the function's one result is the suspension's value.
LogicalResult LazySuspendOp::verifySymbolUses(SymbolTableCollection &symbols) {
  FailureOr<FunctionType> at = calleeAt(*this, getCalleeAttr(), getIndexArgs(), symbols);
  if (failed(at))
    return failure();
  if (!llvm::equal(getCaptures().getTypes(), at->getInputs()))
    return emitOpError("captures ")
           << getCaptures().getTypes() << ", which are not the parameters of " << getCalleeAttr();
  Type value = cast<LazyType>(unrestricted(getResult().getType())).getValue();
  if (at->getNumResults() != 1 || unrestricted(at->getResult(0)) != unrestricted(value))
    return emitOpError("suspends ") << getCalleeAttr() << ", which returns " << at->getResults()
                                    << ", where " << value << " is expected";
  return success();
}

//===----------------------------------------------------------------------===//
// idr.lazy.delay
//===----------------------------------------------------------------------===//

// An evaluated suspension holds its operand: the suspension's value is the
// operand's carrier, at the quantity a force gives it.
LogicalResult LazyDelayOp::verify() {
  Type held = cast<LazyType>(unrestricted(getResult().getType())).getValue();
  if (unrestricted(held) != unrestricted(getValue().getType()))
    return emitOpError("holds ") << getValue().getType() << " in a suspension of " << held;
  return success();
}

//===----------------------------------------------------------------------===//
// idr.lazy.force
//===----------------------------------------------------------------------===//

// The force of an evaluated suspension is the value it holds. A value
// used once is taken this way only by the suspension's one force, which
// would otherwise use it twice.
OpFoldResult LazyForceOp::fold(FoldAdaptor) {
  auto delay = getSuspension().getDefiningOp<LazyDelayOp>();
  if (!delay)
    return {};
  Value value = delay.getValue();
  if (value.getType() != getType())
    return {};
  if (isLinear(value.getType()) && !delay.getResult().hasOneUse())
    return {};
  return value;
}

Value LazyForceOp::getLabelCarrier() { return getSuspension(); }

// The force gives the value its suspension holds, at the quantity the
// force gives it.
LogicalResult LazyForceOp::verify() {
  Type held = cast<LazyType>(unrestricted(getSuspension().getType())).getValue();
  if (unrestricted(held) != unrestricted(getType()))
    return emitOpError("gives ") << getType() << " where its suspension holds " << held;
  return success();
}

//===----------------------------------------------------------------------===//
// idr.fn.apply
//===----------------------------------------------------------------------===//

// Upstream's indirect call: the callee is the closure, a value, and the
// arguments are the operands after it.
CallInterfaceCallable FnApplyOp::getCallableForCallee() { return getCallee(); }
void FnApplyOp::setCalleeFromCallable(CallInterfaceCallable callee) {
  getCalleeMutable().set(cast<Value>(callee));
}
Operation::operand_range FnApplyOp::getArgOperands() { return getArgs(); }
MutableOperandRange FnApplyOp::getArgOperandsMutable() { return getArgsMutable(); }

Value FnApplyOp::getLabelCarrier() { return getCallee(); }

// The arguments are the closure's inputs and the results its results, each
// used as often as its type says; what each holds is counting's to grade.
LogicalResult FnApplyOp::verify() {
  auto fn = cast<FnType>(unrestricted(getCallee().getType()));
  if (!sameCarriers(fn.getInputs(), getArgs().getTypes()))
    return emitOpError("applies ") << fn << " to " << getArgs().getTypes();
  if (!sameCarriers(fn.getResults(), getResultTypes()))
    return emitOpError("gives ") << getResultTypes() << " where the closure gives " << fn;
  return success();
}

//===----------------------------------------------------------------------===//
// idr.memo.run
//===----------------------------------------------------------------------===//

DataType MemoRunOp::getDataType() { return dataTypeOf(getCell().getType()); }
Tag MemoRunOp::getTag() { return *getDataType().singleTag(); }

// The cell is refined to a label that memoizes; the region binds that
// label's captures as the exchange moves them out, each at its own hold.
LogicalResult MemoRunOp::verify() {
  if (failed(memoizes(*this, getDataType())))
    return failure();
  std::optional<SmallVector<Type>> captures = capturesMovedOut(getCell().getType());
  if (!captures)
    return emitOpError("exchanges ") << getCell().getType()
                                     << ", whose refinement gives its label no binders";
  Block &body = getRegion().front();
  if (!standAsCaptures(*captures, body.getArgumentTypes()))
    return emitOpError("binds captures ")
           << body.getArgumentTypes() << " where its label's fields move out as "
           << TypeRange(*captures) << ", at any hold";
  return success();
}

// The region ends in idr.memo.yield of the value the cell's forced state
// holds at its indices, and of the op's results.
LogicalResult MemoRunOp::verifyRegions() {
  Type forced = forcedAt(getDataType());
  auto end = dyn_cast<MemoYieldOp>(getRegion().front().getTerminator());
  if (!end)
    return emitOpError("ends its region in no idr.memo.yield");
  if (end.getValue().getType() != forced)
    return emitOpError("moves a value of type ") << end.getValue().getType()
                                                 << " into a forced state that holds " << forced;
  if (!llvm::equal(end.getResults().getTypes(), getOuts().getTypes()))
    return emitOpError("yields ") << end.getResults().getTypes() << " where its results are "
                                  << getOuts().getTypes();
  return success();
}

// The exchange as its steps, for a pass that cannot keep the region: the
// captures taken out of the cell, each at the type the region binds it, so
// at the hold counting and exclusivity gave it, the region's code in place
// on them, and its value stored into the cell, a step of its own that a
// continuation can begin with; the op's results are what the region
// yields after the value.
void MemoRunOp::split(RewriterBase &rewriter) {
  Block &body = getRegion().front();
  auto end = cast<MemoYieldOp>(body.getTerminator());
  Value value = end.getValue();
  SmallVector<Value> results(end.getResults());
  rewriter.setInsertionPoint(getOperation());
  auto taken =
      MemoTakeOp::create(rewriter, getLoc(), TypeRange(body.getArgumentTypes()), getCell());
  rewriter.inlineBlockBefore(&body, getOperation(), taken.getCaptures());
  rewriter.setInsertionPoint(getOperation());
  MemoStoreOp::create(rewriter, end.getLoc(), getCell(), value);
  rewriter.eraseOp(end);
  rewriter.replaceOp(getOperation(), results);
}

//===----------------------------------------------------------------------===//
// idr.memo.yield
//===----------------------------------------------------------------------===//

// The forced value moves into the cell; the results leave the op.
MutableOperandRange MemoYieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return getResultsMutable();
}

// The value moves into the forced state of the cell its exchange holds,
// which takes its reference over: the one forced state of every cell of
// the family, whatever state a refinement names.
void MemoYieldOp::getFlowEdges(FlowEdges &edges) {
  auto run = cast<MemoRunOp>((*this)->getParentOp());
  edges.flow(FlowSource::of(getValueMutable()),
             FlowPlace::partOf(run.getCell(),
                               FlowAnchor::memoStateOf(run.getDataType().unrefined())));
}

// The region runs once, between the move out and the move in, and what it
// gives after the value leaves the op.
void MemoRunOp::getSuccessorRegions(RegionBranchPoint point,
                                    SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent())
    regions.push_back(RegionSuccessor(&getRegion()));
  else
    regions.push_back(RegionSuccessor(getOperation()));
}

ValueRange MemoRunOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getOuts();
  return ValueRange();
}

void MemoRunOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                          SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
}

// Each capture moves out of its field of the label's state into the
// region (movedOut).
void MemoRunOp::getFlowEdges(FlowEdges &edges) {
  for (BlockArgument capture : getRegion().front().getArguments())
    movedOut(*this, capture.getArgNumber(), capture, edges);
}

// The region's value moves into the cell, the memory the exchange holds,
// which its yield writes.
ValueRange MemoRunOp::getYieldTargets() { return getODSOperands(0); }

//===----------------------------------------------------------------------===//
// idr.memo.take and idr.memo.store
//===----------------------------------------------------------------------===//

DataType MemoTakeOp::getDataType() { return dataTypeOf(getCell().getType()); }
Tag MemoTakeOp::getTag() { return *getDataType().singleTag(); }
DataType MemoStoreOp::getDataType() { return dataTypeOf(getCell().getType()); }
Tag MemoStoreOp::getTag() { return *getDataType().singleTag(); }

// The captures, inferred from the cell: each as the exchange moves it out,
// as the region of the exchange binds it.
LogicalResult MemoTakeOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                           Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  Type cell = adaptor.getCell().getType();
  if (!isMemoState(cell))
    return emitOptionalError(location, "takes the captures of ", cell,
                             ", which is no memo cell refined to one state");
  std::optional<SmallVector<Type>> captures = capturesMovedOut(cell);
  if (!captures)
    return emitOptionalError(location, "takes the captures of ", cell,
                             ", whose refinement gives its label no binders");
  llvm::append_range(inferred, *captures);
  return success();
}

// A capture may stand at any hold over its field's carrier and uses, as
// the exchange's region binds it (standAsCaptures).
bool MemoTakeOp::isCompatibleReturnTypes(TypeRange inferred, TypeRange actual) {
  return standAsCaptures(inferred, actual);
}

LogicalResult MemoTakeOp::verify() { return memoizes(*this, getDataType()); }

// The value is what the cell's forced state holds at the cell's indices.
LogicalResult MemoStoreOp::verify() {
  if (failed(memoizes(*this, getDataType())))
    return failure();
  Type forced = forcedAt(getDataType());
  if (getValue().getType() != forced)
    return emitOpError("moves a value of type ") << getValue().getType()
                                                 << " into a forced state that holds " << forced;
  return success();
}

// Each capture moves out of its field, as the exchange's region binds it
// (movedOut).
void MemoTakeOp::getFlowEdges(FlowEdges &edges) {
  for (OpResult capture : getCaptures())
    movedOut(*this, capture.getResultNumber(), capture, edges);
}

// The value moves into the one forced state of every cell of the family,
// as the exchange's yield moves it. The state held nothing: the take left
// the cell running, with no value yet, so the store fills it and releases
// nothing, as a put-back fills the place a take left.
void MemoStoreOp::getFlowEdges(FlowEdges &edges) {
  FlowAnchor forced = FlowAnchor::memoStateOf(getDataType().unrefined());
  edges.flow(FlowSource::of(getValueMutable()), FlowPlace::partOf(getCell(), forced));
  edges.fill(getCell(), forced);
}
