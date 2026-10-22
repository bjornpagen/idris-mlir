// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the structure ops' control flow: idr.join, idr.loop, idr.jump,
// idr.yield and lit.match, read three ways. Upstream's region branch
// interface gives each branch point's successors; idr::forwardedValues
// hands every reader that follows a value each operand moved, with the
// value it becomes; and a join point's op says what arrives at each of its
// regions and at its results, read off its tokens' uses. Each case is a
// function holding a nest of those ops, built from a seed, and the builder
// keeps what it meant as it builds: the three readings must be exactly
// that, as multisets. A jump crosses every op between it and its join
// point, and an idr.loop's regions begin with tokens before their
// parameters, which is where a reading goes wrong; the judgement is shown
// failing each model planted with one such fault, so the cases do reach
// jumps that cross ops, jumps into a loop's regions with parameters, and
// jumps nested below a join point's own regions.

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Enum.h"
#include "idr/Support/Match.h"
#include "idr/Testing/Draws.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/PointerUnion.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/raw_ostream.h"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

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

// The number of seeds the box builds a case from.
constexpr std::uint64_t seeds = 2000;

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

//===----------------------------------------------------------------------===//
// The facts
//===----------------------------------------------------------------------===//

// Where control goes: a region, or out of an op to its results.
using Place = llvm::PointerUnion<mlir::Region *, mlir::Operation *>;

Place placeOf(mlir::RegionSuccessor successor) {
  if (successor.isRegion())
    return successor.getSuccessor();
  return successor.getSuccessorOp();
}

// A successor of a branch point: `from` is the op itself, entered, or a
// terminator of one of its regions.
struct Edge {
  mlir::Operation *from;
  Place to;
};
// An operand a branch point forwards, and the value it becomes there.
struct Move {
  mlir::OpOperand *use;
  mlir::Value input;
};
// A branch point that arrives at `at`, a region of the join point's op
// `group` or its results: `from` is the op itself, entering its body, or a
// terminator.
struct Arrival {
  mlir::Operation *group;
  Place at;
  mlir::Operation *from;
};

struct Facts {
  std::vector<Edge> edges;
  std::vector<Move> moves;
  std::vector<Arrival> arrivals;
};

std::uintptr_t address(const void *p) { return reinterpret_cast<std::uintptr_t>(p); }

// Each fact by the identities it names, which order a multiset of facts.
auto keyOf(const Edge &edge) {
  return std::tuple(address(edge.from), address(edge.to.getOpaqueValue()));
}
auto keyOf(const Move &move) {
  return std::tuple(address(move.use), address(move.input.getAsOpaquePointer()));
}
auto keyOf(const Arrival &arrival) {
  return std::tuple(address(arrival.group), address(arrival.at.getOpaqueValue()),
                    address(arrival.from));
}

// The name the builder gave an op, which the printed case shows.
std::string nameOf(mlir::Operation *op) {
  return llvm::cast<mlir::NameLoc>(op->getLoc()).getName().str();
}

std::string nameOf(Place place) {
  return idr::match(
      place,
      [](mlir::Region *region) {
        return "region " + std::to_string(region->getRegionNumber()) + " of " +
               nameOf(region->getParentOp());
      },
      [](mlir::Operation *op) { return "the results of " + nameOf(op); });
}

std::string nameOf(mlir::Value value) {
  if (auto argument = llvm::dyn_cast<mlir::BlockArgument>(value))
    return "argument " + std::to_string(argument.getArgNumber()) + " of " +
           nameOf(Place(argument.getOwner()->getParent()));
  auto result = llvm::cast<mlir::OpResult>(value);
  return "result " + std::to_string(result.getResultNumber()) + " of " +
         nameOf(result.getOwner());
}

std::string describe(const Edge &edge) { return nameOf(edge.from) + " goes to " + nameOf(edge.to); }
std::string describe(const Move &move) {
  return "operand " + std::to_string(move.use->getOperandNumber()) + " of " +
         nameOf(move.use->getOwner()) + " becomes " + nameOf(move.input);
}
std::string describe(const Arrival &arrival) {
  return nameOf(arrival.from) + " arrives at " + nameOf(arrival.at);
}

