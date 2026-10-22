// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the structure ops' control flow: idr.join, idr.loop, idr.jump,
// idr.yield and lit.match, read three ways. Upstream's region branch
// interface gives each branch point's successors; idr::forwardedValues
// hands every reader that follows a value each operand moved, with the
// value it becomes; and a join point's op says what arrives at each of its
// regions and at its results, read off its tokens' uses. Each case is a
// function holding a nest of those ops, built from a seed (FlowCases.cpp),
// whose builder keeps what it meant as it builds: the three readings must
// be exactly that, as multisets. A jump crosses every op between it and its
// join point, and an idr.loop's regions begin with tokens before their
// parameters, which is where a reading goes wrong; the judgement is shown
// failing each model planted with one such fault, so the cases do reach
// jumps that cross ops, jumps into a loop's regions with parameters, and
// jumps nested below a join point's own regions.

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"
#include "idr/Testing/FlowCases.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstdint>
#include <iterator>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace {

using idr::box::flow::Arrival;
using idr::box::flow::Case;
using idr::box::flow::Edge;
using idr::box::flow::Facts;
using idr::box::flow::Move;
using idr::box::flow::Place;

// The number of seeds the box builds a case from.
constexpr std::uint64_t seeds = 2000;

//===----------------------------------------------------------------------===//
// The readings
//===----------------------------------------------------------------------===//

Place placeOf(mlir::RegionSuccessor successor) {
  if (successor.isRegion())
    return successor.getSuccessor();
  return successor.getSuccessorOp();
}

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
    Case built = idr::box::flow::caseOf(context, seed);
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
// the op whose region, or whose results, the target is.
bool crosses(mlir::Operation *jump, Place target) {
  mlir::Operation *owner = idr::match(
      target, [](mlir::Region *region) { return region->getParentOp(); },
      [](mlir::Operation *op) { return op; });
  return jump->getParentOp() != owner;
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
           crosses(edge.from, edge.to);
  });
  // A value's queries are not const, so the predicate asks a copy of the
  // handle.
  std::erase_if(facts.moves, [](const Move &move) {
    mlir::Operation *owner = move.use->getOwner();
    mlir::Value input = move.input;
    return llvm::isa<idr::JumpOp>(owner) && crosses(owner, Place(input.getParentRegion()));
  });
  std::erase_if(facts.arrivals, [](const Arrival &arrival) {
    return llvm::isa<idr::JumpOp>(arrival.from) &&
           crosses(arrival.from, arrival.at);
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
