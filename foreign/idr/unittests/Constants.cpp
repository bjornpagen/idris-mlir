// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that every constant of the box is the one attribute `get` gives for its value however it was built, that walkFields gives each field once at its index, and that two remaps of one kind that differ only inside a field name its holder differently.
// The box of a constant constructor's one form (#idr.con) and of the shape
// a remap decides for a field. Constants: lists along either field of every
// length to 64, built a cell at a time by `get` and at once by `getRun`;
// left chains of a tree, which run along their first field; nodes that hold
// their own constructor twice; and zig-zags. For each, `get` of its first
// cell's fields, and `getRun` of its cells, give the constant back, and
// walkFields gives every field of every cell once, at an index of the
// constructor.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Parser/Parser.h"

#include "gtest/gtest.h"

#include <optional>
#include <string>

using namespace mlir;
using namespace idr;

namespace {

DataType dataOf(MLIRContext &ctx, StringRef text) {
  return cast<DataType>(parseType(text, &ctx));
}

Attribute i64(MLIRContext &ctx, int64_t value) {
  return IntegerAttr::get(IntegerType::get(&ctx, 64), value);
}

// The one form: the constant is what `get` and `getRun` give for it, and
// its walk is every field of every cell once.
void holdsOneForm(ConAttr con) {
  MLIRContext *ctx = con.getContext();
  EXPECT_EQ(ConAttr::get(ctx, con.getData(), con.getTag(), con.getFields()), con);
  EXPECT_EQ(ConAttr::getRun(ctx, con.getData(), con.getTag(), con.getSpine(), con.getCells()),
            con);
  size_t width = con.getCtor().fields.size();
  size_t walked = 0;
  con.walkFields([&](Attribute field, unsigned index) {
    EXPECT_TRUE(static_cast<bool>(field));
    EXPECT_LT(index, width);
    ++walked;
  });
  // Every cell but the last holds every field but the spine.
  size_t cells = con.getRunLength();
  EXPECT_EQ(walked, (cells - 1) * (width - 1) + width);
}

TEST(ConAttr, ListsAlongEitherFieldHaveOneForm) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect>();
  for (unsigned spine : {0u, 1u}) {
    DataType list = dataOf(
        ctx, spine == 1
                 ? R"(!idr.data<"L1", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L1">>) cons]>)"
                 : R"(!idr.data<"L0", plain [@Nil(), @Cons(!idr.box<!idr.data<"L0">>, i64)]>)");
    Tag nil = *list.getTag("Nil"), cons = *list.getTag("Cons");
    ConAttr con = ConAttr::get(&ctx, list, nil, ArrayAttr::get(&ctx, {}));
    holdsOneForm(con);
    for (int64_t i = 0; i < 64; ++i) {
      SmallVector<Attribute> fields{i64(ctx, i)};
      fields.insert(fields.begin() + spine, con);
      con = ConAttr::get(&ctx, list, cons, ArrayAttr::get(&ctx, fields));
      holdsOneForm(con);
      // A list is one level deep: one cell per cons.
      EXPECT_EQ(con.getRunLength(), static_cast<unsigned>(i + 1));
    }
  }
}

TEST(ConAttr, TreesHaveOneForm) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect>();
  DataType tree = dataOf(ctx, R"(!idr.data<"T", plain [@Leaf(), @Node(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>)");
  Tag leafTag = *tree.getTag("Leaf"), node = *tree.getTag("Node");
  ConAttr leaf = ConAttr::get(&ctx, tree, leafTag, ArrayAttr::get(&ctx, {}));
  auto nodeOf = [&](Attribute left, int64_t key, Attribute right) {
    return ConAttr::get(&ctx, tree, node, ArrayAttr::get(&ctx, {left, i64(ctx, key), right}));
  };
  // A left chain runs along its first field; a node of two nodes is one
  // cell; a chain whose next node runs along another field is a zig-zag.
  ConAttr left = leaf;
  for (int64_t i = 0; i < 16; ++i)
    holdsOneForm(left = nodeOf(left, i, leaf));
  ConAttr both = nodeOf(left, 99, left);
  holdsOneForm(both);
  EXPECT_EQ(both.getRunLength(), 1u);
  ConAttr zig = nodeOf(leaf, 1, left);
  holdsOneForm(zig);
  holdsOneForm(nodeOf(zig, 2, leaf));
  holdsOneForm(nodeOf(both, 3, leaf));
}

