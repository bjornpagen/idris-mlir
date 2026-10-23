// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cases of the control-flow box: a function holding a nest of
// idr.join, idr.loop and lit.match, built from a seed, each region ending
// in a yield of its op's results or a jump to a join point it sees. The
// builder keeps what it means as it builds: each edge into a region or out
// to an op's results, each operand a terminator forwards with the value it
// becomes, and what arrives at a join point's op. The cases reach jumps
// that cross ops, jumps into a loop's regions with parameters, and jumps
// nested below a join point's own regions.

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Enum.h"
#include "idr/Testing/Draws.h"
#include "idr/Testing/FlowCases.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/OperationSupport.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"

#include <cstddef>
#include <cstdint>
#include <utility>

namespace {

// Whether a region holds an op before it ends.
enum class Before : std::uint8_t { Nothing, Nest };
// How a region ends: yielding its op's results, or jumping to a join point
// it sees.
enum class Exit : std::uint8_t { Yield, Jump };
// The op a region holds.
enum class Kind : std::uint8_t { Join, Loop, Match };
// Where a join point's op holds its tokens: in its body alone, as an
// idr.join does, so no join region repeats; or at the head of every region,
// as an idr.loop does, so its join regions may jump to themselves.
enum class Tokens : std::uint8_t { InBody, InEveryRegion };

} // namespace

template <>
struct idr::EnumTraits<Before> {
  static constexpr std::size_t count = 2;
};
template <>
struct idr::EnumTraits<Exit> {
  static constexpr std::size_t count = 2;
};
template <>
struct idr::EnumTraits<Kind> {
  static constexpr std::size_t count = 3;
};

namespace {

using idr::EnumArray;
using idr::box::Draws;
using idr::box::flow::Case;
using idr::box::flow::Facts;

constexpr EnumArray<Kind, const char *> kindNames{{"join", "loop", "match"}};

// How often each choice comes in one case, drawn first from its seed, the
// first case of each choice at least once in four. The most ops a region
// lies inside for it to hold one more is drawn too, so some cases are one
// op deep and others nest three.
struct Swarm {
  EnumArray<Before, unsigned> before;
  EnumArray<Exit, unsigned> exit;
  EnumArray<Kind, unsigned> kind;
  unsigned deepest;

  explicit Swarm(Draws &draws)
      : before{{1 + draws.below(4), draws.below(5)}}, exit{{1 + draws.below(4), draws.below(5)}},
        kind{{1 + draws.below(4), draws.below(5), draws.below(5)}}, deepest(1 + draws.below(3)) {}
};

// A join point a region may jump to: the token that designates it there,
// its join region, and that region's parameters.
struct Target {
  mlir::Value token;
  mlir::Region *region;
  mlir::Block::BlockArgListType parameters;
};

// What a region sees: how many ops it lies inside, the join points it may
// jump to, and the words it may pass.
struct Scope {
  unsigned depth;
  llvm::SmallVector<Target, 4> targets;
  llvm::SmallVector<mlir::Value, 4> values;
};

// A region still to fill: its block, the op whose region it is, that op's
// kind, and what the region sees.
struct Pending {
  mlir::Block *block;
  mlir::Operation *op;
  Kind kind;
  Scope scope;
};

// The builder of one case. The function takes a string, the scrutinee of
// every lit.match, and two words; the top op's results are its own. Each
// region is filled once, from a stack, so no recursion follows the nest.
class Builder {
public:
  Builder(mlir::MLIRContext &context, std::uint64_t seed)
      : draws(seed), swarm(draws), b(&context), word(b.getI64Type()),
        token(b.getType<mlir::TokenType>()), text(idr::StrType::get(&context)) {}

