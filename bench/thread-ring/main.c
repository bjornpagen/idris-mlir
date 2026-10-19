// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* thread-ring (the Benchmarks Game), as Main.idr here. The game specifies
   503 threads in a ring passing a token; threads are outside the compiler
   this compares against, so this is the same workload under the same
   deterministic cooperative scheduler, without threads: the ring is
   explicit state, each thread with its name and its mailbox, and the
   scheduler visits the threads round-robin in ring order. A thread with an
   empty mailbox is blocked on its receive and yields; one with the token
   in its mailbox runs, takes it, and sends it on, less one, to the next;
   the thread given it at 0 prints its name. Its output is byte for byte
   Main.idr's. */
#include <stdio.h>

#define THREADS 503

typedef struct {
  int name;
  int full; /* whether the mailbox holds the token */
  long token;
} thread;

int main(void) {
  long n = 0;
  if (scanf("%ld", &n) != 1) return 1;
  static thread ring[THREADS];
  for (int i = 0; i < THREADS; i++) ring[i] = (thread){ i + 1, 0, 0 };
  ring[0].full = 1;
  ring[0].token = n;
  for (int i = 0;; i = (i + 1) % THREADS) {
    thread *t = &ring[i];
    if (!t->full) continue;
    long k = t->token;
    t->full = 0;
    if (k == 0) {
      printf("%d\n", t->name);
      return 0;
    }
    thread *next = &ring[(i + 1) % THREADS];
    next->full = 1;
    next->token = k - 1;
  }
}
