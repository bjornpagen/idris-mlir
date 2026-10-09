# Findings

The code is the specification. A note here becomes work only when a plan
picks it up. Since cb65104 the findings are three design notes, the
decisions the user has taken, and one directory of test output.

| File | What it is |
|---|---|
| `substrate.md` | How the compiler holds what it knows: six representation moves (S1–S6), the promises that become checks, the upstream mechanisms used and rejected, and the requirements deleted. |
| `concurrency.md` | Thunks, task frames, shards and futures, built on the substrate: what a suspended computation is, the runtime that runs it on many cores, and the future Rust is polled on. |
| `decision-*.md` | Decisions the user took. They stand unless a decision of the user's changes them. |
| `upstream-idris/` | The output of `tests/upstream-idris/run`: which upstream Idris 2 tests this compiler passes, and why the others fail. |

The notes cb65104 wrote (`frame.md`, `copies.md`, `future.md`,
`async-dialect.md`, `papers.md`, `rust-executor.md`, `scheduler.md`,
`execution.md`, `shards.md` and `cross-shard.md`) are folded into
`concurrency.md`, with their errors corrected in its §1. The notes cb65104
deleted are still in history at 4cfce76, and what they left open is carried
in `substrate.md`:

- `one-representation.md`, the duplication audit;
- `lists.md`, deforestation and contiguous lists;
- `simd.md`, vectorization by default;
- `mlir-survey.md`, what upstream offers that we do not use.

## The method

Four rules decide how every design note here is written:

- **Representation before control flow.** When a new case shows up, change
  the data, the types and the invariants until it is not special. This is
  the lineage of Brooks, Pike, Raymond and Torvalds; the type-theoretic
  account is Minsky, King, Dijkstra and SICP; the limit is Brooks's "No
  Silver Bullet" (`substrate.md` §0).
- **Five steps, in order:**
  1. question every requirement;
  2. delete the part;
  3. simplify what remains;
  4. accelerate it;
  5. automate it.
- **MLIR first, in a fixed order of preference:**
  1. an upstream mechanism;
  2. an upstream interface implemented on our ops;
  3. an op of ours carrying a fact Idris proved, or a meaning only our
     runtime gives;
  4. a pass of ours;
  5. C++.
- **Claims are marked:** read, measured, decision, conjecture.

## Decisions that stand

- **`decision-acyclic-heap.md`.** The heap stays acyclic: a type that can
  knot a mutable cell is `unsupported (cycle)`. The check that enforces it
  does not exist yet (`substrate.md` §3, W2).
- **`decision-nat.md`.** A `Nat` or `Integer` proved to fit a word is a
  plain `i64`; otherwise it is the tagged small value or a GMP cell. Heap
  references stay untagged addresses.
- **`decision-primitive-semantics.md`.** A primitive's one meaning is the
  runtime's. Chez is the oracle, not the specification.
- **`decision-inhouse-linear.md`** (and `decision-linear-libraries.md`,
  superseded in part by it). The compiler implements Idris 2 over the
  upstream prelude and base; linear code comes from `libs/mlir-linear`; the
  language does not change.
- **`decision-no-oracle.md`.** No oracle: a test's committed expected
  files are its specification. The Chez comparison, its divergence classes
  and the stock evaluator's `Oracle.idr` proofs go; Chez stays only as the
  host Idris runs on and as a benchmark baseline.
- **`decision-threads-pointers.md`.** User threads, collector finalizers,
  raw pointers, `%foreign` and the C ABI are outside the language.

## Decisions proposed to the user

These change or extend a decision above, or the surface the compiler
accepts, so they are the user's to take. Each is argued where it is cited.

1. **One world per shard** (`concurrency.md` §4). The runtime starts one
   reactor per core, each with its own heap, world and plain counts. Values
   cross between them by move, copy or lend, inside messages. User `fork`,
   `threadWait`, `System.Future` and base's `System.Concurrency` stay
   outside the language, by name. This amends `decision-threads-pointers.md`,
   whose "one world" becomes one per shard.
2. **Base's foreign surface is runtime primitives** (`substrate.md` S5.2).
   Files, directories, clock, environment, arguments, errno and terminal
   size are recognized by name, as `Data.Buffer` is, each with one meaning
   behind `rt.platform`. A `File` is the runtime's small integer. Signal
   handlers are `unsupported (signal)`. This clarifies the `%foreign`
   decision; it does not reopen it.
