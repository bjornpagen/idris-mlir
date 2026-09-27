// The memory gate's runtime prototype, over snmalloc (docs/plan.md 4.3,
// 4.4, 5.6, 7.4). runtime.h has the ABI and the cell layout;
// bench/gate/README.md has the build and the experiments.
//
// Restricted C++ as the real runtime will be (plan 5.4): no exceptions, no
// RTTI, no standard containers; threads are pthreads.
//
// Build-time switches:
//   IDR_GATE_STATS  count cells, frees, atomic count operations, moved and
//                   marked cells, and print them to stderr at exit
//   IDR_GATE_FLUSH  idr_turn_end flushes the allocator's remote frees
//   IDR_GATE_HOME   idr_drop_foreign sends dead roots home
#include "runtime.h"

#include <snmalloc/snmalloc.h>

#include <atomic>
#include <limits.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

namespace {

// ---- statistics ------------------------------------------------------------

#ifdef IDR_GATE_STATS
struct Stats {
  uint64_t cells;    // cells allocated
  uint64_t frees;    // cells freed
  uint64_t atomics;  // atomic read-modify-writes on counts
  uint64_t marked;   // cells marked shared
  uint64_t moved;    // cells moved to another core
  uint64_t sends;    // values sent to another core
  uint64_t sched;    // atomic read-modify-writes of the scheduler (not on data)
};
thread_local Stats tls;
std::atomic<uint64_t> totals[7];

void publish() {
  const uint64_t *v = &tls.cells;
  for (int i = 0; i < 7; i++) totals[i].fetch_add(v[i], std::memory_order_relaxed);
  tls = Stats{};
}

void report() {
  uint64_t t[7];
  for (int i = 0; i < 7; i++) t[i] = totals[i].load();
  fprintf(stderr,
          "idr-stats: cells=%llu frees=%llu live=%lld atomic-rc=%llu marked=%llu "
          "moved=%llu sends=%llu sched-rmw=%llu\n",
          (unsigned long long)t[0], (unsigned long long)t[1], (long long)(t[0] - t[1]),
          (unsigned long long)t[2], (unsigned long long)t[3], (unsigned long long)t[4],
          (unsigned long long)t[5], (unsigned long long)t[6]);
}
#define STAT(field, n) (tls.field += (n))
#else
void publish() {}
void report() {}
#define STAT(field, n) ((void)0)
#endif

// ---- cells -----------------------------------------------------------------

// With IDR_GATE_FLUSH, whether this thread has used its allocator since the
// last flush: snmalloc's thread allocator must not be flushed before its
// first use.
#ifdef IDR_GATE_FLUSH
thread_local bool dirty = false;
#define DIRTY() (dirty = true)
#else
#define DIRTY() ((void)0)
#endif

inline bool is_cell(const void *v) { return v != nullptr && ((uintptr_t)v & 1) == 0; }

inline void **fields(IdrCell *c) { return reinterpret_cast<void **>(c + 1); }

template <size_t S> inline void *alloc_cell() {
  STAT(cells, 1);
  DIRTY();
  return snmalloc::alloc<S>();
}

template <size_t S> inline void free_sized(void *p) {
  STAT(frees, 1);
  DIRTY();
  snmalloc::dealloc<S>(p);
}

inline void free_words(IdrCell *c, unsigned nwords) {
  switch (nwords) {
  case 2: free_sized<16>(c); break;
  case 3: free_sized<24>(c); break;
  case 4: free_sized<32>(c); break;
  case 5: free_sized<40>(c); break;
  case 6: free_sized<48>(c); break;
  case 7: free_sized<56>(c); break;
  case 8: free_sized<64>(c); break;
  default: STAT(frees, 1); DIRTY(); snmalloc::dealloc(c); break;
  }
}

// The free list runs through the headers: bytes 0-5 of a dying cell hold
// the next one (user addresses fit in 48 bits on x86-64 and arm64 Linux).
constexpr uint64_t kLink = (uint64_t(1) << 48) - 1;

inline void push(IdrCell *&todo, IdrCell *c) {
  uint64_t h;
  memcpy(&h, c, 8);
  h = (h & ~kLink) | (uint64_t)(uintptr_t)todo;
  memcpy(c, &h, 8);
  todo = c;
}

inline IdrCell *next(IdrCell *c) {
  uint64_t h;
  memcpy(&h, c, 8);
  return reinterpret_cast<IdrCell *>((uintptr_t)(h & kLink));
}

// Drops one reference to a field of a dying cell; a field that dies too
// joins the free list.
inline void release(void *v, IdrCell *&todo) {
  if (!is_cell(v)) return;
  IdrCell *c = static_cast<IdrCell *>(v);
  int32_t rc = c->rc;
  if (rc > 1) {
    if (rc != INT_MAX) c->rc = rc - 1;
  } else if (rc == 1) {
    push(todo, c);
  } else if (rc < 0) {
    STAT(atomics, 1);
    if (__atomic_fetch_add(&c->rc, 1, __ATOMIC_ACQ_REL) == -1) push(todo, c);
  }
}

// A growable stack of cells, for the move-or-mark walk.
struct Stack {
  IdrCell **items = nullptr;
  size_t size = 0, cap = 0;
  void push(IdrCell *c) {
    if (size == cap) {
      cap = cap ? 2 * cap : 1024;
      items = static_cast<IdrCell **>(realloc(items, cap * sizeof *items));
      if (!items) abort();
    }
    items[size++] = c;
  }
  IdrCell *pop() { return items[--size]; }
};
thread_local Stack walk;

// Marks c and everything it reaches shared: count n becomes -n. The cells
// still belong to this core, so plain stores suffice (Lean's markMT). Uses
// the walk stack above what the caller has on it.
void mark(IdrCell *c) {
  size_t base = walk.size;
  walk.push(c);
  while (walk.size > base) {
    IdrCell *x = walk.pop();
    int32_t rc = x->rc;
    if (rc <= 0) continue;  // shared or persistent already, and so is all below
    x->rc = -rc;
    STAT(marked, 1);
    void **f = fields(x);
    for (unsigned i = 0; i < x->nptr; i++)
      if (is_cell(f[i])) walk.push(static_cast<IdrCell *>(f[i]));
  }
}

void drop(void *v) {
  if (!is_cell(v)) return;
  IdrCell *c = static_cast<IdrCell *>(v);
  int32_t rc = c->rc;
  if (rc > 1 && rc != INT_MAX) c->rc = rc - 1;
  else idr_dec_cold(c);
}

// ---- threads and channels --------------------------------------------------

int64_t ncores() {
  static int64_t n = [] {
    long k = sysconf(_SC_NPROCESSORS_ONLN);
    return (int64_t)(k > 0 ? k : 1);
  }();
  return n;
}

void pin(int64_t core) {
  cpu_set_t set;
  CPU_ZERO(&set);
  CPU_SET((int)(core % ncores()), &set);
  pthread_setaffinity_np(pthread_self(), sizeof set, &set);
}

struct Chan {
  size_t mask;
  alignas(64) std::atomic<size_t> head{0};
  alignas(64) std::atomic<size_t> tail{0};
  alignas(64) uint64_t received = 0;  // dead roots dropped by the producer
  void **slot;

