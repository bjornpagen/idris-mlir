// A value computed in the match's block that only the match's regions use
// moves into each region that uses it, when there it meets a consumer that
// folds against it: output of a string it builds, a consumer a match of
// its moves into (case-of-case), or an apply that eliminates the result of
// a call, which raising then moves into the callee. Only one region runs,
// so the value is still computed at most once. A constructor, a closure or
// an entry into a linear type moves into the regions that use it without a
// consumer to meet: built where it is used, a cell is built only on the
// paths that use it, and after the reads there of the fields it takes,
// which then need no count of their own; entered on a path that does not
// use it, a linear value would be left there for counting to drop. Such a
// copy is one op, and no consumer follows it in.
//
// A value that only computes may run on fewer paths. One that may crash or
// not return moves only when every region uses it and every op between it
// and the match only computes: every path still computes it, before
// anything it could hide.
//
// The copies are bounded: each region past the first may receive at most
// kSinkBudget ops, so a large match is not copied into every case of
// another. A constant stays where it is: the folder hoists constants back,
// and each would undo the other.

#include "Dialect/Canonicalize/Matches.h"


using namespace mlir;
using namespace idr;

namespace {

constexpr int64_t kSinkBudget = 64;

// Whether the user holding `use` folds or canonicalizes against `value`
// once they meet: what feeds() says for a value an op builds, and for a
// match's result, a consumer that case-of-case would move into the match.
bool meets(Value value, OpOperand &use) {
  if (canon::feeds(value, use))
    return true;
  auto result = dyn_cast<OpResult>(value);
  return result && isa<MatchOp, MatchLitOp>(result.getOwner()) &&
         canon::meetsInSomeRegion(result, use.getOwner());
}

// The regions of `match` in which `value` is used.
SmallVector<Region *> usersIn(Operation *value, Operation *match) {
  SmallVector<Region *> out;
  for (Region &region : match->getRegions())
    if (llvm::any_of(value->getUsers(), [&](Operation *user) {
          return region.isAncestor(user->getParentRegion());
        }))
      out.push_back(&region);
  return out;
}

// Whether `value` may run later, in the regions of `match` that use it.
bool movesInto(Operation *value, Operation *match, size_t regions) {
  if (onlyAllocates(value))
    return true;
  if (regions != match->getNumRegions() || performsIO(value))
    return false;
  for (Operation *between = value->getNextNode(); between != match;
       between = between->getNextNode())
    if (!onlyAllocates(between))
      return false;
  return true;
}

bool sinkable(Operation *value, Operation *match) {
  if (value->getNumResults() == 0 || value->use_empty() ||
      value->hasTrait<OpTrait::ConstantLike>())
    return false;
  if (!llvm::all_of(value->getUsers(), [&](Operation *user) {
        return user != match && match->isAncestor(user);
      }))
    return false;
  size_t regions = usersIn(value, match).size();
  if (!movesInto(value, match, regions))
    return false;
  if (!isa<ConOp, ClosureOp, LinEnterOp>(value) &&
      !llvm::any_of(value->getResults(), [](Value result) {
        return llvm::any_of(result.getUses(), [&](OpOperand &use) { return meets(result, use); });
      }))
    return false;
  int64_t size = 0;
  value->walk([&](Operation *) { ++size; });
  return (static_cast<int64_t>(regions) - 1) * size <= kSinkBudget;
}

template <typename Match>
struct SinkIntoRegions : OpRewritePattern<Match> {
  explicit SinkIntoRegions(MLIRContext *context) : OpRewritePattern<Match>(context) {
    this->setDebugName("idr-sink-into-regions");
  }
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    // The candidates are the ops before the match in its block. Visiting the
    // values its regions use instead would walk all of its nested regions
    // each time the match is revisited, and the rewrite driver revisits a
    // match whenever anything inside it changes: in a function whose matches
    // nest dozens deep, as case-of-case makes them, that dominated
    // compilation.
    Operation *value = nullptr;
    for (Operation *def = op->getPrevNode(); def && !value; def = def->getPrevNode())
      if (sinkable(def, op))
        value = def;
    if (!value)
      return failure();
    for (Region *region : usersIn(value, op)) {
      auto inside = [&](OpOperand &use) {
        return region->isAncestor(use.getOwner()->getParentRegion());
      };
      rewriter.setInsertionPointToStart(&region->front());
      Operation *copy = rewriter.clone(*value);
      rewriter.replaceUsesWithIf(value->getResults(), copy->getResults(), inside);
    }
    rewriter.eraseOp(value);
    return success();
  }
};

} // namespace

template <typename Match> void canon::addSink(RewritePatternSet &results, MLIRContext *context) {
  results.add<SinkIntoRegions<Match>>(context);
}

template void canon::addSink<MatchOp>(RewritePatternSet &, MLIRContext *);
template void canon::addSink<MatchLitOp>(RewritePatternSet &, MLIRContext *);
