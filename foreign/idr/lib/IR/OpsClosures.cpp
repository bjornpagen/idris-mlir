// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Closures and suspensions. idr.closure captures a function's leading
// parameters, and idr.apply runs one. idr.suspend builds a cell and does
// not run its function; idr.force reads that cell, and the first entry
// computes the value and leaves it there. After idr-defunctionalize the cell
// is a value of a memo family, a force is a call of the family's dispatch,
// and the dispatch exchanges the cell's state through idr.memo.run, which
// moves the captures out and the value in. A suspension of a value that
// already exists, idr.delay, is evaluated where it is built: forcing it
// computes nothing, and the force is the value.
//
// A suspension has no fold: the cell it builds is the one thing that
// changes while references to it live, so folding one into a constant
// would make every run share one cell whose forced value lives until the
// program ends, and a trusted library's effect inside it would run once
// instead of where its value is demanded. Nor do these ops carry rewrite
// patterns: defunctionalization replaces every one of them before any
// simplification runs, and what is left of a force after it (a call of a
// known label, a cell forced in one case) is the e-graph's.

#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

namespace {

} // namespace

//===----------------------------------------------------------------------===//
// idr.closure
//===----------------------------------------------------------------------===//

// The callee's leading parameters are the captures, and the rest of its
// signature is the closure's carrier, whatever quantity the captures give
// it (Idr_LinearWhenACaptureIs).
LogicalResult FnClosureOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(*this, getCalleeAttr());
  if (!fn)
    return emitOpError("refers to an unknown function ") << getCalleeAttr();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  size_t captures = getCaptures().size();
  if (captures > inputs.size() ||
      !llvm::equal(getCaptures().getTypes(), inputs.take_front(captures)))
    return emitOpError("captures ")
           << getCaptures().getTypes() << ", which are not the leading parameters of "
           << getCalleeAttr();
  auto expected = FnType::get(getContext(), inputs.drop_front(captures), fn.getResultTypes());
  if (expected != unrestricted(getType()))
    return emitOpError("has type ") << getType() << ", but a closure of " << getCalleeAttr()
                                    << " with these captures is " << expected;
  return success();
}

// A closure of constants is an immutable value nothing reads the identity
// of, so it is the constant. A capture folds only as a constant the
// dialect builds at its type: a poison capture is the program's value
// where control never arrives, which no constant holds, so the closure
// stays an op around it.
OpFoldResult FnClosureOp::fold(FoldAdaptor adaptor) {
  for (auto [capture, operand] : llvm::zip_equal(adaptor.getCaptures(), getCaptures()))
    if (!capture || !fold::buildable(capture, operand.getType()))
      return {};
  return ClosureAttr::get(getContext(), getCalleeAttr(),
                          ArrayAttr::get(getContext(), adaptor.getCaptures()));
}

//===----------------------------------------------------------------------===//
// idr.suspend
//===----------------------------------------------------------------------===//

// Every parameter is a capture, and the function's one result is the
// suspension's value.
LogicalResult LazySuspendOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(*this, getCalleeAttr());
  if (!fn)
    return emitOpError("refers to an unknown function ") << getCalleeAttr();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  if (getCaptures().size() != inputs.size() ||
      !llvm::equal(getCaptures().getTypes(), inputs))
    return emitOpError("captures ")
           << getCaptures().getTypes() << ", which are not the parameters of " << getCalleeAttr();
  Type value = cast<LazyType>(unrestricted(getResult().getType())).getValue();
  if (fn.getResultTypes().size() != 1 || unrestricted(fn.getResultTypes()[0]) != unrestricted(value))
    return emitOpError("suspends ") << getCalleeAttr() << ", which returns "
                                    << fn.getResultTypes() << ", where " << value << " is expected";
  return success();
}

//===----------------------------------------------------------------------===//
// idr.force
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

//===----------------------------------------------------------------------===//
// idr.memo.run
//===----------------------------------------------------------------------===//

DataType MemoRunOp::getDataType() { return dataTypeOf(getCell().getType()); }

// The cell is in the state of a label that memoizes: a label run by name
// leaves its cell as it is, so it has no exchange. A memo family's states
// are its labels, then running and forced, by its kind, so a tag past its
// labels names a state, which no exchange runs. The region binds that
// label's captures, each as a field read from the cell is.
LogicalResult MemoRunOp::verify() {
  DataType cell = getDataType();
  std::optional<families::MemoView> memo = cell ? cell.memo() : std::nullopt;
  if (!memo)
    return emitOpError("exchanges the state of ") << getCell().getType()
                                                  << ", which is no memo family's cell";
  ArrayRef<families::MemoLabelDecl> labels = memo->labels();
  auto tag = static_cast<unsigned>(getTag());
  if (tag >= labels.size() || labels[tag].mode != families::Mode::Memoized)
    return emitOpError("runs the state ") << tag
                                          << ", which is no label of the cell that memoizes";
  const families::LabelDecl &label = labels[tag].label;
  Block &body = getRegion().front();
  if (body.getNumArguments() != label.fields.size())
    return emitOpError("binds ") << body.getNumArguments() << " captures where its label "
                                 << label.fn << " has " << label.fields.size();
  for (auto [arg, field] : llvm::zip_equal(body.getArguments(), label.fields))
    if (arg.getType() != fieldType(getCell().getType(), field))
      return emitOpError("binds a capture of type ")
             << arg.getType() << " where its label " << label.fn << " holds " << field;
  return success();
}

// The region ends in idr.memo.yield of the value the cell's forced state
// holds, then each result.
LogicalResult MemoRunOp::verifyRegions() {
  DataType memo = getDataType();
  SmallVector<Type> types{memo.ctor(memo.memo()->forced()).fields.front()};
  llvm::append_range(types, getOuts().getTypes());
  auto end = dyn_cast<MemoYieldOp>(getRegion().front().getTerminator());
  if (!end)
    return emitOpError("ends its region in no idr.memo.yield");
  if (!llvm::equal(end.getValues().getTypes(), types))
    return emitOpError("yields ") << end.getValues().getTypes() << " where its cell's forced "
                                  << "value and its results are " << types;
  return success();
}

//===----------------------------------------------------------------------===//
// idr.memo.yield
//===----------------------------------------------------------------------===//

// One value at least: the forced state's.
LogicalResult MemoYieldOp::verify() {
  if (getValues().empty())
    return emitOpError("yields no value for its cell's forced state");
  return success();
}

// The forced value moves into the cell; what follows it leaves the op.
MutableOperandRange MemoYieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return MutableOperandRange(getOperation(), 1, getNumOperands() - 1);
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
// region, with the reference the cell held; the yield moves the value into
// the forced state.
void MemoRunOp::getFlowEdges(FlowEdges &edges) {
  Value cell = getCell();
  DataType memo = getDataType();
  for (BlockArgument capture : getCaptures())
    edges.flow(FlowPoint::partOf(cell, FlowAnchor::fieldOf(memo, getTag(), capture.getArgNumber())),
               FlowPoint::of(Value(capture)));
}
