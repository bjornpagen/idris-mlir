// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The canonicalization patterns of idr.match and idr.match_lit, which their
// getCanonicalizationPatterns add after upstream's region patterns, and how
// a match whose taken region is known is replaced by it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Worklist.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/Sequence.h"

using namespace mlir;
using namespace idr;

namespace {

// The literal match on `scrutinee`, or on a string appended of it, that
// has the case `""`: what a string known not to be empty reaches through
// the appends it is part of, which are then not empty either. Each value is
// looked at once.
MatchLitOp emptyCaseAbove(Value scrutinee) {
  OnceWorklist<Value> work;
  work.push(scrutinee);
  while (std::optional<Value> next = work.pop())
    for (Operation *user : next->getUsers()) {
      if (auto match = dyn_cast<MatchLitOp>(user);
          match && match.getScrutinee() == *next &&
          llvm::is_contained(match.getCases(), StringAttr::get(user->getContext(), "")))
        return match;
      if (auto append = dyn_cast<StrAppendOp>(user))
        work.push(append.getResult());
    }
  return {};
}

// A string that cannot be empty never takes the case `""`. Whether it can
// is read down the appends it is built of; a change there reaches the op
// above it alone. So the pattern is tried at every op: at a literal match,
// for its own scrutinee, and at a string known not to be empty, for the
// matches it reaches up through the appends it is part of.
struct DropEmptyStringCase : RewritePattern {
  explicit DropEmptyStringCase(MLIRContext *context)
      : RewritePattern(MatchAnyOpTypeTag(), PatternBenefit(1), context) {
    setDebugName("idr-drop-empty-string-case");
  }

  LogicalResult matchAndRewrite(Operation *root, PatternRewriter &rewriter) const final {
    auto match = dyn_cast<MatchLitOp>(root);
    if (match && knownNonEmpty(match.getScrutinee()) && drop(match, rewriter))
      return success();
    if (root->getNumResults() != 1 || !isa<StrType>(unrestricted(root->getResult(0).getType())) ||
        !knownNonEmpty(root->getResult(0)))
      return failure();
    MatchLitOp above = emptyCaseAbove(root->getResult(0));
    return success(above && drop(above, rewriter));
  }

private:
  // Drops the case `""` of `op`; whether it had one.
  static bool drop(MatchLitOp op, PatternRewriter &rewriter) {
    auto empty = rewriter.getStringAttr("");
    const auto *it = llvm::find(op.getCases(), empty);
    if (it == op.getCases().end())
      return false;
    auto dropped = static_cast<unsigned>(it - op.getCases().begin());
    SmallVector<unsigned> kept;
    for (unsigned index = 0, count = op.getNumCases(); index < count; ++index)
      if (index != dropped)
        kept.push_back(index);
    rewriter.replaceOp(op, op.rebuild(rewriter, op.getResultTypes(), kept, &op.getDefaultRegion()));
    return true;
  }
};

// A match that can take no region that yields never completes, so nothing
// after it in its block runs: that block, a region of another match or the
// function's body, ends in ub.unreachable right after it, as a region does
// after a crash. The regions it can take are the ones control may enter,
// as RegionBranchOpInterface says with its scrutinee's constant: the one it
// selects, or every region that is not empty, whatever the others do.
// Case-of-case copies a consumer into every region, so one region of a
// match may yield the result of a match that never completes, followed by
// what consumes it there. The block is the only one of its region, so
// nothing after the match is read anywhere else.
struct EndAfterNoYield : RewritePattern {
  EndAfterNoYield(StringRef root, MLIRContext *context)
      : RewritePattern(root, PatternBenefit(1), context) {
    setDebugName("idr-end-after-no-yield");
  }

