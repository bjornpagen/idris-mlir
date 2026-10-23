// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of idr-columns for what carries an array of records from one
// function or region to another: a signature and its entry block, a call,
// a return, and a match's results and the yields that give them. Each array
// moves as its columns.

#include "idr/Transforms/Columns.h"

#include "idr/IR/Func.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cstdint>
#include <optional>

using namespace mlir;

namespace idr::columns {

namespace {

// Each attribute dictionary of `attrs` once per value its position became.
ArrayAttr expand(ArrayAttr attrs, ArrayRef<unsigned> counts) {
  if (!attrs)
    return attrs;
  SmallVector<Attribute> out;
  for (auto [attr, count] : llvm::zip_equal(attrs, counts))
    out.append(count, attr);
  return ArrayAttr::get(attrs.getContext(), out);
}

//===----------------------------------------------------------------------===//
// Functions, calls and returns
//===----------------------------------------------------------------------===//

// How a signature's values become what they convert to, as the function's
// edits take it: each that converts to anything but itself has what it
// becomes inserted after it, each taking its attributes, and is erased.
// So every fact the signature states by position moves with its value, and
// what an erased value alone was said to be goes with it, but the sizes of
// its axes, which its columns hold too (comesFrom).
struct Expansion {
  // Before which original value each inserted one goes, its type, its
  // attributes (none when the signature has none) and the value it came
  // from.
  SmallVector<unsigned> before;
  SmallVector<Type> types;
  SmallVector<DictionaryAttr> attrs;
  SmallVector<unsigned> from;
  // The values erased, at their positions once the others are inserted.
  llvm::BitVector erased;
};

Expansion expansion(TypeRange types, ArrayRef<Type> converted, ArrayRef<unsigned> counts,
                    ArrayAttr attrs) {
  Expansion out;
  SmallVector<unsigned> erased;
  ArrayRef<Type> rest = converted;
  // A function numbers its arguments and its results by unsigned, as its
  // type counts them and its edits take them, before and after the edits.
  const auto values = static_cast<unsigned>(types.size());
  assert(counts.size() == values && "every value has its count");
  unsigned inserted = 0;
  for (unsigned position : llvm::seq(0u, values)) {
    unsigned count = counts[position];
    ArrayRef<Type> into = rest.take_front(count);
    rest = rest.drop_front(count);
    if (into.size() == 1 && into.front() == types[position])
      continue;
    // What was inserted before it moved it on by as many.
    erased.push_back(position + inserted);
    out.before.append(count, position + 1);
    out.types.append(into.begin(), into.end());
    out.from.append(count, position);
    inserted += count;
    if (attrs)
      out.attrs.append(count, cast<DictionaryAttr>(attrs[position]));
  }
  assert(inserted == out.types.size() && "every value inserted is counted");
  out.erased.resize(values + inserted);
  for (unsigned position : erased)
    out.erased.set(position);
  return out;
}

// Of each value a signature's values become, the position of the value it
// comes from, as many times as that value became values: a value kept is
// itself, and each column of an array of records holds the array's axes,
// the array's shape with a leaf at each index, so a size the array's
// extents name is that size of each column.
SmallVector<std::optional<std::uint32_t>> comesFrom(ArrayRef<unsigned> counts) {
  SmallVector<std::optional<std::uint32_t>> from;
  for (auto [position, count] : llvm::enumerate(counts))
    from.append(count, static_cast<std::uint32_t>(position));
  return from;
}

// The function remade without its body, so that its edits change only its
// signature and what the signature states, then its body moved in and its
// entry block converted to match, as upstream's function conversions make a
// function anew. Its calls take its facts again once every signature is
// final (Columns.cpp).
struct FuncColumns : OpConversionPattern<FuncOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(FuncOp fn, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    FunctionType type = fn.getFunctionType();
    SmallVector<Type> inputs, results;
    SmallVector<unsigned> inputCounts, resultCounts;
    if (failed(convertEach(*getTypeConverter(), type.getInputs(), inputs, inputCounts)) ||
        failed(convertEach(*getTypeConverter(), type.getResults(), results, resultCounts)))
      return failure();
    Expansion parameters = expansion(type.getInputs(), inputs, inputCounts, fn.getArgAttrsAttr());
    Expansion outputs = expansion(type.getResults(), results, resultCounts, fn.getResAttrsAttr());
    SmallVector<Location> locs = llvm::map_to_vector(
        parameters.from, [&](unsigned at) { return fn.getArgument(at).getLoc(); });
    TypeConverter::SignatureConversion entry(type.getNumInputs());
    ArrayRef<Type> rest = inputs;
    for (auto [at, count] : llvm::enumerate(inputCounts)) {
      entry.addInputs(static_cast<unsigned>(at), rest.take_front(count));
      rest = rest.drop_front(count);
    }
    auto made = cast<FuncOp>(rewriter.cloneWithoutRegions(*fn.getOperation()));
    if (failed(made.insertArguments(parameters.before, parameters.types, parameters.attrs, locs)) ||
        failed(made.eraseArguments(parameters.erased)) ||
        failed(made.insertResults(outputs.before, outputs.types, outputs.attrs)) ||
        failed(made.eraseResults(outputs.erased)))
      return failure();
    // The edits move a kept value's entries, and a column inserted has none
    // of its own: each column keeps the array's, so the sizes Idris knew of
    // the array stay known of its columns, and a call that passes a column
    // at a known size still meets the signature where the array did.
    made.setExtentsAttr(
        extentsFrom(fn.getExtentsAttr(), comesFrom(inputCounts), comesFrom(resultCounts)));
    rewriter.inlineRegionBefore(fn.getBody(), made.getBody(), made.getBody().end());
    if (failed(rewriter.convertRegionTypes(&made.getBody(), *getTypeConverter(), &entry)))
      return failure();
    rewriter.eraseOp(fn);
    return success();
  }
};

struct CallColumns : OpConversionPattern<CallOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(CallOp call, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> results;
    SmallVector<unsigned> counts;
    if (failed(convertEach(*getTypeConverter(), call->getResultTypes(), results, counts)))
      return failure();
    SmallVector<unsigned> argCounts = llvm::map_to_vector(
        adaptor.getArgs(), [](ValueRange arg) { return static_cast<unsigned>(arg.size()); });
    auto made = cast<CallOp>(
        remakeOp(rewriter, call, flatten(adaptor.getOperands()), results));
    rewriter.modifyOpInPlace(made, [&] {
      if (ArrayAttr attrs = made.getArgAttrsAttr())
        made.setArgAttrsAttr(expand(attrs, argCounts));
      if (ArrayAttr attrs = made.getResAttrsAttr())
        made.setResAttrsAttr(expand(attrs, counts));
    });
    SmallVector<SmallVector<Value>> replaced = runs(made->getResults(), counts);
    rewriter.replaceOpWithMultiple(call, replaced);
    return success();
  }
};

