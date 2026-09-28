// Allocation shapes of the planned runtime, used to choose its allocator
// (how to build and run it: README.md here).
// Build with exactly one of -DUSE_MI, -DUSE_SN, -DUSE_LIBC.
// Objects model our heap layout: an 8-byte header (count, tag), then fields.
// Freeing is iterative through the header, as in Lean's lean_del_core.
#if defined(USE_MI)
#include "static.c"
#include <mimalloc.h>
#elif defined(USE_SN)
#include <snmalloc/snmalloc.h>
#else
#include <stdlib.h>
#endif
#include <atomic>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <thread>
#include <vector>

// ---- allocator policy: size is a compile-time constant at every call ----
#if defined(USE_MI)
static thread_local mi_theap_t* tl_heap;
static inline void core_init() { tl_heap = mi_theap_get_default(); }
template<size_t S> static inline void* A() { return mi_theap_malloc_small(tl_heap, S); }
template<size_t S> static inline void F(void* p) { mi_free_small(p); }
static const char* NAME = "mimalloc";
#elif defined(USE_SN)
static inline void core_init() {}
template<size_t S> static inline void* A() { return snmalloc::alloc<S>(); }
template<size_t S> static inline void F(void* p) { snmalloc::dealloc<S>(p); }
static const char* NAME = "snmalloc";
#else
static inline void core_init() {}
template<size_t S> static inline void* A() { return malloc(S); }
template<size_t S> static inline void F(void* p) { free(p); }
static const char* NAME = "glibc";
#endif

struct Node { union { uint64_t hdr; Node* next; }; Node* l; Node* r; int64_t key; };  // 32 bytes

static double now() { timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static void pin(int cpu) { cpu_set_t s; CPU_ZERO(&s); CPU_SET(cpu, &s); pthread_setaffinity_np(pthread_self(), sizeof s, &s); }

static Node* build(int d, int64_t k) {
  Node* n = (Node*)A<sizeof(Node)>();
  n->hdr = 1; n->key = k;
  if (d == 0) { n->l = n->r = nullptr; }
  else { n->l = build(d - 1, 2 * k); n->r = build(d - 1, 2 * k + 1); }
  return n;
}
static int64_t check(Node* n) { int64_t s = 0; while (n) { s += n->key + check(n->r); n = n->l; } return s; }
// Iterative free through the header word (Lean's to-do list).
static void drop(Node* root) {
  Node* todo = root; root->next = nullptr;
  while (todo) {
    Node* n = todo; todo = n->next;
    if (n->l) { n->l->next = todo; todo = n->l; }
    if (n->r) { n->r->next = todo; todo = n->r; }
    F<sizeof(Node)>(n);
  }
}

// ---- W1: binarytrees shape on one core ----
static int64_t trees(int maxd) {
  int64_t s = 0;
  Node* longlived = build(maxd, 1);
  for (int d = 4; d <= maxd; d += 2) {
    long iters = 1L << (maxd - d + 4);
    for (long i = 0; i < iters; i++) { Node* t = build(d, i); s += check(t) & 1; drop(t); }
  }
  s += check(longlived); drop(longlived);
  return s;
}

// ---- W2: mixed-size churn (constructors of several sizes, random lifetimes) ----
static uint64_t rng(uint64_t& x) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return x; }
static void* allocIdx(int i) {
  switch (i) { case 0: return A<16>(); case 1: return A<24>(); case 2: return A<32>();
               case 3: return A<48>(); case 4: return A<64>(); default: return A<96>(); }
}
static void freeIdx(int i, void* p) {
  switch (i) { case 0: F<16>(p); break; case 1: F<24>(p); break; case 2: F<32>(p); break;
               case 3: F<48>(p); break; case 4: F<64>(p); break; default: F<96>(p); }
}
static int64_t churn(long live, long steps) {
  std::vector<void*> ps(live); std::vector<uint8_t> cls(live);
  uint64_t x = 88172645463325252ull;
  for (long i = 0; i < live; i++) { cls[i] = rng(x) % 6; ps[i] = allocIdx(cls[i]); *(uint64_t*)ps[i] = i; }
  int64_t s = 0;
  for (long t = 0; t < steps; t++) {
    long i = rng(x) % live; s += *(uint64_t*)ps[i];
    freeIdx(cls[i], ps[i]); cls[i] = rng(x) % 6; ps[i] = allocIdx(cls[i]); *(uint64_t*)ps[i] = t;
  }
  for (long i = 0; i < live; i++) freeIdx(cls[i], ps[i]);
  return s;
}

// ---- single-producer single-consumer ring between cores ----
struct Ring {
  static const size_t N = 64;
  alignas(64) std::atomic<size_t> head{0};
  alignas(64) std::atomic<size_t> tail{0};
  alignas(64) Node* slot[N];
  void push(Node* n) { size_t h = head.load(std::memory_order_relaxed);
    while (h - tail.load(std::memory_order_acquire) >= N) __builtin_ia32_pause();
    slot[h % N] = n; head.store(h + 1, std::memory_order_release); }
  Node* pop() { size_t t = tail.load(std::memory_order_relaxed);
    while (head.load(std::memory_order_acquire) == t) __builtin_ia32_pause();
    Node* n = slot[t % N]; tail.store(t + 1, std::memory_order_release); return n; }
};

