// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The table of idr-expect's properties and the contracts' universal check,
// both made from the one list of them (Properties.inc): a row holds a
// property's name once and pairs its check with the shape of its argument,
// so a row whose check reads another shape does not compile.

#include "Checks.h"

#include "llvm/ADT/STLExtras.h"

#include <iterator>
#include <type_traits>

using namespace mlir;

namespace idr::expect {

namespace {

const Property properties[] = {
#define IDR_EXPECT_PROPERTY(name, Shape, check) property<Shape, check>(name),
#define IDR_EXPECT_SELF_CHECK(name, Shape, check) IDR_EXPECT_PROPERTY(name, Shape, check)
#define IDR_EXPECT_UNIVERSAL(name, Shape, check) IDR_EXPECT_PROPERTY(name, Shape, check)
#include "Properties.inc"
#undef IDR_EXPECT_UNIVERSAL
#undef IDR_EXPECT_SELF_CHECK
#undef IDR_EXPECT_PROPERTY
};

// The argument of the whole program, for a shape that has one: no
// argument, every function, the whole module. A universal row of another
// shape has no overload here and does not compile, as its record cannot be
// written.
Nothing wholeProgram(std::type_identity<Nothing>, ModuleOp) { return Nothing{}; }
Functions wholeProgram(std::type_identity<Functions>, ModuleOp module) {
  return Functions{"", functionsOf(module)};
}
Roots wholeProgram(std::type_identity<Roots>, ModuleOp) { return Roots{std::nullopt}; }

// One universal property, of the whole program.
template <typename A, LogicalResult (*Check)(const Request<A> &)>
LogicalResult ofWholeProgram(ModuleOp module, AnalysisManager &analyses, StringRef name) {
  A argument = wholeProgram(std::type_identity<A>{}, module);
  return Check(Request<A>{module, analyses, name, argument});
}

} // namespace

const Property *lookup(StringRef name) {
  // The name is a test's text, read here once, where the request is parsed.
  const Property *at =
      llvm::find_if(properties, [&](const Property &row) { return row.name == name; });
  return at == std::end(properties) ? nullptr : at;
}

LogicalResult universal(ModuleOp module, AnalysisManager &analyses) {
  bool held = true;
#define IDR_EXPECT_PROPERTY(name, Shape, check)
#define IDR_EXPECT_SELF_CHECK(name, Shape, check)
#define IDR_EXPECT_UNIVERSAL(name, Shape, check)                                                   \
  held = succeeded(ofWholeProgram<Shape, check>(module, analyses, name)) && held;
#include "Properties.inc"
#undef IDR_EXPECT_UNIVERSAL
#undef IDR_EXPECT_SELF_CHECK
#undef IDR_EXPECT_PROPERTY
  return success(held);
}

} // namespace idr::expect
