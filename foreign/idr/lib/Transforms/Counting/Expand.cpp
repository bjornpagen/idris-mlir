// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-expand: the last step of counting at the dialect's level. A take
// of a value whose grade proves its own cell the holder's alone (a claim on
// its family's cells, or on everything it reaches) stays a take: its fields
// move out of the cell with no count read, and its token is the cell, never
// null. Any other take becomes the one test of sharing left to run, a match
// on uniqueness of two regions (count.match_unique), of which exactly one
// runs:
//   - unique: the value held the only reference to its cell, so the op gives
//     the region the token (unique, never null) and the fields, moved out;
//     the region drops the fields nothing needs and gives the rest on;
//   - shared: the value is given to the region, which reads the fields that
//     live on, takes a reference of its own for each from the counted value
//     it read it from, and drops the value.
// What the token becomes is read off what reuse made of it, one case each:
// freed (the unique region frees the cell; the shared region has none);
// recycled into one construction (count.take_into: the unique region
// recycles the cell, the shared one makes a new one, so the code after the
// match has a cell either way and tests nothing); or given on elsewhere
// (the unique region gives the token on, its claim forgotten, the shared
// region the null token, which the one recycle or free that consumes it
// tests). The test is never built for a value its type answers, so a value
// typed unique meets no test and no count.
#include "Counting.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRRCEXPAND
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting {
namespace {

// What reuse made of a take's token, one case each.
enum class TokenUse : std::uint8_t { Freed, Recycled, GivenOn };

// A take to expand, read once: the value, its fields and what becomes of
// each, and of its token.
struct Taken {
  Operation *op;
  Value value;
  ResultRange fields;
  TokenUse use;
  // The token (taken), or the cell (fused into one recycle).
  Value given;
  // The free of a freed token.
  Operation *free = nullptr;
  // The fields whose one use is a drop right where the take is: they die
  // with the cell.
  llvm::SmallBitVector dying;
};

Taken read(CountTakeOp take) {
  Taken taken{take, take.getValue(), take.getFields(), TokenUse::GivenOn, take.getToken(), nullptr,
              llvm::SmallBitVector(take.getFields().size())};
  Value token = take.getToken();
  if (token.hasOneUse())
    if (auto free = dyn_cast<TokenFreeOp>(*token.user_begin())) {
      taken.use = TokenUse::Freed;
      taken.free = free;
    }
  for (auto [index, field] : llvm::enumerate(take.getFields()))
    if (field.hasOneUse() && isa<CountDropOp>(*field.user_begin()))
      taken.dying.set(index);
  return taken;
}

Taken read(CountTakeIntoOp into) {
  Taken taken{into, into.getValue(), into.getFields(), TokenUse::Recycled, into.getCell(), nullptr,
              llvm::SmallBitVector(into.getFields().size())};
  for (auto [index, field] : llvm::enumerate(into.getFields()))
    if (field.hasOneUse() && isa<CountDropOp>(*field.user_begin()))
      taken.dying.set(index);
  return taken;
}

// The fields of a counted value that live on, each read from it, and one
// its count frees given a reference of its own: the shared region's fields.
SmallVector<Value> dupFields(RewriterBase &rewriter, Location loc, Value owner,
                             llvm::ArrayRef<unsigned> fields) {
  SmallVector<Value> dups;
  for (unsigned index : fields) {
    Value read = DataFieldOp::create(rewriter, loc, owner, index).getResult();
    dups.push_back(countsOf(read.getType()) == Counts::Counted
                       ? CountDupOp::create(rewriter, loc, atHold(read.getType(), Hold::counted()), read)
                             .getResult()
                       : read);
  }
  return dups;
}

// The take made a match on uniqueness: its token or cell and its living
// fields as the match's results, its dying fields dropped in the unique
// region, where they were moved out, and left in the shared one, where the
// value's drop releases them.
void expand(RewriterBase &rewriter, Taken &taken) {
  Location loc = taken.op->getLoc();
  Type tokenType = taken.op->getResult(0).getType();
  SmallVector<unsigned> living;
  for (unsigned index = 0; index < taken.fields.size(); ++index)
    if (!taken.dying.test(index))
      living.push_back(index);
  // The match's results: what replaces the token or the cell, then the
  // living fields.
  SmallVector<Type> results;
  if (taken.use != TokenUse::Freed)
    results.push_back(tokenType);
  for (unsigned index : living)
    results.push_back(taken.fields[index].getType());
  rewriter.setInsertionPoint(taken.op);
  auto match = CountMatchUniqueOp::create(rewriter, loc, results, taken.value);
  // The unique region: the cell's token, the holder's alone, and the fields
  // moved out.
  {
    SmallVector<Type> args{graded(Grade{Uses::Once, Hold::counted(Unique::Deep)}, unrestricted(tokenType))};
    if (taken.use == TokenUse::Recycled)
      args[0] = graded(Grade{Uses::Once, Hold::counted(Unique::Deep)},
                       TokenType::of(cast<DataType>(unrestricted(taken.value.getType()))));
    for (Value field : taken.fields)
      args.push_back(field.getType());
    Block *unique = rewriter.createBlock(&match.getUnique(), {}, args,
                                         SmallVector<Location>(args.size(), loc));
    Value token = unique->getArgument(0);
    SmallVector<Value> yields;
    for (unsigned index = 0; index < taken.fields.size(); ++index)
      if (taken.dying.test(index))
        CountDropOp::create(rewriter, loc, unique->getArgument(1 + index));
    switch (taken.use) {
    case TokenUse::Freed:
      TokenFreeOp::create(rewriter, loc, token);
      break;
    case TokenUse::Recycled:
      yields.push_back(CellRecycleOp::create(rewriter, loc, tokenType, token).getCell());
      break;
    case TokenUse::GivenOn:
      yields.push_back(CountShareOp::create(rewriter, loc, tokenType, token).getResult());
      break;
    }
    for (unsigned index : living)
      yields.push_back(unique->getArgument(1 + index));
    YieldOp::create(rewriter, loc, yields);
  }
  // The shared region: the value given to it; the living fields read from
  // it, each with a reference of its own; the value dropped.
  {
    Block *shared = rewriter.createBlock(&match.getShared(), {}, {taken.value.getType()}, {loc});
    Value owner = shared->getArgument(0);
    SmallVector<Value> dups = dupFields(rewriter, loc, owner, living);
    CountDropOp::create(rewriter, loc, owner);
    SmallVector<Value> yields;
    switch (taken.use) {
    case TokenUse::Freed:
      break;
    case TokenUse::Recycled:
      yields.push_back(CellNewOp::create(rewriter, loc, tokenType).getCell());
      break;
    case TokenUse::GivenOn:
      yields.push_back(TokenNullOp::create(rewriter, loc, tokenType).getToken());
      break;
    }
    llvm::append_range(yields, dups);
    YieldOp::create(rewriter, loc, yields);
  }
  // The code after the take reads the match's results; the dying fields'
  // drops and a freed token's free went into the unique region.
  unsigned next = 0;
  if (taken.use != TokenUse::Freed)
    rewriter.replaceAllUsesWith(taken.given, match.getResult(next++));
  for (unsigned index : living)
    rewriter.replaceAllUsesWith(taken.fields[index], match.getResult(next++));
  for (unsigned index = 0; index < taken.fields.size(); ++index)
    if (taken.dying.test(index))
      rewriter.eraseOp(*taken.fields[index].user_begin());
  if (taken.free)
    rewriter.eraseOp(taken.free);
  rewriter.eraseOp(taken.op);
}

struct Expand : impl::IdrRcExpandBase<Expand> {
  void runOnProgram(ProgramOp) {
    // Found first, expanded after: each expansion erases the take the walk
    // would stand on.
    SmallVector<Taken> takes;
    getOperation().walk([&](Operation *op) {
      if (auto take = dyn_cast<CountTakeOp>(op)) {
        if (!claims(take.getValue().getType(), Unique::Self))
          takes.push_back(read(take));
      } else if (auto into = dyn_cast<CountTakeIntoOp>(op)) {
        if (!claims(into.getValue().getType(), Unique::Self))
          takes.push_back(read(into));
      }
    });
    IRRewriter rewriter(&getContext());
    for (Taken &taken : takes)
      expand(rewriter, taken);
    numTests += takes.size();
  }
};

} // namespace
} // namespace idr::counting
