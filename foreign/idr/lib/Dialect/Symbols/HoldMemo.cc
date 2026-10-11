// Whether a type may hold a world or a closure, remembered while a pass
// that does not change a data declaration is running. mayHoldWorld and
// mayHoldClosure answer from the memo the pass published, and each thread
// keeps the answers it walked.

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/Support/ThreadPool.h"

using namespace mlir;
using namespace idr;

namespace {

HoldMemo *&localHead() {
  static thread_local HoldMemo *top = nullptr;
  return top;
}

void *threadToken() {
  thread_local char token;
  return &token;
}

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

IdrDialect *requireDialect(MLIRContext *context) {
  // Loading a dialect while a pass manager runs is fatal, so the opener
  // must have it already.
  auto *idr = context->getLoadedDialect<IdrDialect>();
  if (!idr)
    llvm::reportFatalInternalError("HoldMemo opened on a context without the idr dialect");
  return idr;
}

// The answers this thread walked for one memo. The map is not the memo's:
// a worker filling it would race a walk on another thread. The epoch is
// never reused, including from another context, because this map is keyed
// by it and outlives the memo. The counter hands out epochs and holds no
// answer.
struct Answers {
  uint64_t epoch = 0;
  DenseMap<Type, bool> world;
  DenseMap<Type, bool> closure;
};

Answers &answersFor(uint64_t epoch) {
  static thread_local Answers local;
  if (local.epoch != epoch) {
    local.world.clear();
    local.closure.clear();
    local.epoch = epoch;
  }
  return local;
}

uint64_t freshEpoch() {
  static std::atomic<uint64_t> next{1};
  return next.fetch_add(1, std::memory_order_relaxed);
}

std::optional<bool> find(const DenseMap<Type, bool> &map, Type type) {
  auto it = map.find(type);
  if (it == map.end())
    return std::nullopt;
  return it->second;
}

} // namespace

HoldMemo::HoldMemo(MLIRContext *context)
    : context(context), outer(localHead()), epoch(freshEpoch()) {
  IdrDialect *idr = requireDialect(context);
  localHead() = this;
  if (!callerPublishes(context))
    return;
  void *me = threadToken();
  std::atomic<void *> &owner = idr->publishedMemoOwner();
  void *cur = owner.load(std::memory_order_acquire);
  if (cur == nullptr) {
    void *expected = nullptr;
    if (!owner.compare_exchange_strong(expected, me, std::memory_order_acq_rel,
                                       std::memory_order_acquire))
      return;
    cur = me;
  }
  if (cur != me)
    return;
  published = true;
  idr->publishedMemos().store(this, std::memory_order_release);
}

HoldMemo::~HoldMemo() {
  HoldMemo *&top = localHead();
  if (top != this)
    llvm::reportFatalInternalError("HoldMemo closed out of order");
  top = outer;
  if (!published)
    return;
  IdrDialect *idr = requireDialect(context);
  std::atomic<HoldMemo *> &head = idr->publishedMemos();
  if (head.load(std::memory_order_relaxed) != this)
    llvm::reportFatalInternalError("HoldMemo closed out of order");
  head.store(outer, std::memory_order_release);
  if (!top)
    idr->publishedMemoOwner().store(nullptr, std::memory_order_release);
}

HoldMemo *HoldMemo::of(MLIRContext *context) {
  for (HoldMemo *memo = localHead(); memo; memo = memo->outer)
    if (memo->context == context)
      return memo;
  auto *idr = context->getLoadedDialect<IdrDialect>();
  if (!idr)
    return nullptr;
  for (HoldMemo *memo = idr->publishedMemos().load(std::memory_order_acquire); memo;
       memo = memo->outer)
    if (memo->context == context)
      return memo;
  return nullptr;
}

std::optional<bool> HoldMemo::world(Type type) const {
  return find(answersFor(epoch).world, type);
}

std::optional<bool> HoldMemo::closure(Type type) const {
  return find(answersFor(epoch).closure, type);
}

void HoldMemo::rememberWorld(Type type, bool answer) {
  answersFor(epoch).world.try_emplace(type, answer);
}

void HoldMemo::rememberClosure(Type type, bool answer) {
  answersFor(epoch).closure.try_emplace(type, answer);
}
