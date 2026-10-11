// A symbol by name, from the symbol table a SymbolScope holds when one is
// open for the table, else by scanning the nearest symbol table's body.
// The scope a pass opened before its nested pipeline is published on the
// context; a scope a worker opens stays on that worker.

#include "idr/Idr.h"

#include "llvm/Support/ThreadPool.h"

using namespace mlir;
using namespace idr;

namespace {

// The scopes this thread has opened, innermost first. Open and close stay
// in order because only this thread moves the head.
SymbolScope *&localHead() {
  static thread_local SymbolScope *top = nullptr;
  return top;
}

// Identifies the publishing thread. A thread id of zero is a real id on
// some hosts, so the token is an address only this thread holds.
void *threadToken() {
  thread_local char token;
  return &token;
}

// The thread running the pass, not a worker of the context's pool. A worker
// that published would destroy the scope when its pass returned, while a
// sibling could still be reading it. With threading off every thread is
// that thread: the pool does not run a pass.
bool callerPublishes(MLIRContext *context) {
  if (!context->isMultithreadingEnabled())
    return true;
  llvm::ThreadPoolInterface &pool = context->getThreadPool();
#if LLVM_ENABLE_THREADS
  return !static_cast<llvm::StdThreadPool &>(pool).isWorkerThread();
#else
  return !static_cast<llvm::SingleThreadExecutor &>(pool).isWorkerThread();
#endif
}

IdrDialect *requireDialect(Operation *op) {
  // Loading a dialect while a pass manager runs is fatal, so the opener
  // must have it already: idr-inline and idr-rc declare it, and the module
  // verifier that opens one is the idr dialect's own.
  auto *idr = op->getContext()->getLoadedDialect<IdrDialect>();
  if (!idr)
    llvm::reportFatalInternalError("SymbolScope opened on a context without the idr dialect");
  return idr;
}

} // namespace

SymbolScope::SymbolScope(Operation *op, SymbolTable &table)
    : op(op), table(table), outer(localHead()) {
  IdrDialect *idr = requireDialect(op);
  localHead() = this;
  // A worker keeps the scope on its own chain. Publishing it would let a
  // sibling load this stack object.
  if (!callerPublishes(op->getContext()))
    return;
  void *me = threadToken();
  std::atomic<void *> &owner = idr->publishedScopeOwner();
  void *cur = owner.load(std::memory_order_acquire);
  if (cur == nullptr) {
    void *expected = nullptr;
    if (!owner.compare_exchange_strong(expected, me, std::memory_order_acq_rel,
                                       std::memory_order_acquire))
      return;
    cur = me;
  }
  // Another publishing thread owns the chain. This scope stays local, so
  // the two chains are not interleaved by which thread opened last.
  if (cur != me)
    return;
  published = true;
  // `outer` already links the previous scope on this thread. Publishing
  // this one is what a worker walks.
  idr->publishedScopes().store(this, std::memory_order_release);
}

SymbolScope::~SymbolScope() {
  SymbolScope *&top = localHead();
  if (top != this)
    llvm::reportFatalInternalError("SymbolScope closed out of order");
  top = outer;
  if (!published)
    return;
  IdrDialect *idr = requireDialect(op);
  std::atomic<SymbolScope *> &head = idr->publishedScopes();
  if (head.load(std::memory_order_relaxed) != this)
    llvm::reportFatalInternalError("SymbolScope closed out of order");
  // Drop the head before releasing ownership. A later publisher that won
  // the owner slot must not link onto a scope this destructor is about to
  // end.
  head.store(outer, std::memory_order_release);
  if (!top)
    idr->publishedScopeOwner().store(nullptr, std::memory_order_release);
}

SymbolScope *SymbolScope::of(Operation *op) {
  for (SymbolScope *scope = localHead(); scope; scope = scope->outer)
    if (scope->op == op)
      return scope;
  // A worker has not opened a scope for `op`. The one the pass published
  // before the pipeline is the table the worker reads.
  auto *idr = op->getContext()->getLoadedDialect<IdrDialect>();
  if (!idr)
    return nullptr;
  for (SymbolScope *scope = idr->publishedScopes().load(std::memory_order_acquire); scope;
       scope = scope->outer)
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
