// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-stack: the lifetimes of the program, inferred, and the cells they
// put in a frame made there.
//
// A cell idr.cell.new makes on the heap may be made in its function's
// frame instead, as upstream's promote-buffers-to-stack makes a
// memref.alloc a memref.alloca, when the rules of the frame
// (IR/Lifetimes.h) hold of every value that may reach it once it is the
// frame's: the box its init makes is then of the frame, and so is
// everything that holds or reads it. The step reads those rules, the one
// place they are said, which the function verifier holds its result to:
// each cell starts in the frame, and the values each may reach are found
// forward along the rules' edges, over the whole program at once (a
// parameter reaches what any of its arguments does). A cell that reaches an
// escape stays on the heap, and so does one that reaches the init of a cell
// of the heap, until nothing changes; the set only shrinks, so that ends.
// Then the lifetimes are written: each value a cell of the frame reaches is
// of the frame, signatures included, and where such a value meets one of
// the heap (a join of a region branch, a call's parameter, a select), the
// heap one is shared into the frame (idr.share). idr-lower makes each such
// cell in a slot of the function's entry block, with the stack mark in its
// header, so counting works on it as on any cell, except that when its
// count reaches 0 its fields are released and its memory is not freed. The
// step runs before reuse and exclusivity are decided, which read the
// source of every cell: a stack cell is never recycled, and never
// exclusive.
//
// The cells it can place are those whose op it knows the runs of: in
// regions of one block each of region branches whose runs never overlap,
// up to the function's body. A cell larger than a limit stays on the heap,
// and so do the cells of a function past its frame budget, in the order
// the function makes them; a function that is on a cycle of calls may have
// many frames live at once, each with its slots, so its budget is much
// smaller. And beyond the rules, the step keeps on the heap a cell that may
// reach a call in tail position of a function on its function's cycle of
// calls: the lowering makes no tail call that may reach the frame
// (Conversion/Frame.h), so such a cycle would no longer run in constant
// stack. Each is a performance decision, never a refusal: a cell left on
// the heap is the same cell there.
#include "idr/Analysis/CallCycles.h"
#include "idr/Analysis/Recursion.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Pipeline.h"
#include "idr/Transforms/Stack.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"

#include <deque>

namespace idr {
#define GEN_PASS_DEF_IDRRCSTACK
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The size policies of the stack, in bytes: the largest cell a frame
// holds, and how much of a frame a function's cells take, much less for a
// function on a cycle of calls, which may have many frames live at once.
// They bound how far a frame grows, never what compiles: a cell they leave
// on the heap is the same cell there.
constexpr unsigned stackCellLimit = 256;
constexpr unsigned stackFrameLimit = 1024;
constexpr unsigned recursiveStackFrameLimit = 64;

// idr-rc-stack puts one cell on the stack; the unit is the cell.
struct StackCellAction : idr::support::TaggedAction<StackCellAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-stack-cell";
};

// Whether the runs of the region `op` is in are known up to its function's
// body: regions of one block each of region branches whose runs never
// overlap, as they do in a region the op holds as parallel
// (HasParallelRegion). A function's body is one block by its type.
bool placeable(Operation *op) {
  for (Region *region = op->getParentRegion(); region;
       region = region->getParentOp()->getParentRegion()) {
    Operation *parent = region->getParentOp();
    if (isa<idr::FuncOp>(parent))
      return true;
    if (!isa<RegionBranchOpInterface>(parent) || !region->hasOneBlock() ||
        parent->hasTrait<OpTrait::HasParallelRegion>())
      return false;
  }
  return false;
}

// The inference over one program: which candidate cells each value may
// reach once its cell is the frame's, found forward along the rules' edges.
class Inference {
public:
  Inference(idr::ProgramOp program, const SymbolTable &symbols, const idr::CallCycles &cycles)
      : symbols(symbols), cycles(cycles) {
    program.walk<WalkOrder::PreOrder>([&](idr::CellNewOp cell) {
      if (!placeable(cell))
        return;
      index.try_emplace(cell.getOperation(), cells.size());
      cells.push_back(cell);
    });
  }

  ArrayRef<idr::CellNewOp> candidates() const { return cells; }

  // The values each candidate reaches, to the least solution: a value
  // enters the queue again whenever what it reaches grows, and what it
  // reaches is a subset of the finitely many candidates.
  void solve() {
    for (auto [i, cell] : llvm::enumerate(cells))
      for (Operation *user : cell.getCell().getUsers())
        if (auto init = dyn_cast<idr::CellInitOp>(user))
          add(init.getResult(), single(static_cast<unsigned>(i)));
    while (!queue.empty()) {
      Value value = queue.front();
      queue.pop_front();
      queued.erase(value);
      llvm::SetVector<Operation *> users(value.user_begin(), value.user_end());
      for (Operation *user : users)
        idr::lifetimes::edgesOf(user, [&](Value from, const idr::lifetimes::Edge &edge) {
          if (from == value)
            follow(from, edge);
        });
    }
  }

