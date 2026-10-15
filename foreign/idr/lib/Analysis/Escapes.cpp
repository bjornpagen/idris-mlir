// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The escape analysis of boxes: which cells can outlive the frame that
// builds them.
//
// The rules, by use, for a value that may hold a cell:
//   - forwarded by a region branch (a yield to its match's results, the
//     initial values and terminators of an scf.while to its arguments and
//     results), to an arith.select's result, or into and out of a linear
//     type: what reaches the value it goes to, in the same way. Linearity
//     has no runtime form, and a value used once may still be used where it
//     escapes;
//   - read (idr.field, the fields a match binds): what is reachable from it
//     reaches what the read gives; its own reference reaches nothing, and
//     idr.tag reads nothing that holds one;
//   - stored in a constructor: everything reachable from it, its own
//     reference too, is reachable from the constructor's value;
//   - taken apart by a match of quantity one: the match leaves the cell to
//     build in again, so its own reference goes with it;
//   - passed to a call: it escapes when that parameter's summary does. A
//     cell passed to a parameter that does not escape is live only while
//     the call runs, inside the caller's frame;
//   - returned, or used by any op this analysis does not know: it escapes.
//     A returned cell is in a frame that is gone whatever the caller does
//     with it, so the return is never the callers' to decide.
//
// The cell an idr.con builds lives in one stack slot per con, in its
// function's entry block. So it also escapes when the con may run again in
// the same frame while the cell is live: the cell must not be forwarded by
// a terminator of a loop around the con, which carries values to the next
// iteration or out of the loop. Nor may it be passed to a call in tail
// position of a function on the same cycle of calls: such a call must be a
// tail call (idr-tail-calls) for the cycle to run in constant stack, or the
// next iteration of a loop (idr-tail-loops) when it is a self call, and
// either way the frame is gone when the callee runs. A function off the
// cycle never calls back round to this frame's function, so a call of it in
// tail position may stay a call that keeps the frame. A con counts only in
// a function body of one block whose regions on the way are those of
// matches (at most one runs, once) and of scf.while (one iteration at a
// time); anywhere else it escapes.
#include "idr/Analysis/Escapes.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Iterators.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>

using namespace mlir;
using namespace mlir::dataflow;

namespace idr {

namespace {

// Where the uses one way of standing for a value reach. `escapes`: a use
// that lets it go. `tailCalled`: a call in tail position of a function on
// its function's cycle, which ends the frame. `loops`: the scf.while ops
// whose terminators forward it to the next iteration or out. The last two
// are about the frame of the value's own function, so they never cross a
// call: a cell passed to a callee is in the caller's frame, which outlives
// whatever the callee does with its own frame and loops. Only `escapes`
// does.
struct Reach {
  bool escapes = false;
  bool tailCalled = false;
  // Sorted, each once: two states compare by what they hold.
  SmallVector<Operation *, 1> loops;

  void add(const Reach &other) {
    escapes |= other.escapes;
    tailCalled |= other.tailCalled;
    for (Operation *loop : other.loops)
      if (auto at = llvm::lower_bound(loops, loop); at == loops.end() || *at != loop)
        loops.insert(at, loop);
  }
  bool operator==(const Reach &) const = default;
};

// The state of a value: how its own reference reaches (shallow) and how
// everything reachable from it does (deep). Nothing reaches anywhere until
// a use says so, and the solve only adds, so it ends with the least
// solution.
struct Escape {
  Reach shallow;
  Reach deep;

  static Escape join(const Escape &lhs, const Escape &rhs) {
    Escape out = lhs;
    out.shallow.add(rhs.shallow);
    out.deep.add(rhs.deep);
    // Everything reachable from a value includes its own reference.
    out.deep.add(out.shallow);
    return out;
  }
  // A backward analysis meets what each use says; here that is the union.
  static Escape meet(const Escape &lhs, const Escape &rhs) { return join(lhs, rhs); }
  bool operator==(const Escape &) const = default;

