// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-expect: properties of a module that tests state by name, instead of
// matching the ops that happen to show them. Each property is a check that
// reports every place it fails, one error each, and changes nothing. What a
// property needs of the module beyond its ops (the symbol table, the cells'
// layouts) it asks of the analysis manager, so properties that ask the same
// share one answer and the pass keeps nothing between runs. The properties
// are listed once, as Idris records (harness/Properties.idr), whose printed
// table (ExpectProperties.inc) gives each its name, the shape of its
// argument, its check and what it checks; the pass's table and the checks'
// declarations are made from it. A request's argument is read once, before
// its check runs, into the typed value of its shape (ExpectArguments.h): a
// function named, a name, a pair of them.
//
// A property reads what the dialect declares of an op (an interface, a
// trait, the effect system's one query) or a value's type, never a list of
// ops, so it states the same of every op that declares the same.
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
#include "idr/Support/Changed.h"
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

// The checks, one per row of the table: each takes the typed argument of
// its row's shape, so a check written for another shape than its row's
// does not compile. A test reaches a check only by its property's name,
// and the contracts reach the universal ones only through `universal`.
#define IDR_EXPECT_PROPERTY(name, Shape, check) mlir::LogicalResult check(const Request<Shape> &);
#define IDR_EXPECT_SELF_CHECK(name, Shape, check) IDR_EXPECT_PROPERTY(name, Shape, check)
#define IDR_EXPECT_UNIVERSAL(name, Shape, check) IDR_EXPECT_PROPERTY(name, Shape, check)
#include "idr/Transforms/ExpectProperties.inc"
#undef IDR_EXPECT_UNIVERSAL
#undef IDR_EXPECT_SELF_CHECK
#undef IDR_EXPECT_PROPERTY

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

// The module a check of a pass's run on `op` reads, when the run is one the
// stage expectations and the contracts check: a run on the module itself,
// or on an op whose run covers the whole program (CheckedRoot), which the
// module holds. Null for a run on an op inside the program, a function the
// nest runs on a worker thread, which is checked as the nest's run.
mlir::ModuleOp checkedModule(mlir::Operation *op);

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

// The module's program where it is first-order and its functions are ours,
// past defunctionalization and before the lowering: the program the program
// graph indexes. Null elsewhere: a program whose closures remain, a module
// the lowering has left, a hand-written module with no program.
ProgramOp firstOrderProgram(mlir::ModuleOp module);

class WalkNumbering;

namespace detail {
// The functions numbered by their walk.
struct WalkedFunction {
  using Minter = WalkNumbering;
};
} // namespace detail

// What a check reads of the program's functions, at every stage: the
// functions of the op that holds them, numbered once in their walk, their
// order in its one block, as the analysis of that op, so every check of one
// module walks them once. How many there are is the size of every bit set
// and table a check keeps of them, so no check keeps a map of functions. A
// function's id is its position in the walk, found by the order MLIR keeps
// of the block, which it numbers once and holds in each op until the block
// changes; so no map, keyed by a handle or by a name, holds an id.
class WalkNumbering {
public:
  using Node = Id<detail::WalkedFunction>;

  explicit WalkNumbering(mlir::Operation *holder);

  Count<Node> size() const { return Count<Node>(static_cast<std::uint32_t>(walk.size())); }
  auto functions() const { return size().ids(); }
  // Any function op: before the lowering an idr.func, after it LLVM's.
  mlir::FunctionOpInterface op(Node f) const { return walk[f.index()]; }
  // The position of `fn`, a function the holder holds, in the walk.
  Node id(mlir::FunctionOpInterface fn) const;

private:
  llvm::SmallVector<mlir::FunctionOpInterface> walk;
};

// The walk of the module's program, made once for every check that asks.
const WalkNumbering &walkOf(mlir::ModuleOp module, mlir::AnalysisManager &analyses);

// The ids of `functions`, the functions a request named.
inline llvm::SmallVector<WalkNumbering::Node>
idsOf(const WalkNumbering &numbering, llvm::ArrayRef<mlir::FunctionOpInterface> functions) {
  llvm::SmallVector<WalkNumbering::Node> ids;
  for (mlir::FunctionOpInterface fn : functions)
    ids.push_back(numbering.id(fn));
  return ids;
}

// The functions the body of `fn` names by a symbol use (a call, a closure,
// a constant), each once, by id, in id order.
llvm::SmallVector<WalkNumbering::Node> callees(const WalkNumbering &numbering,
                                               mlir::SymbolTable &symbols, WalkNumbering::Node fn);

// What `edges` gives of a function: the functions it refers to, each by its
// id.
template <class Edges>
concept FunctionEdges =
    std::invocable<Edges &, WalkNumbering::Node> &&
    std::convertible_to<std::invoke_result_t<Edges &, WalkNumbering::Node>,
                        llvm::SmallVector<WalkNumbering::Node>>;