  void put(void *v) {
    size_t h = head.load(std::memory_order_relaxed);
    while (h - tail.load(std::memory_order_acquire) > mask) __builtin_ia32_pause();
    slot[h & mask] = v;
    head.store(h + 1, std::memory_order_release);
  }
  bool try_get(void *&v) {
    size_t t = tail.load(std::memory_order_relaxed);
    if (head.load(std::memory_order_acquire) == t) return false;
    v = slot[t & mask];
    tail.store(t + 1, std::memory_order_release);
    return true;
  }
  void *get() {
    void *v;
    while (!try_get(v)) __builtin_ia32_pause();
    return v;
  }
};

Chan *make_chan(size_t cap) {
  void *mem = nullptr;
  if (posix_memalign(&mem, 64, sizeof(Chan)) != 0) abort();
  Chan *c = new (mem) Chan;
  c->mask = cap - 1;
  c->slot = static_cast<void **>(calloc(cap, sizeof(void *)));
  if (!c->slot) abort();
  return c;
}

struct Thread {
  pthread_t id;
  int64_t core;
  void (*run)(Thread *);
  idr_body body;
  idr_task task;
  void *env;
  int64_t ntasks;
  int64_t *results;
  std::atomic<int64_t> *next;
};

void *thread_main(void *arg) {
  Thread *t = static_cast<Thread *>(arg);
  pin(t->core);
  t->run(t);
  publish();
  return nullptr;
}

void run_body(Thread *t) { t->body(t->env, t->core); }

void run_tasks(Thread *t) {
  for (;;) {
    int64_t i = t->next->fetch_add(1, std::memory_order_relaxed);
    STAT(sched, 1);
    if (i >= t->ntasks) return;
    t->results[i] = t->task(t->env, i);
  }
}

// Runs t[0] on the calling thread (core 0) and t[1..n) on new threads.
void run_threads(Thread *t, int64_t n) {
  for (int64_t i = 1; i < n; i++)
    if (pthread_create(&t[i].id, nullptr, thread_main, &t[i]) != 0) abort();
  t[0].run(&t[0]);
  for (int64_t i = 1; i < n; i++) pthread_join(t[i].id, nullptr);
}

} // namespace

