// A symbol by name, from the symbol table a SymbolScope holds when one is
// open, else by scanning the nearest symbol table's body.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

namespace {

// The innermost scope open on this thread; each holds the one it shadows.
thread_local SymbolScope *innermost = nullptr;

} // namespace

SymbolScope::SymbolScope(Operation *op, SymbolTable &table)
    : op(op), table(table), outer(innermost) {
  innermost = this;
}

SymbolScope::~SymbolScope() { innermost = outer; }

SymbolScope *SymbolScope::of(Operation *op) {
  for (SymbolScope *scope = innermost; scope; scope = scope->outer)
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
