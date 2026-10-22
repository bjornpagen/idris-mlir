// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Accumulate.cpp - idr-accumulate ------------------------------------===//
//
// A self call whose result its tail combines becomes a tail call that
// carries the combination so far: the function calls a clone with the
// operation's identity, and the clone combines before it calls itself. A
// tail of the clone that gives a value combines it with what it carries;
// a tail that is already a self call passes it on. idr-tail-loops makes
// the clone a loop, and the combination a value of the iteration. A
// short circuit (`&&`, `||` with the self call first) combines by a match
// the clone builds of the two constructors, whose second operand moves
// before the call: it runs on every path, which only a value that
// computes and may run anywhere does.
//
// What the clone combines by is held as data, never as an op of the
// function: the first site's op is gone once its site is rewritten, and
// the function's own body once it starts the clone.
//
// It runs before counting, while the call's result is still what the tail
// combines: counting borrows that result and drops it after the
// combination, after which the call would no longer be the tail.
//
// An optimization, so each clone is an action a debug counter may skip:
// the function is left as it was, and its frames keep its depth.
//
// The pass stays at the program: each clone is a new symbol of the
// program, which no pass on one function may add. Every function is
// planned on the program as it stands, each plan reading its own function.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Control/MatchFamily.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

#include <array>

namespace idr {
#define GEN_PASS_DEF_IDRACCUMULATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// idr-accumulate gives one function its accumulator clone; the unit is the
// function.
struct AccumulateAction : support::TaggedAction<AccumulateAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::accumulate;
};

// `value`, of a type refined to one constructor of `type`'s data, at
// `type`: the refinement forgotten by the dialect's cast, then the grade.
Value forgetRefinement(OpBuilder &b, Location loc, Value value, Type type) {
  Type carrier = unrestricted(type);
  if (unrestricted(value.getType()) != carrier)
    value = DataReindexOp::create(b, loc, graded(gradeOf(value.getType()), carrier), value);
  return heldAs(b, loc, value, type);
}

// `a ⊕ b` at `type`, the function's result type: the law's op made again
// from what it is; or the short circuit's match, which gives `a` where `a`
// is the absorbing constructor and `b` where it is the other, so `b` is
// read only where `a` does not decide. Where `a`'s type already says which
// it is, that decides here, never at run time.
Value combine(RewriterBase &rewriter, Location loc, const Combination &by, Type type, Value a,
              Value b) {
  return idr::match(
      by,
      [&](const Law &law) -> Value {
        OperationState state(loc, law.name);
        state.addOperands({a, b});
        state.addTypes(type);
        state.addAttributes(law.discardable.getValue());
        state.propertiesAttr = law.properties;
        return rewriter.create(state)->getResult(0);
      },
      [&](const ShortCircuit &circuit) -> Value {
        std::optional<Tag> known = statedConstructor(a);
        if (known == circuit.absorbing)
          return a;
        if (known == circuit.identity)
          return b;
        std::array<Tag, 2> tags{circuit.absorbing, circuit.identity};
        auto made = DataMatchOp::create(rewriter, loc, TypeRange(type), a, ValueRange(), tags);
        OpBuilder::InsertionGuard guard(rewriter);
        Region &absorbing = made.getCaseRegion(0);
        Block *absorbs =
            rewriter.createBlock(&absorbing, absorbing.end(), circuit.absorbingType, loc);
        YieldOp::create(rewriter, loc,
                        forgetRefinement(rewriter, loc, absorbs->getArgument(0), type));
        Region &other = made.getCaseRegion(1);
        rewriter.createBlock(&other, other.end(), circuit.identityType, loc);
        YieldOp::create(rewriter, loc, b);
        return made->getResult(0);
      });
}

// The operation's identity at `type`, from which the function the program
// calls starts the clone: the law's constant, as its op's dialect makes it;
// or the short circuit's other constructor, a constant of its refined type.
Value identityAt(RewriterBase &rewriter, Location loc, const Combination &by, Type type) {
  return idr::match(
      by,
      [&](const Law &law) -> Value {
        return law.name.getDialect()
            ->materializeConstant(rewriter, law.identity, type, loc)
            ->getResult(0);
      },
      [&](const ShortCircuit &circuit) -> Value {
        Type bare = unrestricted(circuit.identityType);
        auto constructor =
            ConAttr::get(rewriter.getContext(), dataTypeOf(bare), rewriter.getArrayAttr({}));
        Value made = ConstantOp::create(rewriter, loc, bare, constructor);
        return forgetRefinement(rewriter, loc, made, type);
      });
}

// The value the combination at `site` takes beside the call's, ready where
// the combination is: a law's other operand; or what the short circuit's
// other region gives, its ops moved out before the match, which they may
// precede (they only compute, on every path), each call among them taking
// the fact its new place gives it.
Value otherOf(RewriterBase &rewriter, const Combined &site, Operation *at) {
  return idr::match(
      site.by,
      [&](const Law &) -> Value { return at->getOperand(site.side == Side::Left ? 1 : 0); },
      [&](const ShortCircuit &circuit) -> Value {
        Region *other =
            control::takenRegion(cast<DataMatchOp>(at), static_cast<int32_t>(circuit.identity));
        Block &body = other->front();
        llvm::SmallVector<Operation *> moved;
        for (Operation &op : llvm::make_early_inc_range(body.without_terminator())) {
          rewriter.moveOpBefore(&op, at);
          moved.push_back(&op);
        }
        for (Operation *op : moved)
          op->walk([](CallOp call) { call.setTailKind(decide(call)); });
        return body.getTerminator()->getOperand(0);
      });
}