// getRun re-canonicalizes cells however they were linked: a last cell that
// is itself the rest of the run is taken in.
TEST(ConAttr, RunsLinkedAnyWayAreOneAttribute) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect>();
  DataType list = dataOf(
      ctx, R"(!idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>)");
  Tag nil = *list.getTag("Nil"), cons = *list.getTag("Cons");
  ConAttr end = ConAttr::get(&ctx, list, nil, ArrayAttr::get(&ctx, {}));
  ConAttr byCells = end;
  for (int64_t i = 4; i >= 1; --i)
    byCells = ConAttr::get(&ctx, list, cons, ArrayAttr::get(&ctx, {i64(ctx, i), byCells}));
  ConAttr four = ConAttr::get(&ctx, list, cons, ArrayAttr::get(&ctx, {i64(ctx, 4), end}));
  ConAttr byRun = ConAttr::getRun(
      &ctx, list, cons, 1,
      {ArrayAttr::get(&ctx, {i64(ctx, 1)}), ArrayAttr::get(&ctx, {i64(ctx, 2)}),
       ArrayAttr::get(&ctx, {i64(ctx, 3), four})});
  EXPECT_EQ(byRun, byCells);
}

// Two remaps of kind box over a holder H whose closure field takes a T: one
// boxes T, one does not, and both box U, so both remake H. What H's field
// becomes inside the closure type differs, so H's names differ, and both
// remaps make their bodies in one context.
TEST(DataRemap, NamesFollowWhatAFieldBecomesAtAnyDepth) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect, arith::ArithDialect>();
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
!T = !idr.data<"T", plain [@A(i64)]>
!U = !idr.data<"U", plain [@B(i64)]>
!H = !idr.data<"H", plain [@C(!idr.fn<(!T) -> i64>, !U)]>
idr.program @p root(@root) stage(higher) {
  idr.func @use(%h: !H) {
    return
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
)mlir",
                                                             &ctx);
  ASSERT_TRUE(module);
  auto program = cast<ProgramOp>(module->getBody()->front());
  auto use = SymbolTable::lookupNearestSymbolFrom<FuncOp>(program, StringAttr::get(&ctx, "use"));
  DataType holder = dataTypeOf(use.getArgumentTypes()[0]);
  ArrayRef<Type> fields = holder.getCtors().front().fields;
  DataType t = dataTypeOf(cast<FnType>(fields[0]).getInputs()[0]);
  DataType u = dataTypeOf(fields[1]);
  auto nameAfter = [&](ArrayRef<DataType> boxed) -> std::string {
    OwningOpRef<ModuleOp> copy = cast<ModuleOp>((*module)->clone());
    FailureOr<std::unique_ptr<DataRemap>> remap = DataRemap::create(
        *copy, "box",
        [](Type, std::optional<DataRemap::FieldPlace>) { return std::optional<Type>(); }, boxed);
    if (failed(remap))
      return "";
    (*remap)->retype(*copy);
    auto again = cast<ProgramOp>(copy->getBody()->front());
    auto remade = SymbolTable::lookupNearestSymbolFrom<FuncOp>(again, StringAttr::get(&ctx, "use"));
    return dataTypeOf(remade.getArgumentTypes()[0]).getName().str();
  };
  std::string both = nameAfter({t, u}), onlyU = nameAfter({u});
  EXPECT_FALSE(both.empty());
  EXPECT_FALSE(onlyU.empty());
  EXPECT_NE(both, onlyU);
}

} // namespace
