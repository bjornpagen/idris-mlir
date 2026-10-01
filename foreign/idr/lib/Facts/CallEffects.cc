// The effects of a func.call, through MLIR's own interface: what the
// callee's facts say (`idr.effects`, `idr.total`, Functions/Of.cc) and what
// the closures the call is given may do (Closures/Passed.cc). Every pass,
// upstream or ours, then asks a call what it does the way it asks any op:
// canonicalize erases an unused call that only computes, CSE merges two
// calls of a pure function on the same arguments, LICM hoists one out of
// a loop, and nothing re-derives any of it.
//
// IO is a read and a write of the IO resource, as the idr.io ops declare
// it; a possible crash writes the crash resource and a function that may
// not return the divergence resource, each with a write of the IO resource
// too, as idr.crash and idr.may_loop declare theirs, so that neither
// moves, merges, goes, or is reordered with output. A result that is not a
// scalar is a fresh value the call allocates on the lin resource (no heap,
// a value no pass may merge with another, as idr.lin.enter declares its
// own), which keeps CSE from merging two calls that make cells and still
// lets an unused one go. A callee the module lacks may do anything.

#include "idr/Idr.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"

import idr.facts;

using namespace mlir;

namespace {

struct CallEffects : MemoryEffectOpInterface::ExternalModel<CallEffects, func::CallOp> {
  void getEffects(Operation *op,
                  SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) const {
    auto call = cast<func::CallOp>(op);
    idr::facts::Effects what = idr::facts::of(
        SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr()));
    for (Value operand : call.getOperands())
      what |= idr::facts::passed(call, operand);
    if (what.io) {
      effects.emplace_back(MemoryEffects::Read::get(), idr::IOResource::get());
      effects.emplace_back(MemoryEffects::Write::get(), idr::IOResource::get());
    }
    if (what.crash)
      effects.emplace_back(MemoryEffects::Write::get(), idr::CrashResource::get());
    if (what.partial)
      effects.emplace_back(MemoryEffects::Write::get(), idr::DivergenceResource::get());
    if ((what.crash || what.partial) && !what.io)
      effects.emplace_back(MemoryEffects::Write::get(), idr::IOResource::get());
    for (OpResult result : call.getResults()) {
      Type type = idr::unrestricted(result.getType());
      if (!type.isIntOrIndexOrFloat() && !idr::isWorld(type) && !idr::isErased(type))
        effects.emplace_back(MemoryEffects::Allocate::get(), result, idr::LinResource::get());
    }
  }
};

} // namespace

void idr::registerCallEffects(DialectRegistry &registry) {
  registry.addExtension(+[](MLIRContext *ctx, func::FuncDialect *) {
    func::CallOp::attachInterface<CallEffects>(*ctx);
  });
}
