// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The loan of a tensor or a buffer to upstream's ops (idr.carrier): its
// hooks, the questions every pass asks of a loan, how one use of a loan's
// alias is read (Lifetimes/Loans.h walks them), and the rule of loans, one
// rule of the lifetimes' walk of a function (verify::LifetimeRules), run
// after every pass. It is the one rule of that walk that follows values:
// a bare alias names no lifetime, so where a loan goes is known only by
// following it.

#include "idr/IR/Lifetimes/Loans.h"

#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Lifetimes/Rules.h"
#include "idr/IR/Ownership.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <string>

using namespace mlir;
using namespace idr;
using State = verify::LifetimeRules::State;

//===----------------------------------------------------------------------===//
// idr.carrier
//===----------------------------------------------------------------------===//

// The value's carrier, the same words at run time: what upstream's ops take.
LogicalResult CarrierOp::inferReturnTypes(MLIRContext *, std::optional<Location>, Adaptor adaptor,
                                          SmallVectorImpl<Type> &inferred) {
  inferred.push_back(unrestricted(adaptor.getValue().getType()));
  return success();
}

// A view of the value it lends, whose memory upstream's alias readers and
// the effect system attribute to that value.
Value CarrierOp::getViewSource() { return getValue(); }

// Nothing moves: the value stays its holder's at its grade, and the result
// is a reference of no one's, which no count follows and no flow explains.
void CarrierOp::getFlowEdges(FlowEdges &) {}

bool idr::isLendable(Type type) {
  return holdOf(type).has_value() && isa<TensorType, BaseMemRefType>(unrestricted(type));
}

//===----------------------------------------------------------------------===//
// A loan
//===----------------------------------------------------------------------===//

// A lifetime's extent is where its value is bound: an opener's entry, a
// function's parameter, or this activation's place in its region.
Region *idr::lifetimes::loanRegion(CarrierOp loan) {
  return extentOf(loan.getLifetime()).getParentRegion();
}

// A carrier is itself a view of what it lends, so the walk up stops at the
// first one it meets, the loan the value is.
CarrierOp idr::lifetimes::loanOf(Value value) {
  Value root = definitionChain(value, [](Value at) -> std::optional<Value> {
                 auto view = at.getDefiningOp<ViewLikeOpInterface>();
                 if (!view || isa<CarrierOp>(view.getOperation()) || view.getViewDest() != at)
                   return std::nullopt;
                 return view.getViewSource();
               }).back();
  return root.getDefiningOp<CarrierOp>();
}

namespace {

// Whether an op of ours moves what `use` gives it into what it holds or
// gives, as its flow edges declare: the operand, taken over or read whole,
// the source of a move into a value the op makes, a part of one or of a
// value it or its parent holds, or a function's parameter or result; the
// reference given up at the op; or an argument of a call by value, which
// moves into a parameter of whatever runs. Each such place holds a
// reference counting then owns, whatever the operand's uses, so an alias
// there is someone's. A move of a part of the operand (an element, a
// field) moves that part and not the operand, and an op of ours that only
// reads the operand declares no move of it (a view of it among them, whose
// result the walk follows as an alias): each leaves the use a read. An op
// of upstream's that holds the flow interface is read by its forwarding,
// its aliases and its stores instead.
bool movesInto(OpOperand &use) {
  Operation *user = use.getOwner();
  auto declared = dyn_cast<FlowOpInterface>(user);
  if (!declared || !llvm::isa_and_present<IdrDialect>(user->getDialect()))
    return false;
  FlowEdges edges;
  declared.getFlowEdges(edges);
  Value given = use.get();
  auto fromUse = [&](const FlowSource &source) {
    return match(
        source.at, [&](const FlowSource::Taken &taken) { return taken.use == &use; },
        [&](const FlowSource::Whole &whole) { return whole.value == given; },
        [](const OneOf<FlowSource::Part, FlowSource::Parameter, FlowSource::Result> auto &) {
          return false;
        });
  };
  return llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    return match(
        edge.move, [&](const FlowEdges::Flow &flow) { return fromUse(flow.from); },
        [&](const FlowEdges::Release &release) { return release.use == &use; },
        [&](const FlowEdges::Dispatch &dispatch) {
          return llvm::is_contained(dispatch.call.getArgOperands(), given);
        },
        [](const OneOf<FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh,
                       FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Constant> auto &) {
          return false;
        });
  });
}

} // namespace