// Every function `roots` reach by `edges`, the roots included, each once,
// by its id, in the order first reached. The set is a test's question of
// one module, asked once per check: a bit per id while it is asked, the
// functions it reaches its answer.
template <FunctionEdges Edges>
llvm::SmallVector<WalkNumbering::Node> reachable(const WalkNumbering &numbering,
                                                 llvm::ArrayRef<WalkNumbering::Node> roots,
                                                 Edges edges) {
  using Node = WalkNumbering::Node;
  BitSet<Node> seen(numbering.size());
  llvm::SmallVector<Node> order;
  auto reach = [&](Node id) {
    if (seen.raise(id) == Changed::Yes)
      order.push_back(id);
  };
  for (Node root : roots)
    reach(root);
  for (std::size_t at = 0; at < order.size(); ++at)
    for (Node next : std::invoke(edges, order[at]))
      reach(next);
  return order;
}

// The cycles among `nodes` by `edges`, an edge to a function outside
// `nodes` dropped: each strongly connected component of two or more, or of
// one that refers to itself, callees first, found by the solver layer's
// components over the graph of the program's functions, whose edges are
// those of `nodes` alone.
template <FunctionEdges Edges>
llvm::SmallVector<llvm::SmallVector<WalkNumbering::Node>>
cycles(const WalkNumbering &numbering, llvm::ArrayRef<WalkNumbering::Node> nodes, Edges edges) {
  using Node = WalkNumbering::Node;
  using Tag = Node::tag;
  BitSet<Node> among(numbering.size());
  llvm::SmallVector<Node> ids;
  for (Node id : nodes)
    if (among.raise(id) == Changed::Yes)
      ids.push_back(id);
  CsrBuilder<Tag> builder(numbering.size());
  for (Node from : ids)
    for (Node to : std::invoke(edges, from))
      if (among.test(to))
        builder.edge(from, to);
  Csr<Tag> graph = std::move(builder).finish();
  Partition<Tag> parts = components(graph);
  llvm::SmallVector<llvm::SmallVector<Node>> out;
  for (auto component : parts.size().ids()) {
    if (!parts.cyclic(component))
      continue;
    llvm::SmallVector<Node> &cycle = out.emplace_back();
    for (Node member : parts.members(component))
      cycle.push_back(member);
  }
  return out;
}

// The symbol `call` names: none for a call through a value.
mlir::SymbolRefAttr calleeOf(mlir::CallOpInterface call);

// Whether `call` calls `g`: its callee's symbol is g, or it calls a
// function of `symbols` made from the code written as g (`names`).
bool callsNamed(mlir::CallOpInterface call, const Symbol &g, mlir::SymbolTable &symbols);

// The identity a binder's location carries, the `#idr.binder<definition,
// index>` Emit fuses into it, however passes nested it in names, call sites
// and fusions; none for a binder a pass made.
std::optional<BinderAttr> identityOf(mlir::Location loc);

// A parameter of a function of the emitted module that Idris proved used
// once, by its identity, and that function's symbol.
struct OnceParameter {
  BinderAttr identity;
  mlir::StringAttr function;
};

// What Idris proved of the binders of the emitted module: the uses of
// each, by its identity, which passes copy with the value as MLIR copies
// locations (a typed identity, never a printed key: no two binders share
// one, so none is dropped); and each parameter used once, with its
// function, which while the program has it keeps a position used once
// (linear-kept), so some binder still carries that identity.
struct ProvedUses {
  llvm::DenseMap<BinderAttr, Uses> uses;
  llvm::SmallVector<OnceParameter> onceParameters;
};

// What Idris proved of every binder of `emitted` that carries an identity:
// the parameters of its functions, lambdas among them, and of its join
// regions, the binders Emit gives one. Fails, at the second binder, when
// Emit gave two binders one identity.
mlir::FailureOr<ProvedUses> provedUses(mlir::ModuleOp emitted);

// Every binder of `module` that carries an identity has the uses `proved`
// holds for it, and every parameter `proved` holds used once of a function
// the program's `symbols` still hold is carried by some binder; each one
// that does not is an error of `property`.
mlir::LogicalResult usesKept(const ProvedUses &proved, mlir::ModuleOp module,
                             mlir::SymbolTable &symbols, llvm::StringRef property);

// The universal properties of the table, each checked of the whole
// program: what the contracts check when a compilation's pipeline ends.
// Fails when one fails, each failure reported at its place.
mlir::LogicalResult universal(mlir::ModuleOp module, mlir::AnalysisManager &analyses);

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECT_H
