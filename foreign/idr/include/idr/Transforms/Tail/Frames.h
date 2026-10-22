// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of idr-frames share (lib/Transforms/Tail): one component's
// state while its code moves into functions of their own (Continuations,
// with a join point's regions in Dissolve and a lifetime's region in
// Split), the calls made jumps on the stack, the resumes and the wrappers
// (Jumps), and the pass that runs both steps per component (Frames).
#ifndef IDR_TRANSFORMS_TAIL_FRAMES_H
#define IDR_TRANSFORMS_TAIL_FRAMES_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Transforms/Tail.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr::tail::frames {

//===----------------------------------------------------------------------===//
// The component's lifetimes
//===----------------------------------------------------------------------===//

// The lifetimes `fn` takes, in order: for every function of a component,
// the component's lifetimes, which it passes on at each of its tails.
llvm::SmallVector<mlir::BlockArgument> lifetimesOf(FuncOp fn);

// The place among `fn`'s lifetimes of the one `lifetime` has the extent
// of: one of them, or a view of one; none for any other lifetime, which
// ends with `fn`'s call.
std::optional<unsigned> placeOf(mlir::Value lifetime, FuncOp fn);

// The row `fn` gives: its result types, and where each scoped one lives.
Row givenRow(FuncOp fn);

// The lifetime that operand `index` of `terminator` lives in where it goes:
// a return's, where its function's signature says that result lives; a
// yield's, the lifetime its op states for the result it becomes. Null for
// a value that is not scoped.
mlir::Value givenIn(mlir::Operation *terminator, unsigned index);

// `op` made again giving `results`: its scoped results live in
// `resultOuters`, one each in order, and what its regions bind where `op`
// stated it. The caller replaces `op` by it.
mlir::Operation *remakeGiving(mlir::RewriterBase &rewriter, mlir::Operation *op,
                              mlir::TypeRange results, mlir::ValueRange resultOuters);

//===----------------------------------------------------------------------===//
// Moving code into a function
//===----------------------------------------------------------------------===//

// `a`'s terms then `b`'s: a jump's terms for its join region's own binders
// after the levels of the scope the region's function is made in.
IndexArgsAttr concatArgs(mlir::MLIRContext *ctx, IndexArgsAttr a, IndexArgsAttr b);

// The index binders in scope at `region`: each op around it that binds
// index variables, outermost first. A function made of code there binds
// them all, in order, so every type of the code names its own levels.
llvm::SmallVector<families::Sort> scopeSorts(mlir::Region *region);

// What the ops of `first`'s block from `first` on read that they do not
// make, in the order first read: what a function made of them takes.
llvm::SetVector<mlir::Value> liveIns(mlir::Operation *first);

// `values` without the lifetimes among them, which a function made of code
// reading them takes as the component's own.
llvm::SmallVector<mlir::Value> withoutLifetimes(llvm::ArrayRef<mlir::Value> values);

// A function the pass made, and what a call of it from the function its
// code came from passes: the values it takes, then that function's
// lifetimes.
struct Made {
  FuncOp fn;
  llvm::SmallVector<mlir::Value> args;
};

// A call to frame and the tail call of its rest that follows it.
struct Framed {
  CallOp call;
  CallOp rest;
};

// The component's state while the pass rebuilds it: its functions, the
// program's first, each with the row it gives; the calls the pass made of
// functions it made; and each call to frame with the tail call of its
// rest. Each sized by the component, which may be the whole program.
class Component {
public:
  Component(mlir::RewriterBase &rewriter, mlir::SymbolTable &symbols,
            const solver::ProgramGraph &graph, solver::SccId scc)
      : rewriter(rewriter), symbols(symbols), graph(graph), scc(scc) {}

  // Whether `call` runs a function of the program's in this component:
  // the graph names every function the program had, and the pass's own
  // calls, which name the functions it made, are asked first.
  bool isMade(CallOp call) const { return llvm::is_contained(made, call); }
  bool isMember(CallOp call) const {
    return !isMade(call) && graph.sccOf(graph.id(call.getCalleeAttr())) == scc;
  }
  // A call to frame: of a function of the component, and no tail call.
  bool frames(CallOp call) const {
    return call.getTailKind() == TailKind::nontail && isMember(call);
  }

  // Step 1 on `fn`: every call to frame ends its block in a tail of its
  // function, its rest a function of its own.
  mlir::LogicalResult restructure(FuncOp fn, unsigned row);

  // A function of the component, with its row.
  struct Function {
    FuncOp fn;
    unsigned row;
  };
  footprint::Vector<Function> functions;
  footprint::Vector<CallOp> made;
  footprint::Vector<Framed> framed;
  // How many of `functions`, the first, are the program's.
  unsigned members = 0;

