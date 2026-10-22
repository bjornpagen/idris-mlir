// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-expect: properties of a module that tests state by name, instead of
// matching the ops that happen to show them. Each property is a check that
// reports every place it fails, one error each, and changes nothing. What a
// property needs of the module beyond its ops (the symbol table, the cells'
// layouts) it asks of the analysis manager, so properties that ask the same
// share one answer and the pass keeps nothing between runs. The table of
// properties (Lookup.cpp) is the one list of what idr-expect checks: a row
// holds a property's name once, pairs it with the shape of its argument,
// which the row's type checks, and says what it checks. A request's
// argument is read once, before its check runs, into the typed value of its
// shape (ExpectArguments.h): a function named, a count, a list, a module
// read from a file.
//
// A property is stated of the program: the functions the module's
// idr.program holds, under its symbol table, before idr-lower; the
// functions of the module itself after it, which moves them out and erases
// the op. So one property reads a module of either stage.
//
// `@f` names every function made from the code the programmer wrote as f:
// a function whose symbol is f, and a function whose own location names f.
// Emit gives each function, lambdas and delays included, the name of its
// Idris definition; a copy a pass makes keeps its original's location; and
// deduplication fuses the locations of the functions it merges into the
// one it keeps. So a property stated of f holds of every copy of f's code,
// however the passes named it. A hand-written module names a function by
// its symbol, or gives it `loc("f")` where its copies must be found too.
#ifndef IDR_TRANSFORMS_EXPECT_H
#define IDR_TRANSFORMS_EXPECT_H

#include "idr/Analysis/Solver/Components.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"
#include "idr/Transforms/ExpectArguments.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <concepts>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>

