// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Extraction and the writing back of one function.
//
// Extraction takes each class's cheapest member by the engine's own cost,
// an op one and a constant none, until a measured model replaces it,
// among the members computable in the class's reach. Every use of a class
// is in its reach, so such a member is computable at each use, and its
// operands' reaches hold it, so theirs are too.
//
// A class may hold a member that reads the class itself, so prices are
// relaxed: passes over every node in creation order, each pricing a node
// whose operands are priced and moving its class to it where it costs
// less, until a pass moves none, and at most one pass per class. The best
// form of a class never reads one class twice down a path, since going
// round a cycle costs more, so each pass carries it at least one class
// further and the passes are enough.
//
// Elaboration goes through the regions in program order, a region's ops
// before the op after the region op that holds it, on an explicit stack.
// Before each skeleton op its operands are demanded where it is: a class
// placed in this scope or an enclosing one is that value; any other is
// made there, its operands first, so a value is computed in each scope
// that needs it and never above a match that does not. The skeleton's
// edits are carried out as their ops are reached. Then every floating op
// left unused is erased (sweep), and every call takes the tail fact its new
// place gives it. The placements and the regions' stack are the
// footprint's; a demand's postorder is the shared depth-first walk's.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/Tail.h"
#include "idr/Support/Nest.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <cassert>

using namespace mlir;

namespace idr::egraph::detail {

namespace {

// The attribute of an integer at `type`, as its form writes it.
TypedAttr attributeOf(Type type, const node::Integer &integer) {
  switch (integer.form) {
  case IntegerForm::Word:
    return IntegerAttr::get(type, integer.value);
  case IntegerForm::Splat:
    return DenseIntElementsAttr::get(cast<ShapedType>(type), integer.value);
  }
  return {};
}

// The engine's own cost: an op one, an atom, which is placed for nothing,
// none.
Cost ownCost(const Node &node) {
  return match(node.what, []<Atom N>(const N &) { return Cost::of(0); },
               [](const OneOf<node::Input, node::Built> auto &) { return Cost::of(1); });
}

} // namespace

// A class moves to a member only for a lower price, or for an equal price
// and a larger id, the newer form a rule's side built, while the price is
// below the cost's saturation. An op costs at least one, so a member chosen
// costs more than each class it reads; a move to a member reading a class
// that leads back to this one would raise its price, which no move does:
// so the chosen members close no cycle, and the demand's walk over them
// ends. Every node is settled at its class's root.
void Function::extract() {
  best.assign(classes.size(), std::nullopt);
  cost.assign(classes.size(), Cost::most());
  for (std::uint32_t pass = 0; pass < classes.size(); ++pass) {
    Changed moved = Changed::No;
    for (std::uint32_t n = 0; n < nodes.size(); ++n) {
      ++steps;
      NodeId member(n);
      const Node &node = at(member);
      std::uint32_t c = classOfNode(member).index();
      // A member computable only inside its class's reach is not computable
      // at every use of the class.
      if (needs(node) != classes[c].reach)
        continue;
      std::span<const ClassId> operands = childrenOf(node);
      auto priced = [&](ClassId operand) { return best[operand.index()].has_value(); };
      if (!llvm::all_of(operands, priced))
        continue;
      Cost total = ownCost(node);
      for (ClassId operand : operands)
        total = total.plus(cost[operand.index()]);
      if (best[c] && !(total < cost[c] ||
                       (total == cost[c] && total < Cost::most() && *best[c] < member)))
        continue;
      best[c] = member;
      cost[c] = total;
      moved = Changed::Yes;
    }
    if (moved == Changed::No)
      break;
  }
  for (std::uint32_t c = 0; c < classes.size(); ++c)
    assert((!forest.isRoot(ClassId(c)) || best[c]) && "every class has a member priced");
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
    // A leaf is where it is, and is chosen only for a class whose reach is
    // its region, which holds every scope that demands the class; anything
    // else is made there.
    return match(
        at(*best[c.index()]).what,
        [](const node::Leaf &leaf) -> std::optional<Value> { return leaf.value; },
        [](const node::Constant &) -> std::optional<Value> { return std::nullopt; },
        [](const node::Integer &) -> std::optional<Value> { return std::nullopt; },
        [](const node::Input &) -> std::optional<Value> { return std::nullopt; },
        [](const node::Built &) -> std::optional<Value> { return std::nullopt; });
  };

  // The value of `root` where `scope` demands it, made before the
  // rewriter's insertion point where it is not yet there: a postorder over
  // the chosen members, which goes past a class `scope` already sees and
  // makes each other one once its operands are made. The chosen members
  // form a DAG, so a class shared by two operands is made by the first and
  // seen by the second.
  auto demand = [&](ClassId root, RegionId scope, Location loc) -> Value {
    auto operandsOf = [&](ClassId c) { return childrenOf(at(*best[c.index()])); };
    auto seen = [&](ClassId c) { return placedIn(c, scope) ? Descend::Past : Descend::Into; };
    auto make = [&](ClassId c) {
      const Node &node = at(*best[c.index()]);
      SmallVector<Value, 4> values;
      for (ClassId operand : childrenOf(node))
        values.push_back(*placedIn(operand, scope));
      // A constant held as an attribute is materialized by its dialect; an
      // integer gets its attribute here, the one place the graph makes one;
      // an op of the input is copied, its properties with it; a built one is
      // made of its kind's op with the op's default properties; a leaf is
      // where it is.
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
          [&](const node::Integer &integer) -> Value {
            return arith::ConstantOp::create(rewriter, loc, node.type,
                                             attributeOf(node.type, integer))
                .getResult();
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
      placed[c.index()].emplace_back(scope, made);
    };
    depthFirst(root, operandsOf, seen, make);
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
                mlir::Region &region = op->getRegion(take.region);
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
              // The last turn decides no Rewrite: its rewrites ran between
              // the turns.
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
  if (tail::decided(fn))
    fn.getBody().walk([](CallOp call) { call.setTailKind(tail::decide(call)); });
}

} // namespace idr::egraph::detail
