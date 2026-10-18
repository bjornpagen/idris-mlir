// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function returns, stated as a value: a constant the passes
// computed, or one of the function's own parameters. A fold, a known
// match or a known application is then stated by what it computes, not by
// the ops that are left; every copy of the function is asked (`names`).

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;

namespace idr::expect {

namespace {

// The returns of `fn`: the terminators of its body's blocks that return.
SmallVector<Operation *> returnsOf(FunctionOpInterface fn) {
  SmallVector<Operation *> out;
  for (Block &block : fn.getFunctionBody())
    if (!block.empty() && block.back().hasTrait<OpTrait::ReturnLike>())
      out.push_back(&block.back());
  return out;
}

// Whether `value` is what `item` states (Item): computed at run time, no
// constant; a number by its value, an integer of any width or a float,
// which an integer written stands for too; an attribute, equal to the
// constant's, as a constant is stored.
bool isConstant(Value value, const Item &item) {
  Attribute attr;
  bool constant = matchPattern(value, m_Constant(&attr));
  return std::visit(llvm::makeVisitor(
                        [&](Computed) { return !constant; },
                        [&](int64_t integer) {
                          if (auto have = dyn_cast_if_present<IntegerAttr>(attr))
                            return have.getType().isInteger(1)
                                       ? have.getValue().getZExtValue() == uint64_t(integer)
                                       : have.getValue().getSExtValue() == integer;
                          auto have = dyn_cast_if_present<FloatAttr>(attr);
                          return have && have.getValueAsDouble() == double(integer);
                        },
                        [&](double real) {
                          auto have = dyn_cast_if_present<FloatAttr>(attr);
                          return have && have.getValueAsDouble() == real;
                        },
                        [&](Attribute written) { return constant && written == attr; }),
                    item);
}

// What a test wrote, for an error: an item as Item reads it, or a
// parameter's position.
void put(InFlightDiagnostic &error, const Item &item) {
  std::visit(llvm::makeVisitor([&](Computed) { error << "_"; },
                               [&](int64_t integer) { error << integer; },
                               [&](double real) { error << real; },
                               [&](Attribute attr) { error << attr; }),
             item);
}
void put(InFlightDiagnostic &error, unsigned position) { error << position; }

// Each return of each copy of @f (`function`), its results against
// `wanted`, one for each result, by `matches`; a result that does not match
// is not `saying` what was written. `property` fails.
template <typename T>
LogicalResult eachReturn(StringRef property, const Functions &function, ArrayRef<T> wanted,
                         function_ref<bool(FunctionOpInterface, Value, const T &)> matches,
                         StringRef saying) {
  bool held = true;
  for (FunctionOpInterface fn : function.functions) {
    SmallVector<Operation *> returns = returnsOf(fn);
    if (returns.empty()) {
      fail(fn->getLoc(), property) << where(fn) << " never returns";
      held = false;
    }
    for (Operation *ret : returns) {
      if (ret->getNumOperands() != wanted.size()) {
        fail(ret->getLoc(), property) << where(fn) << " returns " << ret->getNumOperands()
                                      << " results, not " << wanted.size();
        held = false;
        continue;
      }
      for (auto [index, value] : llvm::enumerate(ret->getOperands()))
        if (!matches(fn, value, wanted[index])) {
          InFlightDiagnostic error = fail(ret->getLoc(), property)
                                     << "result " << index << " of " << where(fn) << " is not "
                                     << saying;
          put(error, wanted[index]);
          held = false;
        }
    }
  }
  return success(held);
}

// The constants `value` may be on the paths that reach it, through the
// regions of the matches that yield it; false when some path gives a value
// that is no constant. A region that never yields gives none, and an empty
// default, an exhaustive match's, is no path.
bool constantsOnPaths(Value value, SmallVectorImpl<Value> &out) {
  if (matchPattern(value, m_Constant())) {
    out.push_back(value);
    return true;
  }
  auto result = dyn_cast<OpResult>(value);
  auto match = result ? dyn_cast<MatchOpInterface>(result.getOwner()) : MatchOpInterface();
  if (!match)
    return false;
  for (Region &region : match->getRegions()) {
    if (region.empty())
      continue;
    Operation *end = region.front().getTerminator();
    if (auto yield = dyn_cast_or_null<YieldOp>(end))
      if (!constantsOnPaths(yield->getOperand(result.getResultNumber()), out))
        return false;
  }
  return true;
}

} // namespace

// The one result of @f is, on its paths, one of the constants written, and
// each of them on some path.
LogicalResult returnsOnPaths(const Request<PathValues> &request) {
  ArrayRef<Item> items = request.argument.values;
  bool held = true;
  for (FunctionOpInterface fn : request.argument.function.functions) {
    SmallVector<Value> found;
    bool constant = true;
    for (Operation *ret : returnsOf(fn))
      constant &= ret->getNumOperands() == 1 && constantsOnPaths(ret->getOperand(0), found);
    if (!constant) {
      fail(fn->getLoc(), request.property)
          << where(fn) << " returns, on some path, what is no constant";
      held = false;
      continue;
    }
    for (Value value : found)
      if (llvm::none_of(items, [&](const Item &item) { return isConstant(value, item); })) {
        InFlightDiagnostic error = fail(value.getLoc(), request.property)
                                   << where(fn) << " may return a constant not among ";
        llvm::interleave(items, [&](const Item &item) { put(error, item); }, [&] { error << "+"; });
        held = false;
      }
    for (const Item &item : items)
      if (llvm::none_of(found, [&](Value value) { return isConstant(value, item); })) {
        InFlightDiagnostic error = fail(fn->getLoc(), request.property) << where(fn) << " returns ";
        put(error, item);
        error << " on no path";
        held = false;
      }
  }
  return success(held);
}

LogicalResult returnsConstants(const Request<ReturnedValues> &request) {
  return eachReturn<Item>(
      request.property, request.argument.function, request.argument.values,
      [](FunctionOpInterface, Value value, const Item &item) { return isConstant(value, item); },
      "the constant ");
}

LogicalResult returnsArguments(const Request<ReturnedArguments> &request) {
  return eachReturn<unsigned>(
      request.property, request.argument.function, request.argument.positions,
      [](FunctionOpInterface fn, Value value, const unsigned &index) {
        return index < fn.getNumArguments() && value == fn.getArgument(index);
      },
      "its parameter ");
}

} // namespace idr::expect
