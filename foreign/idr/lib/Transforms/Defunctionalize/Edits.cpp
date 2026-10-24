// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Each function's edits, read off the solve by the decision on the pass
// thread before any type changes, each with every type and attribute it
// builds, so a worker only makes them:
//   - each value whose type changes, the entry block's arguments taking
//     the converted signature;
//   - each operand whose value moves between two keys, and its coercion,
//     built before the op that moves it;
//   - each closure and suspension, and the constructor it becomes;
//   - each apply, and the match it becomes, with the moves in its cases;
//   - each force, and the move after its call;
//   - each constant that holds a closure, converted.
// A match or a coercion is built where the index variables of the region
// it stands in are bound; a case's binders bind more for what stands in it.
// Another function is read only through its signature.

#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Joins.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// Whether an apply stands in tail position, read off its function's tails
// before it is replaced: an apply holds no fact of where it stands.
enum class TailPosition : bool { Within, Tail };

} // namespace

FailureOr<Edits> Decision::plan(FuncOp fn) {
  Edits edits{fn, {}, {}, {}, {}, {}, {}};
  auto retype = [&](Value value, Type type) {
    if (value.getType() != type)
      edits.retypes.push_back({value, type});
  };
  for (auto [arg, type] :
       llvm::zip_equal(fn.getArguments(), signature(graph.id(fn)).converted.getInputs()))
    retype(arg, type);
  // Each value's type and each move, in one walk: the regions an op holds
  // bind their arguments, which are retyped with it.
  fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
    for (OpOperand &use : op->getOpOperands()) {
      Slot from = keyOf(use.get()), to = sinkOf(use);
      if (from && to && *from != *to)
        edits.moves.push_back({&use, coercionOf(typeOf(use.get().getType(), from), *from, *to,
                                              joins::scopeDepth(op->getParentRegion()))});
    }
    for (Value result : op->getResults())
      retype(result, typeOf(result.getType(), keyOf(result)));
    if (op == fn.getOperation())
      return;
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Value arg : block.getArguments())
          retype(arg, typeOf(arg.getType(), keyOf(arg)));
  });

  // A closure or a suspension is its label's constructor, refined to it at
  // the terms the op gives its function's index variables, built at its own
  // grade.
  fn.walk([&](BuildsLabelOpInterface op) {
    Key key = *keyOf(op.getResult());
    Type type = typeOf(op.getResult().getType(), key);
    edits.constructs.push_back({op, constructorOf(familyOf(key).at, tagOf(key, op.getCalleeAttr()),
                                                  gradeOf(type), op.getIndexArgs().getTerms())});
  });

  // An apply's cases: each label's call takes the captures, then the
  // arguments, each moved into the label's parameter where their keys
  // differ, and gives its results, each moved into the apply's. A tail
  // apply's calls are in tail position, so no result may be rebuilt after
  // one. What stands at the function's tails, read once.
  SmallVector<Operation *> tails = tail::sourcesOf(fn);
  WalkResult applied = fn.walk([&](FnApplyOp apply) -> WalkResult {
    Key key = *keyOf(apply.getCallee());
    if (key.labels.empty()) {
      edits.applies.push_back(Unreached{apply});
      return WalkResult::advance();
    }
    unsigned depth = joins::scopeDepth(apply->getParentRegion());
    TailPosition position = llvm::is_contained(tails, apply.getOperation())
                                ? TailPosition::Tail
                                : TailPosition::Within;
    MatchId over = matchOver(typeOf(apply.getCallee().getType(), key), depth);
    Dispatch dispatch{apply, over, {}};
    for (auto [at, label] : llvm::enumerate(key.labels.getAsRange<FlatSymbolRefAttr>())) {
      const Signature &run = signature(graph.id(label));
      // Read before a coercion adds a match.
      unsigned inner = depth + static_cast<unsigned>(match(over).cases[at].binders.getCount());
      auto captures = static_cast<unsigned>(match(over).cases[at].fields.size());
      FunctionType bound = match(over).callees[at].bound;
      CaseMoves moves;
      for (auto [i, arg] : llvm::enumerate(apply.getArgs())) {
        Slot own = keyOf(arg);
        const Slot &into = run.arguments[captures + i];
        moves.arguments.push_back(
            own && into && *own != *into
                ? std::optional(coercionOf(typeOf(arg.getType(), own), *own, *into, inner))
                : std::nullopt);
      }
      // Each result with its slot in the label's signature and its type
      // at the case's terms, one walk over the three.
      for (auto [result, out, given] :
           llvm::zip_equal(apply.getResults(), run.results, bound.getResults())) {
        Slot own = keyOf(result);
        if (!own || !out || *own == *out) {
          moves.results.push_back(std::nullopt);
          continue;
        }
        if (position == TailPosition::Tail) {
          apply.emitError("internal error: idr-defunctionalize: the label ")
              << label << " of a tail apply gives a closure of other labels than the "
              << "apply's, rebuilt after the call";
          return WalkResult::interrupt();
        }
        moves.results.push_back(coercionOf(given, *out, *own, inner));
      }
      dispatch.cases.push_back(std::move(moves));
    }
    edits.applies.push_back(std::move(dispatch));
    return WalkResult::advance();
  });
  if (applied.wasInterrupted())
    return failure();

  // A force calls its cell's dispatch function; what it gives is the
  // forced state's value, moved into the force's slot where the two differ.
  fn.walk([&](LazyForceOp force) {
    Key cell = *keyOf(force.getSuspension());
    KeyId memo = idOf(cell);
    Slot forced = anchorKey(FlowAnchor::forcedOf(cast<LazyType>(cell.carrier)));
    Slot own = keyOf(force.getResult());
    std::optional<CoercionId> moved;
    if (own && forced && *own != *forced)
      moved = coercionOf(family(memo).force.gives, *forced, *own,
                         joins::scopeDepth(force->getParentRegion()));
    edits.forces.push_back({force, memo, moved});
  });

  fn.walk([&](ConstantOp op) {
    Attribute value = constantOf(op.getValue(), keyOf(op.getResult()));
    if (value != op.getValue())
      edits.constants.push_back({op, value});
  });
  return edits;
}

} // namespace idr::defunctionalize