// What `read` lacks of `meant` and holds beyond it, a line per fact;
// nothing when the two are one multiset.
template <typename Fact>
std::string differ(llvm::StringRef reading, std::vector<Fact> meant, std::vector<Fact> read) {
  auto less = [](const Fact &a, const Fact &b) { return keyOf(a) < keyOf(b); };
  std::ranges::sort(meant, less);
  std::ranges::sort(read, less);
  std::vector<Fact> lacks, beyond;
  std::ranges::set_difference(meant, read, std::back_inserter(lacks), less);
  std::ranges::set_difference(read, meant, std::back_inserter(beyond), less);
  std::string out;
  for (const Fact &fact : lacks)
    out += "\n  the " + reading.str() + " lack: " + describe(fact);
  for (const Fact &fact : beyond)
    out += "\n  the " + reading.str() + " hold beyond: " + describe(fact);
  return out;
}

// The three readings of a function: each branch point's successors as its
// region branch says, every value idr::forwardedValues hands on, and what
// arrives at each region of a join point's op and at its results, as the
// op says.
Facts readingOf(mlir::Operation *function) {
  Facts facts;
  auto successors = [&](mlir::RegionBranchOpInterface branch, mlir::RegionBranchPoint point,
                        mlir::Operation *from) {
    llvm::SmallVector<mlir::RegionSuccessor> found;
    branch.getSuccessorRegions(point, found);
    for (mlir::RegionSuccessor successor : found)
      facts.edges.push_back({from, placeOf(successor)});
  };
  function->walk([&](mlir::Operation *op) {
    if (auto branch = llvm::dyn_cast<mlir::RegionBranchOpInterface>(op))
      successors(branch, mlir::RegionBranchPoint::parent(), op);
    if (auto terminator = llvm::dyn_cast<mlir::RegionBranchTerminatorOpInterface>(op))
      if (auto branch = llvm::dyn_cast<mlir::RegionBranchOpInterface>(op->getParentOp()))
        successors(branch, mlir::RegionBranchPoint(terminator), op);
    idr::forwardedValues(op, [&](mlir::OpOperand &use, mlir::Value input) {
      facts.moves.push_back({&use, input});
    });
    if (!llvm::isa<idr::JoinPointsOpInterface>(op))
      return;
    auto branch = llvm::cast<mlir::RegionBranchOpInterface>(op);
    auto arrivals = [&](mlir::RegionSuccessor at) {
      llvm::SmallVector<mlir::RegionBranchPoint> points;
      branch.getPredecessors(at, points);
      // A point is the op itself or a terminator: upstream's two kinds.
      for (mlir::RegionBranchPoint point : points)
        facts.arrivals.push_back(
            {op, placeOf(at),
             point.isParent() ? op : point.getTerminatorPredecessorOrNull().getOperation()});
    };
    for (mlir::Region &region : op->getRegions())
      arrivals(mlir::RegionSuccessor(&region));
    arrivals(mlir::RegionSuccessor(op));
  });
  return facts;
}

//===----------------------------------------------------------------------===//
// The cases
//===----------------------------------------------------------------------===//

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

