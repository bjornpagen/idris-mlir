<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0017: the heap as Apple's data memory-dependent prefetcher reads it

**Status:** open (2026-10-19).
- **Built:** the heap's first block is one 4 GiB region aligned to 4 GiB
  (efe0ad36; `HeapConfig` in `runtime/Alloc/Cells.cpp`), past which
  snmalloc grows as it does with no bound (1445d894). `tests/heap-region`
  passes on arm64 macOS. That is D7.
- **Next:** P0, the native measurement that can withdraw every speedup
  claim here, and then P1, the stack beside the heap (D9) and the census
  D10 reads. Both run on the arm64 macOS build machine, a native Apple
  M2 Max (`kern.hv_vmm_present` 0, two performance levels, *measured*
  2026-10-19), and wait on nothing in the tree. §3's numbers were taken in a macOS guest; its C
  sources and the audit's were scratch and are gone, so P0 rebuilds the
  pairs from §3's method.
- **AFTER-SELF:** P2 lands with 0009's stages 3 and 4, P3 with 0012's
  gates, and P4 with 0006's G1.

**Sources.**
- GoFetch (Chen, Wang, Shome, Fletcher, Kohlbrenner, Paccagnella, Genkin,
  USENIX Security 2024): §2, §4 in full, §8, footnotes 2 and 22.
- Augury (Sanchez Vicarte et al., IEEE S&P 2022): §II-E, §V-F and §VI.
- The runtime's DMP audit: efe0ad36's message.

Neither paper is in `sources/` yet, and P0 snapshots both. `L/` is the
pinned LLVM, `.toolchain/llvm-project/llvm/`. Claims are marked *read*,
*measured*, *recalled*, *conjecture* or *decision*.

## 1. What the DMP does (*read*)

- **Where.** Only the performance cores have it (GoFetch §2; Augury
  §II-E). M2 and M3 respond to every access pattern that M1 does
  (GoFetch §4.5).
- **When.** A load that fills a line into L1, from DRAM or from L2,
  triggers it (§4.2). A store never does (fn. 2). A scanned line is
  marked "do not scan" until it has left both L1 and L2. A per-core
  history filter of about 128 entries, reset after 100 µs idle, drops a
  target that was fetched recently (§4.2).
- **What it scans.** It scans the one 64-byte L1 line that was filled,
  and not the other half of the 128-byte L2 line. Every 8-byte-aligned
  word in that line is a candidate (§4.2, §4.4; Augury §VI-A4: a
  misaligned pointer is never followed).
- **Which words it follows.** It follows a word whose bits 32 to 55 equal
  the bits of the word's own address, so the target and the word lie in
  one 4 GiB-aligned region. Bits 56 to 63 are ignored, which is ARMv8's
  Top Byte Ignore (§4.3, Figs. 5 to 7).
- **What it fetches.** It fetches the target's 128-byte L2 line and the
  next line, into L2 and not into L1. It walks the page tables and fills
  the TLB on the way (§4.3, §4.4; Augury §VI-C).
- **How deep it goes.** One level. A fetched line sits in L2 and is
  scanned only when a load brings it into L1. Augury tested for a
  two-level prefetcher and for an index-based one (`B[A[i]]`) and found
  neither (§V-F, "Results").
- **What turns it off.** Setting DIT turns it off on M3, but not on M1 or
  M2 (fn. 22). Efficiency cores have no DMP.

Augury describes the DMP as prefetching ahead through a streamed array of
pointers, up to 64 KiB ahead, stopping at the array's 2 MiB boundaries.
That is GoFetch's mechanism seen through the stream prefetcher: lines the
stream prefetcher brings in ahead of the loop are scanned as they arrive
(*conjecture*). Augury also reports that macOS addresses from
0x280000000 to 0x7fe840004000 cannot be prefetched. GoFetch's sweep inside
that range found the region rule instead, and §3's effects all occur at
0x70_0000_0000 to 0x7b_0000_0000, inside Augury's range. So the region
rule is the model this proposal uses.

What follows for a compiler (*conjecture*, which §3 tests): the DMP gives
a load one line of lookahead. Every reference in the line a load fills has
its target fetched at that moment. That pays where the program follows the
reference later than it loads the line holding it. It pays nothing where
the program follows the reference at once, as in a pure pointer chase.

## 2. What the compiler and the runtime decide that the DMP reads (*read*)

