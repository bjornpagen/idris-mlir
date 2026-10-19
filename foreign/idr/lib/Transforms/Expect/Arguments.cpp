// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The arguments of the properties, read once, at the request, into the
// typed value of their shape: one parser per shape, and each part of a
// shape (`@f:` before what is stated of f, a `[...]` list, a list of
// values, Values.cpp) read by one parser that every shape with that part
// calls. A text without its shape is refused in the one wording
// (Written::malformed) before anything it names is looked up, so a
// malformed request reads the same whatever the module holds; then each
// `@f` is resolved, and one that names no function is refused, once, here.

#include "idr/Transforms/Expect.h"

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/Parser/Parser.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/ADT/Twine.h"

using namespace mlir;

namespace idr::expect {

LogicalResult Written::malformed() const {
  InFlightDiagnostic error = module->emitError() << "idr-expect: " << property << "=" << text
                                                << " does not read as " << property;
  if (!form.empty())
    error << "=" << form;
  return error;
}

namespace {

// `<head>:<rest>`, split at the first `:`; none when there is no `:`.
std::optional<std::pair<StringRef, StringRef>> headAndRest(StringRef text) {
  size_t at = text.find(':');
  if (at == StringRef::npos)
    return std::nullopt;
  return std::make_pair(text.take_front(at), text.drop_front(at + 1));
}

// The functions `symbol` names, by `names`: at least one, or the error that
// it names none.
FailureOr<Functions> resolve(const Written &written, Symbol symbol) {
  Functions out{symbol.name, {}};
  for (FunctionOpInterface fn : functionsOf(written.module))
    if (names(fn, symbol.name))
      out.functions.push_back(fn);
  if (out.functions.empty()) {
    fail(written.module->getLoc(), written.property)
        << "no function @" << symbol.name << ", and no copy of it";
    return failure();
  }
  return out;
}

// `[@g, @h, ...]`: the names, in their order; `[]`, none.
FailureOr<SmallVector<Symbol>> listOf(const Written &written, StringRef text) {
  if (!text.consume_front("[") || !text.consume_back("]"))
    return written.malformed();
  SmallVector<Symbol> out;
  if (text.trim().empty())
    return out;
  SmallVector<StringRef> parts;
  text.split(parts, ',');
  for (StringRef part : parts) {
    FailureOr<Symbol> name = Symbol::parse(written, part.trim());
    if (failed(name))
      return failure();
    out.push_back(*name);
  }
  return out;
}

// `result` (result 0), `result<n>` or `arg<n>`; none otherwise.
std::optional<Position> positionOf(StringRef text) {
  unsigned index = 0;
  if (text.consume_front("result")) {
    if (text.empty() || !text.getAsInteger(10, index))
      return Position{Position::Kind::Result, index};
    return std::nullopt;
  }
  if (text.consume_front("arg") && !text.getAsInteger(10, index))
    return Position{Position::Kind::Arg, index};
  return std::nullopt;
}

} // namespace

FailureOr<Nothing> Nothing::parse(const Written &written, StringRef text) {
  if (!text.empty())
    return written.malformed();
  return Nothing{};
}

FailureOr<Symbol> Symbol::parse(const Written &written, StringRef text) {
  if (!text.consume_front("@") || text.empty())
    return written.malformed();
  return Symbol{text};
}

FailureOr<Functions> Functions::parse(const Written &written, StringRef text) {
  FailureOr<Symbol> symbol = Symbol::parse(written, text);
  if (failed(symbol))
    return failure();
  return resolve(written, *symbol);
}

FailureOr<Roots> Roots::parse(const Written &written, StringRef text) {
  if (text.empty())
    return Roots{std::nullopt};
  FailureOr<Functions> scope = Functions::parse(written, text);
  if (failed(scope))
    return failure();
  return Roots{std::move(*scope)};
}

SmallVector<Operation *> Roots::roots(ModuleOp module) const {
  if (!scope)
    return {module.getOperation()};
  return llvm::map_to_vector(scope->functions,
                             [](FunctionOpInterface fn) -> Operation * { return fn; });
}

std::string Roots::in() const { return scope ? (" in @" + scope->name).str() : std::string(); }

FailureOr<Pair> Pair::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> caller = Symbol::parse(written, parts->first);
  if (failed(caller))
    return failure();
  FailureOr<Symbol> callee = Symbol::parse(written, parts->second);
  if (failed(callee))
    return failure();
  FailureOr<Functions> functions = resolve(written, *caller);
  if (failed(functions))
    return failure();
  return Pair{std::move(*functions), *callee};
}

FailureOr<TwoFunctions> TwoFunctions::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> first = Symbol::parse(written, parts->first);
  if (failed(first))
    return failure();
  FailureOr<Symbol> second = Symbol::parse(written, parts->second);
  if (failed(second))
    return failure();
  // Each name that names no function is reported.
  FailureOr<Functions> firsts = resolve(written, *first);
  FailureOr<Functions> seconds = resolve(written, *second);
  if (failed(firsts) || failed(seconds))
    return failure();
  return TwoFunctions{std::move(*firsts), std::move(*seconds)};
}