  LogicalResult matchAndRewrite(Operation *root, PatternRewriter &rewriter) const final {
    auto match = cast<MatchOpInterface>(root);
    Attribute scrutinee;
    matchPattern(match.getScrutinee(), m_Constant(&scrutinee));
    SmallVector<RegionSuccessor> taken;
    cast<RegionBranchOpInterface>(root).getEntrySuccessorRegions(scrutinee, taken);
    if (!llvm::all_of(taken, [](RegionSuccessor &successor) {
          return isa<ub::UnreachableOp>(successor.getSuccessor()->front().getTerminator());
        }))
      return failure();
    Block *block = root->getBlock();
    if (!isa<MatchOpInterface, idr::FuncOp>(block->getParentOp()) ||
        isa<ub::UnreachableOp>(root->getNextNode()))
      return failure();
    SmallVector<Operation *> after;
    for (Operation *next = root->getNextNode(); next; next = next->getNextNode())
      after.push_back(next);
    // Users before what they use.
    for (Operation *dead : llvm::reverse(after))
      rewriter.eraseOp(dead);
    rewriter.setInsertionPointToEnd(block);
    ub::UnreachableOp::create(rewriter, root->getLoc());
    return success();
  }
};

// A result that every region that yields gives as a constructor of one tag
// of a value sum, built there for the yield alone, and that is only ever
// taken apart (each use reads a field of that tag): the match yields the
// constructor's fields instead, and the constructor is built once after it,
// where each read of a field folds to the field the regions gave. A field
// is then the value its region built it of, a linear one the thread it
// was, never a read of a value the match built: a linear array passed back
// beside a value (`Res`) stays the one buffer each region wrote. Before
// the grades, which fix each field's at its constructor's.
struct YieldFields : RewritePattern {
  YieldFields(StringRef root, MLIRContext *context)
      : RewritePattern(root, PatternBenefit(1), context) {
    setDebugName("idr-yield-fields");
  }

  LogicalResult matchAndRewrite(Operation *root, PatternRewriter &rewriter) const final {
    auto match = cast<MatchOpInterface>(root);
    auto fn = root->getParentOfType<idr::FuncOp>();
    if (!fn || stageFacts(fn.getProgram().getStage()).grades())
      return failure();
    for (OpResult result : root->getResults())
      if (std::optional<SmallVector<ConOp>> built = constructors(result)) {
        split(match, result, built->front(), rewriter);
        return success();
      }
    return failure();
  }

private:
  // The constructor each region that yields gives as `result`, when the
  // result is one to split.
  static std::optional<SmallVector<ConOp>> constructors(OpResult result) {
    if (!isa<DataType>(result.getType()) || result.use_empty())
      return std::nullopt;
    std::optional<Tag> tag;
    for (Operation *user : result.getUsers()) {
      auto field = dyn_cast<FieldOp>(user);
      if (!field || (tag && *tag != field.getTag()))
        return std::nullopt;
      tag = field.getTag();
    }
    SmallVector<ConOp> built;
    for (Region &region : result.getOwner()->getRegions()) {
      auto yield = region.empty() ? YieldOp() : dyn_cast<YieldOp>(region.front().getTerminator());
      if (!yield)
        continue;
      Value given = yield->getOperand(result.getResultNumber());
      auto con = given.getDefiningOp<ConOp>();
      if (!con || con->getBlock() != yield->getBlock() || !given.hasOneUse() ||
          con.getTag() != *tag ||
          (!built.empty() &&
           !llvm::equal(built.front().getFields().getTypes(), con.getFields().getTypes())))
        return std::nullopt;
      built.push_back(con);
    }
    if (built.empty())
      return std::nullopt;
    return built;
  }

