// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of a value's structural source (idr::sourceOf): each value of a
// function, parsed, against what it is made of. Only the structure is
// read, so the module is not verified.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Parser/Parser.h"
#include "llvm/ADT/STLExtras.h"

#include "gtest/gtest.h"

#include <variant>

using namespace mlir;
using namespace idr;

namespace {

bool made(const Source &source) { return std::holds_alternative<Made>(source); }

bool same(const Source &source, Value value) {
  const auto *found = std::get_if<Same>(&source);
  return found && found->value == value;
}

bool field(const Source &source, Value scrutinee, Tag tag, unsigned index) {
  const auto *found = std::get_if<Field>(&source);
  return found && found->scrutinee == scrutinee && found->tag == tag && found->index == index;
}

// The one op of kind `OpT` in the body of `fn`, outside its regions' own.
template <typename OpT>
OpT only(FuncOp fn) {
  auto ops = fn.getBody().getOps<OpT>();
  EXPECT_TRUE(llvm::hasSingleElement(ops));
  return *ops.begin();
}

FuncOp function(ModuleOp module, StringRef name) {
  auto program = cast<ProgramOp>(module.getBody()->front());
  return SymbolTable::lookupNearestSymbolFrom<FuncOp>(program,
                                                      StringAttr::get(module.getContext(), name));
}

TEST(SourceOf, LinearPositionsFieldsAndMatches) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect, arith::ArithDialect>();
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
!T = !idr.data<"T">
#types = #idr.types<
  "T" = plain [@A(i64), @B()]
>
idr.program @sources root(@root) stage(first) types #types {
  idr.func @f(%t: !T, %x: i64) -> i64 {
    %l = idr.lin.enter %x : !idr.lin<i64>
    %u = idr.lin.use %l : !idr.lin<i64>
    %a = idr.field %t : !T @A[0] -> i64
    %r = idr.match %t : !T -> (i64) {
    case @A(%y: i64) {
      idr.yield %y : i64
    }
    default(%d: !T) {
      idr.yield %u : i64
    }
    }
    %s = arith.addi %r, %a : i64
    return %s : i64
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
)mlir",
                                                             ParserConfig(&ctx, false));
  ASSERT_TRUE(module);
  FuncOp f = function(*module, "f");
  Value t = f.getArgument(0), x = f.getArgument(1);
  auto enter = only<LinEnterOp>(f);
  auto use = only<LinUseOp>(f);
  auto read = only<FieldOp>(f);
  auto match = only<MatchOp>(f);
  Tag a = *cast<DataType>(t.getType()).getTag("A");
  Value y = match.getCaseRegions()[0].front().getArgument(0);
  Value d = match.getDefaultRegion().front().getArgument(0);
  EXPECT_TRUE(same(sourceOf(enter.getResult()), x));
  EXPECT_TRUE(same(sourceOf(use.getResult()), enter.getResult()));
  EXPECT_TRUE(field(sourceOf(read.getResult()), t, a, 0));
  EXPECT_TRUE(field(sourceOf(y), t, a, 0));
  EXPECT_TRUE(same(sourceOf(d), t));
  EXPECT_TRUE(made(sourceOf(t)));
  EXPECT_TRUE(made(sourceOf(x)));
  EXPECT_TRUE(made(sourceOf(match->getResult(0))));
}

// A borrow keeps its owner's value, identity and exclusivity; a share keeps
// the value but forgets the exclusivity, so it is made where it is.
TEST(SourceOf, BorrowIsItsOwnerAndShareIsMade) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect, arith::ArithDialect>();
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
!B = !idr.data<"B">
#types = #idr.types<
  "B" = plain [@K(i64)]
>
idr.program @owned root(@root) stage(owned) types #types {
  idr.func @views(%o: !idr.own<!idr.box<!B>>) -> !idr.own<!idr.box<!B>> {
    %v = idr.borrow %o : !idr.own<!idr.box<!B>>
    %s = idr.share %o : !idr.own<!idr.box<!B>>
    return %s : !idr.own<!idr.box<!B>>
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
)mlir",
                                                             ParserConfig(&ctx, false));
  ASSERT_TRUE(module);
  FuncOp views = function(*module, "views");
  Value o = views.getArgument(0);
  EXPECT_TRUE(same(sourceOf(only<BorrowOp>(views).getResult()), o));
  EXPECT_TRUE(made(sourceOf(only<ShareOp>(views).getResult())));
}

} // namespace
