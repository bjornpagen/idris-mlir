// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Extraction and the writing back of one function.
//
// Extraction takes each class's cheapest member, bottom-up in creation
// order: a node's operands' classes were made before it, so one pass
// prices every class. Ties go to the larger id, the rewritten form.
//
// Elaboration goes through the regions in program order, a region's ops
// before the op after the region op that holds it, on an explicit stack.
// Before each skeleton op its operands are demanded where it is: a class
// placed in this scope or an enclosing one is that value; any other is
// made there, its operands first, so a value is computed in each scope
// that needs it and never above a match that does not. The skeleton's
// edits are carried out as their ops are reached. Then every floating op
// left unused is erased (sweep), and every call takes the tail fact its new
// place gives it. The placements and both stacks are the footprint's.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/Tail.h"

#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

// What each stage of a program implies: whether every call's tail fact is
// the decider's.
#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;

namespace idr::egraph::detail {

namespace {

Cost ownCost(const Node &node) {
  return match(node.what, []<Atom N>(const N &) { return Cost::of(0); },
               [](const node::Input &) { return Cost::of(1); },
               [](const node::Built &) { return Cost::of(1); });
}

} // namespace

void Function::extract() {
  best.assign(classes.size(), std::nullopt);
  cost.assign(classes.size(), Cost::of(0));
  for (std::uint32_t c = 0; c < classes.size(); ++c) {
    for (NodeId member : membersOf(classes[c])) {
      const Node &node = at(member);
      Cost total = ownCost(node);
      for (ClassId operand : childrenOf(node))
        total = total.plus(cost[operand.index()]);
      if (!best[c] || total < cost[c] || (total == cost[c] && *best[c] < member)) {
        best[c] = member;
        cost[c] = total;
      }
    }
  }
}

bool Function::visible(RegionId placed, RegionId scope) const {
  std::optional<RegionId> at = scope;
  while (at && this->at(*at).depth >= this->at(placed).depth) {
    if (*at == placed)
      return true;
    at = this->at(*at).parent;
  }
  return false;
}

void Function::elaborate(RewriterBase &rewriter) {
  // Where each class is placed so far: a scope and its value there.
  footprint::Vector<footprint::Vector<std::pair<RegionId, Value>>> placed(classes.size());
  auto placedIn = [&](ClassId c, RegionId scope) -> std::optional<Value> {
    for (auto [region, value] : placed[c.index()]) {
      ++steps;
      if (visible(region, scope))
        return value;
    }
    // A leaf is where it is, in every scope; anything else is made there.
    return match(
        at(*best[c.index()]).what,
        [](const node::Leaf &leaf) -> std::optional<Value> { return leaf.value; },
        [](const node::Constant &) -> std::optional<Value> { return std::nullopt; },
        [](const node::Input &) -> std::optional<Value> { return std::nullopt; },
        [](const node::Built &) -> std::optional<Value> { return std::nullopt; });
  };

  // The value of `root` where `scope` demands it, made before the
  // rewriter's insertion point where it is not yet there: a postorder over
  // the chosen members, on an explicit stack.
  auto demand = [&](ClassId root, RegionId scope, Location loc) -> Value {
    struct Step {
      ClassId cls;
      bool expanded;
    };
    footprint::Vector<Step> work{{root, false}};
    while (!work.empty()) {
      Step step = work.back();
      if (placedIn(step.cls, scope)) {
        work.pop_back();
        continue;
      }
      const Node &node = at(*best[step.cls.index()]);
      std::span<const ClassId> operands = childrenOf(node);
      if (!step.expanded && !operands.empty()) {
        work.back().expanded = true;
        for (ClassId operand : llvm::reverse(operands))
          if (!placedIn(operand, scope))
            work.push_back({operand, false});
        continue;
      }
      SmallVector<Value, 4> values;
      for (ClassId operand : operands)
        values.push_back(*placedIn(operand, scope));
      // A constant is materialized by its dialect; an op of the input is
      // copied, its properties with it; a built one is made of its kind's op
      // with the op's default properties; a leaf is where it is.
      Value made = match(
          node.what, [](const node::Leaf &leaf) -> Value { return leaf.value; },
          [&](const node::Constant &literal) -> Value {
            Operation *op =
                literal.dialect->materializeConstant(rewriter, literal.value, node.type, loc);
            // A dialect folds only to what it materializes (MLIR's folding
            // contract), so a constant class always has its op.
            if (!op)
              llvm::reportFatalInternalError("idr-simplify: a folded constant its dialect does "
                                             "not materialize");
            return op->getResult(0);
          },
          [&](const node::Input &op) -> Value {
            IRMapping mapping;
            for (auto [old, now] : llvm::zip_equal(op.origin->getOperands(), values))
              mapping.map(old, now);
            return rewriter.clone(*op.origin, mapping)->getResult(0);
          },
          [&](const node::Built &op) -> Value {
            OperationState state(loc, op.name);
            state.addOperands(values);
            state.addTypes(node.type);
            return rewriter.create(state)->getResult(0);
          });
      placed[step.cls.index()].emplace_back(scope, made);
      work.pop_back();
    }
    return *placedIn(root, scope);
  };

  // One region's skeleton, written back in `scope`: a region's own, or, for
  // a region a Take moved into its op's place, the op's, whose terminator
  // gives the taken op its results.
  struct Frame {
    Run skeleton;
    std::uint32_t next;
    RegionId scope;
    Operation *taken;
  };
  // The function's body is the first region the build numbered.
  RegionId body = RegionId(0);
  footprint::Vector<Frame> stack{{at(body).skeleton, 0, body, nullptr}};
  auto regionAt = [&](const Skeletal &entry, unsigned index) {
    return RegionId(entry.regions->index() + index);
  };
  auto pushRegions = [&](const Skeletal &entry) {
    for (unsigned index = entry.op->getNumRegions(); index-- > 0;) {
      RegionId id = regionAt(entry, index);
      stack.push_back({at(id).skeleton, 0, id, nullptr});
    }
  };

  while (!stack.empty()) {
    Frame &frame = stack.back();
    if (frame.next == frame.skeleton.count) {
      stack.pop_back();
      continue;
    }
    Skeletal entry = skeleton[frame.skeleton.first + frame.next++];
    RegionId scope = frame.scope;
    Operation *taken = frame.taken;
    Operation *op = entry.op;

    rewriter.setInsertionPoint(op);
    SmallVector<Value, 4> operands;
    for (Value operand : op->getOperands())
      operands.push_back(demand(*classOf[numbering.at(operand)], scope, op->getLoc()));
    if (!llvm::equal(operands, op->getOperands()))
      rewriter.modifyOpInPlace(op, [&] { op->setOperands(operands); });

    // The terminator of a region a Take moved: what it yields is the taken
    // op's results.
    if (taken && op->hasTrait<OpTrait::IsTerminator>()) {
      rewriter.replaceOp(taken, operands);
      rewriter.eraseOp(op);
      continue;
    }

    match(
        entry.fate, [&](const Kept &) { pushRegions(entry); },
        [&](const Merged &merged) { rewriter.replaceOp(op, merged.into->getResults()); },
        [&](const Decided &decided) {
          match(
              decided.edit,
              [&](const Forward &forward) {
                SmallVector<Value, 2> results;
                for (unsigned operand : forward.operandOfResult)
                  results.push_back(operands[operand]);
                rewriter.replaceOp(op, results);
              },
              [&](const Take &take) {
                Region &region = op->getRegion(take.region);
                Block &block = region.front();
                SmallVector<Value, 2> arguments;
                for (auto [argument, operand] :
                     llvm::zip_equal(block.getArguments(), take.operandOfArgument)) {
                  ClassId argClass = *classOf[numbering.at(argument)];
                  placed[argClass.index()].emplace_back(scope, operands[operand]);
                  arguments.push_back(operands[operand]);
                }
                RegionId moved = regionAt(entry, take.region);
                rewriter.inlineBlockBefore(&block, op, arguments);
                stack.push_back({at(moved).skeleton, 0, scope, op});
              },
              // The last round decides no Rewrite: its rewrites ran between
              // the rounds.
              [&](const Rewrite &) { pushRegions(entry); });
        });
  }

  sweep(rewriter);

  // What follows a call is new wherever a floating op followed it, since
  // every one was made again where it is demanded and the input's erased;
  // a call that floated was made again itself, and an edit or a merge
  // erased the op it stood for. So a call may now end a tail, or its
  // result flow into cells built for it, or neither any more. Telling an
  // unchanged call apart costs what deciding it does, so each takes its
  // fact where it now stands. Before the program is first order its calls
  // promise nothing, and no pass decides one.
  if (tailsAt[fn.getProgram().getStage()] == StageTails::Decided)
    fn.getBody().walk([](CallOp call) { call.setTailKind(tail::decide(call)); });
}

} // namespace idr::egraph::detail