  Case build() && {
    mlir::Location loc = b.getUnknownLoc();
    Case built{mlir::ModuleOp::create(loc), {}};
    b.setInsertionPointToEnd(built.module->getBody());
    llvm::SmallVector<mlir::Type> results(draws.below(3), word);
    auto fn = mlir::func::FuncOp::create(b, loc, "flow",
                                         b.getFunctionType({text, word, word}, results));
    mlir::Block *entry = fn.addEntryBlock();
    scrutinee = entry->getArgument(0);
    b.setInsertionPointToEnd(entry);
    Scope outside{0, {}, {entry->getArgument(1), entry->getArgument(2)}};
    mlir::Operation *top = nest(draws.weighted(swarm.kind), results.size(), outside);
    mlir::func::ReturnOp::create(b, loc, top->getResults());
    while (!pending.empty())
      fill(pending.pop_back_val());
    built.meant = std::move(meant);
    return built;
  }

private:
  // A location naming the op it is given to.
  mlir::Location named(llvm::StringRef kind) {
    return mlir::NameLoc::get(b.getStringAttr(kind + llvm::Twine(made++)));
  }

  // An op of `kind` with `results` words at the builder's point, inside
  // `outer`: its regions' blocks made with their arguments and queued to
  // be filled, and the edges into them meant. Each kind is made by its own
  // member, chosen once from the table.
  mlir::Operation *nest(Kind kind, std::size_t results, const Scope &outer) {
    using Make = mlir::Operation *(Builder::*)(mlir::TypeRange, const Scope &);
    static constexpr EnumArray<Kind, Make> makers{
        {&Builder::group<idr::JoinOp, Kind::Join, Tokens::InBody>,
         &Builder::group<idr::LoopOp, Kind::Loop, Tokens::InEveryRegion>, &Builder::match}};
    llvm::SmallVector<mlir::Type> types(results, word);
    return (this->*makers[kind])(types, outer);
  }

  // A join point's op: its body and one or two join regions, each with
  // up to two parameters. Its body enters once from the op, with nothing.
  template <typename Group, Kind kind, Tokens tokens>
  mlir::Operation *group(mlir::TypeRange types, const Scope &outer) {
    unsigned joins = 1 + draws.below(2);
    mlir::Location loc = named(kindNames[kind]);
    mlir::OperationState state(loc, Group::getOperationName());
    state.addTypes(types);
    llvm::SmallVector<mlir::Attribute> binders(
        joins, idr::IndexBindersAttr::get(b.getContext(), llvm::ArrayRef<idr::families::Sort>()));
    state.getOrAddProperties<typename Group::Properties>().binders = b.getArrayAttr(binders);
    for (unsigned region = 0; region <= joins; ++region)
      state.addRegion();
    mlir::Operation *op = b.create(state);

    // The tokens each region begins with: the body always, a join region
    // only where the tokens head every region.
    unsigned heads = tokens == Tokens::InEveryRegion ? joins : 0;
    mlir::Block &body = op->getRegion(0).emplaceBlock();
    for (unsigned k = 0; k < joins; ++k)
      body.addArgument(token, loc);
    for (mlir::Region &region : op->getRegions().drop_front()) {
      mlir::Block &block = region.emplaceBlock();
      for (unsigned k = 0; k < heads; ++k)
        block.addArgument(token, loc);
      for (unsigned p = draws.below(3); p > 0; --p)
        block.addArgument(word, loc);
    }

    // What a region whose block begins with the op's tokens sees: what
    // `outer` sees, and the op's join points through those tokens.
    auto through = [&](mlir::Block &entry) {
      Scope inner{outer.depth + 1, outer.targets, outer.values};
      for (unsigned k = 0; k < joins; ++k) {
        mlir::Region &join = op->getRegion(k + 1);
        inner.targets.push_back(
            {entry.getArgument(k), &join, join.front().getArguments().drop_front(heads)});
      }
      return inner;
    };
    pending.push_back({&body, op, kind, through(body)});
    for (mlir::Region &region : op->getRegions().drop_front()) {
      mlir::Block &block = region.front();
      Scope inner{outer.depth + 1, outer.targets, outer.values};
      if constexpr (tokens == Tokens::InEveryRegion)
        inner = through(block);
      llvm::append_range(inner.values, block.getArguments().drop_front(heads));
      pending.push_back({&block, op, kind, std::move(inner)});
    }
    meant.edges.push_back({op, &op->getRegion(0)});
    meant.arrivals.push_back({op, &op->getRegion(0), op});
    return op;
  }