// A terminator that forwards an alias to no successor (the walk asks the
// forwarding first) is its function's return. An op of ours takes a
// reference over where it consumes the operand, makes one of its own where
// its trait says, and holds or gives one where it moves the operand into a
// place (movesInto); an op of upstream's stores the value it writes where
// its effects name the memory and not the value.
lifetimes::LoanUse idr::lifetimes::loanUseOf(OpOperand &use) {
  Operation *user = use.getOwner();
  if (user->hasTrait<OpTrait::ReturnLike>())
    return LoanUse::Returns;
  if (effects::consumes(use) || user->hasTrait<AdoptsCarrier>() || movesInto(use))
    return LoanUse::Adopts;
  if (ownership::storedBy(use))
    return LoanUse::Stores;
  return LoanUse::Reads;
}

const bufferization::BufferizationOptions &idr::lifetimes::aliasOptions() {
  static const bufferization::BufferizationOptions options;
  return options;
}

//===----------------------------------------------------------------------===//
// An alias made again
//===----------------------------------------------------------------------===//

void idr::lifetimes::brokenAt(Operation *op, const llvm::Twine &what) {
  std::string text;
  llvm::raw_string_ostream out(text);
  out << "internal error: " << what << "; at " << op->getName() << " (" << op->getLoc() << ")";
  llvm::reportFatalInternalError(llvm::Twine(text));
}

bool idr::lifetimes::remakeable(Operation *op) {
  return effects::whole(op) == effects::EffectSet{} && isSpeculatable(op);
}

//===----------------------------------------------------------------------===//
// The rule of loans
//===----------------------------------------------------------------------===//

// At each loan: the value lent outlives it, so once references are counted
// no use of the value inside the loan's region gives it up; and every alias
// of the loan stays in that region, is never returned, never stored as a
// write's value, and never adopted by an op of ours. Before counting a use
// that consumes the value inside the region is one placement keeps the
// value alive across, duplicating it there, so only the counted program
// holds that half of the rule.
LogicalResult State::loans(Operation &op) {
  auto loan = dyn_cast<CarrierOp>(&op);
  if (!loan)
    return success();
  Region *extent = lifetimes::loanRegion(loan);
  auto lent = [&](InFlightDiagnostic &&error) -> LogicalResult {
    error.attachNote(loan.getLoc()) << "lent here";
    return failure();
  };

  if (counting == StageCounting::Counted)
    for (OpOperand &use : loan.getValue().getUses())
      if (extent->isAncestor(use.getOwner()->getParentRegion()) && effects::consumes(use))
        return lent(use.getOwner()->emitOpError(
            "gives up a value lent to upstream's ops inside the region of the loan's lifetime, "
            "which the value outlives"));

  LogicalResult judged = success();
  SmallVector<OpOperand *, 4> starts;
  for (OpOperand &use : loan.getResult().getUses())
    starts.push_back(&use);
  lifetimes::forEachLoanUse(
      starts,
      [&](Value alias) {
        if (failed(judged) || extent->isAncestor(alias.getParentRegion()))
          return;
        Operation *maker = isa<OpResult>(alias)
                               ? alias.getDefiningOp()
                               : cast<BlockArgument>(alias).getOwner()->getParentOp();
        judged = lent(maker->emitOpError(
            "gives an alias of a loan outside the region of the loan's lifetime"));
      },
      [&](OpOperand &use, lifetimes::LoanUse kind) {
        if (failed(judged))
          return;
        Operation *user = use.getOwner();
        switch (kind) {
        case lifetimes::LoanUse::Reads:
        case lifetimes::LoanUse::Forwards:
          return;
        case lifetimes::LoanUse::Returns:
          judged = lent(user->emitOpError("returns an alias of a loan from its function"));
          return;
        case lifetimes::LoanUse::Stores:
          judged = lent(user->emitOpError("stores an alias of a loan into memory as a value"));
          return;
        case lifetimes::LoanUse::Adopts:
          judged = lent(user->emitOpError("takes an alias of a loan as a reference of its own"));
          return;
        }
      });
  return judged;
}