  void print(raw_ostream &os) const {
    auto reach = [&](const Reach &r) {
      os << (r.escapes ? "escapes" : "-") << (r.tailCalled ? " tail" : "") << " loops "
         << r.loops.size();
    };
    os << "shallow ";
    reach(shallow);
    os << ", deep ";
    reach(deep);
  }
};

class EscapeLattice : public Lattice<Escape> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(EscapeLattice)
  using Lattice::Lattice;
};

enum class Mode : uint8_t { Shallow, Deep };

bool isBox(Type type) { return isa<BoxType>(unrestricted(type)); }

// The values whose references the analysis follows: boxes, and unboxed
// sums, whose fields may hold boxes. A type as it is at runtime: linearity
// has no runtime form.
bool holdsCells(Type type) { return isa<BoxType, DataType>(unrestricted(type)); }

// The part of `state` that stands for `value` in `mode`: a sum's only part
// is deep.
const Reach &part(Value value, const Escape &state, Mode mode) {
  return mode == Mode::Shallow && isBox(value.getType()) ? state.shallow : state.deep;
}

Escape lost() {
  Escape all;
  all.shallow.escapes = true;
  all.deep.escapes = true;
  return all;
}

// Whether `a` and `b` are on one cycle of calls: each may call the other,
// through any calls. A function is on one with itself.
bool together(const DenseMap<Operation *, unsigned> &component, Operation *a, Operation *b) {
  if (a == b)
    return true;
  auto at = component.find(a), bt = component.find(b);
  return at != component.end() && bt != component.end() && at->second == bt->second;
}

// The scf.while ops around `con`, innermost first, which may run it again
// in its frame. Nothing when the con is somewhere else than in regions of
// matches and loops of one block each, in a function of `module`.
std::optional<SmallVector<Operation *, 2>> loopsAround(ConOp con, Operation *module) {
  SmallVector<Operation *, 2> loops;
  for (Operation *op = con;; op = op->getParentOp()) {
    Region *region = op->getParentRegion();
    if (!region || !region->hasOneBlock())
      return std::nullopt;
    Operation *parent = region->getParentOp();
    if (isa<FuncOp>(parent) && parent->getParentOp() == module)
      return loops;
    if (isa<scf::WhileOp>(parent))
      loops.push_back(parent);
    else if (!isa<MatchOp, MatchLitOp>(parent))
      return std::nullopt;
  }
}

// The rules above, on upstream's backward base. The base forwards along
// region branches; the ops whose rule is not the base's are taken before it.
class Flow : public SparseBackwardDataFlowAnalysis<EscapeLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Flow)

  Flow(DataFlowSolver &solver, SymbolTableCollection &unresolved, SymbolTable &symbols,
       const DenseMap<Operation *, unsigned> &component)
      : SparseBackwardDataFlowAnalysis(solver, unresolved), symbols(symbols),
        component(component) {}

  LogicalResult initialize(Operation *top) override;
  LogicalResult visit(ProgramPoint *point) override;
  LogicalResult visitOperation(Operation *op, ArrayRef<EscapeLattice *> operands,
                               ArrayRef<const EscapeLattice *> results) override;
  void visitBranchOperand(OpOperand &operand) override;
  void visitCallOperand(OpOperand &operand) override;
  void visitNonControlFlowArguments(RegionSuccessor &, ArrayRef<BlockArgument>) override {}

  using SparseBackwardDataFlowAnalysis::setToExitState;
  void setToExitState(EscapeLattice *lattice) override { reach(lattice, lost()); }

  // A return lets every cell it returns go, whatever its callers do.
  LogicalResult visitCallableOperation(Operation *, CallableOpInterface,
                                       ArrayRef<AbstractSparseLattice *> operands) override {
    AbstractSparseBackwardDataFlowAnalysis::setAllToExitStates(operands);
    return success();
  }

private:
  void reach(EscapeLattice *lattice, const Escape &update) {
    propagateIfChanged(lattice, lattice->meet(update));
  }
  void visitCall(CallOp call);

  SymbolTable &symbols;
  const DenseMap<Operation *, unsigned> &component;
};

LogicalResult Flow::initialize(Operation *top) {
  // The base visits an op only where its block is executable. Every block
  // is: the frame question is asked of every function, called from this
  // module or not, as the rules above read every use.
  top->walk([&](Block *block) {
    auto *live = getOrCreate<Executable>(getProgramPointBefore(block));
    propagateIfChanged(live, live->setToLive());
  });
  // Every op once, users before what they use, through this analysis's own
  // visit, so that the base never takes an idr.call by its rule.
  WalkResult walked = top->walk<WalkOrder::PostOrder, ReverseIterator>([&](Operation *op) {
    if (op == top || succeeded(visit(getProgramPointAfter(op))))
      return WalkResult::advance();
    return WalkResult::interrupt();
  });
  return failure(walked.wasInterrupted());
}

LogicalResult Flow::visit(ProgramPoint *point) {
  if (point->isBlockStart())
    return success();
  Operation *op = point->getPrevOp();
  if (auto call = dyn_cast<CallOp>(op)) {
    visitCall(call);
    return success();
  }
  if (failed(AbstractSparseBackwardDataFlowAnalysis::visit(point)))
    return failure();
  // A terminator of a loop carries what it forwards into the loop's next
  // iteration, where a con in the loop writes its slot again, or out of it.
  auto loop = dyn_cast_or_null<scf::WhileOp>(op->getParentOp());
  if (!loop || !op->hasTrait<OpTrait::IsTerminator>())
    return success();
  Escape update;
  update.shallow.loops.push_back(loop);
  update.deep.loops.push_back(loop);
  for (Value operand : op->getOperands())
    if (holdsCells(operand.getType()))
      reach(getLatticeElement(operand), update);
  return success();
}

