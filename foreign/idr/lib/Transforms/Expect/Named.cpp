// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions a property names. A test names the function the
// programmer wrote, by its symbol or by its Idris definition, and a
// property stated of it holds of every copy the passes made of it: a
// specialization, a copy made for a pass's own purpose, the one function
// deduplication kept of several. What a function is made from is in its
// location, which every pass keeps with what it copies: Emit names each
// function's location after its Idris definition, a copy is a clone of its
// original with the original's location, and deduplication fuses the
// locations of the functions it merges into the one it keeps. No fact a
// pass decides, and no name a pass makes, is read.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Location.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <cstdint>

#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;

namespace idr::expect {

Operation *programOf(ModuleOp module) {
  for (ProgramOp program : module.getOps<ProgramOp>())
    return program;
  return module;
}

SmallVector<FunctionOpInterface> functionsOf(ModuleOp module) {
  return llvm::to_vector(programOf(module)->getRegion(0).getOps<FunctionOpInterface>());
}

// The table is the analysis of the program's own op, so it lives as long as
// the pass's analyses and is built by whichever property asks first.
SymbolTable &symbolsOf(ModuleOp module, AnalysisManager &analyses) {
  Operation *program = programOf(module);
  if (program == module.getOperation())
    return analyses.getAnalysis<SymbolTable>();
  return analyses.nest(program).getAnalysis<SymbolTable>();
}

// The stage table says what a program's functions may hold, so whether the
// program graph indexes them is read off it, never off the functions.
ProgramOp firstOrderProgram(ModuleOp module) {
  auto program = dyn_cast<ProgramOp>(programOf(module));
  if (!program || closuresAt[program.getStage()] != StageClosures::FirstOrder ||
      functionsAt[program.getStage()] != StageFunctions::Ours)
    return ProgramOp();
  return program;
}

WalkNumbering::WalkNumbering(Operation *holder)
    : walk(llvm::to_vector(holder->getRegion(0).getOps<FunctionOpInterface>())) {}

// The walk is in the block's order, so the functions before `fn` are the
// ones MLIR orders before it, and their count is its position.
WalkNumbering::Node WalkNumbering::id(FunctionOpInterface fn) const {
  Operation *target = fn.getOperation();
  auto at = llvm::partition_point(
      walk, [&](FunctionOpInterface before) { return before->isBeforeInBlock(target); });
  assert(at != walk.end() && static_cast<Operation *>(*at) == target &&
         "a function the holder holds is in its walk");
  return Node(static_cast<std::uint32_t>(at - walk.begin()));
}

// The walk is the analysis of the program's own op, as the table is.
const WalkNumbering &walkOf(ModuleOp module, AnalysisManager &analyses) {
  Operation *holder = programOf(module);
  if (holder == module.getOperation())
    return analyses.getAnalysis<WalkNumbering>();
  return analyses.nest(holder).getAnalysis<WalkNumbering>();
}

namespace {

// A location names `f` where a NameLoc called `f` is reached through the
// names and the fusions that wrap it: Emit's library wrapper is a fusion,
// and so is what deduplication made. A call site is no part of a
// function's own location, so the walk passes over everything but a name
// and a fusion. Locations nest as deep as passes wrapped them, so the walk
// is upstream's, which keeps its place on a stack of its own, never the
// native one.
bool locationNames(Location loc, StringRef f) {
  return loc->walk([&](Location part) {
              if (auto named = dyn_cast<NameLoc>(part))
                return named.getName().getValue() == f ? WalkResult::interrupt()
                                                        : WalkResult::advance();
              return isa<FusedLoc>(part) ? WalkResult::advance() : WalkResult::skip();
            })
      .wasInterrupted();
}

} // namespace

bool names(FunctionOpInterface fn, StringRef f) {
  return SymbolTable::getSymbolName(fn).getValue() == f || locationNames(fn->getLoc(), f);
}

// A callee the module holds is asked whether it is made from `g`, so a
// call of a copy of g is a call of g; a callee it does not hold (a
// runtime function after lowering is declared, so it is held) is its
// symbol alone.
SymbolRefAttr calleeOf(CallOpInterface call) {
  return dyn_cast<SymbolRefAttr>(call.getCallableForCallee());
}

bool callsNamed(CallOpInterface call, const Symbol &g, SymbolTable &symbols) {
  SymbolRefAttr callee = calleeOf(call);
  if (!callee)
    return false;
  StringAttr root = callee.getRootReference();
  if (root.getValue() == g.name)
    return true;
  auto fn = symbols.lookup<FunctionOpInterface>(root);
  return fn && names(fn, g.name);
}

} // namespace idr::expect
