// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of giving back (idr::identities::givesBackOf): the component {@f},
// whose body returns the call of @g, which the solve reads frozen through
// its outside answer, @g giving back argument 0. Whether the call returns is
// the call's own property, its effects.

#include "idr/Analysis/Identities.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Parser/Parser.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"

#include "gtest/gtest.h"

#include <optional>
#include <string>

using namespace mlir;

namespace {

// What @f gives back when its call of @g has the effects `effects`.
llvm::SmallVector<std::optional<unsigned>> givenBackWith(llvm::StringRef effects) {
  MLIRContext ctx;
  ctx.loadDialect<idr::IdrDialect, arith::ArithDialect>();
  std::string text = (R"mlir(
!L = !idr.data<"L", plain [@N(), @C(i64, !idr.box<!idr.data<"L">>)]>
idr.program @identities root(@root) stage(first) {
  idr.func effects<none> @g(%x: !idr.box<!L>) -> !idr.box<!L> attributes {total} {
    return %x : !idr.box<!L>
  }
  idr.func @f(%x: !idr.box<!L>) -> !idr.box<!L> attributes {total} {
    %r = idr.call @g(%x) )mlir" +
                      effects + R"mlir( : (!idr.box<!L>) -> !idr.box<!L>
    return %r : !idr.box<!L>
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
)mlir")
                         .str();
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(text, &ctx);
  if (!module) {
    ADD_FAILURE() << "the module does not parse with " << effects.str();
    return {};
  }
  auto program = *module->getOps<idr::ProgramOp>().begin();
  auto f = SymbolTable::lookupNearestSymbolFrom<idr::FuncOp>(program, StringAttr::get(&ctx, "f"));
  StringAttr g = StringAttr::get(&ctx, "g");
  return idr::identities::givesBackOf({f}, [&](StringAttr callee) -> std::optional<unsigned> {
    if (callee == g)
      return 0;
    return std::nullopt;
  });
}

TEST(Identities, ACallThatMayDivergeGivesNothingBack) {
  llvm::SmallVector<std::optional<unsigned>> givesBack = givenBackWith("effects<diverge>");
  ASSERT_EQ(givesBack.size(), 1u);
  EXPECT_FALSE(givesBack[0].has_value());
}

TEST(Identities, ACallThatReturnsGivesBackWhatItsCalleeDoes) {
  llvm::SmallVector<std::optional<unsigned>> givesBack = givenBackWith("effects<none>");
  ASSERT_EQ(givesBack.size(), 1u);
  ASSERT_TRUE(givesBack[0].has_value());
  EXPECT_EQ(*givesBack[0], 0u);
}

} // namespace
