// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function returns, stated as a value: a constant the passes
// computed, or one of the function's own parameters. A fold, a known
// match or a known application is then stated by what it computes, not by
// the ops that are left; every copy of the function is asked (`named`).

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/IR/Matchers.h"

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

// The items of `text` split at `separator` where it stands outside brackets
// and quotes, so a value written as MLIR writes it keeps its own. The `>`
// of an arrow closes nothing.
SmallVector<StringRef> itemsOf(StringRef text, char separator) {
  SmallVector<StringRef> out;
  int depth = 0;
  bool quoted = false;
  size_t start = 0;
  for (size_t i = 0; i < text.size(); ++i) {
    char c = text[i];
    if (quoted) {
      if (c == '\\')
        ++i;
      else if (c == '"')
        quoted = false;
      continue;
    }
    if (c == '"')
      quoted = true;
    else if (c == '(' || c == '[' || c == '{' || c == '<')
      ++depth;
    else if (c == ')' || c == ']' || c == '}' || (c == '>' && !(i > 0 && text[i - 1] == '-')))
      --depth;
    else if (c == separator && depth == 0) {
      out.push_back(text.slice(start, i));
      start = i + 1;
    }
  }
  out.push_back(text.substr(start));
  return out;
}

// An item without the parentheses that keep the commas in it from
// splitting the list of properties: an opening one whose match is the
// item's last character.
StringRef unwrapped(StringRef item) {
  item = item.trim();
  if (item.size() < 2 || item.front() != '(' || item.back() != ')')
    return item;
  int depth = 0;
  for (size_t i = 0; i + 1 < item.size(); ++i) {
    if (item[i] == '(')
      ++depth;
    else if (item[i] == ')' && --depth == 0)
      return item;
  }
  return item.drop_front().drop_back().trim();
}

// `@f:a/b/...`: the function and one expected item per result.
std::optional<std::pair<StringRef, SmallVector<StringRef>>>
functionAndResults(ModuleOp module, StringRef argument, StringRef property, StringRef form) {
  auto [function, results] = argument.split(':');
  SmallVector<StringRef> items = itemsOf(results, '/');
  if (function.ltrim('@').empty() || results.empty()) {
    fail(module.getLoc(), property) << "name the function and its results, as " << property << "="
                                    << form;
    return std::nullopt;
  }
  return std::make_pair(function, items);
}

// The attribute `text` writes, read as the constant `attr` of the same
// kind is read: alone, or, for one whose syntax needs its type (a
// constructor, named in its data type), at the constant's type. The first
// reading's errors are no failure of the property's, so they are not shown.
Attribute want(StringRef text, Attribute attr) {
  MLIRContext *context = attr.getContext();
  {
    ScopedDiagnosticHandler quiet(context, [](Diagnostic &) { return success(); });
    if (Attribute alone = parseAttribute(text, context))
      return alone;
  }
  auto typed = dyn_cast<TypedAttr>(attr);
  return typed ? parseAttribute(text, context, typed.getType()) : Attribute();
}

// Whether `value` is what the item spells: `_`, a value computed at run
// time, no constant; a number, an integer of any width or a float, by its
// value; anything else an attribute as MLIR writes it (a big, a string, a
// constructor), read in the value's context and the constant's own.
bool isConstant(Value value, StringRef item) {
  StringRef text = unwrapped(item);
  Attribute attr;
  bool constant = matchPattern(value, m_Constant(&attr));
  if (text == "_")
    return !constant;
  if (!constant)
    return false;
  int64_t integer;
  if (auto have = dyn_cast<IntegerAttr>(attr); have && !text.getAsInteger(10, integer))
    return have.getType().isInteger(1) ? have.getValue().getZExtValue() == uint64_t(integer)
                                       : have.getValue().getSExtValue() == integer;
  double real;
  if (auto have = dyn_cast<FloatAttr>(attr); have && !text.getAsDouble(real))
    return have.getValueAsDouble() == real;
  return want(text, attr) == attr;
}

