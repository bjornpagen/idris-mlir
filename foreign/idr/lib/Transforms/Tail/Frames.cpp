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
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Tail.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

namespace idr {
#define GEN_PASS_DEF_IDRFRAMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

using namespace frames;
using solver::FunctionId;
using solver::ProgramGraph;
using solver::SccId;

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
      Rows rows;
      for (FunctionId f : graph.members(scc)) {
        FuncOp fn = graph.op(f);
        memberOf[f] = static_cast<unsigned>(component.functions.size());
        component.functions.push_back({fn, rowIndex(rows, fn.getResultTypes())});
      }
      component.members = static_cast<unsigned>(component.functions.size());
      numFunctions += component.members;

      // 1. Continuations become functions, each read in turn.
      for (size_t at = 0; at < component.functions.size(); ++at)
        if (failed(component.restructure(component.functions[at].fn, component.functions[at].row)))
          return signalPassFailure();
      for (CallOp call : component.made)
        call.setTailKind(decide(call));

      // The kinds of frame, and the family.
      footprint::Vector<FrameKind> kinds;
      footprint::Vector<Rest> rests;
      for (const Framed &f : component.framed) {
        auto owner = f.call->getParentOfType<FuncOp>();
        unsigned continues = 0;
        for (const Component::Function &g : component.functions)
          if (g.fn == owner)
            continues = g.row;
        FuncOp callee = symbols.lookup<FuncOp>(f.call.getCalleeAttr().getAttr());
        FrameKind kind{rowIndex(rows, callee.getResultTypes()), continues, {}};
        for (Value held : f.rest.getArgs().drop_front(f.call->getNumResults()))
          kind.held.push_back(held.getType());
        kinds.push_back(std::move(kind));
        rests.push_back({symbols.lookup<FuncOp>(f.rest.getCalleeAttr().getAttr()),
                         f.rest.getIndexArgsAttr()});
      }
      numFrames += kinds.size();
      FuncOp first = component.functions.front().fn;
      FramesFamily family = declareFrames(
          ctx, StringAttr::get(ctx, first.getSymName() + ".frames"), first.getLoc(), rows, kinds);

      // 2. Calls become jumps. Each function of the program's body moves
      // into its run, and the function, keeping its name, its signature and
      // its place in the program graph, becomes the wrapper that starts it.
      footprint::Vector<FuncOp> wrappers, runs;
      for (unsigned m = 0; m < component.members; ++m) {
        FuncOp wrapper = component.functions[m].fn;
        FuncOp run = beside(symbols, wrapper, StringAttr::get(ctx, wrapper.getSymName() + ".run"),
                            wrapper.getFunctionType());
        run.setBindersAttr(wrapper.getBindersAttr());
        run.setArgAttrsAttr(wrapper.getArgAttrsAttr());
        run.setResAttrsAttr(wrapper.getResAttrsAttr());
        run.setLivesInAttr(wrapper.getLivesInAttr());
        run.getBody().takeBody(wrapper.getBody());
        component.functions[m].fn = run;
        wrappers.push_back(wrapper);
      }
      for (const Component::Function &f : component.functions)
        runs.push_back(f.fn);
      footprint::Vector<FuncOp> resumes;
      for (unsigned row = 0; row < family.rows; ++row) {
        llvm::SmallVector<Type> inputs(rows[row]);
        inputs.push_back(family.stacks[row]);
        StringAttr name = StringAttr::get(ctx, first.getSymName() + ".resume");
        resumes.push_back(beside(symbols, first, name, FunctionType::get(ctx, inputs, {})));
      }

      Jumps jumps(rewriter, component, family, resumes, runs, memberOf, graph);
      for (const Component::Function &f : component.functions)
        jumps.retype(f.fn, f.row);
      for (const Component::Function &f : component.functions)
        jumps.onStack(f.fn, f.row);
      if (failed(jumps.frameCalls(kinds)))
        return signalPassFailure();
      for (unsigned row = 0; row < family.rows; ++row)
        fillResume(rewriter, resumes[row], row, family, kinds, rests);
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
    markAnalysesPreserved<SymbolTable, ProgramGraph>();
  }
};

} // namespace
} // namespace idr::tail
