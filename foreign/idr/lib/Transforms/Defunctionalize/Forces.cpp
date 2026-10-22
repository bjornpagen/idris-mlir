// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dispatch function of each memo family, `<family>.force`: what every
// force of one of its cells becomes, a call, so the program graph sees
// each label a force may run, as it sees a call's callee. Its body matches
// the cell's state. A memoized label's case is the exchange of the cell's
// state (idr.memo.run): the captures move out of the cell, which is running
// while the label's function runs on them, and the value moves in, the
// cell forced with it. A label run by name leaves the cell as it is and
// calls its function on the captures, so every force runs its effect. The
// running case is a force that reached its own cell again before its value
// moved in, a loop the program would never leave: the program crashes
// there instead. The forced case is the value. It calls no function of its
// own cycle, so it terminates where its labels do.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Joins.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

FailureOr<FuncOp> Decision::defineForce(const Family &family) {
  DataType cell = family.type;
  std::optional<families::MemoView> memo = cell.memo();
  ArrayRef<families::MemoLabelDecl> labels = memo->labels();
  unsigned indices = static_cast<unsigned>(cell.getIndices().size());
  // The function takes the cell's family indices as its own binders, so a
  // force passes the cell's.
  ArrayRef<families::Sort> sorts = idr::match(
      cell.getGroup().getMembers()[cell.getMember()],
      [](const families::MemoMember &member) { return member.indices; },
      [](const auto &) { return ArrayRef<families::Sort>(); });
  DataType own = DataType::get(ctx, cell.getGroup(), cell.getMember(),
                               families::levelArgs(ctx, 0, indices).getTerms());
  Type value = own.ctor(memo->forced()).fields.front();

  // Its name is its family's place in the decision, which the program
  // fixes; no Idris name holds a `$`.
  auto position = static_cast<unsigned>(ids.find(family.key)->second);
  auto name = StringAttr::get(ctx, "lazy$" + llvm::Twine(position) + ".force");
  // Each label's case is at the label's function, the code it runs; the
  // dispatch, and what no one label does, at the program.
  Location loc = NameLoc::get(name, program.getLoc());
  OpBuilder b(ctx);
  FuncOp::Properties properties;
  properties.setSymName(name);
  properties.setFunctionType(TypeAttr::get(FunctionType::get(ctx, TypeRange(own), TypeRange(value))));
  properties.setBinders(IndexBindersAttr::get(ctx, sorts));
  properties.setTerminates(TerminatesAttr::get(ctx, TerminationProof(Acyclic{})));
  auto fn = FuncOp::create(b, loc, TypeRange(), ValueRange(), properties);
  Block *entry = b.createBlock(&fn.getBody(), {}, TypeRange(own), {loc});
  Value taken = entry->getArgument(0);

  // A case per state, and no default.
  SmallVector<int32_t> tags;
  for (unsigned at = 0; at < labels.size() + 2; ++at)
    tags.push_back(static_cast<int32_t>(at));
  auto match = DataMatchOp::create(b, loc, TypeRange(value), taken, b.getDenseI32ArrayAttr(tags), ValueRange());
  for (unsigned at = 0; at < labels.size() + 2; ++at) {
    Region &region = match.getCaseRegion(at);
    Tag tag{at};
    unsigned depth = joins::scopeDepth(&region);
    IndexArgsAttr binders =
        families::levelArgs(ctx, depth, static_cast<unsigned>(own.binderSorts(tag).size()));
    DataType refined = own.refinedTo(tag, binders.getTerms());
    Block *state = b.createBlock(&region, region.end(), TypeRange(refined), {loc});
    SmallVector<Value> fields;
    for (auto [i, field] : llvm::enumerate(*refined.determinedFields(tag)))
      fields.push_back(DataFieldOp::create(b, loc, field, state->getArgument(0), static_cast<unsigned>(i)));
    if (tag == memo->running()) {
      CrashCauseOp::create(b, loc, CrashCause::SuspensionForcedItself, siteOf(program.getLoc()));
      ub::UnreachableOp::create(b, loc);
      continue;
    }
    if (tag == memo->forced()) {
      YieldOp::create(b, loc, heldAs(b, loc, fields.front(), value));
      continue;
    }
    const families::MemoLabelDecl &label = labels[at];
    auto target = SymbolTable::lookupNearestSymbolFrom<FuncOp>(program, label.label.fn);
    Location at_ = target.getLoc();
    // The label's function on `captures`, its value held as the force
    // gives it.
    auto call = [&](ValueRange captures) {
      SmallVector<Value> args;
      for (auto [capture, param] : llvm::zip_equal(captures, target.getArgumentTypes()))
        args.push_back(heldAs(b, at_, capture, param));
      auto called = CallOp::create(b, at_, target, binders, target.getResultTypes(), args,
                                   TailKind::nontail);
      return heldAs(b, at_, called.getResult(0), value);
    };
    switch (label.mode) {
    case families::Mode::ByName:
      YieldOp::create(b, at_, call(fields));
      break;
    case families::Mode::Memoized: {
      // The exchange moves the captures out of the cell, runs the label on
      // them, and moves the value into the cell, which it also gives.
      auto exchange = MemoRunOp::create(b, at_, TypeRange(value), taken, b.getI32IntegerAttr(at));
      SmallVector<Type> captures = llvm::map_to_vector(
          *refined.determinedFields(tag), [&](Type field) { return fieldType(own, field); });
      Block *body = b.createBlock(&exchange.getRegion(), {}, captures,
                                  SmallVector<Location>(captures.size(), at_));
      Value computed = call(body->getArguments());
      MemoYieldOp::create(b, at_, computed, ValueRange{computed});
      b.setInsertionPointAfter(exchange);
      YieldOp::create(b, at_, exchange->getResult(0));
      break;
    }
    }
  }
  b.setInsertionPointToEnd(entry);
  ReturnOp::create(b, loc, match->getResults());
  program.getBody()->push_back(fn);
  return fn;
}

} // namespace idr::defunctionalize
