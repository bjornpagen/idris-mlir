// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Trmc.cpp - idr-trmc ------------------------------------------------===//
//
// Every self call modulo a context becomes a tail call that writes its
// result. The call's fact says it is one (`modulo_context`, which the
// frontend wrote and every pass kept, the verifier holding each to the
// rule), so nothing here searches: each call's context is read once, off
// the call, and executed.
//
// `copy (Cons x xs) = Cons x (copy xs)` returns through every level of the
// list. The cell can be built before the call, with the field a hole, and
// the call given the hole's destination (`!idr.dest`) to write once it has
// its value; then the call is the last thing the tail does. So can every
// cell the returned value holds the first one in (`x :: x :: dup xs`, the
// action of the rest inside the actions that run it), and across a
// rejoin: where the context's cell is built after a match whose regions
// give its field, the cell is built before the match and each region
// writes its value into the hole, its own self call by passing the hole on.
// The function keeps its signature and does that for its first level; its
// self calls modulo a context go to a clone that takes a destination and
// returns nothing, whose own such tails write the value they build to the
// destination they got and recurse on the new one, whose self tail calls
// pass the destination on, and whose other tails write their value.
// idr-tail-loops makes the clone a loop: the structure is written top down
// in constant stack.
//
// It runs after counting, which honours each context: the cells on it are
// fresh heap cells, the scrutinee's token recycled into them, and nothing
// is placed between the call and its context's constructors. A promise, so
// no step of it is an action a debug counter may skip; a context it cannot
// execute is an internal error.
//
// The pass stays at the program: each clone is a new symbol of the program.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Traits.h"
#include "idr/Support/Match.h"
#include "idr/Support/Remake.h"
#include "idr/Transforms/Effects.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

namespace idr {
#define GEN_PASS_DEF_IDRTRMC
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// What a context's step made a value: the hole's cell, a cell or a part
// further out, or a part read back out of a value laid out inline.
struct Hole {
  Into into;
};
struct Outer {
  Into into;
};
struct Part {
  ReadBack read;
};
using Making = std::variant<std::monostate, Hole, Outer, Part>;

// The value a change of grade carries, through every such change.
Value throughRegrades(Value value) {
  while (Operation *def = value.getDefiningOp()) {
    if (!def->hasTrait<ResultCarriesOperand>())
      break;
    value = def->getOperand(0);
  }
  return value;
}

// A context mapped into a copy of its function.
Context mapped(const Context &context, const IRMapping &mapping) {
  auto op = [&](Operation *from) { return mapping.lookup(from); };
  auto value = [&](Value from) { return mapping.lookup(from); };
  auto into = [&](const Into &from) {
    return Into{op(from.op), from.operand, from.field, value(from.built)};
  };
  Context to{cast<CallOp>(op(context.call)), {}, into(context.hole), {}};
  for (const Approach &step : context.approach)
    to.approach.push_back(idr::match(
        step, [&](const Regrade &r) -> Approach { return Regrade{op(r.op)}; },
        [&](const Forward &f) -> Approach { return Forward{op(f.terminator), f.position}; }));
  for (const Step &step : context.rest)
    to.rest.push_back(idr::match(
        step, [&](const Regrade &r) -> Step { return Regrade{op(r.op)}; },
        [&](const Into &i) -> Step { return into(i); },
        [&](const ReadBack &r) -> Step { return ReadBack{op(r.op), value(r.part)}; },
        [&](const Forward &f) -> Step { return Forward{op(f.terminator), f.position}; }));
  return to;
}

// Where a value given at a tail goes: on, as the function's first level
// returns it, or into a destination.
struct Given {};
struct Written {
  Value dest;
};
using Target = std::variant<Given, Written>;

class Rewrite {
public:
  Rewrite(RewriterBase &rewriter, FuncOp fn, FuncOp clone, llvm::ArrayRef<Context> contexts)
      : rewriter(rewriter), fn(fn), clone(clone), contexts(contexts) {}