// ---- the ABI ---------------------------------------------------------------

extern "C" {

void *idr_alloc_16(void) { return alloc_cell<16>(); }
void *idr_alloc_24(void) { return alloc_cell<24>(); }
void *idr_alloc_32(void) { return alloc_cell<32>(); }
void *idr_alloc_40(void) { return alloc_cell<40>(); }
void *idr_alloc_48(void) { return alloc_cell<48>(); }
void *idr_alloc_56(void) { return alloc_cell<56>(); }
void *idr_alloc_64(void) { return alloc_cell<64>(); }
void idr_free_16(void *c) { free_sized<16>(c); }
void idr_free_24(void *c) { free_sized<24>(c); }
void idr_free_32(void *c) { free_sized<32>(c); }
void idr_free_40(void *c) { free_sized<40>(c); }
void idr_free_48(void *c) { free_sized<48>(c); }
void idr_free_56(void *c) { free_sized<56>(c); }
void idr_free_64(void *c) { free_sized<64>(c); }

void idr_inc_cold(IdrCell *c) {
  int32_t rc = c->rc;
  if (rc < 0) {
    STAT(atomics, 1);
    __atomic_fetch_sub(&c->rc, 1, __ATOMIC_RELAXED);
  }
  // 0: persistent; INT_MAX: stuck.
}

void idr_dec_cold(IdrCell *c) {
  int32_t rc = c->rc;
  if (rc == 1) {
    idr_free_cell(c);
  } else if (rc < 0) {
    STAT(atomics, 1);
    if (__atomic_fetch_add(&c->rc, 1, __ATOMIC_ACQ_REL) == -1) idr_free_cell(c);
  }
  // 0: persistent; INT_MAX: stuck.
}

void idr_free_cell(IdrCell *cell) {
  IdrCell *todo = nullptr;
  push(todo, cell);
  while (todo) {
    IdrCell *c = todo;
    todo = next(c);
    unsigned nptr = c->nptr, nwords = c->nwords;
    void **f = fields(c);
    for (unsigned i = 0; i < nptr; i++) release(f[i], todo);
    free_words(c, nwords);
  }
}

void idr_send(void *value) {
  STAT(sends, 1);
  if (!is_cell(value)) return;
  walk.push(static_cast<IdrCell *>(value));
  while (walk.size) {
    IdrCell *c = walk.pop();
    int32_t rc = c->rc;
    if (rc == 1) {
      // Moved: only this reference reaches it, so it stays non-atomic.
      STAT(moved, 1);
      void **f = fields(c);
      for (unsigned i = 0; i < c->nptr; i++)
        if (is_cell(f[i])) walk.push(static_cast<IdrCell *>(f[i]));
    } else if (rc > 1) {
      // The sender still holds it: shared from now on.
      mark(c);
    }
    // <= 0: shared or persistent already.
  }
}

int32_t idr_str_eq(const void *a, const void *b) {
  if (a == b) return 1;
  const int64_t *x = static_cast<const int64_t *>(a) + 1;
  const int64_t *y = static_cast<const int64_t *>(b) + 1;
  return x[0] == y[0] && memcmp(x + 1, y + 1, (size_t)x[0]) == 0;
}

int64_t idr_read_int(void) {
  int64_t n = 0;
  int ch;
  while ((ch = getchar()) == ' ' || ch == '\n' || ch == '\t') {}
  for (; ch >= '0' && ch <= '9'; ch = getchar()) n = n * 10 + (ch - '0');
  return n;
}

void idr_put_int(int64_t v) { printf("%lld", (long long)v); }

void idr_put_str(const char *bytes, int64_t length) { fwrite(bytes, 1, (size_t)length, stdout); }

void idr_put_char(int32_t c) {
  char b[4];
  size_t n;
  if (c < 0x80) { b[0] = (char)c; n = 1; }
  else if (c < 0x800) { b[0] = (char)(0xC0 | (c >> 6)); b[1] = (char)(0x80 | (c & 0x3F)); n = 2; }
  else if (c < 0x10000) {
    b[0] = (char)(0xE0 | (c >> 12)); b[1] = (char)(0x80 | ((c >> 6) & 0x3F));
    b[2] = (char)(0x80 | (c & 0x3F)); n = 3;
  } else {
    b[0] = (char)(0xF0 | (c >> 18)); b[1] = (char)(0x80 | ((c >> 12) & 0x3F));
    b[2] = (char)(0x80 | ((c >> 6) & 0x3F)); b[3] = (char)(0x80 | (c & 0x3F)); n = 4;
  }
  fwrite(b, 1, n, stdout);
}

int64_t idr_cores(void) { return ncores(); }

void idr_run_on_cores(int64_t n, idr_body body, void *env) {
  Thread *t = static_cast<Thread *>(calloc((size_t)n, sizeof(Thread)));
  if (!t) abort();
  for (int64_t i = 0; i < n; i++) {
    t[i].core = i;
    t[i].run = run_body;
    t[i].body = body;
    t[i].env = env;
  }
  run_threads(t, n);
  free(t);
}

void idr_parallel(int64_t ntasks, idr_task task, void *env, int64_t *results) {
  int64_t n = ncores();
  std::atomic<int64_t> next{0};
  Thread *t = static_cast<Thread *>(calloc((size_t)n, sizeof(Thread)));
  if (!t) abort();
  for (int64_t i = 0; i < n; i++) {
    t[i].core = i;
    t[i].run = run_tasks;
    t[i].task = task;
    t[i].env = env;
    t[i].ntasks = ntasks;
    t[i].results = results;
    t[i].next = &next;
  }
  run_threads(t, n);
  free(t);
}

void *idr_chan_new(void) { return make_chan(64); }

void idr_chan_send(void *chan, void *value) {
  idr_send(value);
  static_cast<Chan *>(chan)->put(value);
}

void *idr_chan_recv(void *chan) { return static_cast<Chan *>(chan)->get(); }

void *idr_home_new(void) { return make_chan(256); }

void idr_drop_foreign(void *home, void *value) {
#ifdef IDR_GATE_HOME
  // Dead here: no walk. The producer drains `home` before each send, so it
  // never holds more than the forward channel's 64 entries plus one.
  static_cast<Chan *>(home)->put(value);
#else
  (void)home;
  drop(value);
#endif
}

void idr_producer_turn(void *home) {
  Chan *h = static_cast<Chan *>(home);
  void *v;
  while (h->try_get(v)) {
    drop(v);
    h->received++;
  }
}

void idr_producer_finish(void *home, int64_t sent) {
#ifdef IDR_GATE_HOME
  Chan *h = static_cast<Chan *>(home);
  while ((int64_t)h->received < sent) {
    void *v = h->get();
    drop(v);
    h->received++;
  }
#else
  (void)home;
  (void)sent;
#endif
}

void idr_turn_end(void) {
#ifdef IDR_GATE_FLUSH
  if (dirty) {
    snmalloc::ThreadAlloc::get().flush();
    dirty = false;
  }
#endif
}

} // extern "C"

int main() {
  pin(0);
  int32_t r = idr_main();
  fflush(stdout);
  publish();
  report();
  return r;
}
