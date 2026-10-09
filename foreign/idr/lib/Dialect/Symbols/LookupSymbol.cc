// A symbol by name, from the symbol table a SymbolScope open on the context
// holds when one is, else by scanning the nearest symbol table's body.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

namespace {

// The scopes open on a context are a chain its idr dialect holds. A scope
// opens and closes on the op its pass runs on, outside every nested
// pipeline, so the chain changes in order, on one thread, and never while
// another thread reads it. An exchange that finds another head than the
// one this thread left is a scope opened against that contract, and it
// dies here rather than racing.
std::atomic<SymbolScope *> &chain(Operation *op) {
  // Loading a dialect while a pass manager runs is fatal, so the opener
  // must have it already: idr-inline and idr-rc declare it, and the module
  // verifier that opens one is the idr dialect's own.
  auto *idr = op->getContext()->getLoadedDialect<IdrDialect>();
  if (!idr)
    llvm::reportFatalInternalError("SymbolScope opened on a context without the idr dialect");
  return idr->symbolScopes();
}

} // namespace

SymbolScope::SymbolScope(Operation *op, SymbolTable &table)
    : op(op), table(table), outer(chain(op).load(std::memory_order_relaxed)) {
  SymbolScope *expected = outer;
  if (!chain(op).compare_exchange_strong(expected, this, std::memory_order_release))
    llvm::reportFatalInternalError("SymbolScope opened while another thread opened or closed one");
}

SymbolScope::~SymbolScope() {
  SymbolScope *expected = this;
  if (!chain(op).compare_exchange_strong(expected, outer, std::memory_order_release))
    llvm::reportFatalInternalError("SymbolScope closed out of order");
}

SymbolScope *SymbolScope::of(Operation *op) {
  // A context without the idr dialect has no scope open.
  auto *idr = op->getContext()->getLoadedDialect<IdrDialect>();
  for (SymbolScope *scope = idr ? idr->symbolScopes().load(std::memory_order_acquire) : nullptr;
       scope; scope = scope->outer)
    if (scope->op == op)
      return scope;
  return nullptr;
}

Operation *idr::lookupSymbol(Operation *from, StringAttr name) {
  Operation *table = SymbolTable::getNearestSymbolTable(from);
  if (!table)
    return nullptr;
  if (SymbolScope *scope = SymbolScope::of(table))
    return scope->symbols().lookup(name);
  return SymbolTable::lookupSymbolIn(table, name);
}