  // The candidates that stay on the heap: those that reach an escape.
  llvm::BitVector escaping() const {
    llvm::BitVector out(static_cast<unsigned>(cells.size()));
    for (Value value : escapes)
      out |= reached(value);
    return out;
  }

  // Leaves on the heap, in `framed`, each candidate that reaches the init
  // of a cell that is not the frame's, until none does.
  void keepFills(llvm::BitVector &framed) const {
    for (bool changed = true; changed;) {
      changed = false;
      for (auto [init, value] : fills) {
        auto it = index.find(init.getCell().getDefiningOp());
        if (it != index.end() && framed.test(it->second))
          continue;
        llvm::BitVector reaches = reached(value);
        reaches &= framed;
        if (reaches.none())
          continue;
        framed.reset(reaches);
        changed = true;
      }
    }
  }

  // Whether `value` may reach a cell of `framed`.
  bool inFrame(Value value, const llvm::BitVector &framed) const {
    return reached(value).anyCommon(framed);
  }

  // Every value that may reach a candidate.
  SmallVector<Value> values() const {
    SmallVector<Value> out;
    for (const auto &entry : reach)
      out.push_back(entry.first);
    return out;
  }

private:
  llvm::BitVector single(unsigned i) const {
    llvm::BitVector one(static_cast<unsigned>(cells.size()));
    one.set(i);
    return one;
  }

  llvm::BitVector reached(Value value) const {
    auto it = reach.find(value);
    return it == reach.end() ? llvm::BitVector(static_cast<unsigned>(cells.size())) : it->second;
  }

  void add(Value value, const llvm::BitVector &more) {
    auto [it, fresh] =
        reach.try_emplace(value, llvm::BitVector(static_cast<unsigned>(cells.size())));
    llvm::BitVector grown = it->second;
    grown |= more;
    if (!fresh && grown == it->second)
      return;
    it->second = std::move(grown);
    if (queued.insert(value).second)
      queue.push_back(value);
  }

  void follow(Value from, const idr::lifetimes::Edge &edge) {
    llvm::BitVector here = reached(from);
    std::visit(llvm::makeVisitor(
                   [&](const idr::lifetimes::Carries &carries) { add(carries.to, here); },
                   [&](idr::lifetimes::Fills fill) {
                     if (filled.insert({fill.init.getOperation(), from}).second)
                       fills.emplace_back(fill.init, from);
                   },
                   [&](idr::lifetimes::Passes passes) {
                     auto callee =
                         symbols.lookup<idr::FuncOp>(passes.call.getCalleeAttr().getAttr());
                     // A call in tail position of a function on its own
                     // cycle ends the frame, the lowering's tail call or
                     // the next iteration of a loop: it stays a call that
                     // keeps the frame only by giving up constant stack.
                     auto caller = passes.call->getParentOfType<idr::FuncOp>();
                     if (idr::tail::inTailPosition(passes.call) &&
                         cycles.together(caller, callee))
                       escapes.insert(from);
                     // A parameter of a function that loops in its frame
                     // is passed on to the next iteration, which a value
                     // of the frame may never be: whatever its own self
                     // call passes there, its type is the parameter's.
                     if (loopsInFrame(callee))
                       escapes.insert(from);
                     add(callee.getArgument(passes.index), here);
                   },
                   [&](idr::lifetimes::Escape) { escapes.insert(from); }),
               edge);
  }

  // Whether `fn` holds a self call that is the next iteration of a loop in
  // its frame (lifetimes::loopsInFrame), asked once per function.
  bool loopsInFrame(idr::FuncOp fn) {
    auto [it, fresh] = loops.try_emplace(fn.getOperation(), false);
    if (fresh)
      it->second = fn.walk([](idr::CallOp call) {
                       return idr::lifetimes::loopsInFrame(call) ? WalkResult::interrupt()
                                                                 : WalkResult::advance();
                     }).wasInterrupted();
    return it->second;
  }

  const SymbolTable &symbols;
  const idr::CallCycles &cycles;
  DenseMap<Operation *, bool> loops;
  SmallVector<idr::CellNewOp> cells;
  DenseMap<Operation *, unsigned> index;
  llvm::MapVector<Value, llvm::BitVector> reach;
  std::deque<Value> queue;
  DenseSet<Value> queued;
  llvm::SetVector<Value> escapes;
  SmallVector<std::pair<idr::CellInitOp, Value>> fills;
  DenseSet<std::pair<Operation *, Value>> filled;
};

// `use` takes a value of the frame: one of the heap there is shared into
// it, as any join forgets what one of its sides proved.
void shareInto(RewriterBase &rewriter, OpOperand &use) {
  Value value = use.get();
  if (!idr::mayBeFrame(value.getType()) ||
      idr::lifetimeOf(value.getType()) == idr::Lifetime::Frame)
    return;
  Operation *owner = use.getOwner();
  rewriter.setInsertionPoint(owner);
  Value shared = idr::ShareOp::create(rewriter, owner->getLoc(),
                                      idr::atLifetime(value.getType(), idr::Lifetime::Frame), value);
  rewriter.modifyOpInPlace(owner, [&] { use.set(shared); });
}