| Decision | Where | What the DMP sees |
|---|---|---|
| A reference's bits | `components` (`lib/IR/Layout/Components.cpp`): a value that holds a reference is `!llvm.ptr`, the cell's address. A big's word is an odd small integer or the bignum cell's address, untagged (`runtime/idris_rt.h`) | a raw address, which it follows; a small integer's upper 32 bits are 0 or all ones, never a heap region |
| Field order | `cellOf` (`lib/IR/Layout/Layouts.cpp`): the header, then the count word or the group where one is needed, then every counted component (the object slots), then the rest, most aligned first | every reference sits in the words right after the header |
| Cell size | the size rounded to a word. snmalloc's classes step by 8 bytes up to 64 (`SNMALLOC_MIN_ALLOC_STEP_SIZE`, `runtime/CMakeLists.txt`), then go four to a doubling, and an object sits at a multiple of its class from its slab's start | the 16-, 32- and 64-byte classes never cross a 64-byte line; the 24-, 40-, 48- and 56-byte classes cross one at some positions |
| Arrays | an element is a one-field cell less the header, object slots first; one too large for the header's fields is boxed, one reference (`Layouts.cpp`); arrays of records are columns (`include/idr/Transforms/Columns.h`) | an array of boxes, or a counted column, is Augury's array of pointers, 8 bytes apart |
| Sums held in place | a tag plus shared slots; a counted slot that a constructor does not use is NULL (`include/idr/IR/Layout.h`) | a zero word, never a candidate |
| Closures, suspensions, dictionaries | a closure is a constructor of a sum held in place, boxed only when its sum contains itself (`lib/Transforms/Defunctionalize/`, `lib/IR/Layout/Fit.cpp`); a suspension is a memo cell laid out as a box; specialization leaves no dictionary at a monomorphic site | a closure is usually no reference at all; a thunk's captures come first |
| The heap's region | `HeapConfig` (`runtime/Alloc/Cells.cpp`): snmalloc's standard configuration, whose global range is given one 4 GiB-aligned region at the first allocation; past it snmalloc grows from its platform layer | before efe0ad36 the heap began in the executable's region and left it after about 800 MiB, and 47% of cell-to-cell references crossed at 1.3 GiB live. After: no crossing below 4 GiB (*measured* by the audit) |
| The stack, and stack cells | the program runs on one reservation of 64 GiB (`stackSize`, `runtime/Start/Runner.cpp`), an mmap with no address hint (`rt::platform::reserve`), so it lies in regions of its own. idr-stack builds a box that does not escape (≤ 256 bytes; ≤ 1024 bytes per frame) in the frame (`lib/Transforms/Stack/Stack.cpp`) | every reference between a frame and the heap crosses regions (D9) |
| Static data | persistent cells in the executable image (`lib/Conversion/StaticData.cpp`), in region 0x1 on arm64 macOS (the audit) | a heap cell's reference to one always crosses; a constant's reference to another constant does not (D10) |

The stack cell rule itself needs no change (*conjecture*, from §1): a
stack cell is built by stores, which never trigger a scan, and read while
its frame is in L1. Frames matter as a whole, not their cells. A deep
recursion outgrows the caches and reads its frames back on the way out,
and a frame holds the references its caller keeps across the call. §3
measures that case.

