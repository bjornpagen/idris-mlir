// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Output and the first character of a string being built, as each builder
// says of itself (StrBuilderOpInterface): whether its string is never
// empty, whether output may write the pieces it is built of instead, and
// whether its first character is known without building it. Two patterns
// read the interface, output of a builder's string and its first
// character, and folding drops output of the empty string (PutStrOp::fold).
// Output of a list (idr.io.put_list) takes one step of the list it meets
// (PutList.cpp).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;
using namespace idr;

namespace {

// The interface builds a piece only where its predicate holds: asked
// otherwise, the asker skipped the predicate, a bug of ours.
[[noreturn]] void unasked(Operation *op, StringRef method) {
  llvm::reportFatalInternalError(llvm::Twine(method) + " asked of " +
                                 op->getName().getStringRef() + ", whose predicate denies it");
}

// Output of a string its builder writes in pieces writes them instead, in
// the same order, through the world: a string built only to be written is
// never built, and one with another use is built for that use alone.
struct PutStrOfBuilder : OpRewritePattern<PutStrOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(PutStrOp op, PatternRewriter &rewriter) const final {
    auto builder = op.getStr().getDefiningOp<StrBuilderOpInterface>();
    if (!builder || !builder.writesInPieces())
      return failure();
    rewriter.setInsertionPoint(op);
    rewriter.replaceOp(op, builder.writePieces(rewriter, op.getWorld()));
    return success();
  }
};

// The first character of a string its builder knows is what it builds it
// with, read on the builder's string or through the guard that it is not
// empty, which Emit puts before a head and which folds away on such a
// builder.
struct HeadOfBuilder : OpRewritePattern<StrHeadOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(StrHeadOp op, PatternRewriter &rewriter) const final {
    Value str = op.getStr();
    if (auto guard = str.getDefiningOp<CheckNonemptyOp>())
      str = guard.getStr();
    auto builder = str.getDefiningOp<StrBuilderOpInterface>();
    if (!builder || !builder.knowsFirstChar())
      return failure();
    rewriter.setInsertionPoint(op);
    rewriter.replaceOp(op, builder.firstChar(rewriter));
    return success();
  }
};

} // namespace

//===----------------------------------------------------------------------===//
// What each builder says of itself
//===----------------------------------------------------------------------===//

// `a ++ b`: either part may be empty, and its head is unknown; output
// writes `a`, then `b`.
bool StrAppendOp::nonEmpty() { return false; }
bool StrAppendOp::writesInPieces() { return true; }
Value StrAppendOp::writePieces(OpBuilder &b, Value world) {
  Value after = PutStrOp::create(b, getLoc(), world.getType(), getLhs(), world).getNext();
  return PutStrOp::create(b, getLoc(), world.getType(), getRhs(), after).getNext();
}
bool StrAppendOp::knowsFirstChar() { return false; }
Value StrAppendOp::firstChar(OpBuilder &) { unasked(*this, "firstChar"); }

// A character before a string: output writes the character, then the
// string; the character is its head.
bool StrConsOp::nonEmpty() { return true; }
bool StrConsOp::writesInPieces() { return true; }
Value StrConsOp::writePieces(OpBuilder &b, Value world) {
  Value after = PutCharOp::create(b, getLoc(), world.getType(), getHead(), world).getNext();
  return PutStrOp::create(b, getLoc(), world.getType(), getTail(), after).getNext();
}
bool StrConsOp::knowsFirstChar() { return true; }
Value StrConsOp::firstChar(OpBuilder &) { return getHead(); }

// One character, written as itself, its own head.
bool StrFromCharOp::nonEmpty() { return true; }
bool StrFromCharOp::writesInPieces() { return true; }
Value StrFromCharOp::writePieces(OpBuilder &b, Value world) {
  return PutCharOp::create(b, getLoc(), world.getType(), getValue(), world).getNext();
}
bool StrFromCharOp::knowsFirstChar() { return true; }
Value StrFromCharOp::firstChar(OpBuilder &) { return getValue(); }