struct Stack : idr::impl::IdrRcStackBase<Stack> {
  void runOnProgram(idr::ProgramOp program) override {
    const idr::Layouts &layouts = getAnalysis<idr::Layouts>();
    const idr::Recursion &recursion = getAnalysis<idr::Recursion>();
    const idr::CallCycles &cycles = getAnalysis<idr::CallCycles>();
    const SymbolTable &symbols = getAnalysis<SymbolTable>();
    program.walk([&](idr::CellNewOp) { ++numBoxes; });

    Inference inference(program, symbols, cycles);
    inference.solve();
    ArrayRef<idr::CellNewOp> cells = inference.candidates();
    llvm::BitVector framed(static_cast<unsigned>(cells.size()), true);
    framed.reset(inference.escaping());
    inference.keepFills(framed);

    // The size policies, each function's budget taken in the order it
    // makes its cells, then the actions: a skipped one leaves its cell on
    // the heap, and its budget stays taken.
    DenseMap<Operation *, unsigned> left;
    for (auto [i, made] : llvm::enumerate(cells)) {
      idr::CellNewOp cell = made;
      auto at = static_cast<unsigned>(i);
      if (!framed.test(at))
        continue;
      auto fn = cell->getParentOfType<idr::FuncOp>();
      unsigned &room =
          left.try_emplace(fn, recursion.recursive(fn) ? recursiveStackFrameLimit
                                                        : stackFrameLimit)
              .first->second;
      idr::CellType type = cell.getCell().getType();
      unsigned size = layouts.box(type.getBox().getData()).cell(type.getTag()).size;
      if (size > stackCellLimit || size > room) {
        framed.reset(at);
        continue;
      }
      room -= size;
      bool performed = false;
      idr::support::perform<StackCellAction>(cell, [&] { performed = true; });
      if (!performed)
        framed.reset(at);
    }
    inference.keepFills(framed);
    if (framed.none())
      return markAllAnalysesPreserved();

    // The lifetimes written: each cell of the frame made there, and each
    // value one reaches of the frame, the parameters of the signatures
    // with them.
    IRRewriter rewriter(&getContext());
    SmallVector<Value> values = inference.values();
    for (auto [i, made] : llvm::enumerate(cells)) {
      if (!framed.test(static_cast<unsigned>(i)))
        continue;
      idr::CellNewOp cell = made;
      idr::CellType type = cell.getCell().getType();
      rewriter.setInsertionPoint(cell);
      rewriter.replaceOpWithNewOp<idr::CellStackOp>(
          cell, idr::CellType::get(&getContext(), type.getBox(), type.getTag(), idr::Lifetime::Frame));
    }
    numStackCells += framed.count();
    llvm::SetVector<idr::FuncOp> signatures;
    for (Value value : values) {
      if (!inference.inFrame(value, framed))
        continue;
      value.setType(idr::atLifetime(value.getType(), idr::Lifetime::Frame));
      if (auto arg = dyn_cast<BlockArgument>(value))
        if (auto fn = dyn_cast<idr::FuncOp>(arg.getOwner()->getParentOp()))
          signatures.insert(fn);
    }
    for (idr::FuncOp fn : signatures)
      fn.setFunctionType(FunctionType::get(&getContext(), fn.getBody().getArgumentTypes(),
                                           fn.getResultTypes()));

    // Where a value of the frame meets one of the heap: the joins of
    // region branches, a call's parameters, a select's choices. Found
    // first and shared after: each share is an op of its own.
    SmallVector<OpOperand *> meetings;
    program.walk([&](Operation *op) {
      idr::forwardedValues(op, [&](OpOperand &use, Value input) {
        if (idr::lifetimeOf(input.getType()) == idr::Lifetime::Frame)
          meetings.push_back(&use);
      });
      if (auto call = dyn_cast<idr::CallOp>(op)) {
        auto callee = symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr());
        for (auto [use, param] :
             llvm::zip_equal(call.getArgsMutable(), callee.getArgumentTypes()))
          if (idr::lifetimeOf(param) == idr::Lifetime::Frame)
            meetings.push_back(&use);
      }
      if (auto select = dyn_cast<arith::SelectOp>(op);
          select && idr::lifetimeOf(select.getType()) == idr::Lifetime::Frame) {
        meetings.push_back(&select.getTrueValueMutable());
        meetings.push_back(&select.getFalseValueMutable());
      }
    });
    for (OpOperand *use : meetings)
      shareInto(rewriter, *use);
    // A cell's source changes what an op does to memory, which the
    // ownership analyses read, and nothing a data type or a symbol says.
    markAnalysesPreserved<idr::TypeGraph, idr::Layouts, SymbolTable>();
  }
};

} // namespace
