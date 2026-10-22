// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Frames.cpp - idr-frames --------------------------------------------===//
//
// A recursion on a cycle of calls keeps its depth on a typed frame stack,
// never on the native stack, which then holds only the program's acyclic
// call depth: every call between two functions of one component of the
// call graph that is not in tail position pushes the rest of its code as a
// frame and becomes a tail call. Running an action is the first case (a
// bind whose left action is a bind runs it as a tail call, its nesting on
// the heap as the program built it), and a recursion over data the second
// (`size l + size r` pushes the addition's frame).
//
// The stack is a family the pass declares per component (FramesFamily),
// indexed by the row of results a frame awaits, so a frame awaiting
// another row is never on top where a value of one row is given, and the
// resume of a row has a case for exactly the frames that await it. A frame
// is linear and uncounted: pushed once (data.con), popped once by the
// resume's match (data.match, count.unpack), its held values keeping their
// grades across both, so no quantity is lost at the push or forged at the
// pop. The base frame holds one destination per result of its row, each
// at the result's whole type, so a result comes back from the slots at the
// grade it was written at, its claim and its lifetime with it.
//
// The construction, per component, in two steps: continuations become
// functions (Continuations.cpp), then calls become jumps (Jumps.cpp).
//
// Every function the component runs on its stack takes the component's
// lifetimes, the same kinds in the same order, and passes them on at each
// tail, the resume's among them: so no frame holds a lifetime, a cursor
// comes back to the code after a call as current as the callee left it,
// and every function a tail joins takes as many cursors as the next. The
// construction reads them off its members, which take them alike and pass
// them to one another unchanged.
//
// Every call made is in tail position, so the native stack never grows on
// the cycle, which the native stack's bound checks on the final module. A
// promise: no step is an action a debug counter may skip, and a call this
// construction cannot reach is an internal error.
//
// It runs after counting and idr-trmc, so a reuse token live across a
// framed call is a value its frame holds, and a cell rebuilt in place
// across the cycle is still rebuilt in place; and before idr-tail-loops,
// which makes each run's self tail calls a loop.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail/Frames.h"

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Counting/Bound.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Tail.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

#define GEN_PASS_DEF_IDRFRAMES
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

using namespace frames;
using solver::FunctionId;
using solver::ProgramGraph;
using solver::SccId;

// The bounds `fn` states between its lifetimes, each by the places of the
// two among them.
llvm::SmallVector<Outlives> boundsOf(FuncOp fn) {
  llvm::SmallVector<Outlives> bounds;
  Block &entry = fn.getBody().front();
  if (LivesInAttr lives = fn.getLivesInAttr())
    for (const Outlives &bound : lives.getBounds())
      bounds.push_back({*placeOf(entry.getArgument(bound.longer), fn),
                        *placeOf(entry.getArgument(bound.shorter), fn)});
  return bounds;
}

// The component's lifetimes, its first member's, and the bounds between
// them: every member takes the same kinds in the same order, states the
// same bounds, and passes its own to each member it calls, each at its
// place (a stack's lifetime split around a call standing for the cursor
// below it, which the call is given instead). No frame may hold a
// lifetime, so a component whose members share none would need each member
// made again per arrangement of lifetimes its calls pass: the decide step
// makes those copies or leaves the values counted, so meeting a second
// arrangement is its invariant broken.
LogicalResult shareLifetimes(Component &component, const ProgramGraph &graph, SccId scc) {
  auto kinds = [](FuncOp fn) {
    return llvm::map_to_vector(lifetimesOf(fn), [](BlockArgument arg) { return arg.getType(); });
  };
  FuncOp first = graph.op(*graph.members(scc).begin());
  component.lifetimes = kinds(first);
  component.bounds = boundsOf(first);
  for (FunctionId f : graph.members(scc)) {
    FuncOp fn = graph.op(f);
    if (kinds(fn) != component.lifetimes || boundsOf(fn) != component.bounds)
      return fn.emitOpError(
                 "internal error: an invariant of idr-lifetimes is broken (idr-frames): every "
                 "function on the stack of a component that runs calls on frames takes its "
                 "lifetimes in one arrangement, but this one takes other lifetimes, or bounds "
                 "them otherwise, than ")
             << first.getSymNameAttr();
    WalkResult walked = fn.walk([&](CallOp call) {
      FunctionId callee = graph.id(call.getCalleeAttr());
      if (graph.sccOf(callee) != scc)
        return WalkResult::advance();
      for (auto [place, param] : llvm::enumerate(lifetimesOf(graph.op(callee)))) {
        Value given = lifetimes::extentOf(call.getArgs()[param.getArgNumber()]);
        std::optional<unsigned> at = placeOf(given, fn);
        if (Value base = lifetimes::baseOf(given); !at && base)
          at = placeOf(base, fn);
        if (at != place) {
          call.emitOpError(
              "internal error: an invariant of idr-lifetimes is broken (idr-frames): on a "
              "component that runs calls on frames, a member calls a member only as a copy's "
              "put, given its own lifetimes in their order (a stack opened on one standing for "
              "it), but this call passes others");
          return WalkResult::interrupt();
        }
      }
      return WalkResult::advance();
    });
    if (walked.wasInterrupted())
      return failure();
  }
  return success();
}