  // The lifetimes every function of the component takes, in order, and the
  // bounds between them, each by the places of the two.
  llvm::SmallVector<mlir::Type> lifetimes;
  llvm::SmallVector<Outlives> bounds;

private:
  mlir::FailureOr<Made> makeFunction(FuncOp owner, llvm::StringRef kind,
                                     llvm::ArrayRef<mlir::Value> takes, mlir::TypeRange results,
                                     llvm::ArrayRef<mlir::Value> resultsIn,
                                     llvm::ArrayRef<families::Sort> binders);
  mlir::LogicalResult adoptLifetimes(FuncOp owner, FuncOp fn, llvm::ArrayRef<mlir::Value> reads);
  mlir::FailureOr<CallOp> outline(FuncOp owner, unsigned row, mlir::Operation *first,
                                  mlir::ValueRange params, llvm::StringRef kind);
  void sinkInto(mlir::Operation *rejoin, CallOp call);
  void normalize(mlir::Block *root);
  mlir::LogicalResult dissolve(FuncOp owner, unsigned row, mlir::Operation *join);
  mlir::LogicalResult split(FuncOp owner, unsigned row, CallOp site, mlir::Operation *opener);

  mlir::RewriterBase &rewriter;
  mlir::SymbolTable &symbols;
  const solver::ProgramGraph &graph;
  solver::SccId scc;
};

//===----------------------------------------------------------------------===//
// Calls into jumps
//===----------------------------------------------------------------------===//

// The rows of a component, each found or added.
using Rows = footprint::Vector<Row>;
unsigned rowIndex(Rows &rows, const Row &row);

// What a kind's case runs: the continuation the frame's rest was, at the
// terms its call passed.
struct Rest {
  FuncOp fn;
  IndexArgsAttr terms;
};

// Every function of the component on the stack: it takes the stack
// awaiting its row and returns nothing; each tail gives its value and the
// component's lifetimes to its row's resume, or passes the stack on to the
// function it runs.
class Jumps {
public:
  Jumps(mlir::RewriterBase &rewriter, Component &component, const FramesFamily &family,
        llvm::ArrayRef<FuncOp> resumes, llvm::ArrayRef<FuncOp> runs,
        const IndexVector<solver::FunctionId, unsigned> &memberOf,
        const solver::ProgramGraph &graph)
      : rewriter(rewriter), component(component), family(family), resumes(resumes), runs(runs),
        memberOf(memberOf), graph(graph) {}

  // `fn` takes the stack awaiting its row, last, and returns nothing.
  // Every function of the component is retyped before any call of one is
  // made, so each call reads its callee's final signature.
  void retype(FuncOp fn, unsigned row);
  // `fn`'s tails, `fn` retyped: each gives its value to the resume or
  // passes the stack on.
  void onStack(FuncOp fn, unsigned row);
  mlir::LogicalResult frameCalls(llvm::ArrayRef<FrameKind> kinds);

private:
  // The function a tail call of a function of the component goes to on
  // the stack: a function the pass made, as it is; the program's, its run.
  FuncOp target(CallOp call) const;
  // `call` made again with the stack after its arguments, giving nothing.
  void passStack(CallOp call, mlir::Value stack);

  mlir::RewriterBase &rewriter;
  Component &component;
  const FramesFamily &family;
  llvm::ArrayRef<FuncOp> resumes;
  llvm::ArrayRef<FuncOp> runs;
  const IndexVector<solver::FunctionId, unsigned> &memberOf;
  const solver::ProgramGraph &graph;
};

// The resume of row `row`, `given`: the row's values, the component's
// lifetimes and the stack awaiting the values.
void fillResume(mlir::RewriterBase &rewriter, FuncOp resume, unsigned row, const Row &given,
                const FramesFamily &family, llvm::ArrayRef<FrameKind> kinds,
                llvm::ArrayRef<Rest> rests);

// The function of the program as it is called from outside the
// component: its slots, the run started on them, their results returned.
void fillWrapper(mlir::RewriterBase &rewriter, FuncOp wrapper, FuncOp run, unsigned row,
                 const FramesFamily &family);

// A function beside `like` with its facts, named `name`, of type `type`,
// binding no index variable, its scoped parameters living where `lives`
// says; an empty entry block taking its parameters.
FuncOp beside(mlir::SymbolTable &symbols, FuncOp like, mlir::StringAttr name,
              mlir::FunctionType type, LivesInAttr lives);

} // namespace idr::tail::frames

#endif // IDR_TRANSFORMS_TAIL_FRAMES_H
