# Decision: shards are copies of the single-threaded runtime

The user decided on 2026-10-09 that a shard is one more copy of the
single-threaded runtime this compiler already has, with a world of its own,
and asked for the rest to be pinned against the corpus. The decisions below
that the user did not state themselves were pinned on that delegation, by
`decision-single-thread-first.md`. They stand until the user changes them.
The design they apply is `concurrency.md` §4; markers are those of
`substrate.md` (**read**, **recalled**, **decision**, **conjecture**).

## 1. One world per shard (the user's)

A shard is a runtime thread with its own heap, its own world, plain counts,
its own top-level constant cells, its own handle table and its own output
buffer. Only that shard touches any of them. Values cross shards inside
messages, by move, copy or lend (`concurrency.md` §4.3). This amends
`decision-threads-pointers.md`, whose "one world" becomes one per shard.
What that note excludes stays excluded: base's `fork`, `threadWait` and
`System.Concurrency` start a second schedule of effects on one heap, and are
`unsupported (threads)`. Parallelism is `libs/mlir-shard`'s structured fork
(`concurrency.md` §4.4), whose join is linear.

This is Seastar's model, applied to the whole runtime: "Any sharing of
resources across cores must be handled explicitly... one CPU must explicitly
forward the request to the other" (read: `sources/docs/seastar/shared-nothing.html`),
and an object is used on its home thread or moved there (read:
`sources/docs/seastar/tutorial.md`, the `foreign_ptr` section).

## 2. Effects are causally ordered

**decision** Effects on one shard happen in program order. Across shards,
everything a shard did before it posted a message (a fork, a join's reply, a
hop) happens before everything the receiving shard does after it takes the
message. Effects no message orders interleave, and each one is whole: a
`putStr` is never split by another shard's output, and a line read goes to
one reader. Messages between two shards arrive in the order they were
posted, since a wake queue is a multi-producer, single-consumer queue that
keeps each producer's order (read: `sources/papers/lietar-2019-snmalloc`
§2.2, the queue the wake queue copies).

## 3. The standard streams work on every shard

**decision** (amends proposed decision 4 of `README.md`, which gave the
streams to shard 0 and made every other shard hop there to write):

- **Output: a buffer per shard.** Each shard writes standard output into a
  buffer of its own, exactly as the single-threaded runtime does today
  (read: `runtime/Io/Output.cppm`, one 4 KiB buffer that a flush writes).
  No lock is on the write path. A flush writes the whole buffer with one
  `writeAll` under a lock on the descriptor, the one lock a shard takes for
  output, so two shards' flushes never interleave, whatever the descriptor
  is: POSIX makes a pipe write atomic only up to `PIPE_BUF`, 512 bytes on
  macOS (recalled).
- **When a shard flushes:** when its buffer is full; before it blocks (a
  read, a blocking hop, its reactor going to sleep); before it posts any
  message; and at its end. Flushing before a post is what makes output
  causal: shard A's line is in the kernel before shard B can act on A's
  message. Flushing before sleep keeps an idle shard's buffer empty.
- **Standard error** is written unbuffered today (read:
  `runtime/Io/Ending.cppm`, `writeAll(2, ...)`), so each write is one
  `writeAll` under standard error's lock.
- **Input belongs to shard 0.** Its buffer is the single-threaded runtime's
  (read: `runtime/Io/Input.cppm`), with no lock on shard 0's read path. A
  read on another shard is a blocking hop to shard 0: the reading shard
  flushes its own output (so a prompt precedes the read, as it does today),
  posts the request, and blocks until shard 0 replies with the line, the
  bytes or the end. Requests are served in arrival order, so lines go to
  readers whole. A shard 0 busy computing delays them, which costs nothing
  on one shard.

Rejected: one process-wide output buffer behind a lock, and a write call
per `putStr`, each of which puts a cost on every single-shard write; all
output owned by shard 0 (the earlier proposal), which makes every other
shard's write a message and puts shard 0's work in front of every line,
for the same causal order the per-shard buffers give without either; one
process-wide input buffer behind a lock, which locks shard 0's every read.

## 4. Files and directories

**decision** Each shard has its own handle table (read:
`runtime/Io/Handles.cppm`, today one table per process). A handle stays an
`int64_t`, and a handle of slot `i` on shard `k` carries `k` above bit 47,
so shard 0's handles are today's numbers. `0`, `1` and `2` are the
standard streams on every shard (§3), and `-1` is null. An operation on a
handle whose home is another shard is a blocking hop to its home, which
performs it and replies; so a file opened on one shard can be sent, as the
integer it is, and used or closed on another. A string the runtime keeps
(the environment's, a directory's last entry) is a slot of the calling
shard's table. A single-shard program pays one compare per file operation,
beside a system call.

## 5. Process state

**decision** The environment and the current directory belong to the
process, as the kernel and the C library have them. The platform layer
serializes `getenv`, `setenv`, `unsetenv`, `getcwd` and `chdir` with one
lock: C does not let `getenv` race `setenv` (recalled), and these calls
are rare. A relative path resolves against the directory current at the
call.