// A terminator whose every operand moves on: each array of records moves
// on as its columns.
template <typename OpT>
struct TerminatorColumns : OpConversionPattern<OpT> {
  using OpConversionPattern<OpT>::OpConversionPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpConversionPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> operands = flatten(adaptor.getOperands());
    rewriter.modifyOpInPlace(op, [&] { op->setOperands(operands); });
    return success();
  }
};

} // namespace

// A match gives each array of records its regions yield as the columns
// they yield (ResultColumns). A match's regions bind the fields of its
// constructors, which a data type holds whole, so only what it gives is
// converted. A function is legal once its signature and its body are.
void populateCallColumnPatterns(const TypeConverter &converter, RewritePatternSet &patterns,
                                ConversionTarget &target) {
  ConversionTarget::DynamicLegalityCallbackFn legal = whole(converter);
  addColumns<FuncColumns, FuncOp>(converter, patterns, target,
                                  [&converter](Operation *op) -> std::optional<bool> {
                                    auto fn = cast<FuncOp>(op);
                                    return converter.isSignatureLegal(fn.getFunctionType()) &&
                                           converter.isLegal(&fn.getBody());
                                  });
  addColumns<CallColumns, CallOp>(converter, patterns, target, legal);
  addColumns<TerminatorColumns<ReturnOp>, ReturnOp>(converter, patterns, target, legal);
  addColumns<TerminatorColumns<YieldOp>, YieldOp>(converter, patterns, target, legal);
  addColumns<ResultColumns<DataMatchOp>, DataMatchOp>(converter, patterns, target, legal);
  addColumns<ResultColumns<LitMatchOp>, LitMatchOp>(converter, patterns, target, legal);
}

} // namespace idr::columns