3. **The memo is decided per thunk** (`concurrency.md` §2.5): inlined when
   used once, one-shot when exclusive, memoized when shared. A thunk whose
   body forges a world is never memoized, as on Chez.
4. **The standard streams belong to shard 0** (`concurrency.md` §4.7). A
   program whose output depends on how shards interleave gets the
   divergence class `shard-interleaving`.
5. **Rust bindings are generated primitives**, not `%foreign "rust:"`
   (`concurrency.md` §5.5). This amends proposal 0001 §9.2.
6. **The in-place promise becomes the default** once the benchmarks pass it
   (`substrate.md` §3).

## The ordered work

Each step is a research conclusion made concrete: what changes, and what
proves it. Every step runs AGENTS.md's checks. W1 to W10 are compiled into
one swarm packet, `proposals/0002-representation-cutover/`. It narrows W6
to its first phase (closure conversion leaves Idris; regions do not yet
live through the simplify loop), and records the corrections it made to
`substrate.md` and `concurrency.md`. W0 is this restructure. The
steps are ordered by what each needs; steps on separate lines of the graph
can run at once.

**W1. Patch instead of working around.**

- **Change:** reduce the two clang module crashes, carry
  `upstream/<bug>/clang.patch`, and delete the workarounds in
  `Stack/Escape.cppm` and `Driver/Retarget.cppm` with their `PIN` markers.
- **Proof:** `tests/upstream/clang-module-*` report "no longer crashes"
  against the patched clang, and the build is green with the code written
  plainly.

**W2. Enforce what is already decided.**

- **Change:**
  - the acyclic-heap check in the `idr.program` verifier after
    defunctionalization;
  - base's `System.Concurrency` refused as `threads`;
  - signal handlers refused as `signal`.
- **Proof:**
  - the knot program of `decision-acyclic-heap.md` is rejected with the
    types named;
  - an array of arrays passes against Chez;
  - a reject fixture for each new name.

**W3. Ownership and effects on operands and types**
(`substrate.md` S2.1, S2.2, S2.4, S2.5).

- **Change:**
  - consumption becomes `MemFree` of a reference resource, conditional on
    the grade; `useOf` goes;
  - the owned stage is read from the grades (views stay plain);
    `idr.stage` goes;
  - one `holdsReferences` function, since a type cannot look up an
    unboxed sum's declaration;
  - `std::optional` instead of `ub.poison` sentinels;
  - idr-canonicalize wraps upstream's pass;
  - `missed` remarks where passes decline.
- **Proof:**
  - every program's output and object code is unchanged;
  - a lit test in which a consuming call with an unused result survives
    `remove-dead-values`;
  - `IDRIS_RT_LIVE=1` reports zero everywhere.

**W4. Guards** (S2.3).

- **Change:** the `idr.check.*` ops; total consumers; `idr-in-bounds`
  becomes a folder of the guard; the `in_bounds` attribute goes.
- **Proof:**
  - the semantics fixtures against Chez;
  - crash messages, locations and exit status unchanged;
  - `in-bounds=@f` restated as "no guard is left in @f".

**W5. One evaluation mode, and no runtime closures** (S3.1, S3.2).

- **Change:**
  - idr-eval defunctionalizes its scratch module;
  - `idr-meter` and `idr-entry`;
  - the `jit` flag, the closure lowering and the runtime's closure
    release go.
- **Proof:**
  - every program gives the same output with and without `--no-eval`;
  - `tests/programs/eval`;
  - compile times within 10%.

**W6. Deferred computation as regions** (S1, S5.1).

- **Change:**
  - `idr.lambda` and `idr.delay` with implicit captures;
  - `idr-isolate` on `makeRegionIsolatedFromAbove`;
  - the four Lazy.cc patterns become two region rules (phase 2);
  - closure conversion leaves Idris;
  - `ArrayGen`/`ArrayFold` become one generic node;
  - `Prim` and `IOOp` are generated.
- **Proof:**
  - all suites;
  - a compile-time result holding a closure round-trips;
  - `no-closures` where it held before;
  - the Idris side's size, measured before and after.

**W7. Thunks as memo sums** (`concurrency.md` §2.3–2.5).

- **Change:**
  - thunks join defunctionalization as memo sums;
  - `Running` as the black hole; captures moved at entry;
  - static memo cells marked by their kind and released by
    `@__idr_release_cafs`; `idris_rt_lazy_kept` goes;
  - the one-shot force at `excl`;
  - no memo for a body that reaches an observable effect.