`exitWith`, or a crash, on any shard ends the process: that shard flushes
its own output, writes its message, and exits with its status. Output that
is causally before the exit is already written (§3). Output another shard
buffered concurrently with it may be lost, as any effect concurrent with an
exit may not happen. At a normal end, `runShards` has joined every fork (a
join is linear), and every join's reply flushed its worker, so every line
is out.

## 6. Top-level constants are per shard

**decision** A top-level constant is evaluated at most once per shard that
demands it, in a cell of that shard's own: `concurrency.md` §2.4's
thread-local copy of an immutable template, with the index that its
correction gives static data. With one shard it is evaluated once, as
today. A `trace` in a top-level constant prints once per shard that forces
it. This amends the reason proposal 0002's owner decision O3 gives for
memoizing a static constant ("evaluated once"): once per shard.

Rejected: one process-wide cell per constant, forced once behind a
once-guard. The forced value is then reachable from every shard, so it
would have to be persistent, never counted and never freed (Lean's
persistent kind: "from persistent values, we can only reach other
persistent values"; read: `ullrich-2019-counting-immutable-beans/threadsafety.tex`),
and every thunk inside it would need a force that tests whether it is
shared. That test lands on the single-shard force path.

## 7. Lazy streams across shards

A lazy stream is a cons cell whose tail is an `Inf` thunk: after
defunctionalization, a memo sum forced with plain writes and plain counts
(`concurrency.md` §2.3). There are three ways for one stream to live on
two shards.

**decision 1: by value, supported.** A send detaches it as it detaches any
value (`concurrency.md` §4.3): the forced prefix is copied with its values,
the unforced tail is copied as its label and captures. Afterwards each
shard has its own stream and forces it alone. An infinite stream crosses in
time proportional to its forced prefix and its captures. Elements both
shards force are computed twice. Nothing changes on one shard.

**decision 2: a shared memo, not supported.** One thunk whose memo every
shard sees needs an atomic state on the thunk, a force that knows whether
its thunk is shared, and counts on everything the forced value reaches that
two shards can drop. Every way to have those costs the single-shard path or
adds a second counting regime:

- a tag tested on every force and count, Lean's `markMT`, whose "additional
  test does not require any synchronization" but is still paid by every
  single-threaded force (read: `threadsafety.tex`);
- persistent values, which need no count but are never freed, so an
  infinite stream forced without end is memory without end;
- atomic counts on a kind of cell of its own, which is a second reference
  count beside ours, the reason the async dialect was rejected
  (`substrate.md` §4).

**decision 3: a pipe, supportable and not scheduled.** A pipe evaluates a
stream on a producer shard and hands it, element by element, to one
consumer shard. The atomics live in the channel and nowhere else.

- **Surface**, in `libs/mlir-shard`:
  `pipe : (s' : Fin n) -> (ahead : Nat) -> Stream a -> Shard n s (Stream a)`.
  Read as written, `pipe s' k xs = pure xs`. So the consumer sees the same
  values, the result is deterministic, and only where the elements are
  computed, and how far ahead, changes.
- **Representation:**
  - A ring of `ahead` slots in memory that is not an Idris cell
    (`concurrency.md` §4.9), a head and a tail index, a closed flag, and a
    wake token for each side. The two indices are the only atomics: the
    side that advances one stores it with release, the other loads it with
    acquire.
  - A producer fork on `s'` owns the stream. It forces the next element,
    detaches it (a freshly made element is at count 1, so it moves and its
    pointer is the slot), and pushes it. A full ring parks the producer's
    task.
  - The consumer's stream is the ordinary memo sum with one more label,
    `pipe_next ring`. Its force pops one slot and memoizes
    `x :: pipe_next ring` as any force memoizes. An empty ring blocks the
    consumer shard, since pure code cannot wait, as a read of standard input
    from pure code cannot.
  - So the consumer's forces, counts and memo stay plain, and no other
    thunk changes. The cost is the label's arm in the force's switch, and
    only pipes have it.
- **Lifetime.** Releasing the last `pipe_next` thunk closes the ring. The
  producer sees the flag at its next push, drops its stream and ends, and
  the runtime joins it. Elements still in the ring are freed by the
  release, and go home through snmalloc's remote frees.
- **The send check.** A pipe has one consumer, and a copy of its stream
  would make two. The `pipe_next` label is visible in a stream's memo sum
  after defunctionalization, so the send check (`concurrency.md` §4.6)
  rejects sending a value whose lazy keys can hold it: `unsupported
  (send)`, naming the path.
- **When.** It needs waits (W12), the reactor (W13) and shards (W14). It is
  built when a program measures a need for it (W17), not before.

## 8. Tests

**decision** One set of expected files serves every core count. Every
fixture runs at `IDRIS_RT_SHARDS=1` against its expected files. A program
whose output is causally ordered (it prints after its joins, or its prints
are ordered by them) is deterministic at any count and runs at more shards
against the one-shard run. A program whose output has concurrent writes is
checked at one shard only.

## What stays open

These are measurements, not decisions (`README.md`, questions 1 and 2):

- whether placing work by queue depth is enough on 8 performance and 4
  efficiency cores;
- whether the detach walk costs enough to justify lending;
- the cost of a top-level constant's force through a thread-local cell on
  each target (**conjecture**: a few instructions; on Mach-O, a
  thread-local variable is reached through a descriptor);
- whether any program wants a pipe.