// Each return of each copy, its results against `items`, by `matches`.
LogicalResult eachReturn(ModuleOp module, StringRef argument, StringRef property, StringRef form,
                         function_ref<bool(FunctionOpInterface, Value, StringRef)> matches,
                         StringRef saying) {
  auto parsed = functionAndResults(module, argument, property, form);
  if (!parsed)
    return failure();
  auto &[function, items] = *parsed;
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    SmallVector<Operation *> returns = returnsOf(fn);
    if (returns.empty()) {
      fail(fn->getLoc(), property) << where(fn) << " never returns";
      held = false;
    }
    for (Operation *ret : returns) {
      if (ret->getNumOperands() != items.size()) {
        fail(ret->getLoc(), property) << where(fn) << " returns " << ret->getNumOperands()
                                      << " results, not " << items.size();
        held = false;
        continue;
      }
      for (auto [index, value] : llvm::enumerate(ret->getOperands()))
        if (!matches(fn, value, items[index])) {
          fail(ret->getLoc(), property) << "result " << index << " of " << where(fn) << " is not "
                                        << saying << items[index];
          held = false;
        }
    }
  }
  return success(held);
}

// The constants `value` may be on the paths that reach it, through the
// regions of the matches that yield it; false when some path gives a value
// that is no constant. A region that never yields gives none.
bool constantsOnPaths(Value value, SmallVectorImpl<Value> &out) {
  if (matchPattern(value, m_Constant())) {
    out.push_back(value);
    return true;
  }
  auto result = dyn_cast<OpResult>(value);
  Operation *match = result ? result.getOwner() : nullptr;
  if (!isa_and_nonnull<MatchOp, MatchLitOp>(match))
    return false;
  for (Region &region : match->getRegions()) {
    Operation *end = region.front().getTerminator();
    if (auto yield = dyn_cast_or_null<YieldOp>(end))
      if (!constantsOnPaths(yield->getOperand(result.getResultNumber()), out))
        return false;
  }
  return true;
}

} // namespace

// `@f:a+b+...`: the one result of @f is, on its paths, one of the constants
// written, and each of them on some path.
LogicalResult returnsOnPaths(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "returns-on-paths";
  auto [function, alternatives] = argument.split(':');
  SmallVector<StringRef> items = itemsOf(alternatives, '+');
  if (function.ltrim('@').empty() || alternatives.empty())
    return fail(module.getLoc(), property) << "name the function and its values, as "
                                              "returns-on-paths=@f:<v>+<v>...";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    SmallVector<Value> found;
    bool constant = true;
    for (Operation *ret : returnsOf(fn))
      constant &= ret->getNumOperands() == 1 && constantsOnPaths(ret->getOperand(0), found);
    if (!constant) {
      fail(fn->getLoc(), property) << where(fn) << " returns, on some path, what is no constant";
      held = false;
      continue;
    }
    for (Value value : found)
      if (llvm::none_of(items, [&](StringRef text) { return isConstant(value, text); })) {
        fail(value.getLoc(), property) << where(fn) << " may return a constant not among "
                                       << alternatives;
        held = false;
      }
    for (StringRef text : items)
      if (llvm::none_of(found, [&](Value value) { return isConstant(value, text); })) {
        fail(fn->getLoc(), property) << where(fn) << " returns " << text << " on no path";
        held = false;
      }
  }
  return success(held);
}

LogicalResult returnsConstants(ModuleOp module, AnalysisManager &, StringRef argument) {
  return eachReturn(
      module, argument, "returns", "@f:<value>/<value>...",
      [](FunctionOpInterface, Value value, StringRef text) { return isConstant(value, text); },
      "the constant ");
}

LogicalResult returnsArguments(ModuleOp module, AnalysisManager &, StringRef argument) {
  return eachReturn(
      module, argument, "returns-argument", "@f:<n>/<n>...",
      [](FunctionOpInterface fn, Value value, StringRef text) {
        unsigned index;
        if (text.getAsInteger(10, index) || index >= fn.getNumArguments())
          return false;
        return value == fn.getArgument(index);
      },
      "its parameter ");
}

} // namespace idr::expect