namespace idr {
#define GEN_PASS_DECL_IDREXPECT
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace idr::expect {

// What a check is given: the module, the pass's analyses, the name it was
// asked by, which its errors carry, and its argument, read.
template <typename A> struct Request {
  mlir::ModuleOp module;
  mlir::AnalysisManager &analyses;
  llvm::StringRef property;
  const A &argument;
};

// A row of the table: a property's name, and what checks a request of it,
// the text after `=` (empty when there is none) read by its argument's
// parser, then its check run. Fails when it reported an error.
struct Property {
  llvm::StringRef name;
  mlir::LogicalResult (*run)(mlir::ModuleOp module, mlir::AnalysisManager &analyses,
                             llvm::StringRef property, llvm::StringRef text);
};

// The row of `Check` under `name`: its argument is of shape A, so a check
// paired with an argument of another shape does not compile.
template <typename A, mlir::LogicalResult (*Check)(const Request<A> &)>
constexpr Property property(llvm::StringRef name) {
  return {name, [](mlir::ModuleOp module, mlir::AnalysisManager &analyses, llvm::StringRef asked,
                   llvm::StringRef text) -> mlir::LogicalResult {
            mlir::FailureOr<A> argument = A::parse(Written{module, asked, text, A::form}, text);
            if (mlir::failed(argument))
              return mlir::failure();
            return Check(Request<A>{module, analyses, asked, *argument});
          }};
}

// The row of the property named `name`, or null when there is none.
const Property *lookup(llvm::StringRef name);

// --idr-expect-at=<stage>:<property>,...: properties a test states of a
// stage of the pipeline, checked in the compilation itself, so no test
// names a pass and none reads a dump. A property of a stage is checked
// after every pass that leaves the program at that stage. A property an
// optimization makes true holds from the pass that makes it on, so it is
// pending until it first holds and, once held, must hold after every later
// pass of the stage: a pass that breaks it fails, named. A property still
// pending when the program leaves its stage, or when the pipeline ends,
// never held there, and fails. The checks run on the pass manager's own
// thread, on runs of the module and of its program, as the contracts do.
struct StageRequest {
  Stage stage;
  const Property *property;
  std::string text;
};

// The requests one `<stage>:<property>,...` writes: a property's text runs
// to the next comma outside brackets, so an argument may hold commas in a
// list. Fails, with an error at `module`, on a stage or a property that is
// none.
mlir::FailureOr<llvm::SmallVector<StageRequest>> parseStageRequests(mlir::MLIRContext *context,
                                                                     llvm::StringRef written);

class StageInstrumentation final : public mlir::PassInstrumentation {
public:
  explicit StageInstrumentation(llvm::SmallVector<StageRequest> requests);
  void runAfterPass(mlir::Pass *pass, mlir::Operation *op) override;

  // After the pipeline: every request of the stage it ended at that never
  // held fails. The pass manager instruments no end of its own pipeline, so
  // the tool that ran it calls this once, with the module.
  mlir::LogicalResult finish(mlir::ModuleOp module);

private:
  // Whether a request has held yet at its stage.
  enum class Seen : std::uint8_t { Pending, Held };
  struct Tracked {
    StageRequest request;
    Seen seen = Seen::Pending;
  };
  llvm::SmallVector<Tracked> tracked;
  std::optional<Stage> current;

  // The requests of `stage` still pending fail: each never held there.
  bool closePending(Stage stage, mlir::ModuleOp module);
};

// The error that `property` fails at `loc`, to which the caller adds what
// was found: `expected <property>: <what>`.
mlir::InFlightDiagnostic fail(mlir::Location loc, llvm::StringRef property);

// The function that holds `op` (or is it), as `@name`, or "the module".
std::string where(mlir::Operation *op);

// The op whose symbol table holds the program's functions: the module's
// idr.program, or the module once lowering has erased it.
mlir::Operation *programOf(mlir::ModuleOp module);

// The program's functions, in their order.
llvm::SmallVector<mlir::FunctionOpInterface> functionsOf(mlir::ModuleOp module);

// The program's symbol table, built once for every property that asks.
mlir::SymbolTable &symbolsOf(mlir::ModuleOp module, mlir::AnalysisManager &analyses);

// Whether `fn` is made from the code written as `f`: its symbol is `f`, or
// its own location names `f`.
bool names(mlir::FunctionOpInterface fn, llvm::StringRef f);

// The functions the body of `fn` names by a symbol use (a call, a closure,
// a constant), in the order the walk meets them, each once.
llvm::SmallVector<mlir::Operation *> callees(mlir::SymbolTable &symbols, mlir::Operation *fn);

// What `edges` gives of a function: the functions it refers to.
template <class Edges>
concept FunctionEdges = std::invocable<Edges &, mlir::Operation *> &&
                        std::convertible_to<std::invoke_result_t<Edges &, mlir::Operation *>,
                                            llvm::SmallVector<mlir::Operation *>>;

// Every function `roots` reach by `edges`, the roots included, each once,
// in the order first reached. The set is a test's question of one module,
// asked once per check: the functions it reaches are its answer, kept
// nowhere after it.
template <FunctionEdges Edges>
llvm::SmallVector<mlir::Operation *> reachable(llvm::ArrayRef<mlir::Operation *> roots,
                                               Edges edges) {
  llvm::SetVector<mlir::Operation *, llvm::SmallVector<mlir::Operation *>> seen;
  seen.insert(roots.begin(), roots.end());
  for (std::size_t at = 0; at < seen.size(); ++at)
    for (mlir::Operation *next : std::invoke(edges, seen[at]))
      seen.insert(next);
  return seen.takeVector();
}

namespace detail {
// The functions of one check, numbered in the order given: the minter of
// the ids the solver layer's graph of them is built on.
class FunctionNumbering;
struct CheckedFunction {
  using Minter = FunctionNumbering;
};
class FunctionNumbering {
public:
  using Node = Id<CheckedFunction>;
  explicit FunctionNumbering(llvm::ArrayRef<mlir::Operation *> nodes) : nodes(nodes) {
    for (auto [at, fn] : llvm::enumerate(nodes))
      number.try_emplace(fn, static_cast<std::uint32_t>(at));
  }
  Count<Node> count() const { return Count<Node>(static_cast<std::uint32_t>(nodes.size())); }
  // The id of a function of the check; none for one outside it.
  std::optional<Node> idOf(mlir::Operation *fn) const {
    auto at = number.find(fn);
    if (at == number.end())
      return std::nullopt;
    return Node(at->second);
  }
  mlir::Operation *operator[](Node n) const { return nodes[n.index()]; }

private:
  llvm::ArrayRef<mlir::Operation *> nodes;
  // The numbering a check reads its functions into, once, where it reads
  // them: no fact about a function lives here, only its number.
  llvm::DenseMap<mlir::Operation *, std::uint32_t> number;
};
} // namespace detail

// The cycles among `nodes` by `edges`, an edge to a node outside `nodes`
// dropped: each strongly connected component of two or more, or of one
// that refers to itself, callees first, found by the solver layer's
// components over the graph of the check's functions.
template <FunctionEdges Edges>
llvm::SmallVector<llvm::SmallVector<mlir::Operation *>>
cycles(llvm::ArrayRef<mlir::Operation *> nodes, Edges edges) {
  detail::FunctionNumbering numbering(nodes);
  CsrBuilder<detail::CheckedFunction> builder(numbering.count());
  for (detail::FunctionNumbering::Node from : numbering.count().ids())
    for (mlir::Operation *target : std::invoke(edges, numbering[from]))
      if (std::optional<detail::FunctionNumbering::Node> to = numbering.idOf(target))
        builder.edge(from, *to);
  Csr<detail::CheckedFunction> graph = std::move(builder).finish();
  Partition<detail::CheckedFunction> parts = components(graph);
  llvm::SmallVector<llvm::SmallVector<mlir::Operation *>> out;
  for (auto component : parts.size().ids()) {
    if (!parts.cyclic(component))
      continue;
    llvm::SmallVector<mlir::Operation *> &cycle = out.emplace_back();
    for (detail::FunctionNumbering::Node member : parts.members(component))
      cycle.push_back(numbering[member]);
  }
  return out;
}

// Whether `call` calls `g`: its callee's symbol is g, or it calls a
// function of `symbols` made from the code written as g (`names`).
bool callsNamed(mlir::CallOpInterface call, const Symbol &g, mlir::SymbolTable &symbols);

// How many places of `fn` may crash: an idr op that never returns, a
// guard, or a call of the LLVM dialect that never returns (the call says
// so, or its callee in `symbols`).
unsigned crashSitesOf(mlir::FunctionOpInterface fn, mlir::SymbolTable &symbols);

// The uses Idris proved of each binder of the emitted module, by the
// binder's identity: the `#idr.binder<definition, index>` Emit fuses into
// its location, which passes copy with the value as MLIR copies locations.
// A typed identity, never a printed key: no two binders share one, so none
// is dropped.
using ProvedUses = llvm::DenseMap<BinderAttr, Uses>;

// The uses of every binder of `emitted` that carries an identity: a
// function's parameters and the fields a match's case binds. Fails, at the
// second binder, when Emit gave two binders one identity.
mlir::FailureOr<ProvedUses> provedUses(mlir::ModuleOp emitted);

// Every binder of `module` that carries an identity has the uses `proved`
// holds for it; each one that does not is an error of `property`.
mlir::LogicalResult usesKept(const ProvedUses &proved, mlir::ModuleOp module,
                             llvm::StringRef property);

// The checks, by the shape of their argument; the table says what each
// checks.
mlir::LogicalResult noClosures(const Request<Roots> &);
mlir::LogicalResult labels(const Request<Labels> &);
mlir::LogicalResult labelsLeast(const Request<Nothing> &);
mlir::LogicalResult noHeapAllocation(const Request<Roots> &);
mlir::LogicalResult oneClone(const Request<Symbol> &);
mlir::LogicalResult specializedOnce(const Request<Functions> &);
mlir::LogicalResult notCalled(const Request<Symbol> &);
mlir::LogicalResult quantitiesKept(const Request<Module> &);
mlir::LogicalResult reusesInPlace(const Request<Functions> &);
mlir::LogicalResult movesOut(const Request<Roots> &);
mlir::LogicalResult countsNothing(const Request<Functions> &);
mlir::LogicalResult noGuards(const Request<Functions> &);
mlir::LogicalResult testsNothing(const Request<Functions> &);
mlir::LogicalResult exclusiveCopy(const Request<Functions> &);
mlir::LogicalResult resetsUnshared(const Request<Roots> &);
mlir::LogicalResult reusesEveryCell(const Request<Functions> &);
mlir::LogicalResult contified(const Request<Nothing> &);
mlir::LogicalResult outputFused(const Request<Roots> &);
mlir::LogicalResult folded(const Request<Functions> &);
mlir::LogicalResult constantStack(const Request<Functions> &);
mlir::LogicalResult tailCalls(const Request<Pair> &);
mlir::LogicalResult countedLoop(const Request<Functions> &);
mlir::LogicalResult wordLoop(const Request<Functions> &);
mlir::LogicalResult structuredLoops(const Request<Roots> &);
mlir::LogicalResult inPlace(const Request<Roots> &);
mlir::LogicalResult fused(const Request<Functions> &);
mlir::LogicalResult largestFunction(const Request<Bound> &);
mlir::LogicalResult vectorized(const Request<Roots> &);
mlir::LogicalResult narrowedLanes(const Request<Roots> &);
mlir::LogicalResult matches(const Request<Functions> &);
mlir::LogicalResult matchesNothing(const Request<Functions> &);
mlir::LogicalResult forcesSome(const Request<Functions> &);
mlir::LogicalResult forcesNothing(const Request<Functions> &);
mlir::LogicalResult buildsSome(const Request<Functions> &);
mlir::LogicalResult buildsNothing(const Request<Functions> &);
mlir::LogicalResult readsFields(const Request<Functions> &);
mlir::LogicalResult readsNoFields(const Request<Functions> &);
mlir::LogicalResult applies(const Request<Functions> &);
mlir::LogicalResult neverReturns(const Request<Functions> &);
mlir::LogicalResult calls(const Request<Pair> &);
mlir::LogicalResult neverCalls(const Request<Pair> &);
mlir::LogicalResult callsClosed(const Request<Pair> &);
mlir::LogicalResult returnsConstants(const Request<ReturnedValues> &);
mlir::LogicalResult returnsOnPaths(const Request<PathValues> &);
mlir::LogicalResult returnsArguments(const Request<ReturnedArguments> &);
mlir::LogicalResult buildsWhereUsed(const Request<Functions> &);
mlir::LogicalResult callsWhereUsed(const Request<Pair> &);
mlir::LogicalResult matchesOnce(const Request<Functions> &);
mlir::LogicalResult crashesBeforeOutput(const Request<Functions> &);
mlir::LogicalResult parametersUsed(const Request<Functions> &);
mlir::LogicalResult resultsUsed(const Request<Functions> &);
mlir::LogicalResult regionsDistinct(const Request<Functions> &);
mlir::LogicalResult checksEveryPath(const Request<Functions> &);
mlir::LogicalResult growsNothing(const Request<FunctionsAndModule> &);
mlir::LogicalResult callOrder(const Request<Listed> &);
mlir::LogicalResult callsDistinct(const Request<Pair> &);
mlir::LogicalResult callsRead(const Request<Pair> &);
mlir::LogicalResult callsOnly(const Request<Listed> &);
mlir::LogicalResult directCalls(const Request<Roots> &);
mlir::LogicalResult crashSites(const Request<CountOf> &);
mlir::LogicalResult lowered(const Request<Roots> &);
mlir::LogicalResult inLLVM(const Request<Nothing> &);
mlir::LogicalResult signature(const Request<TypeOf> &);
mlir::LogicalResult convention(const Request<ConventionOf> &);
mlir::LogicalResult entry(const Request<Nothing> &);
mlir::LogicalResult linkerNames(const Request<Nothing> &);
mlir::LogicalResult loops(const Request<Loops> &);
mlir::LogicalResult straightLine(const Request<Functions> &);
mlir::LogicalResult alignedAccess(const Request<Roots> &);
mlir::LogicalResult readsNothing(const Request<Functions> &);
mlir::LogicalResult writesNothing(const Request<Functions> &);
mlir::LogicalResult solvedEffects(const Request<EffectsOf> &);
mlir::LogicalResult computesNothing(const Request<Functions> &);
mlir::LogicalResult dimsKnown(const Request<Functions> &);
mlir::LogicalResult byName(const Request<Symbol> &);
mlir::LogicalResult notByName(const Request<Symbol> &);
mlir::LogicalResult total(const Request<Functions> &);
mlir::LogicalResult notTotal(const Request<Functions> &);
mlir::LogicalResult apart(const Request<TwoFunctions> &);
mlir::LogicalResult reaches(const Request<Pair> &);
mlir::LogicalResult stage(const Request<StageIs> &);

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECT_H