struct Frames : impl::IdrFramesBase<Frames> {
  void runOnProgram(ProgramOp program) {
    MLIRContext *ctx = program.getContext();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    ProgramGraph &graph = getAnalysis<ProgramGraph>();
    IRRewriter rewriter(ctx);

    // The components with a call to frame, read before any change.
    footprint::Vector<SccId> framing;
    for (SccId scc : graph.sccCount().ids()) {
      bool any = false;
      for (FunctionId f : graph.members(scc))
        any = any || llvm::any_of(graph.callees(f), [&](const solver::Call &call) {
                return call.kind == TailKind::nontail && graph.sccOf(call.callee) == scc;
              });
      if (any)
        framing.push_back(scc);
    }
    if (framing.empty())
      return markAllAnalysesPreserved();

    // The functions the pass makes and those whose calls change, for the
    // program graph's editor at the end.
    footprint::Vector<FuncOp> made, touched;
    IndexVector<FunctionId, unsigned> memberOf = graph.table<unsigned>(0);
    for (SccId scc : framing) {
      Component component(rewriter, symbols, graph, scc);
      if (failed(shareLifetimes(component, graph, scc)))
        return signalPassFailure();
      Rows rows;
      for (FunctionId f : graph.members(scc)) {
        FuncOp fn = graph.op(f);
        memberOf[f] = static_cast<unsigned>(component.functions.size());
        component.functions.push_back({fn, rowIndex(rows, givenRow(fn))});
      }
      component.members = static_cast<unsigned>(component.functions.size());
      numFunctions += component.members;

      // 1. Continuations become functions, each read in turn.
      for (size_t at = 0; at < component.functions.size(); ++at)
        if (failed(component.restructure(component.functions[at].fn, component.functions[at].row)))
          return signalPassFailure();
      for (CallOp call : component.made)
        call.setTailKind(decide(call));

      // The kinds of frame, and the family. A frame holds what its rest
      // takes after the call's results, but the component's lifetimes, each
      // scoped value at the place of the one it lives in, which every
      // function the rest was made of states among them.
      footprint::Vector<FrameKind> kinds;
      footprint::Vector<Rest> rests;
      // Each by value: a Framed is two op handles, whose accessors are not
      // const.
      for (Framed f : component.framed) {
        auto owner = f.call->getParentOfType<FuncOp>();
        unsigned continues = 0;
        for (const Component::Function &g : component.functions)
          if (g.fn == owner)
            continues = g.row;
        FuncOp callee = symbols.lookup<FuncOp>(f.call.getCalleeAttr().getAttr());
        FrameKind kind{rowIndex(rows, givenRow(callee)), continues, {}, {}};
        for (Value held : f.rest.getArgs()
                              .drop_front(f.call->getNumResults())
                              .drop_back(component.lifetimes.size())) {
          kind.held.push_back(held.getType());
          if (freedBy(held.getType(), Release::Scoped))
            kind.heldIn.push_back(*placeOf(lifetimes::statedLifetime(held), owner));
        }
        kinds.push_back(std::move(kind));
        rests.push_back({symbols.lookup<FuncOp>(f.rest.getCalleeAttr().getAttr()),
                         f.rest.getIndexArgsAttr()});
      }
      numFrames += kinds.size();
      FuncOp first = component.functions.front().fn;
      FramesFamily family =
          declareFrames(ctx, StringAttr::get(ctx, first.getSymName() + ".frames"), rows, kinds);

      // 2. Calls become jumps. Each function of the program's body moves
      // into its run, and the function, keeping its name, its signature and
      // its place in the program graph, becomes the wrapper that starts it.
      footprint::Vector<FuncOp> wrappers, runs;
      for (unsigned m = 0; m < component.members; ++m) {
        FuncOp wrapper = component.functions[m].fn;
        FuncOp run = beside(symbols, wrapper, StringAttr::get(ctx, wrapper.getSymName() + ".run"),
                            wrapper.getFunctionType(), wrapper.getLivesInAttr());
        run.setBindersAttr(wrapper.getBindersAttr());
        run.setArgAttrsAttr(wrapper.getArgAttrsAttr());
        run.setResAttrsAttr(wrapper.getResAttrsAttr());
        run.getBody().takeBody(wrapper.getBody());
        component.functions[m].fn = run;
        wrappers.push_back(wrapper);
      }
      for (const Component::Function &f : component.functions)
        runs.push_back(f.fn);
      // Each resume takes its row's values, the component's lifetimes, each
      // scoped value living in the one its row names, and the stack.
      footprint::Vector<FuncOp> resumes;
      for (unsigned row = 0; row < family.rows; ++row) {
        const Row &given = rows[row];
        llvm::SmallVector<Type> inputs(given.types.begin(), given.types.end());
        llvm::append_range(inputs, component.lifetimes);
        inputs.push_back(family.stacks[row]);
        auto lifetimesAt = static_cast<std::uint32_t>(given.types.size());
        llvm::SmallVector<LivesIn> scoped;
        for (auto [index, type] : llvm::enumerate(given.types))
          if (freedBy(type, Release::Scoped))
            scoped.push_back({static_cast<std::uint32_t>(index),
                              lifetimesAt + given.livesIn[scoped.size()]});
        llvm::SmallVector<Outlives> bounds =
            llvm::map_to_vector(component.bounds, [&](const Outlives &bound) {
              return Outlives{lifetimesAt + bound.longer, lifetimesAt + bound.shorter};
            });
        LivesInAttr lives = scoped.empty() && bounds.empty()
                                ? LivesInAttr()
                                : LivesInAttr::get(ctx, scoped, ArrayRef<LivesIn>(), bounds);
        StringAttr name = StringAttr::get(ctx, first.getSymName() + ".resume");
        resumes.push_back(
            beside(symbols, first, name, FunctionType::get(ctx, inputs, {}), lives));
      }

      Jumps jumps(rewriter, component, family, resumes, runs, memberOf, graph);
      for (const Component::Function &f : component.functions)
        jumps.retype(f.fn, f.row);
      for (const Component::Function &f : component.functions)
        jumps.onStack(f.fn, f.row);
      if (failed(jumps.frameCalls(kinds)))
        return signalPassFailure();
      for (unsigned row = 0; row < family.rows; ++row)
        fillResume(rewriter, resumes[row], row, rows[row], family, kinds, rests);
      for (unsigned m = 0; m < component.members; ++m)
        fillWrapper(rewriter, wrappers[m], runs[m], component.functions[m].row, family);

      llvm::append_range(made, runs);
      llvm::append_range(made, resumes);
      llvm::append_range(touched, runs);
      llvm::append_range(touched, resumes);
      llvm::append_range(touched, wrappers);
    }

    // The program graph learns the functions made and the calls changed;
    // then every row is made equal to its derivation again.
    {
      solver::Editor editor = graph.thaw();
      for (FuncOp fn : made)
        (void)editor.insert(fn);
      for (FuncOp fn : touched)
        editor.setCallees(editor.id(FlatSymbolRefAttr::get(fn.getSymNameAttr())),
                          solver::rowOf(fn, editor));
      std::move(editor).freeze();
    }
    solver::Work work;
    rows::write(program, graph, work);
    numWork += work.steps();

    // What each function made or changed holds that it no longer needs, on
    // the rows just made exact, which say where memory may be acquired: a
    // run or a continuation holds the reuse tokens its code held, a resume
    // each one a frame gives back until its rest takes it, and a wrapper
    // none of the body it gave up; each kept or copied the bound of the
    // code it came from, so each is measured as it now stands.
    const Layouts &layouts = getAnalysis<Layouts>();
    for (FuncOp fn : touched)
      fn.setFrameBound(counting::frameBound(fn, layouts));
    markAnalysesPreserved<SymbolTable, ProgramGraph>();
  }
};

} // namespace
} // namespace idr::tail