// A case: its module, which owns its function, and what its builder meant.
struct Case {
  mlir::OwningOpRef<mlir::ModuleOp> module;
  Facts meant;
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
  // each entered from the match. A case binds nothing; the default binds
  // the scrutinee, which enters it.
  mlir::Operation *match(mlir::TypeRange types, const Scope &outer) {
    llvm::SmallVector<mlir::Attribute> keys;
    for (unsigned cases = draws.below(3), k = 0; k < cases; ++k)
      keys.push_back(b.getStringAttr("k" + llvm::Twine(k)));
    mlir::Location loc = named(kindNames[Kind::Match]);
    auto op = idr::LitMatchOp::create(b, loc, types, scrutinee, b.getArrayAttr(keys));
    for (mlir::Region &region : op->getRegions()) {
      pending.push_back(
          {&region.emplaceBlock(), op, Kind::Match, Scope{outer.depth + 1, outer.targets, outer.values}});
      meant.edges.push_back({op, &region});
    }
    mlir::Value refined = op.getDefaultRegion().front().addArgument(text, loc);
    meant.moves.push_back({&op->getOpOperand(0), refined});
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

//===----------------------------------------------------------------------===//
// The judgement
//===----------------------------------------------------------------------===//

// Whether a failing case is reported: by the box's own judgement, each;
// by a mutant's, none, since a mutant must fail.
enum class Report : std::uint8_t { Each, None };

std::string printed(mlir::ModuleOp module) {
  std::string text;
  llvm::raw_string_ostream out(text);
  module->print(out, mlir::OpPrintingFlags().enableDebugInfo().printGenericOpForm());
  return text;
}

// The cases, over every seed up to `limit` of them, whose readings differ
// from what their builder meant once `plant` has planted its fault in it,
// or that do not verify. Each is reported, when `report` says so, with its
// seed, every difference and the case printed.
template <typename Plant>
unsigned judge(Plant plant, unsigned limit, Report report) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::func::FuncDialect>();
  std::string diagnostic;
  mlir::ScopedDiagnosticHandler capture(&context, [&](mlir::Diagnostic &found) {
    if (diagnostic.empty())
      diagnostic = found.str();
    return mlir::success();
  });
  unsigned failures = 0;
  for (std::uint64_t seed = 1; seed <= seeds && failures < limit; ++seed) {
    diagnostic.clear();
    Case built = Builder(context, seed).build();
    std::string why;
    if (mlir::failed(mlir::verify(*built.module))) {
      why = "\n  the case does not verify: " + diagnostic;
    } else {
      Facts meant = built.meant;
      plant(meant);
      Facts read = readingOf(*built.module);
      why = differ("successors", std::move(meant.edges), std::move(read.edges)) +
            differ("forwarded values", std::move(meant.moves), std::move(read.moves)) +
            differ("arrivals", std::move(meant.arrivals), std::move(read.arrivals));
    }
    if (why.empty())
      continue;
    ++failures;
    if (report == Report::Each)
      ADD_FAILURE() << "seed " << seed << why << "\n" << printed(*built.module);
  }
  return failures;
}

TEST(ControlFlow, EveryReadingIsWhatTheBuilderMeant) {
  EXPECT_EQ(judge([](Facts &) {}, 10, Report::Each), 0u);
}

// Whether a jump crosses an op on its way to `target`: its own op is not
// the target's.
bool crosses(mlir::Operation *jump, mlir::Region *target) {
  return jump->getParentOp() != target->getParentOp();
}

// A loop's tokens taken for its join region's first parameters.
void tokensAsParameters(Facts &facts) {
  for (Move &move : facts.moves) {
    auto jump = llvm::dyn_cast<idr::JumpOp>(move.use->getOwner());
    if (!jump)
      continue;
    unsigned argument = move.use->getOperandNumber() - jump.getArgs().getBeginOperandIndex();
    move.input = llvm::cast<mlir::BlockArgument>(move.input).getOwner()->getArgument(argument);
  }
}

// A jump kept by an op it crosses, which lets nothing through.
void crossingsKept(Facts &facts) {
  std::erase_if(facts.edges, [](const Edge &edge) {
    return llvm::isa<idr::JumpOp>(edge.from) &&
           crosses(edge.from, llvm::cast<mlir::Region *>(edge.to));
  });
  std::erase_if(facts.moves, [](const Move &move) {
    mlir::Operation *owner = move.use->getOwner();
    return llvm::isa<idr::JumpOp>(owner) && crosses(owner, move.input.getParentRegion());
  });
  std::erase_if(facts.arrivals, [](const Arrival &arrival) {
    return llvm::isa<idr::JumpOp>(arrival.from) &&
           crosses(arrival.from, llvm::cast<mlir::Region *>(arrival.at));
  });
}

// A jump read as a yield of the op it ends.
void jumpsAsYields(Facts &facts) {
  for (Edge &edge : facts.edges)
    if (llvm::isa<idr::JumpOp>(edge.from))
      edge.to = edge.from->getParentOp();
  std::erase_if(facts.moves,
                [](const Move &move) { return llvm::isa<idr::JumpOp>(move.use->getOwner()); });
  std::erase_if(facts.arrivals,
                [](const Arrival &arrival) { return llvm::isa<idr::JumpOp>(arrival.from); });
}

// A join point's op hearing only the terminators of its own regions, as a
// walk of each region's last op would.
void ownTerminatorsOnly(Facts &facts) {
  std::erase_if(facts.arrivals, [](const Arrival &arrival) {
    return arrival.from != arrival.group && arrival.from->getParentOp() != arrival.group;
  });
}

// The judgement can fail: each model with a planted fault disagrees with
// the readings on some case.
TEST(ControlFlow, EachMutantModelIsCaught) {
  EXPECT_GT(judge(tokensAsParameters, 1, Report::None), 0u);
  EXPECT_GT(judge(crossingsKept, 1, Report::None), 0u);
  EXPECT_GT(judge(jumpsAsYields, 1, Report::None), 0u);
  EXPECT_GT(judge(ownTerminatorsOnly, 1, Report::None), 0u);
}

} // namespace
