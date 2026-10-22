// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-trmc's rewrite of a function's tails: at each tail, the value given
// goes on (the function's first level) or into the destination the clone
// takes. A self call whose result is given unchanged passes a destination
// on; a rejoin gives its own in each region; a value a context builds is
// built before what fills its hole, the hole's destination handed to the
// call or to the regions that fill it; any other value is written.

#include "idr/Transforms/Tail/Trmc.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Traits.h"
#include "idr/Support/Match.h"
#include "idr/Support/Remake.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

using namespace mlir;

namespace idr::tail::trmc {

namespace {

// The value a change of grade carries, through every such change.
Value throughRegrades(Value value) {
  while (Operation *def = value.getDefiningOp()) {
    if (!def->hasTrait<ResultCarriesOperand>())
      break;
    value = def->getOperand(0);
  }
  return value;
}

} // namespace

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
  CallOp::create(rewriter, call.getLoc(), clone, call.getIndexArgsAttr(), args,
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

namespace {

// The ends of `rejoin`'s regions that give its results, `position` among
// them: a region that never ends, or that jumps on, gives nothing here.
llvm::SmallVector<Operation *> endsGiving(Operation *rejoin, unsigned position) {
  llvm::SmallVector<Operation *> ends;
  for (Region &region : rejoin->getRegions()) {
    if (region.empty())
      continue;
    Operation *end = region.front().getTerminator();
    if (isa<RegionBranchTerminatorOpInterface>(end) && end->getNumOperands() > position &&
        end->getNumOperands() == rejoin->getNumResults())
      ends.push_back(end);
  }
  return ends;
}

} // namespace

void Rewrite::fillByRegions(Operation *rejoin, unsigned position, Value dest,
                            llvm::SmallVectorImpl<Pending> &work) {
  work.push_back(RemakeWithout{rejoin, position});
  llvm::SmallVector<Operation *> ends = endsGiving(rejoin, position);
  for (Operation *end : llvm::reverse(ends))
    work.push_back(GiveAt{end, position, Written{dest}});
}

void Rewrite::remakeWithout(Operation *rejoin, unsigned position) {
  llvm::SmallVector<Type> results(rejoin->getResultTypes());
  results.erase(results.begin() + position);
  Operation *made = remakeOp(rewriter, rejoin, rejoin->getOperands(), results);
  llvm::SmallVector<Value> kept;
  for (auto [at, result] : llvm::enumerate(rejoin->getResults()))
    if (at != position)
      kept.push_back(result);
  rewriter.replaceAllUsesWith(kept, made->getResults());
  rewriter.eraseOp(rejoin);
}

namespace {

// The destination a target writes, if it writes one.
Value destOf(const Target &target) {
  return idr::match(
      target, [](Given) { return Value(); }, [](Written written) { return written.dest; });
}

} // namespace

LogicalResult Rewrite::give(Operation *terminator, unsigned position, Target target) {
  llvm::SmallVector<Pending> work{GiveAt{terminator, position, target}};
  while (!work.empty()) {
    Pending next = work.pop_back_val();
    LogicalResult taken = idr::match(
        next, [&](const GiveAt &step) { return take(step, work); },
        [&](const RemakeWithout &remake) {
          remakeWithout(remake.rejoin, remake.position);
          return success();
        });
    if (failed(taken))
      return failure();
  }
  return success();
}

LogicalResult Rewrite::take(const GiveAt &step, llvm::SmallVectorImpl<Pending> &work) {
  Operation *terminator = step.terminator;
  unsigned position = step.position;
  Value value = terminator->getOperand(position);
  Value source = throughRegrades(value);
  Operation *def = source.getDefiningOp();
  Value dest = destOf(step.target);

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
      llvm::SmallVector<Operation *> ends = endsGiving(def, at);
      for (Operation *end : llvm::reverse(ends))
        work.push_back(GiveAt{end, at, Given{}});
      return success();
    }
    dropForwarded(terminator, position);
    fillByRegions(def, at, dest, work);
    return success();
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
    fillByRegions(producer, cast<OpResult>(filler).getResultNumber(), holeDest, work);
    return success();
  }

  // Any other value: the clone writes it.
  if (dest) {
    rewriter.setInsertionPoint(terminator);
    DestWriteOp::create(rewriter, terminator->getLoc(), dest, value);
    dropForwarded(terminator, position);
  }
  return success();
}

} // namespace idr::tail::trmc