- **Proof:**
  - `stream-share` forces each cell once;
  - `allschemes/memo002` compiles and runs;
  - a self-forcing CAF ends with the named crash;
  - a thunk consuming a long list keeps its peak live cells bounded;
  - no bench regression on the lazy programs.

**W8. Flat constants, immutable static data** (S4).

- **Change:** a flat attribute for list spines; no mutable static data.
- **Proof:** a 10^5-element computed list compiles on an 8 MiB stack, and
  the list cases of `mlir-recursion` and `bytecode-deferred-quadratic`
  retire.

**W9. Base's foreign surface** (S5.2, proposed decision 2).

- **Change:** the primitives behind `rt.platform` on both targets.
- **Proof:** the upstream tests that fail on them today (`ReadDir`, `Time`,
  `NumProcessors`, `TermSize`, the file tests) pass against Chez.

**W10. The in-place promise** (`substrate.md` §3).

- **Change:** `--demand in-place`, then the default.
- **Proof:**
  - the leet fixtures hold `tests-nothing`;
  - a fixture that passes a shared value to a quantity-1 rebuild is
    rejected, naming the call.

**W11. Contiguous runs** (S3.1).

- **Change:** one run cell for strings, arrays and buffers; `!idr.seq`
  (lists note step 3); fusion by raising (lists step 2b).
- **Proof:**
  - fasta, reverse-complement, spectral-norm and k-nucleotide reach the
    lists note's measured contiguous times or better;
  - the verifier rejects a cons onto a shared seq.

**W12. Task frames and the `wait` bit** (`concurrency.md` §3).

- **Change:** `idr.wait`, coroutine lowering of `wait` functions only, and
  tail await.
- **Proof:**
  - a waiting loop of 10^7 iterations runs in constant memory;
  - a program that never waits lowers to byte-identical IR.

**W13. One reactor** (`concurrency.md` §4.8, §5.2).

- **Change:**
  - the task table, wake queue and kick;
  - kqueue with `EVFILT_USER`, and epoll with eventfd;
  - sleep;
  - same-shard fork and join.
- **Proof:** two tasks' sleeps overlap; a foreign-thread post wakes the
  reactor; both targets.

**W14. Shards** (`concurrency.md` §4, S6).

- **Change:**
  - `libs/mlir-shard`, `idr.fork`, `shard.grid`;
  - the send check and the detach walk;
  - the helping join;
  - shard 0 owning the standard streams;
  - `scf.forall` lowered to fork and join.
- **Proof:**
  - every shard fixture at `IDRIS_RT_SHARDS=1` against Chez;
  - at more shards against the one-shard run;
  - parallel binary-trees, spectral-norm and mandelbrot measured against
    one shard.

**W15. Synchronous Rust** (`concurrency.md` §5.5). It can start after W2,
beside everything else.

- **Change:** proposal 0001 R0–R3, re-based on generated primitives.
- **Proof:** the proposal's fixtures against Chez.

**W16. Asynchronous Rust** (`concurrency.md` §5.3–5.4). It follows W13.

- **Change:** the `FutT` loop, the one-word waker, runtime sockets and
  timers, and the blocking offload.
- **Proof:** a hyper client and server on one shard, and cancellation
  freeing the Rust future.

**W17. Later, each on a measurement:**

- lending (`concurrency.md` §4.3);
- taking unstarted messages (§4.1);
- io_uring submission;
- SPMD through upstream's `shard-partition` (S6);
- a generator coroutine as fusion's fallback (§2.6).

## Questions the corpus does not answer

1. **Asymmetric cores.** On 8 performance and 4 efficiency cores, is
   library placement by queue depth enough, or does the runtime need to
   take unstarted messages, or to start shards on performance cores only?
2. **Copy or lend.** For what real programs send (k-nucleotide's sequence,
   spectral-norm's vector), does the detach walk cost enough to justify the
   `lent` permission?
3. **Process creation in base.** Are `system` and `popen` inside the
   language as blocking primitives, or outside with signals?
4. **The cost of colouring.** After CoroElide, does a hot loop of waiting
   calls still allocate a frame per call?
5. **Tensors.** Should pure array programs exist as tensors before
   bufferization, which upstream's SPMD partitioning needs, against arrays
   as memrefs from birth?
6. **Rust crates.** Which crates work with this runtime as their I/O
   provider, without tokio's `rt`, `net` and `time` features?