FailureOr<CountOf> CountOf::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  unsigned count = 0;
  if (!parts || parts->second.getAsInteger(10, count))
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return CountOf{std::move(*function), count};
}

FailureOr<Loops> Loops::parse(const Written &written, StringRef text) {
  StringRef name = text;
  std::optional<unsigned> count;
  if (auto parts = headAndRest(text)) {
    unsigned n = 0;
    if (parts->second.getAsInteger(10, n))
      return written.malformed();
    name = parts->first;
    count = n;
  }
  FailureOr<Functions> function = Functions::parse(written, name);
  if (failed(function))
    return failure();
  return Loops{std::move(*function), count};
}

FailureOr<Bound> Bound::parse(const Written &written, StringRef text) {
  uint64_t bound = 0;
  if (text.getAsInteger(10, bound))
    return written.malformed();
  return Bound{bound};
}

FailureOr<Listed> Listed::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  FailureOr<SmallVector<Symbol>> names = listOf(written, parts->second);
  if (failed(names))
    return failure();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return Listed{std::move(*function), std::move(*names)};
}

FailureOr<Labels> Labels::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  auto placed = parts ? headAndRest(parts->second) : std::nullopt;
  std::optional<Position> position = placed ? positionOf(placed->first) : std::nullopt;
  if (!position)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  FailureOr<SmallVector<Symbol>> names = listOf(written, placed->second);
  if (failed(names))
    return failure();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return Labels{std::move(*function), *position, std::move(*names)};
}

FailureOr<ReturnedValues> ReturnedValues::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  FailureOr<SmallVector<Item>> values = valuesOf(written, parts->second, '/');
  if (failed(values))
    return failure();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return ReturnedValues{std::move(*function), std::move(*values)};
}

FailureOr<PathValues> PathValues::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  FailureOr<SmallVector<Item>> values = valuesOf(written, parts->second, '+');
  if (failed(values))
    return failure();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return PathValues{std::move(*function), std::move(*values)};
}

FailureOr<ReturnedArguments> ReturnedArguments::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  SmallVector<StringRef> items;
  parts->second.split(items, '/');
  SmallVector<unsigned> positions;
  for (StringRef item : items)
    if (item.getAsInteger(10, positions.emplace_back()))
      return written.malformed();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return ReturnedArguments{std::move(*function), std::move(positions)};
}

FailureOr<EffectsOf> EffectsOf::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  // Each item is the text of one case, read alone and or-ed into the set:
  // it is the enum's own spelling of what it reads. The empty text, which
  // the enum reads as no case, the empty set, is no case's spelling.
  SmallVector<StringRef> items;
  parts->second.split(items, '+');
  Effect effects = Effect::none;
  for (StringRef item : items) {
    std::optional<Effect> effect = symbolizeEffect(item);
    if (!effect || stringifyEffect(*effect) != item)
      return written.malformed();
    effects = effects | *effect;
  }
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return EffectsOf{std::move(*function), effects};
}

FailureOr<Module> Module::parse(const Written &written, StringRef text) {
  if (text.empty())
    return written.malformed();
  OwningOpRef<ModuleOp> op = parseSourceFile<ModuleOp>(text, written.module->getContext());
  if (!op) {
    fail(written.module->getLoc(), written.property) << "cannot read " << text;
    return failure();
  }
  return Module{std::move(op)};
}

FailureOr<FunctionsAndModule> FunctionsAndModule::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  FailureOr<Module> module = Module::parse(written, parts->second);
  if (failed(module))
    return failure();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return FunctionsAndModule{std::move(*function), std::move(*module)};
}

FailureOr<StageIs> StageIs::parse(const Written &written, StringRef text) {
  std::optional<Stage> stage = symbolizeStage(text);
  if (!stage)
    return written.malformed();
  return StageIs{*stage};
}

FailureOr<TypeOf> TypeOf::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  Type type = parseType(parts->second, written.module->getContext());
  if (!type)
    return written.malformed();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return TypeOf{std::move(*function), type};
}

FailureOr<ConventionOf> ConventionOf::parse(const Written &written, StringRef text) {
  auto parts = headAndRest(text);
  if (!parts)
    return written.malformed();
  FailureOr<Symbol> symbol = Symbol::parse(written, parts->first);
  if (failed(symbol))
    return failure();
  std::optional<LLVM::cconv::CConv> convention = LLVM::cconv::symbolizeCConv(parts->second);
  if (!convention)
    return written.malformed();
  FailureOr<Functions> function = resolve(written, *symbol);
  if (failed(function))
    return failure();
  return ConventionOf{std::move(*function), *convention};
}

} // namespace idr::expect
