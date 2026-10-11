// A symbol by name, from the symbol table a SymbolScope open on this thread
// holds when one is, else by scanning the nearest symbol table's body.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

namespace {

// The scopes this thread has open, innermost first. A scope opened on the
// calling thread before a nested pipeline runs is not on a worker's chain,
// and a scope a worker opens is not on this one. Open and close stay in
// order because only this thread moves the head.
SymbolScope *&head() {
  static thread_local SymbolScope *top = nullptr;
  return top;
}

SymbolScope *&chain(Operation *op) {
  // Loading a dialect while a pass manager runs is fatal, so the opener
  // must have it already: idr-inline and idr-rc declare it, and the module
  // verifier that opens one is the idr dialect's own.
  if (!op->getContext()->getLoadedDialect<IdrDialect>())
    llvm::reportFatalInternalError("SymbolScope opened on a context without the idr dialect");
  return head();
}

} // namespace

SymbolScope::SymbolScope(Operation *op, SymbolTable &table)
    : op(op), table(table), outer(chain(op)) {
  chain(op) = this;
}

SymbolScope::~SymbolScope() {
  SymbolScope *&top = chain(op);
  if (top != this)
    llvm::reportFatalInternalError("SymbolScope closed out of order");
  top = outer;
}

SymbolScope *SymbolScope::of(Operation *op) {
  // A context without the idr dialect has no scope open. A scope another
  // thread opened is not on this chain.
  if (!op->getContext()->getLoadedDialect<IdrDialect>())
    return nullptr;
  for (SymbolScope *scope = head(); scope; scope = scope->outer)
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