  // `first` is the constructor the first region that yields gives.
  static void split(MatchOpInterface match, OpResult result, ConOp first,
                    PatternRewriter &rewriter) {
    // Read before the regions' constructors, `first` among them, are erased.
    Tag tag = first.getTag();
    unsigned index = result.getResultNumber();
    unsigned kept = match->getNumResults() - 1;
    SmallVector<Type> types;
    for (auto [i, type] : llvm::enumerate(match->getResultTypes()))
      if (i != index)
        types.push_back(type);
    llvm::append_range(types, first.getFields().getTypes());
    Operation *fresh =
        match.rebuild(rewriter, types, llvm::to_vector(llvm::seq(match.getNumCases())),
                      &match.getDefaultRegion());
    for (Region &region : fresh->getRegions()) {
      auto yield = region.empty() ? YieldOp() : dyn_cast<YieldOp>(region.front().getTerminator());
      if (!yield)
        continue;
      auto con = yield->getOperand(index).getDefiningOp<ConOp>();
      SmallVector<Value> fields(con.getFields());
      rewriter.modifyOpInPlace(yield, [&] {
        yield->eraseOperand(index);
        yield->insertOperands(yield->getNumOperands(), fields);
      });
      rewriter.eraseOp(con);
    }
    rewriter.setInsertionPointAfter(fresh);
    Value rebuilt = ConOp::create(rewriter, result.getLoc(), result.getType(),
                                  tag, fresh->getResults().drop_front(kept))
                        .getResult();
    SmallVector<Value> replacements(fresh->getResults().take_front(kept));
    replacements.insert(replacements.begin() + index, rebuilt);
    rewriter.replaceOp(match, replacements);
  }
};

// What both matches canonicalize with besides upstream's region patterns,
// which the hooks add first: each pattern rooted at the ops named `root`.
void populate(RewritePatternSet &results, MLIRContext *context, StringRef root) {
  canon::addMerge(results, context, root);
  results.add<EndAfterNoYield, YieldFields>(root, context);
}

} // namespace

namespace idr::canon {

namespace {

// The value whose fields a match on `scrutinee` is read from once it is
// inlined: the scrutinee seen through the linear positions it passed, back
// to the value nearest where it was made that is held at quantity many.
// Every read of it takes its fields apart again, so it is a value read any
// number of times; a constructor among the positions further on is what
// those reads then fold against. None when every value on the way is
// linear: the match takes a linear value apart, and its one read is the
// match.
std::optional<Value> fieldsReadFrom(Value scrutinee) {
  SmallVector<Value, 4> positions = linearPositions(scrutinee);
  auto plain = llvm::find_if(llvm::reverse(positions), [](Value value) {
    return quantityOf(value.getType()) != Quantity::One;
  });
  if (plain == llvm::reverse(positions).end())
    return std::nullopt;
  return *plain;
}

} // namespace

// A case's argument is the declared field at the scrutinee's grade; read
// from the value fieldsReadFrom gives, it is the field at that value's
// grade, as idr.field reads it, and the read is then held as the argument.
// The default's argument is the scrutinee, which it binds back.
Value readField(OpBuilder &builder, Location loc, Value value) {
  auto arg = cast<BlockArgument>(value);
  auto match = cast<MatchOpInterface>(arg.getOwner()->getParentOp());
  Region &region = *arg.getParentRegion();
  if (&region == &match.getDefaultRegion())
    return match.getScrutinee();
  Value field = FieldOp::create(builder, loc, *fieldsReadFrom(match.getScrutinee()),
                                *match.knownTag(region), arg.getArgNumber());
  return heldAs(builder, loc, field, arg.getType());
}

// One whose fields are read from a value held at quantity many; a literal
// match reads a value, never a linear one, and binds no field.
LogicalResult readsPlainValue(Operation *op) {
  return success(fieldsReadFrom(cast<MatchOpInterface>(op).getScrutinee()).has_value());
}

// Case-of-case and sinking are tried at every op, so the one hook adds
// them for both matches.
void addMatchPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate(results, context, MatchOp::getOperationName());
  canon::addStaticForcePatterns(results, context);
  canon::addCaseOfCase(results, context);
  canon::addSink(results, context);
}

void addMatchLitPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate(results, context, MatchLitOp::getOperationName());
  results.add<DropEmptyStringCase>(context);
}

} // namespace idr::canon
