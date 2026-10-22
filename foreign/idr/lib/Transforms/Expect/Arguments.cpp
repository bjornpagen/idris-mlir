// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The arguments of the properties, read once, at the request, into the
// typed value of their shape: one parser per shape, and each part of a
// shape (`@f:` before what is stated of f, a name) read by one parser that
// every shape with that part calls. A text without its shape is refused in the one wording
// (Written::malformed) before anything it names is looked up, so a
// malformed request reads the same whatever the module holds; then each
// `@f` is resolved, and one that names no function is refused, once, here.

#include "idr/Transforms/Expect.h"

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

} // namespace idr::expect
