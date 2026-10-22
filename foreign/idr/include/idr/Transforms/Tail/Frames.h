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

namespace idr::tail::frames {

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

private:
  FuncOp makeFunction(FuncOp owner, llvm::StringRef kind, mlir::FunctionType type,
                      llvm::ArrayRef<families::Sort> binders);
  CallOp outline(FuncOp owner, unsigned row, mlir::Operation *first, mlir::ValueRange params,
                 llvm::StringRef kind);
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

// The rows of a component: its functions' distinct result types, each
// found or added.
using Rows = footprint::Vector<llvm::SmallVector<mlir::Type, 1>>;
unsigned rowIndex(Rows &rows, mlir::TypeRange results);

// What a kind's case runs: the continuation the frame's rest was, at the
// terms its call passed.
struct Rest {
  FuncOp fn;
  IndexArgsAttr terms;
};

// Every function of the component on the stack: it takes the stack
// awaiting its row and returns nothing; each tail gives its value to its
// row's resume, or passes the stack on to the function it runs.
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

// The resume of row `row`: the row's values and the stack awaiting them.
void fillResume(mlir::RewriterBase &rewriter, FuncOp resume, unsigned row,
                const FramesFamily &family, llvm::ArrayRef<FrameKind> kinds,
                llvm::ArrayRef<Rest> rests);

// The function of the program as it is called from outside the
// component: its slots, the run started on them, their results returned.
void fillWrapper(mlir::RewriterBase &rewriter, FuncOp wrapper, FuncOp run, unsigned row,
                 const FramesFamily &family);

// A function beside `like` with its facts, named `name`, of type `type`,
// binding no index variable; an empty entry block taking its parameters.
FuncOp beside(mlir::SymbolTable &symbols, FuncOp like, mlir::StringAttr name,
              mlir::FunctionType type);

} // namespace idr::tail::frames

#endif // IDR_TRANSFORMS_TAIL_FRAMES_H