// A tail call of `clone` in place of `old`, passing `carried` after the
// call's arguments, at the same index terms: the clone is the same
// recursion with the same facts, and the call takes its row.
CallOp callClone(RewriterBase &rewriter, CallOp old, FuncOp clone, Value carried) {
  llvm::SmallVector<Value> args(old.getArgs());
  args.push_back(carried);
  return CallOp::create(rewriter, old.getLoc(), clone, old.getIndexArgsAttr(), args,
                        TailKind::tail);
}

// The clone of `fn` that carries the combination, entered right after it;
// `fn` calls it with the identity.
void seed(RewriterBase &rewriter, SymbolTable &symbols, FuncOp fn, const Accumulator &plan) {
  MLIRContext *ctx = fn.getContext();
  Type carriedType = fn.getFunctionType().getResult(0);
  IRMapping mapping;
  auto clone = cast<FuncOp>(fn->clone(mapping));
  clone.setSymNameAttr(StringAttr::get(ctx, fn.getSymName() + ".acc"));
  (void)clone.insertArgument(clone.getNumArguments(), carriedType, DictionaryAttr(),
                             fn.getLoc());
  symbols.insert(clone, std::next(fn->getIterator()));
  Value carried = clone.getArguments().back();

  for (const Site &site : plan.sites)
    idr::match(
        site,
        [&](CallOp call) {
          auto inClone = cast<CallOp>(mapping.lookup(call.getOperation()));
          rewriter.setInsertionPoint(inClone);
          rewriter.replaceOp(inClone, callClone(rewriter, inClone, clone, carried));
        },
        [&](const Combined &combined) {
          auto call = cast<CallOp>(mapping.lookup(combined.call.getOperation()));
          Operation *at = mapping.lookup(combined.combine);
          Value other = otherOf(rewriter, combined, at);
          rewriter.setInsertionPoint(at);
          // The other operand joins what is carried on the call's side: for
          // f(...) ⊕ g the clone goes on with g ⊕ carried, for g ⊕ f(...)
          // with carried ⊕ g.
          Value next = combined.side == Side::Left
                           ? combine(rewriter, at->getLoc(), plan.by, carriedType, other, carried)
                           : combine(rewriter, at->getLoc(), plan.by, carriedType, carried, other);
          rewriter.replaceOp(at, callClone(rewriter, call, clone, next));
          rewriter.eraseOp(call);
        });

  // Every other tail of the clone combines the value it gives, on the side
  // the calls were on; a call that gave it is no longer in tail position,
  // and takes the fact its place now gives it.
  for (Block *end : tailEnds(clone)) {
    Operation *terminator = end->getTerminator();
    if (terminator->getNumOperands() != 1)
      continue;
    auto call = dyn_cast_or_null<CallOp>(tailSource(*end));
    if (call && call.getCalleeAttr().getAttr() == clone.getSymNameAttr())
      continue;
    rewriter.setInsertionPoint(terminator);
    Value value = terminator->getOperand(0);
    Location loc = terminator->getLoc();
    Value given = plan.side == Side::Left
                      ? combine(rewriter, loc, plan.by, carriedType, value, carried)
                      : combine(rewriter, loc, plan.by, carriedType, carried, value);
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperand(0, given); });
    if (call)
      call.setTailKind(decide(call));
  }

  // The function the program calls starts the clone at the identity.
  Block &entry = fn.getBody().front();
  for (Operation &op : llvm::make_early_inc_range(llvm::reverse(entry)))
    rewriter.eraseOp(&op);
  rewriter.setInsertionPointToStart(&entry);
  Value identity = identityAt(rewriter, fn.getLoc(), plan.by, carriedType);
  llvm::SmallVector<Value> args(entry.getArguments());
  args.push_back(identity);
  unsigned own = static_cast<unsigned>(
      cast<ErasedBinderOpInterface>(fn.getOperation()).getBoundSorts(fn.getBody()).size());
  auto call = CallOp::create(rewriter, fn.getLoc(), clone, families::levelArgs(ctx, 0, own), args,
                             TailKind::tail);
  ReturnOp::create(rewriter, fn.getLoc(), call.getResults());
}

struct Accumulate : impl::IdrAccumulateBase<Accumulate> {
  void runOnProgram(ProgramOp program) {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    footprint::Vector<std::pair<FuncOp, Accumulator>> plans;
    for (FuncOp fn : program.getOps<FuncOp>())
      if (std::optional<Accumulator> plan = accumulatorOf(fn))
        plans.emplace_back(fn, std::move(*plan));
    IRRewriter rewriter(program.getContext());
    unsigned performed = 0;
    for (auto &[fn, plan] : plans)
      performed += support::perform<AccumulateAction>(fn, [&] {
        seed(rewriter, symbols, fn, plan);
        ++numFunctions;
        numTails += static_cast<uint64_t>(llvm::count_if(plan.sites, [](const Site &site) {
          return idr::match(
              site, [](CallOp) { return false; }, [](const Combined &) { return true; });
        }));
      });
    if (performed == 0)
      return markAllAnalysesPreserved();
    markAnalysesPreserved<SymbolTable>();
  }
};

} // namespace
} // namespace idr::tail