// ---- W4: pipeline: core 2i builds trees, core 2i+1 consumes and frees them (every free remote) ----
static int64_t pipeline(int pairs, int depth, long count) {
  std::vector<Ring*> rings; for (int i = 0; i < pairs; i++) rings.push_back(new Ring);
  std::atomic<int64_t> total{0}; std::vector<std::thread> ts;
  for (int i = 0; i < pairs; i++) {
    ts.emplace_back([&, i] { pin(2 * i); core_init(); for (long k = 0; k < count; k++) rings[i]->push(build(depth, k)); rings[i]->push(nullptr); });
    ts.emplace_back([&, i] { pin(2 * i + 1); core_init(); int64_t s = 0; while (Node* t = rings[i]->pop()) { s += check(t) & 1; drop(t); } total += s; });
  }
  for (auto& t : ts) t.join();
  return total;
}

// ---- W5: thread per core, all local ----
static int64_t percore(int cores, int maxd) {
  std::atomic<int64_t> total{0}; std::vector<std::thread> ts;
  for (int c = 0; c < cores; c++) ts.emplace_back([&, c] { pin(c); core_init(); total += trees(maxd); });
  for (auto& t : ts) t.join();
  return total;
}

// ---- W6: thread per core, a fraction 1/every of the trees crosses to the next core ----
static int64_t mostly_local(int cores, int depth, long count, int every) {
  std::vector<Ring*> rings; for (int i = 0; i < cores; i++) rings.push_back(new Ring);
  std::atomic<int64_t> total{0}; std::atomic<int> done{0}; std::vector<std::thread> ts;
  for (int c = 0; c < cores; c++) ts.emplace_back([&, c] {
    pin(c); core_init(); int64_t s = 0; Ring* out = rings[(c + 1) % cores]; Ring* in = rings[c];
    auto drain = [&] { while (in->head.load(std::memory_order_acquire) != in->tail.load(std::memory_order_relaxed)) { Node* t = in->pop(); if (t) { s += check(t) & 1; drop(t); } else done++; } };
    for (long k = 0; k < count; k++) {
      Node* t = build(depth, k);
      if (k % every == 0) out->push(t); else { s += check(t) & 1; drop(t); }
      drain();
    }
    out->push(nullptr);
    while (done.load() < cores) drain();
    drain(); total += s; });
  for (auto& t : ts) t.join();
  return total;
}

// ---- W7: fan-out/fan-in (futures): core 0 sends inputs, workers return results; both directions remote ----
static int64_t fan(int workers, int depth, long count) {
  std::vector<Ring*> to, from; for (int i = 0; i < workers; i++) { to.push_back(new Ring); from.push_back(new Ring); }
  std::atomic<int64_t> total{0}; std::vector<std::thread> ts;
  for (int w = 0; w < workers; w++) ts.emplace_back([&, w] {
    pin(w + 1); core_init();
    while (Node* in = to[w]->pop()) { int64_t k = check(in); drop(in); from[w]->push(build(depth, k & 1023)); }
    from[w]->push(nullptr); });
  ts.emplace_back([&] {
    pin(0); core_init(); int64_t s = 0; long sent = 0, recv = 0;
    // keep a window of in-flight requests per worker
    for (int w = 0; w < workers; w++) for (int j = 0; j < 8 && sent < count; j++, sent++) to[w]->push(build(depth, sent));
    while (recv < count) for (int w = 0; w < workers && recv < count; w++) {
      Node* r = from[w]->pop(); s += check(r) & 1; drop(r); recv++;
      if (sent < count) { to[w]->push(build(depth, sent)); sent++; }
    }
    for (int w = 0; w < workers; w++) to[w]->push(nullptr);
    for (int w = 0; w < workers; w++) from[w]->pop();
    total += s; });
  for (auto& t : ts) t.join();
  return total;
}

int main(int argc, char** argv) {
  const char* w = argc > 1 ? argv[1] : "trees";
  double t0 = now(); int64_t r = 0;
  if (!strcmp(w, "trees")) { pin(0); core_init(); r = trees(20); }
  else if (!strcmp(w, "churn")) { pin(0); core_init(); r = churn(1 << 20, 40000000); }
  else if (!strcmp(w, "percore1")) r = percore(1, 18);
  else if (!strcmp(w, "percore4")) r = percore(4, 18);
  else if (!strcmp(w, "pipeline")) r = pipeline(2, 10, 20000);
  else if (!strcmp(w, "pipeline16")) r = pipeline(2, 4, 400000);
  else if (!strcmp(w, "local20")) r = mostly_local(4, 10, 20000, 20);
  else if (!strcmp(w, "local2")) r = mostly_local(4, 10, 20000, 2);
  else if (!strcmp(w, "fan")) r = fan(3, 8, 100000);
  double t = now() - t0;
  rusage u; getrusage(RUSAGE_SELF, &u);
  printf("%-9s %-11s %8.3f s  maxrss %7ld KiB  (%lld)\n", NAME, w, t, u.ru_maxrss, (long long)r);
}
