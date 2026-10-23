// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-expand: the last step of counting at the dialect's level. A take
// of a value whose grade proves its own cell the holder's alone (a claim on
// its own cells, which are its family's and those of each in-place family
// it holds, or on everything it reaches) stays a take: its fields move out
// of the cell with no count read, each at the grade its read gives, and its
// token is the cell, never null. Any other take becomes the one test of
// sharing left to run, a match on uniqueness of two regions
// (count.match_unique), of which exactly one runs:
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
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Counting/Facts.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"

#define GEN_PASS_DEF_IDRRCEXPAND
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting {
namespace {

// What reuse made of a take's token, one case each.
enum class TokenUse : std::uint8_t { Freed, Recycled, GivenOn };

// The positions of a take's fields, split by what becomes of each: those
// whose one use is a drop right where the take is die with the cell, and the
// rest live on. Positions are counted as MLIR numbers an op's results.
struct Fates {
  SmallVector<unsigned> living;
  SmallVector<unsigned> dying;
};

Fates fatesOf(ResultRange fields) {
  Fates fates;
  unsigned index = 0;
  for (OpResult field : fields) {
    bool dies = field.hasOneUse() && isa<CountDropOp>(*field.user_begin());
    (dies ? fates.dying : fates.living).push_back(index++);
  }
  return fates;
}

// A take to expand, read once: where it takes its value, its fields and
// what becomes of each, and of its token. The value is read off its
// operand when the take is expanded: a take of a field of another take
// finds that field replaced by the other's match result once the other is
// expanded, and the field itself gone.
struct Taken {
  Operation *op;
  OpOperand *value;
  DataType data;
  ResultRange fields;
  TokenUse use;
  // The token (taken), or the cell (fused into one recycle).
  Value given;
  // The free of a freed token.
  Operation *free = nullptr;
  Fates fates;
};

// A take whose cell becomes free here, its token's one user its free,
// frees the cell in the unique region.
Taken read(CountTakeOp take) {
  Taken taken{take, &take.getValueMutable(), take.getDataType(), take.getFields(), TokenUse::GivenOn,
              take.getToken(), nullptr, fatesOf(take.getFields())};
  if (take.getFreedCellType()) {
    taken.use = TokenUse::Freed;
    taken.free = *take.getToken().user_begin();
  }
  return taken;
}

Taken read(CountTakeIntoOp into) {
  return Taken{into, &into.getValueMutable(), into.getDataType(), into.getFields(), TokenUse::Recycled,
               into.getCell(), nullptr, fatesOf(into.getFields())};
}

// The fields of a counted value that live on, each read from it, and one
// its count frees given a reference of its own: the shared region's fields.
SmallVector<Value> dupFields(RewriterBase &rewriter, Location loc, Value owner,
                             llvm::ArrayRef<unsigned> fields) {
  SmallVector<Value> dups;
  for (unsigned index : fields) {
    Value read = DataFieldOp::create(rewriter, loc, owner, index).getResult();
    dups.push_back(freedBy(read.getType(), Release::Counted)
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
  Value value = taken.value->get();
  Type tokenType = taken.op->getResult(0).getType();
  llvm::ArrayRef<unsigned> living = taken.fates.living;
  // The match's results: what replaces the token or the cell, then the
  // living fields.
  SmallVector<Type> results;
  if (taken.use != TokenUse::Freed)
    results.push_back(tokenType);
  for (unsigned index : living)
    results.push_back(taken.fields[index].getType());
  rewriter.setInsertionPoint(taken.op);
  auto match = CountMatchUniqueOp::create(rewriter, loc, results, value);
  // The unique region: the cell's token, the holder's alone, and the fields
  // moved out.
  {
    SmallVector<Type> args{graded(Grade{Uses::Once, Hold::counted(Unique::Deep)}, unrestricted(tokenType))};
    if (taken.use == TokenUse::Recycled)
      args[0] = graded(Grade{Uses::Once, Hold::counted(Unique::Deep)}, ReuseTokenType::of(taken.data));
    for (Value field : taken.fields)
      args.push_back(field.getType());
    Block *unique = rewriter.createBlock(&match.getUnique(), {}, args,
                                         SmallVector<Location>(args.size(), loc));
    Value token = unique->getArgument(0);
    SmallVector<Value> yields;
    for (unsigned index : taken.fates.dying)
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
    Block *shared = rewriter.createBlock(&match.getShared(), {}, {value.getType()}, {loc});
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
  for (unsigned index : taken.fates.dying)
    rewriter.eraseOp(*taken.fields[index].user_begin());
  if (taken.free)
    rewriter.eraseOp(taken.free);
  rewriter.eraseOp(taken.op);
}

struct Expand : impl::IdrRcExpandBase<Expand> {
  void runOnProgram(ProgramOp) {
    // Found first, expanded after: each expansion erases the take the walk
    // would stand on. Each expansion builds at its own take and reads its
    // value where it stands, so the order they run in builds one program.
    SmallVector<Taken> takes;
    getOperation().walk([&](CountTakeOp take) {
      if (!claims(take.getValue().getType(), Unique::Self))
        takes.push_back(read(take));
    });
    getOperation().walk([&](CountTakeIntoOp into) {
      if (!claims(into.getValue().getType(), Unique::Self))
        takes.push_back(read(into));
    });
    IRRewriter rewriter(&getContext());
    for (Taken &taken : takes)
      expand(rewriter, taken);
    numTests += takes.size();
  }
};

} // namespace
} // namespace idr::counting