// The text of a number, which has a digit at least: output writes the
// number, and its head is its first digit or sign, each by the runtime's
// function for its kind.
bool StrShowSIntOp::nonEmpty() { return true; }
bool StrShowSIntOp::writesInPieces() { return true; }
Value StrShowSIntOp::writePieces(OpBuilder &b, Value world) {
  return PutSIntOp::create(b, getLoc(), world.getType(), getValue(), world).getNext();
}
bool StrShowSIntOp::knowsFirstChar() { return true; }
Value StrShowSIntOp::firstChar(OpBuilder &b) {
  return IntHeadSOp::create(b, getLoc(), b.getI32Type(), getValue()).getResult();
}

bool StrShowUIntOp::nonEmpty() { return true; }
bool StrShowUIntOp::writesInPieces() { return true; }
Value StrShowUIntOp::writePieces(OpBuilder &b, Value world) {
  return PutUIntOp::create(b, getLoc(), world.getType(), getValue(), world).getNext();
}
bool StrShowUIntOp::knowsFirstChar() { return true; }
Value StrShowUIntOp::firstChar(OpBuilder &b) {
  return IntHeadUOp::create(b, getLoc(), b.getI32Type(), getValue()).getResult();
}

bool StrShowDoubleOp::nonEmpty() { return true; }
bool StrShowDoubleOp::writesInPieces() { return true; }
Value StrShowDoubleOp::writePieces(OpBuilder &b, Value world) {
  return PutDoubleOp::create(b, getLoc(), world.getType(), getValue(), world).getNext();
}
bool StrShowDoubleOp::knowsFirstChar() { return true; }
Value StrShowDoubleOp::firstChar(OpBuilder &b) {
  return DoubleHeadOp::create(b, getLoc(), b.getI32Type(), getValue()).getResult();
}

// A list packed or concatenated, which may be empty: output of a string
// built only to be written walks the list instead, and the string is never
// built; a string with another use is built anyway, and writing it is a
// copy.
bool StrPackOp::nonEmpty() { return false; }
bool StrPackOp::writesInPieces() { return getResult().hasOneUse(); }
Value StrPackOp::writePieces(OpBuilder &b, Value world) {
  return PutListOp::create(b, getLoc(), world.getType(), getList(), world).getNext();
}
bool StrPackOp::knowsFirstChar() { return false; }
Value StrPackOp::firstChar(OpBuilder &) { unasked(*this, "firstChar"); }

bool StrConcatOp::nonEmpty() { return false; }
bool StrConcatOp::writesInPieces() { return getResult().hasOneUse(); }
Value StrConcatOp::writePieces(OpBuilder &b, Value world) {
  return PutListOp::create(b, getLoc(), world.getType(), getList(), world).getNext();
}
bool StrConcatOp::knowsFirstChar() { return false; }
Value StrConcatOp::firstChar(OpBuilder &) { unasked(*this, "firstChar"); }

// The decimal text of a big, which has a digit at least, and is written
// whole: the runtime has no output of a big.
bool BigShowOp::nonEmpty() { return true; }
bool BigShowOp::writesInPieces() { return false; }
Value BigShowOp::writePieces(OpBuilder &, Value) { unasked(*this, "writePieces"); }
bool BigShowOp::knowsFirstChar() { return false; }
Value BigShowOp::firstChar(OpBuilder &) { unasked(*this, "firstChar"); }

//===----------------------------------------------------------------------===//
// Output
//===----------------------------------------------------------------------===//

// Writing the empty string writes nothing: the world goes on as it was.
OpFoldResult PutStrOp::fold(FoldAdaptor adaptor) {
  auto text = dyn_cast_or_null<StringAttr>(adaptor.getStr());
  if (!text || !text.getValue().empty())
    return {};
  return getWorld();
}

namespace idr::canon {

void addPutStrPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<PutStrOfBuilder>(context);
}

void addStrHeadPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<HeadOfBuilder>(context);
}

} // namespace idr::canon