  // A lit.match on the function's string: a default and up to two cases,
  // each entered from the match. Every region binds the scrutinee, which
  // enters it: a case's binding equals its key, the default's none of them.
  mlir::Operation *match(mlir::TypeRange types, const Scope &outer) {
    llvm::SmallVector<mlir::Attribute> keys;
    for (unsigned cases = draws.below(3), k = 0; k < cases; ++k)
      keys.push_back(b.getStringAttr("k" + llvm::Twine(k)));
    mlir::Location loc = named(kindNames[Kind::Match]);
    auto op = idr::LitMatchOp::create(b, loc, types, scrutinee, b.getArrayAttr(keys));
    for (mlir::Region &region : op->getRegions()) {
      mlir::Block &block = region.emplaceBlock();
      mlir::Value bound = block.addArgument(text, loc);
      pending.push_back(
          {&block, op, Kind::Match, Scope{outer.depth + 1, outer.targets, outer.values}});
      meant.edges.push_back({op, &region});
      meant.moves.push_back({&op->getOpOperand(0), bound});
    }
    return op;
  }

  // Fills `region`: an op before its end where its depth leaves room and
  // the draw says so, then a yield of its op's results or a jump to a join
  // point it sees, whose operands are drawn from the words it may pass, the
  // results of the op before it first.
  void fill(Pending region) {
    b.setInsertionPointToEnd(region.block);
    llvm::SmallVector<mlir::Value, 4> values = region.scope.values;
    EnumArray<Before, unsigned> before = swarm.before;
    if (region.scope.depth >= swarm.deepest)
      before[Before::Nest] = 0;
    if (draws.weighted(before) == Before::Nest) {
      mlir::Operation *inner = nest(draws.weighted(swarm.kind), draws.below(3), region.scope);
      mlir::ResultRange given = inner->getResults();
      values.insert(values.begin(), given.begin(), given.end());
    }
    EnumArray<Exit, unsigned> exit = swarm.exit;
    if (region.scope.targets.empty())
      exit[Exit::Jump] = 0;
    using Make = void (Builder::*)(const Pending &, llvm::ArrayRef<mlir::Value>);
    static constexpr EnumArray<Exit, Make> exits{{&Builder::yield, &Builder::jump}};
    (this->*exits[draws.weighted(exit)])(region, values);
  }

  // `count` of `values`, round the list from a drawn start.
  llvm::SmallVector<mlir::Value> pick(llvm::ArrayRef<mlir::Value> values, std::size_t count) {
    llvm::SmallVector<mlir::Value> picked;
    unsigned start = draws.below(values.size());
    for (std::size_t i = 0; i < count; ++i)
      picked.push_back(values[(start + i) % values.size()]);
    return picked;
  }

  // Each operand of the yield becomes the result of its op at its place;
  // a join point's op hears it among what arrives at its results.
  void yield(const Pending &region, llvm::ArrayRef<mlir::Value> values) {
    mlir::Operation *op = region.op;
    auto terminator = idr::YieldOp::create(b, named("yield"), pick(values, op->getNumResults()));
    meant.edges.push_back({terminator, op});
    for (mlir::OpOperand &use : terminator->getOpOperands())
      meant.moves.push_back({&use, op->getResult(use.getOperandNumber())});
    if (region.kind != Kind::Match)
      meant.arrivals.push_back({op, op, terminator});
  }

  // Each argument of the jump becomes its target's parameter at its place,
  // whatever ops lie between the jump and the target's op.
  void jump(const Pending &region, llvm::ArrayRef<mlir::Value> values) {
    const Target &target = region.scope.targets[draws.below(region.scope.targets.size())];
    auto terminator = idr::JumpOp::create(b, named("jump"), target.token,
                                          pick(values, target.parameters.size()),
                                          idr::IndexArgsAttr());
    meant.edges.push_back({terminator, target.region});
    for (auto [use, parameter] : llvm::zip_equal(terminator.getArgsMutable(), target.parameters))
      meant.moves.push_back({&use, parameter});
    meant.arrivals.push_back({target.region->getParentOp(), target.region, terminator});
  }

  Draws draws;
  Swarm swarm;
  mlir::OpBuilder b;
  mlir::Type word, token, text;
  mlir::Value scrutinee;
  unsigned made = 0;
  llvm::SmallVector<Pending> pending;
  Facts meant;
};

} // namespace

Case idr::box::flow::caseOf(mlir::MLIRContext &context, std::uint64_t seed) {
  return Builder(context, seed).build();
}
