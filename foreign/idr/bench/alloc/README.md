# Allocation shapes

`shapes.cc` models the heap traffic the planned runtime will produce, and
was used to choose its allocator (`docs/plan.md` section 5.6). Objects have
our layout: an 8-byte header, then fields. Every allocation has a size known
at compile time. Freeing is iterative through the header, as in Lean. Each
thread is pinned to one core, as the schedulers will be.

| workload | shape |
| --- | --- |
| `trees` | binarytrees on one core: build and drop trees of depth 4 to 20 |
| `churn` | one core: a million live objects of six sizes (16 to 96 bytes); forty million random replacements |
| `percore1`, `percore4` | `trees` (depth 18) on 1 or 4 cores, nothing shared |
| `local20`, `local2` | thread per core: every core builds trees; one in 20 (or one in 2) goes to the next core, which drops it |
| `pipeline` | cores 0→1 and 2→3: producers build trees of depth 10, consumers read and drop them, so every free is remote |
| `pipeline16` | the same with trees of depth 4 (31 nodes) |
| `fan` | futures: core 0 sends inputs to three workers and drops their results; frees are remote both ways |

## Build and run

The allocators are compiled into the same translation unit, as Lean does
with mimalloc, from clones of mimalloc `v3.5.3` (`31d034d9`) and snmalloc
`0.7.5-15-ge9f7b2e`:

```
F="-O2 -std=c++20 -DNDEBUG -march=native -pthread"
g++ $F -DUSE_MI -Imimalloc/include -Imimalloc/src shapes.cc -o b_mi
g++ $F -mcx16 -DUSE_SN -DSNMALLOC_USE_WAIT_ON_ADDRESS=1 -Isnmalloc/src shapes.cc -o b_sn
./run.sh 5 trees churn percore1 percore4 pipeline pipeline16 local20 local2 fan
```

`-DUSE_LIBC` builds the same program on the C library's `malloc`.

## Results

On the development container (4 cores of a 2.8 GHz Xeon, one NUMA node),
GCC 13.3, median of 5 runs, in seconds. "mimalloc tuned" sets
`MIMALLOC_PAGE_RECLAIM_ON_FREE=1` and `MIMALLOC_PAGE_FULL_RETAIN=-1`, the two
options that helped its cross-core cases most.

| workload | mimalloc | mimalloc tuned | snmalloc |
| --- | ---: | ---: | ---: |
| `trees` | **4.76** | 7.85 | 5.82 |
| `churn` | **3.58** | 3.90 | 4.25 |
| `percore1` | **0.99** | 1.09 | 1.17 |
| `percore4` | **1.16** | 1.25 | 1.30 |
| `local20` | 0.51 | 0.47 | **0.46** |
| `local2` | 1.88 | 1.08 | **0.92** |
| `pipeline` | 1.78 | 1.09 | **0.63** |
| `pipeline16` | 1.36 | 1.16 | **0.27** |
| `fan` | 4.80 | 4.86 | **3.13** |

- **Local work:** mimalloc is 12–22% faster.
- **Cross-core work:** snmalloc is 1.5–5× faster. The more of the work
  crosses cores, the larger its lead.
- **Peak memory** is within a few MiB between the two in every row once the
  queues are short (64 entries). With 1024-entry queues, mimalloc's slower
  consumers let the queues fill, which first looked like a memory problem.
- **Tuning mimalloc** helps its cross-core rows but costs 65% on `trees`.
- The container is a VM, so single runs vary by up to 20%. An earlier
  round of single runs, and a later rerun of `pipeline16` and `local20`,
  gave the same ordering.

**Why:** in mimalloc, every remote free is an atomic push onto the page's
list, and the owner later walks that list block by block. In snmalloc, the
freeing core batches blocks per slab and per owner with plain stores and
sends a batch with one atomic operation. The owner then splices each slab's
batch in constant time (`dealloc_local_objects_fast` in
`src/snmalloc/mem/corealloc.h`).