LogicalResult Flow::visitOperation(Operation *op, ArrayRef<EscapeLattice *> operands,
                                   ArrayRef<const EscapeLattice *> results) {
  auto each = [&](const Escape &update) {
    for (auto [operand, lattice] : llvm::zip(op->getOperands(), operands))
      if (holdsCells(operand.getType()))
        reach(lattice, update);
  };
  if (isa<TagOp>(op))
    return success();
  if (isa<FieldOp>(op)) {
    Escape update;
    // What the read gives is reachable from the scrutinee only when it
    // holds a cell; a word read out of it reaches nothing.
    if (holdsCells(op->getResult(0).getType()))
      update.deep = results[0]->getValue().deep;
    each(update);
    return success();
  }
  if (isa<ConOp>(op)) {
    Escape update;
    update.shallow = results[0]->getValue().deep;
    update.deep = results[0]->getValue().deep;
    each(update);
    return success();
  }
  if (isa<arith::SelectOp, LinEnterOp, LinUseOp>(op)) {
    const Escape &result = results[0]->getValue();
    Escape update;
    update.shallow = part(op->getResult(0), result, Mode::Shallow);
    update.deep = result.deep;
    each(update);
    return success();
  }
  each(lost());
  return success();
}

// The one operand of a region branch the base does not forward that holds
// a cell is a match's scrutinee: its case regions' arguments are its
// fields.
void Flow::visitBranchOperand(OpOperand &operand) {
  Value value = operand.get();
  if (!holdsCells(value.getType()))
    return;
  EscapeLattice *lattice = getLatticeElement(value);
  auto match = dyn_cast<MatchOp>(operand.getOwner());
  if (!match)
    return setToExitState(lattice);
  Escape update;
  update.shallow.escapes = isBox(value.getType()) && quantityOf(value.getType()) == Quantity::One;
  ProgramPoint *after = getProgramPointAfter(match);
  for (Region &region : match.getRegions())
    for (BlockArgument field : region.getArguments())
      if (holdsCells(field.getType()))
        update.deep.add(getOrCreateFor<EscapeLattice>(after, field)->getValue().deep);
  reach(lattice, update);
}

void Flow::visitCallOperand(OpOperand &operand) {
  if (holdsCells(operand.get().getType()))
    setToExitState(getLatticeElement(operand.get()));
}

// Every callee is a function of the module with a body: a call's symbol
// use is verified, and no function is without one.
void Flow::visitCall(CallOp call) {
  auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
  bool ends = tail::inTailPosition(call) &&
              together(component, call->getParentOfType<FuncOp>(), callee);
  ProgramPoint *after = getProgramPointAfter(call);
  for (auto [index, operand] : llvm::enumerate(call.getArgs())) {
    if (!holdsCells(operand.getType()))
      continue;
    EscapeLattice *lattice = getLatticeElement(operand);
    // The parameter's state is its summary; the solver visits the call
    // again when it grows.
    BlockArgument param = callee.getArgument(static_cast<unsigned>(index));
    const Escape &summary = getOrCreateFor<EscapeLattice>(after, param)->getValue();
    Escape update;
    update.shallow.escapes = part(param, summary, Mode::Shallow).escapes;
    update.deep.escapes = summary.deep.escapes;
    update.shallow.tailCalled = ends;
    update.deep.tailCalled = ends;
    reach(lattice, update);
  }
}

} // namespace

Escapes::Escapes(Operation *op, AnalysisManager &am) : module(op) {
  SymbolTable &symbols = am.getAnalysis<SymbolTable>();
  findCycles(cast<ModuleOp>(op), symbols);
  // One solve over the module: the parameters' summaries, the cons and the
  // loops are one fixpoint, so nothing is solved twice.
  solver.load<Flow>(unresolved, symbols, component);
  status = solver.initializeAndRun(op);
}

bool Escapes::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Escapes>() || !pa.isPreserved<SymbolTable>();
}

bool Escapes::mayEscape(ConOp con) const {
  std::optional<SmallVector<Operation *, 2>> loops = loopsAround(con, module);
  if (!loops)
    return true;
  Value cell = con.getResult();
  const EscapeLattice *state = solver.lookupState<EscapeLattice>(cell);
  if (!state)
    return true;
  const Reach &self = part(cell, state->getValue(), Mode::Shallow);
  return self.escapes || self.tailCalled ||
         llvm::any_of(self.loops, [&](Operation *loop) { return llvm::is_contained(*loops, loop); });
}

} // namespace idr