The dying list is the only tagged word in the runtime: it threads dead
cells through their count and tag, and it is never followed (the audit's
table, in efe0ad36's message). It is a LIFO of cells just touched, so the
DMP has nothing to add (*conjecture*).

**Static counts** (*measured* 2026-10-16, at de7f12d9). The frontend on
Chez wrote `--core` for 288 of the 309 programs then in `tests/programs`
(the other 21 were refused then). A model of `Fit.cpp`, `cellOf` and the
sum slots, applied to every data type in the dumps, gives the following:
- **Constructors.** There are 135 distinct boxed constructors with fields
  (94 from libraries, 41 the programs' own). The 95 with no field are
  static cells and are not counted.
- **Size classes, modelled with 16-byte steps.** 117 of the 135 (87%) fall
  in the 16- and 32-byte classes. 10 fall in the 48-byte class: rbtree's
  `Node`, SortedMap's `Branch3` and a cons of a pair. 8 are larger, and 6
  of those are the layout-limit fixtures, with 255 to 3,841 slots.
- **The header's line.** Of the 129 constructors with at most 7 object
  slots, 97.5% of placements have every slot in the header's 64-byte
  line. Every miss is in the 48-byte class. The runtime's classes step by
  8 bytes, not the 16 this model took, so 24-, 40- and 56-byte cells
  exist and some of their placements miss too: P1's census recomputes the
  share on the real classes.
- **Share of references.** 207 of the 355 components of those cells (58%)
  are references, and 62 of the cells hold nothing else.

Those programs are small. The self-hosted frontend is the large
pointer-heavy workload: 0011 §2 puts 88% of stage 0 in pointer-chasing
phases. Its `Term.App` holds an `FC` in place, so it is the header, three
object slots, four `Int`s and two tags: 72 bytes in the 80-byte class. Its
slots stay within the first 32 bytes, and three of its four placements keep
all of them in the header's line (*conjecture*, by hand; the self module's
Core was not dumped).

## 3. Measurements (*measured*, in a guest)

**Method.**
- **Machine.** `sysctl machdep.cpu.brand_string` is "Apple M2 Max
  (Virtual)": a macOS guest (`kern.hv_vmm_present` 1) with 8 vCPUs, 32
  GiB and 16 KiB pages. The guest reports one performance level
  (`hw.nperflevels` 1), so it cannot choose a core type, and the host
  schedules the vCPUs. Each program sets `QOS_CLASS_USER_INTERACTIVE` on
  its thread anyway.
- **Load.** Each table has two columns. "Quiet" was measured at a load
  average of about 4. "Loaded" was measured at 8 to 19, with the swarm's
  Chez processes running.
- **Build.** Apple clang 21 at `-O2`. Four C programs (the array and list
  families, the tree family, the stack pair, the Top Byte Ignore load);
  their sources were scratch and are gone, and P0 rebuilds them from this
  method.
- **Placement.** The cells are 2^21 cells, in random order, in one
  4 GiB-aligned region of an mmap. An array of references (16 MiB) lies in
  that region or the next. Each run is preceded by a 256 MiB flush.
- **Rounds.** Each family runs every variant once per round, in shuffled
  order, for 7 to 15 rounds. "Ratio" is the median, over rounds, of a
  variant's time over the first variant's time in the same round. Within
  one run, most variants' quartiles span ±3 to 10% quiet, with outliers,
  and ±10 to 25% loaded. Nothing under 5% is claimed.
- **The data control.** A reference is stored as `address ^ key` and the
  loop XORs the key back off before it dereferences, so the variants of
  one loop run the same instructions and differ only in data:
  - key 0: raw;
  - key 1 or 7: a low tag;
  - bit 56: a top-byte tag;
  - bit 48 or bit 35: the word fails the region test;
  - the array stored in the next region.
- **The position control.** The stack test changes only where the
  thread's stack lies: in the cells' region or in the next one, with the
  same code and the same data.
- **Work.** "Work" is the number of dependent multiply-adds per element.
  It stands for a loop body heavy enough to keep the out-of-order window
  from covering the misses.

**The DMP fires in this guest, and GoFetch's model holds bit for bit.**
- **Data.** Raw words, low tags and top-byte tags are followed. Bits 48
  and 35, and a reference held in another region, are not.
- **Position.** Two runs with identical code and data differ by 1.20 to
  1.28× when only the stack's region changes (below). A masked word with
  the stack in the cells' region reads the same as a raw word with the
  stack elsewhere.

No mechanism but a value prefetcher that checks regions explains both
controls.

The audit found no DMP in this guest, with two other designs:
- GoFetch's Listing 1: one load per line, a 100 µs wait, then a dependent
  chain through the targets;
- a dereferencing loop that does no work per element.

The second design reads flat for every key here too (the work-0 column),
even while the DMP fires. The first separates the scan from the use by a
wait, during which the host may move the vCPU away from the L2 that holds
the prefetches (*conjecture*). The guest is not a native machine either
way, so P0's discriminator runs natively.

| Array of references, ratio to raw | work 0, quiet | work 16, quiet / loaded (3 runs) | work 64, quiet / loaded |
|---|---|---|---|
| low tag `\|1`, `\|7` | 1.01 – 1.05 | 0.98 / 0.94 – 1.13 | 1.00 / 0.93 |
| top-byte tag | 1.01 | 1.00 / 0.99 – 1.13 | 0.98 / 1.07 |
| bit 48 or bit 35 (fails the region test) | 0.98 – 1.01 | 2.32 – 2.53 / 1.14 – 1.41 | 2.62 – 2.67 / 1.23 – 1.24 |
| the array in the next 4 GiB region | 1.03 | 2.30 / 1.19 – 1.46 | 2.65 / 1.26 |
| a 32- or 64-bit index, scaled by a shift | 0.63 – 0.70 | 2.35 – 2.42 / 1.15 – 1.24 | 2.65 / — |
| raw, with a software prefetch 16 ahead | 0.75 | 0.44 / 0.25 – 0.29 | 0.76 / 0.30 |
| region bit, with the same prefetch | 0.74 | 0.48 / 0.24 – 0.31 | 0.73 / 0.32 |
| 32-bit index, with the same prefetch | 0.71 | 0.52 / 0.24 – 0.31 | 0.75 / 0.31 |
| floor: every reference to one cell | 0.12 | 0.29 / 0.13 – 0.17 | 0.73 / 0.28 |

At work 0 the index is faster than raw because its array is half the
bytes. An index scaled by a multiply the C compiler could not fold measured
1.7 to 3.4×. That is an artifact of the harness: a compiler with a static
stride emits the shift.

| Lists of 2^21 cells, ratio to raw | work 0, quiet / loaded | work 64, quiet / loaded |
|---|---|---|
| spine only, next at +8, region bit | 1.01 / 0.99 | 0.99 / 0.98 – 1.03 |
| spine at a 128 B stride, next at +72, raw | 1.22 / 1.22 | 1.12 / 1.15 – 1.18 |
| a cons of a box (the head read), region bit | 0.98 / 1.00 | 1.46 / 1.33 – 1.41 |

| Tree of 2^21 − 1 nodes, depth first; ratio to the 64 B node, R at +16, read after the left subtree, raw | work 0, quiet / loaded | work 32, quiet / loaded |
|---|---|---|
| same node, region bit | 1.20 / 1.03 – 1.20 | 1.20 / 1.07 – 1.08 |
| both children read at the match, raw / region bit | 0.92 / 1.11 | 0.95 / 1.16 |
| 128 B node, R at +16, raw / region bit | 1.06 / 1.23 | 1.02 / 1.24 |
| 128 B node, R at +72 (a line touched late), raw / region bit | 1.29 / 1.31 | 1.27 / 1.33 |
| nodes half in the next region | 1.15 / 1.22 – 1.25 | 1.14 / 1.13 – 1.20 |

| Recursion 2^21 deep, each frame keeping a payload reference across the call (quiet) | work 0 | work 16 | work 32 (2 runs) |
|---|---|---|---|
| the stack in the next region, raw | 1.03 | 1.20 | 1.28 |
| the stack in the cells' region, words masked | 1.01 | 1.20 | 1.26 – 1.28 |

**Size classes.**
- **48 B against 64 B cells.** These are reached through an array of
  references at work 64, reading +8 and +40, so half of the 48-byte cells
  cross a line. Over 15 quiet rounds the 48-byte cells run at 1.00× of
  the 64-byte cells. Two shorter runs read 0.89 and 1.20, inside their
  wide quartiles.
- **40-byte tree nodes at a 48-byte stride against a 64-byte one,**
  quiet, at work 32. Read late: 1.00× against 1.07×. Read at the match:
  0.98× against 0.91×.
- **Neither size wins consistently,** within the 7 to 10% the noise
  allows.

**Top Byte Ignore.** A load through an address with top byte 0x5A returns
the cell's value in user space on this guest.

**What the numbers say** (in this guest; P0 decides natively):
- **The DMP has no effect when out-of-order execution already overlaps
  the misses** (every key within 5% at work 0). When the body is heavy
  enough that it cannot, the DMP is worth 2.3 to 2.7× through an array of
  references on a quiet machine, and 1.14 to 1.46× under load.
- **It does nothing for a list spine,** which is a dependent chain. It is
  worth 1.33 to 1.46× when each cons holds a reference that the body
  follows.
- **On a depth-first tree it is worth about 20% quiet** (3 to 20% loaded),
  but only while the reference read late sits in the line that the first
  load filled. In a line touched late (R at +72), the DMP's share falls
  to 1 to 7%, and that layout runs 1.21 to 1.25× slower (quiet) than R in
  the header's line at the same stride.
- **The stack's region matters in deep recursion:** 1.20 to 1.28× at
  work 16 to 32.
- **A software prefetch 16 elements ahead beats the DMP alone** wherever
  the compiler knows the access stream: by 1.3 to 2.3× quiet and 3.4 to
  4.0× loaded. It does so on raw references, DMP-blind words and indices
  alike. At work 64 on a quiet machine it reaches the compute floor.
- **Crossing a line costs nothing consistent.**
- **An index is a DMP-blind reference,** measured equal to one.

x86_64 Linux has run none of it. There, every key is expected to read 1.0
(*conjecture*: no DMP of this kind; GoFetch §4.5 finds that Raptor Lake's
DMP fires only on Augury's first pattern).

## 4. What would break the DMP, ruled out as the compiler grows

Each of these is measured (§3) or read (§1):
- **Pointer compression,** a 32-bit reference relative to a base: the
  same as an index, DMP-blind. Ruled out by AGENTS.md, which keeps heap
  references raw.
- **Offsets in place of pointers:** relative offsets, or ids into a side
  table. DMP-blind. Ruled out for references (D1). Where a layout holds
  ids by design, as 0011's tables and 0012's packed internals do, D4 says
  what pays for the loss.
- **Tags in bits 32 to 55,** such as NaN boxing or a tag above bit 47:
  measured DMP-blind. Ruled out.
- **Top-byte tags.** The DMP ignores the top byte, and arm64 macOS loads
  through one in user space (measured). x86-64-v3 has no Top Byte Ignore
  (*recalled*: Intel's LAM and AMD's UAI are newer than the baseline), so
  each dereference there would need a mask. That would make the reference
  one representation per target, which the targets rule forbids. Ruled out.
- **Low-bit tags.** Measured transparent to the DMP, since a tag within
  the line leaves the target line unchanged. AGENTS.md keeps references
  untagged anyway. This proposal records that the DMP is not the reason:
  a proposal for low tags would have to be argued on other grounds and is
  not made.
- **References across 4 GiB regions:** measured DMP-blind. Fixed for
  heap to heap (efe0ad36). D9 and D10 decide the stack and static data.
- **Setting DIT** turns the DMP off on M3 and later. Nothing in the tree
  sets it today (*read*: `runtime/` names `dit` only as a CPU feature bit,
  `cpu_aarch64.h:35`). D6 keeps it that way.
- **Running on an efficiency core:** no DMP. That is the scheduler's
  business. A background QoS confines a thread to the efficiency cores
  (*recalled*), and the runtime never lowers its thread's QoS (D6).

## 5. Decisions

- **D1. A reference is the raw address of its cell, on every target and
  in every layout, 0012's included.** No compression, no offsets in its
  place, no tag in any bit. *Decision.* Reasons:
  - one representation on every target;
  - it costs nothing on x86;
  - in the guest the DMP is worth up to 2.7× through an array of
    references, up to 1.46× through a cons of a box, and about 20% on a
    tree (§3).

  This restates AGENTS.md and extends it, in writing, to layouts not yet
  built.
- **D2. Every object slot follows the header, and no cell is padded to a
  line.** The first part is built (`cellOf`). With it, 97.5% of corpus
  placements hold every reference in the line that the first load fills
  (a match reads the tag in the header; a dup or drop reads the count),
  a share P1's census recomputes on the runtime's 8-byte classes (§2).
  Padding cells of 33 to 48 bytes to 64 buys nothing consistent (§3,
  "Size classes") and costs a third more memory than the 48-byte class.
  *Decision*, measured. The threshold to revisit: a corpus or bench
  program whose borrowed traversal runs at least 1.1× faster with its
  cells at 64 bytes on native arm64 and no slower on x86.
- **D3. A gather the compiler structures prefetches its targets.** When a
  loop streams an array of references, or an array of indices into a
  table, and follows each one, the compiler prefetches the element some
  distance ahead.
  - **Why.** It is the one mechanism that beats the DMP where the
    compiler knows the stream (1.3 to 4.0×, §3). It also makes an index
    cost what a reference costs, and it helps x86, which has no DMP, more
    than arm64.
  - **What upstream does today.** Nothing for this case. LLVM's
    LoopDataPrefetch handles strided addresses only. It runs for apple-m1
    with a distance of 280 instructions and a minimum stride of 2048
    bytes, and not at all for x86-64-v3, whose TTI gives no distance
    (*read*:
    - `L/lib/Transforms/Scalar/LoopDataPrefetch.cpp:213-218, 311`;
    - `L/lib/Target/AArch64/AArch64Subtarget.cpp:158-172`;
    - `L/lib/Target/AArch64/AArch64Options.td:279`).
  - **Where it lives** (*decision*): a pass of ours in the arrays stage,
    after structuring. An index gather gets upstream's `memref.prefetch`
    on the table. A reference gather needs one op of ours, `idr.prefetch`
    on a box, lowered to `llvm.intr.prefetch`, since no upstream op
    prefetches a reference that is not a memref. Rejected: an upstream
    patch teaching LLVM's LoopDataPrefetch indirect loads (Ainsworth and
    Jones, CGO 2017, *recalled*), because the gather is structure in our
    IR that LLVM would have to recover, and x86's TTI would need a
    distance too.
  - **Its distance** (*decision*): one number for every target, 16
    iterations from §3, unless P2 measures a loss over 5% against the
    best distance on some target; then it becomes a fact of each entry.
  - P2 builds it, behind its measurement.
- **D4. The 0012 rule** (§6): every reference a layout holds is D1's; a
  layout that holds indices instead is chosen only where its gate is met
  against cells with the DMP active, and its gathers carry D3's prefetch.
  *Decision.*
- **D5. No fact "has a DMP" exists, in the target's entry or anywhere
  else, and no layout or pass branches on whether the target prefetches
  values.** *Decision.* Reason: the targets rule.
  - Every choice here is one representation for every target (D1, D2).
  - Or it is one mechanism, with at most a number in the entry (D3's
    distance).
  - Or it is one address-space layout, the same code on every target
    (D7, D9).
  - Or it is measured on every target, with the DMP inside the arm64
    baseline (D4).
- **D6. The runtime never sets DIT and never lowers its thread's QoS.**
  Each would turn the DMP off silently: DIT on M3 and later, a background
  QoS through the efficiency cores. *Decision.* This is the runtime's
  rule. It is written here because it is what keeps D1's benefit, and
  0020 inherits it: Rust code that sets DIT restores it before it returns.
- **D7. The heap lives in one 4 GiB-aligned region while it fits.** Built
  (efe0ad36; `tests/heap-region`). A larger heap grows from snmalloc's
  platform layer, with no bound.
- **D8. An arm64 bench record carries a DMP calibration:** §3's
  array-of-references pair at work 64, raw against the region bit, run
  beside the bench. A record whose pair reads under 1.1 had no DMP (an
  efficiency core, DIT, or another machine) and is not compared with
  records that had one. *Decision.* Reason: the DMP is part of what an
  arm64 number means, and the bench's spread already reaches 15%
  (`bench/README.md`).
- **D9. The stack's top lies in the heap's region,** answering the
  audit's question (a).
  - **The design.** The stack is one reservation of 64 GiB
    (`runtime/Start/Runner.cpp`), far larger than the region, so the
    region cannot hold it; its top can. The runner
    (`idris_rt_run_on_stack`, which programs and the compiler's tools
    share) makes one reservation of the alternate signal stack, the guard,
    the stack and the heap's region, laid out so that the region is
    4 GiB-aligned and the stack's top `budget` bytes lie at its bottom:
    frames within `budget` of the top share the heap's region, and deeper
    frames lie below it. Before `fn` runs, it gives the rest of the region
    to `HeapConfig`, which takes it instead of reserving its own; a heap
    whose first allocation came earlier keeps its own region, as today
    (*conjecture*: none does, which P1's test checks).
  - **The budget** (*decision*): 1 GiB, which leaves the heap 3 GiB of
    the region. A recursion a million calls deep with frames of up to a
    kilobyte stays inside it. Revisited if P1's census finds a bench
    program whose live heap lies between 3 and 4 GiB.
  - **Why.** §3: 1.20 to 1.28× on a deep recursion whose frames hold heap
    references. The position control rules out any other cause: the same
    data and code, with only the stack's region changed. Those are the
    references a non-tail recursion over a structure keeps (the element
    its caller conses or adds on the way back). `foldlM` over a million
    numbers is one such recursion, a million calls deep
    (`tests/foldlm-deep`).
  - **The cost.** The heap's room in the region shrinks by the budget, so
    a heap of 3 to 4 GiB grows out of the region a gibibyte sooner.
  - **Target neutrality.** It is address-space layout, the same code on
    every target. The stack cells inside frames need nothing further.
- **D10. References from the heap to static data stay crossing,**
  answering the audit's question (b). *Decision.* Reasons:
  - **Room.** The executable's region cannot hold the heap. On arm64 macOS
    it has about 800 MiB free above the image (the audit). Starting the heap
    there and growing out is the layout the audit measured at 47%
    crossings with 1.3 GiB live, and heap to heap is the edge that
    structures are made of.
  - **The targets.** What heap cells refer to in static data is
    persistent constants: the fieldless constructors at the end of every
    list and tree, literal strings, constant arrays. Each is shared by
    every use, so a hot one is in cache and the DMP's fetch would hit
    anyway (*conjecture*).
  - **Constants among themselves.** A constant's references to other
    constants stay in the image's one region and are followed.
  - **When to revisit.** If P1's census of live references, sorted by the
    target's place (heap, stack, static), finds a bench program with more
    than 10% of its heap's references going to static data, that program
    is measured with its constants rebuilt on the heap (a C model, as in
    §3). The representation is reconsidered only if that model wins by
    1.1× natively.

## 6. How it relates to 0012, 0009 and 0011

The tension is real but narrow. 0012 removes references where streaming
pays (packed preorder buffers, columns of scalars), and the DMP needs
references. The two meet in four cases, and in each the choice is the
same on every target:

| Access | Layout (0012) | The DMP | Rule |
|---|---|---|---|
| a tree built once and traversed whole | packed, no internal references (D2, D7) | not needed: a preorder walk is a stream, and the stream prefetcher follows addresses, not values | agreement. The references a buffer holds to cells outside it are D1's, so the DMP follows them as the cursor streams |
| a collection of boxes traversed in order | columns: a counted leaf is an array of references (F2, F3) | Augury's own pattern, plus D3's prefetch | agreement: columns win on every target. A list spine gets nothing from the DMP (§3), which is one more reason to hold it as columns |
| sharing, random access, a DAG | cells (D2's "sharing selects cells", "random access selects cells") | one line of lookahead per touched line, with every reference in the header's line (D2 here) | agreement |
| a table keyed by ids (0011's tables, 0012's id columns) | indices | blind, measured equal to a masked reference | the one disagreement. D4: an id gather carries D3's prefetch, and a gate against cells is read with the DMP active |

What this asks of 0012, to be written there when its stages start (the
text here governs until then):
- F4's gate ("1.3× faster than cells on both targets") already measures
  against cells on arm64. Cells there include the DMP's 3 to 20% on a
  tree, so packing must clear a higher bar on arm64. That is the right
  bar. The run needs D8's calibration.
- F3's gate names no target. D4 reads it on every target.
- F2's filler for an unused counted slot is neutral to the DMP: a
  persistent constant in the image is not in the column's region (D10),
  and NULL is no candidate.
- D7's "no tagged pointers" stands, now with a measured reason.

**0009.** §20 item 1 asks for an array of boxes priced. §3 is that price in
C in an arm64 guest. The lever is D3's prefetch, not a second path, so
D17's one path for counted elements stands. D3 lands where 0009 §7 puts
gathers: in the arrays stage, on structured loops, with target facts read
from DLTI as 0009's D20 and D29 read theirs.

**0011.** The self-hosted frontend's trees get the DMP on arm64 today.
0011's tables replace references with typed ids (D1 there), which the DMP
cannot follow. 0011's gates are ratios to O0, measured on every target
(D0 there), so the DMP is inside the arm64 baseline already. Where a table
stage loses on arm64 only, D3's prefetch on the id gather is the fix to
try first.

## 7. What stays target-neutral

Everything this proposal changes or keeps:
- the reference's bits (D1);
- the cell's field order and size (D2);
- the prefetch, an LLVM intrinsic every target lower (D3);
- the 0012 rule (D4);
- the runtime's rules (D6, D7, D9, D10): DIT does not exist on x86, and
  one 4 GiB region for the heap and the stack's top is address-space
  layout, free where no DMP reads it.

The one machine-specific fact is that Apple's CPUs have a DMP (arm64
macOS, and arm64 Linux on Apple Silicon), and no code reads it (D5). D3's
distance becomes a fact of the target's entry only if one number cannot
serve every target (D3).

## 8. Staged plan

| Stage | Needs | Content | Discriminator, and the test that shows it |
|---|---|---|---|
| P0 | nothing | §3's pairs rebuilt from its method (array, list, tree, stack) with GoFetch's activation test (one load per line, a 100 µs wait, a dependent chain through the targets), committed with their results as a record, `bench/records/<date>-dmp-darwin-arm64/`, since a directory of `bench/` is a benchmark. GoFetch and Augury snapshotted under `sources/papers/` (`chen-2024-gofetch`, `vicarte-2022-augury`), a download the owner approves when it is made. Run natively on the arm64 macOS build machine (M2 Max), on an M3 or later when one is at hand, and on x86_64 Linux once 0002's machine exists | **Native arm64:** raw, low tags and top byte within 5% of each other; the region-test failures ≥ 1.5× at work 64; the stack pair ≥ 1.1× at work 32; the activation test at L2 latency for raw, low tag and top byte and at DRAM latency for no reference, bit 48 and the next region. **x86:** every key within 5% of raw. **If native arm64 shows no effect,** every DMP claim in §3 and §5 is withdrawn and recorded so: D1 and D2 stand on their other reasons, D3 on its own measurement (it gains on every target), and D9 is dropped |
| P1 | P0 native | D9 in the runtime: the runner's one reservation, the stack's top `budget` bytes in the heap's region, the rest of the region to `HeapConfig`. The census D10 and D2 read: live references at a program's end by the target's place (heap, stack, static), and every cell's placement against the 64-byte line, in a test build | `tests/heap-region` extended: frames within the budget and the first cells share bits 32 and up, and a frame deeper than the budget does not. The stack pair of P0 linked against the runtime (`idris_rt_run_on_stack`, cells from the runtime's allocator) reads as the mmap version did. The census run on the bench set, D10's and D2's rules applied, and the record committed |
| P2 **AFTER-SELF** | 0009's stages 3 and 4 (structured gathers) | D3: a prefetch of the element `d` ahead in a structured loop that follows references or indices | Benchmarks, each a `bench/` directory with its `main.c`: a map with work over an `Array` of boxes, a gather through an array of `Fin n` into a table, and a fold over a cons of boxes for the control. Each must run ≥ 1.3× faster on every target, and no bench program may run > 2% slower (0009 D35). An `idr-expect` property `prefetched=@f`, stated as a pass guarantee as `fused` is, shows the pass fired |
| P3 **AFTER-SELF** | 0012's F2 to F4 | D4: 0012's gates read on every target with D8's calibration; id columns carry P2's prefetch | 0012's own fixtures and gates |
| P4 **AFTER-SELF** | 0006's G1 | D8 in `bench/run.sh --record` on arm64 | the calibration line in each arm64 record; a record without the DMP is marked and not compared |

DIT as an instrument (`IDRIS_RT_DIT=1`, setting DIT for the program's
thread on arm64) would be the one whole-program A/B of the DMP, but only
on an M3 or later, since DIT does not turn the DMP off on M1 or M2.
*Decision:* not built while the machines at hand are M2.

## 9. Rejected alternatives

- **Padding cells to 64 bytes, or aligning them to 128:** measured to buy
  nothing consistent (D2).
- **Ordering object slots by when they are read** (a right child before a
  left one): the header's line holds every slot in 97.5% of placements
  already. Reading late is the borrowed traversal's choice, and moving
  fields out at the match (owned) removes the case (§3: both children read
  at the match).
- **Top-byte or high-bit tags, NaN boxing, 32-bit references:** §4.
- **A target fact "has a DMP," or a per-target layout:** D5.
- **The heap started beside the executable:** the layout before
  efe0ad36, which crossed on half the references of a large heap (D10).
- **Prefetching every reference a cell holds:** the DMP already does this
  for free on arm64, and on x86 it would be the compiler's guess about a
  traversal it cannot see.
- **Pinning programs to performance cores:** macOS gives user code no
  affinity, and the QoS is the user's and the system's. D6 only keeps the
  runtime from lowering it.

## 10. Rules of AGENTS.md it keeps

- **Raw, untagged heap references** (D1), with the DMP's measured reason.
- **Four first-class targets with nothing per target outside the entry**
  (D5). The only facts that may enter an entry are a prefetch distance
  (D3) and 0009's L1 size.
- **OS calls behind the runtime's platform layer** (D9's reservation),
  and intrinsics through LLVM with no inline asm (D3). DIT, if ever set,
  is set through the platform layer (§8).
- **No pass refuses anything here.** D3 is an optimization, so skipping it
  leaves the program as it was.
- **Tests check behaviour:**
  - P1's test checks a placement;
  - P2's property is the pass's guarantee;
  - the speed claims are bench records, not tests.
- **No oracle:** every measurement here compares a layout with itself
  under a data-only or position-only change, or a program with its C
  counterpart.

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- D3's prefetch is a step of the schedule library at the lowered stage:
  `llvm.intr.prefetch` for a reference, `memref.prefetch` for an index
  gather, no `idr.prefetch`; "d iterations ahead" through
  `scf::pipelineForLoop` (`transform.loop.pipeline`) if its hook admits a
  prefetch stage (P2 checks), else one transform op beside
  `vectorize_lanes`; the distance a DLTI key.