  // `value`, given at operand `position` of `terminator` at a tail, goes
  // to `target`. Fails, reported, on a context it cannot build.
  LogicalResult give(Value value, Operation *terminator, unsigned position, Target target);

private:
  Making makerOf(Value value) const;
  // Rebuilds the hole's cell with its field a hole: its destination.
  Value makeHole(const Into &hole);
  // The ops after `producer` in its block, its terminator aside, moved
  // before it, in order: the context's cells and what their other fields
  // need, which the rule proved may run there. The changes of grade of the
  // producer's own results go, which the hole no longer reads.
  void buildBefore(Operation *producer);
  // `call` made a call of the clone that fills `dest`. Its kind is decided
  // once the function is whole (decide), where its place is final.
  void fillByCall(CallOp call, Value dest);
  // The region op `rejoin`'s result `position` filled in each region, and
  // the op made again without that result.
  LogicalResult fillByRegions(Operation *rejoin, unsigned position, Value dest);
  // `terminator` forwards nothing at `position`; the changes of grade only
  // that operand read go. The op whose region it ends drops that result
  // once every region has (fillByRegions), and the clone its own at last.
  void dropForwarded(Operation *terminator, unsigned position);

  RewriterBase &rewriter;
  FuncOp fn;
  FuncOp clone;
  llvm::ArrayRef<Context> contexts;
};

Making Rewrite::makerOf(Value value) const {
  for (const Context &context : contexts) {
    if (context.hole.built == value)
      return Hole{context.hole};
    for (const Step &step : context.rest) {
      Making found = idr::match(
          step, [](const Regrade &) -> Making { return std::monostate{}; },
          [&](const Into &into) -> Making {
            return into.built == value ? Making(Outer{into}) : Making(std::monostate{});
          },
          [&](const ReadBack &read) -> Making {
            return read.part == value ? Making(Part{read}) : Making(std::monostate{});
          },
          [](const Forward &) -> Making { return std::monostate{}; });
      if (found.index() != 0)
        return found;
    }
  }
  return std::monostate{};
}

Value Rewrite::makeHole(const Into &hole) {
  auto init = cast<CellInitOp>(hole.op);
  rewriter.setInsertionPoint(init);
  llvm::SmallVector<Value> fields;
  for (auto [at, given] : llvm::enumerate(init.getFields()))
    if (at != hole.field)
      fields.push_back(given);
  auto holed = CellInitOp::create(rewriter, init.getLoc(), init.getResult().getType(),
                                  init.getCell(), fields, {static_cast<int32_t>(hole.field)});
  rewriter.replaceAllUsesWith(init.getResult(), holed.getResult());
  rewriter.eraseOp(init);
  return holed.getDest(hole.field);
}

void Rewrite::buildBefore(Operation *producer) {
  llvm::SmallVector<Operation *> after;
  for (Operation *op = producer->getNextNode(); !op->hasTrait<OpTrait::IsTerminator>();
       op = op->getNextNode())
    after.push_back(op);
  for (Operation *op : after) {
    if (op->hasTrait<ResultCarriesOperand>() &&
        throughRegrades(op->getOperand(0)).getDefiningOp() == producer && op->use_empty())
      rewriter.eraseOp(op);
    else
      rewriter.moveOpBefore(op, producer);
  }
}

void Rewrite::fillByCall(CallOp call, Value dest) {
  rewriter.setInsertionPoint(call);
  llvm::SmallVector<Value> args(call.getArgs());
  args.push_back(dest);
  CallOp::create(rewriter, call.getLoc(), clone, call.getIndexArgsAttr(), TypeRange(), args,
                 TailKind::nontail);
  // Its results' changes of grade read nothing now.
  for (Operation *user : llvm::make_early_inc_range(call->getUsers()))
    if (user->hasTrait<ResultCarriesOperand>() && user->use_empty())
      rewriter.eraseOp(user);
  rewriter.eraseOp(call);
}

void Rewrite::dropForwarded(Operation *terminator, unsigned position) {
  Value dropped = terminator->getOperand(position);
  rewriter.modifyOpInPlace(terminator, [&] { terminator->eraseOperand(position); });
  for (Operation *def = dropped.getDefiningOp();
       def && def->hasTrait<ResultCarriesOperand>() && def->use_empty();) {
    Value carried = def->getOperand(0);
    rewriter.eraseOp(def);
    def = carried.getDefiningOp();
  }
}

LogicalResult Rewrite::fillByRegions(Operation *rejoin, unsigned position, Value dest) {
  llvm::SmallVector<Operation *> ends;
  for (Region &region : rejoin->getRegions()) {
    if (region.empty())
      continue;
    Operation *end = region.front().getTerminator();
    // A region that never ends, or that jumps on, gives nothing here.
    if (isa<RegionBranchTerminatorOpInterface>(end) && end->getNumOperands() > position &&
        end->getNumOperands() == rejoin->getNumResults())
      ends.push_back(end);
  }
  for (Operation *end : ends)
    if (failed(give(end->getOperand(position), end, position, Written{dest})))
      return failure();
  llvm::SmallVector<Type> results(rejoin->getResultTypes());
  results.erase(results.begin() + position);
  Operation *made = remakeOp(rewriter, rejoin, rejoin->getOperands(), results);
  llvm::SmallVector<Value> kept;
  for (auto [at, result] : llvm::enumerate(rejoin->getResults()))
    if (at != position)
      kept.push_back(result);
  rewriter.replaceAllUsesWith(kept, made->getResults());
  rewriter.eraseOp(rejoin);
  return success();
}

// The destination a target writes, if it writes one.
Value destOf(const Target &target) {
  return idr::match(
      target, [](Given) { return Value(); }, [](Written written) { return written.dest; });
}

LogicalResult Rewrite::give(Value value, Operation *terminator, unsigned position,
                            Target target) {
  Value source = throughRegrades(value);
  Operation *def = source.getDefiningOp();
  Value dest = destOf(target);

  // A self call whose result is given unchanged: a tail call, or the call a
  // rejoin's region gives into a hole. The clone's passes the destination on.
  if (auto call = dyn_cast_or_null<CallOp>(def);
      call && call.getTailKind() != TailKind::nontail &&
      call.getCalleeAttr().getAttr() == fn.getSymNameAttr()) {
    if (!dest)
      return success();
    dropForwarded(terminator, position);
    fillByCall(call, dest);
    return success();
  }

  // A rejoin: each region gives its own.
  if (def && def->hasTrait<OpTrait::PropagateControlFlowBreak>() &&
      def->getBlock() == terminator->getBlock()) {
    unsigned at = cast<OpResult>(source).getResultNumber();
    if (!dest) {
      for (Region &region : def->getRegions()) {
        if (region.empty())
          continue;
        Operation *end = region.front().getTerminator();
        if (isa<RegionBranchTerminatorOpInterface>(end) && end->getNumOperands() > at &&
            end->getNumOperands() == def->getNumResults())
          if (failed(give(end->getOperand(at), end, at, Given{})))
            return failure();
      }
      return success();
    }
    dropForwarded(terminator, position);
    return fillByRegions(def, at, dest);
  }

  // A value a context builds: built before what fills its hole. Down the
  // context to the hole: an outer cell or a part read back holds the inner
  // value, built with it; the first cell whose field a call or a rejoin
  // gives is the hole.
  if (makerOf(source).index() != 0) {
    Value inner = source;
    std::optional<Into> hole;
    while (!hole) {
      bool stuck = idr::match(
          makerOf(inner), [](std::monostate) { return true; },
          [&](const Hole &h) {
            hole = h.into;
            return false;
          },
          [&](const Outer &o) {
            Value next = throughRegrades(o.into.op->getOperand(o.into.operand));
            Operation *maker = next.getDefiningOp();
            if (maker && maker->hasTrait<OpTrait::PropagateControlFlowBreak>())
              hole = o.into;
            else
              inner = next;
            return false;
          },
          [&](const Part &p) {
            inner = throughRegrades(p.read.op->getOperand(0));
            return false;
          });
      if (stuck)
        return terminator->emitOpError(
            "internal error: idr-trmc: a context whose cells end in no hole");
    }
    Value filler = throughRegrades(hole->op->getOperand(hole->operand));
    Operation *producer = filler.getDefiningOp();
    Value holeDest = makeHole(*hole);
    buildBefore(producer);
    if (dest) {
      rewriter.setInsertionPoint(producer);
      DestWriteOp::create(rewriter, terminator->getLoc(), dest, value);
      dropForwarded(terminator, position);
    }
    if (auto call = dyn_cast<CallOp>(producer)) {
      fillByCall(call, holeDest);
      return success();
    }
    return fillByRegions(producer, cast<OpResult>(filler).getResultNumber(), holeDest);
  }

  // Any other value: the clone writes it.
  if (dest) {
    rewriter.setInsertionPoint(terminator);
    DestWriteOp::create(rewriter, terminator->getLoc(), dest, value);
    dropForwarded(terminator, position);
  }
  return success();
}

// A function with self calls modulo a context: their contexts, each read
// once off its call.
struct Plan {
  FuncOp fn;
  llvm::SmallVector<Context> contexts;
};

struct Trmc : impl::IdrTrmcBase<Trmc> {
  void runOnProgram(ProgramOp program) {
    MLIRContext *ctx = program.getContext();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    solver::ProgramGraph &graph = getAnalysis<solver::ProgramGraph>();
    llvm::SmallVector<Plan> plans;
    LogicalResult read = success();
    for (FuncOp fn : program.getOps<FuncOp>()) {
      Plan plan{fn, {}};
      fn.walk([&](CallOp call) {
        if (call.getTailKind() != TailKind::modulo_context)
          return;
        std::optional<Context> context = contextOf(call);
        if (!context) {
          read = call.emitOpError("internal error: idr-trmc: a call modulo a context whose "
                                  "context no longer holds");
          return;
        }
        plan.contexts.push_back(std::move(*context));
      });
      if (!plan.contexts.empty())
        plans.push_back(std::move(plan));
    }
    if (failed(read))
      return signalPassFailure();
    if (plans.empty())
      return markAllAnalysesPreserved();

    IRRewriter rewriter(ctx);
    llvm::SmallVector<std::pair<FuncOp, FuncOp>> made;
    for (Plan &plan : plans) {
      FuncOp fn = plan.fn;
      ++numFunctions;
      numTails += plan.contexts.size();
      // The clone: the function, taking a destination for its result and
      // returning nothing.
      IRMapping mapping;
      auto clone = cast<FuncOp>(fn->clone(mapping));
      clone.setSymNameAttr(StringAttr::get(ctx, fn.getSymName() + ".trmc"));
      symbols.insert(clone, std::next(fn->getIterator()));
      Type dest = DestType::get(ctx, unrestricted(fn.getResultTypes()[0]));
      unsigned arity = clone.getNumArguments();
      (void)clone.insertArgument(arity, dest, DictionaryAttr(), fn.getLoc());
      llvm::SmallVector<Context> inClone;
      for (const Context &context : plan.contexts)
        inClone.push_back(mapped(context, mapping));

      Rewrite first(rewriter, fn, clone, plan.contexts);
      Rewrite again(rewriter, fn, clone, inClone);
      Operation *returned = fn.getBody().front().getTerminator();
      Operation *cloneReturned = clone.getBody().front().getTerminator();
      if (failed(again.give(cloneReturned->getOperand(0), cloneReturned, 0,
                            Written{clone.getArgument(arity)})) ||
          failed(first.give(returned->getOperand(0), returned, 0, Given{})))
        return signalPassFailure();
      (void)clone.eraseResult(0);
      // Each call the rewrite made or moved takes the kind its final place
      // gives it: the clone's calls in its tails are tail calls, the
      // function's first level calls the clone and then returns the value
      // it built. No call modulo a context is left.
      LogicalResult kinds = success();
      auto settle = [&](CallOp call) {
        if (call.getTailKind() == TailKind::modulo_context)
          kinds = call.emitOpError("internal error: idr-trmc left a call modulo a context");
        else if (call.getCalleeAttr().getAttr() == clone.getSymNameAttr())
          call.setTailKind(decide(call));
      };
      fn.walk(settle);
      clone.walk(settle);
      if (failed(kinds))
        return signalPassFailure();
      made.push_back({fn, clone});
    }

    // The program graph learns the clones and the calls that now go to
    // them; then every row, the clones' with the writes of their holes,
    // is made equal to its derivation.
    {
      solver::Editor editor = graph.thaw();
      for (const std::pair<FuncOp, FuncOp> &pair : made)
        (void)editor.insert(pair.second);
      for (auto [fn, clone] : made) {
        editor.setCallees(editor.id(FlatSymbolRefAttr::get(fn.getSymNameAttr())),
                          callRow(fn, editor));
        editor.setCallees(editor.id(FlatSymbolRefAttr::get(clone.getSymNameAttr())),
                          callRow(clone, editor));
      }
      std::move(editor).freeze();
    }
    rows::write(program, graph);
    markAnalysesPreserved<SymbolTable, solver::ProgramGraph>();
  }
};

} // namespace
} // namespace idr::tail
