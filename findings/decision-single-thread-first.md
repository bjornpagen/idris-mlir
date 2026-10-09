# Decision: single-thread performance wins the tie

The user decided this on 2026-10-09.

When a design choice trades single-thread performance against multithreaded
performance, it takes the single-thread side. This is not a new rule. It is
the reason the compiler counts references, runs one heap per core, and keeps
every count plain; stated once, it settles the cases that follow those
choices.

- **Why.** Most of what a program does runs on one core: every value is
  touched by one thread, and every cost paid "in case it is shared" is paid
  by all of them. Lean measured it: the memory fences of thread-safe counts
  "have a significant performance impact even when only one thread is being
  executed. This is quite unfortunate because most values are only touched
  by a single execution thread" (read:
  `sources/papers/ullrich-2019-counting-immutable-beans/threadsafety.tex`).
  Multithreaded performance is bought where the program says it wants it, a
  fork, a hop, a parallel loop, and only there.
- **What it already decided:**
  - reference counting, not tracing, with plain counts (`substrate.md`);
  - one heap per core, not M:N work stealing (`concurrency.md` §4.1);
  - no tag test on every count, which is Lean's answer, because the test
    itself is paid on every single-threaded count (`concurrency.md` §4.1).
- **What it decides now** (`decision-shards.md`):
  - a thunk's memo stays a plain write: no thunk is ever forced by two
    shards, and no force tests whether it might be;
  - a top-level constant is evaluated once per shard that demands it, in a
    cell of that shard's own, not once per process behind a once-guard;
  - each shard writes standard output through a buffer of its own, with no
    lock on the write path; standard input belongs to shard 0, with no lock
    on its read path;
  - a lazy stream crosses shards by value. A stream whose memo is shared
    between shards is not supported.
- **How to apply it.** A cost that appears only when a program uses more
  than one shard (a detach walk, a message, a lock taken once per flush, a
  blocking hop) is acceptable. A cost on a path that a single-shard program
  runs (a count, a force, an allocation, a write to a buffer, a field read)
  is not, unless it is free there too. When the two cannot be had together,
  this rule decides, and the design note says it did.
