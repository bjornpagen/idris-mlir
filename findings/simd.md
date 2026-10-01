# SIMD by default: what Mojo's `SIMD<>` and Futhark's SOACs mean for idris-mlir

Stream "simd", 2026-10-01. The user's prompt: Mojo makes everything SIMD by
default through its `SIMD[dtype, width]` type, Futhark reaches the same
place from the other side (array combinators the compiler maps to hardware),
and MLIR's `vector` and `linalg` dialects are the giants to stand on. This
note asks what "SIMD by default" means for a compiler of an unmodified
Idris 2, and lays out the representation that gets there.

It builds on, and does not repeat:
- representation.md R5, R6, R12 (`Fin` as `index`, closed `Vect` as
  `vector<N x a>`, symbolic `Vect` as `tensor<?xa>`);
- fusion.md §1, §7.3 L1–L4 (index space → `linalg`, MLIR fuses and
  vectorizes), fusion-experiments e4 (`vector.contract`, ordered
  reduction);
- benchmarks.md (n-body SoA `vector<8xf64>` 1.36x over clang; spectral-norm
  tiled and vectorized 1.7x over clang; harmonic at its floor);
- mutable-buffers.md (arrays as `tensor`/`memref`, bufferization, the
  recursion gap), and its landed note (IOArray as `memref<?xE>`).

Status of claims: **measured** (ran it, here or in the streams above),
**read** (the pinned MLIR at llvmorg-23.1.2), **recalled** (Mojo's and
Futhark's designs from memory of their documentation and papers; treat the
details as approximate), **conjecture**.

## The questions

1. What does Mojo's `SIMD<>` buy, exactly, and which part of it is a type
   system idea and which part is a programmer's lever?
2. What is the equivalent in a language whose types we do not control, and
   whose programmers write `Vect n a`, `List a` and `LinArray a`?
3. Which Idris facts license each vectorization, and which forbid it?
4. What does the pinned MLIR give, and what is the residue?
5. What is "default" operationally: where is the width decided, what is
   the failure mode, and how is it checked?

## Short answer

- **Mojo's idea is two ideas.** (a) *The scalar is the 1-wide vector*:
  `Float64` is `SIMD[float64, 1]`, so one body text compiles at any width,
  and the width is a compile-time parameter bound late. (b) *The programmer
  holds the lever*: `simdwidthof`, `vectorize[...]`, `@parameter` loops,
  explicit shuffles and gathers. (a) is a representation principle and we
  take it whole. (b) is a language surface we do not have and must not add
  (no language change); its work is done by facts the Idris types already
  prove and by one target decision.
- **Our form of "scalar is 1-wide" is the `linalg` body.** An index-space
  computation (fusion.md §1.1) is emitted once as a `linalg.generic` whose
  body is scalar code over the element types. The upstream vectorizer
  instantiates that body at a vector width with masked tails. The body is
  the width-polymorphic text; the width is bound last, by the target, in
  the one place the target is decided (AGENTS.md). Nothing in the Idris
  source names a width, and nothing has to.
- **Futhark is the half that fits Idris.** Its SOACs (`map`, `reduce`,
  `scan`) with size types, regular arrays and uniqueness for in-place are
  exactly `Vect n a` with its ghost length, `Fin n` indices, `LinArray`
  threading and the recursion schemes fusion.md recognizes. Futhark's
  compiler decides the mapping to lanes; so does ours. Where Futhark asks
  for a size type, Idris has one; where Futhark asks for uniqueness, we
  prove it (memory-theory.md) or bufferization decides it.
- **The facts decide legality, per lane, bit-exactly.**
  - Purity and totality: lanes may run past their own exit (predication),
    and a masked-off element may be computed and discarded (speculation).
    A C compiler has to prove the absence of traps and side effects; we
    read `#idr.effects<none>` and `idr.total`.
  - `Int` wraps: integer reductions are associative, so `vector.reduction
    <add>` over lanes is exact. `Double` does not: a floating reduction
    keeps its order, so only parallel dimensions vectorize and the
    reduction stays per lane in program order (spectral-norm) or stays
    scalar (harmonic, at its floor). This is why every number agrees with
    Chez to the last digit.
  - Lengths: a closed `N` is a static shape (`vector<N x a>`, no mask); a
    ghost `n` is `tensor.dim`, the trip count and the mask bound. A `Fin n`
    index is in bounds by ValueBounds, so no check is left to vectorize
    around.
  - Uniqueness, proved or decided by One-Shot: the output is written in
    place, so vectorized stores go to the buffer that exists.
- **The default is the vector form, and a scalar loop is a reported
  miss.** Every index-space loop is vectorized at the target width or gets
  a named remark `missed vectorize(<reason>)`; `--demand vectorized=@f`
  turns the miss into `unsupported (vectorize): <reason>`. The reasons are
  an enum: a data-dependent inner trip count that is not predicable, a
  floating-point reduction along the only dimension, an effectful call in
  the body, a gather the target has no instruction for.
- **What is upstream and what is ours.** Upstream: `linalg::vectorize`
  with masking, `vector.contract`, `vector.multi_reduction`, masked loads
  and stores, `vector.gather`, `vector.mask`, the `vector` → LLVM lowering
  with reductions ordered by default. Ours: the raising to `linalg`
  (fusion.md S3/S4, the one piece with no upstream pass), the
  structure-of-arrays split of records and `Maybe`, the lane-predicated
  `while` for pure loops, the target's width, and the remarks. A dynamic
  byte shuffle is an upstream gap to report.

## 1. Mojo, read closely (recalled)

What Mojo does:
- `SIMD[dtype, width]` is the numeric type. `Float64` and `Int32` are
  aliases of width 1. Arithmetic, comparisons (giving `SIMD[bool, width]`),
  `select`, `cast`, `reduce_add`/`reduce_max`, `shuffle[mask]`, `fma`,
  `load`/`store` from pointers at a width, `splat`, `slice`, `join`.
- `simdwidthof[dtype]()` is the target's natural width, a compile-time
  value. `vectorize[body, width](n)` runs `body[w](i)` over `[0, n)` in
  steps of `width` and once more at the remainder with a smaller `w`.
  `@parameter` marks compile-time control flow and loops that unroll.
- Autotuning picks among widths and tile sizes by running them.
- The programmer writes the kernel against `SIMD`; the type system carries
  the width through generics; the hardware mapping is the backend's
  (MLIR's `vector` and LLVM).

What it buys:
1. **One text, any width.** The body is written for `SIMD[_, w]` and
   instantiated per `w`, including `w = 1`, so the scalar and vector forms
   are the same function. This is the representation principle: the width
   is a parameter, not a rewrite.
2. **Lanes are values.** Masks are `SIMD[bool, w]`; `select` is the
   branch; a lane that would exit keeps computing. The programmer accepts
   speculation by writing it.
3. **Horizontal and vertical in one type.** `SIMD[f64, 4]` is four
   independent lanes (horizontal, across an index space) or one 4-vector
   (vertical, a small closed vector); the type does not care.
4. **No analysis stands between the programmer and the instruction.** That
   is also the cost: the programmer proves safety, chooses the width, and
   writes the tail loop.

What we must not copy: the surface. Idris 2 is unmodified; there is no
`SIMD` type to offer and no `@parameter` to write. What we copy is 1–3 as
properties of the IR: one body, lanes as values, horizontal and vertical as
one mechanism.

## 2. The equivalent for Idris: facts in types, the body in a region, the width in the target

### 2.1 The width-polymorphic form is `linalg.generic`

fusion.md §1.1 already splits sequences into index spaces, streams and
survivors, and lowers index spaces to `linalg.generic` on `tensor<?xT>`
(L1). That generic's body is scalar code over the element type, written
once. The vectorizer (`linalg::vectorize(rewriter, op, inputVectorSizes,
inputScalableVecDims, …)`, Linalg/Transforms/Transforms.h:1013, **read**)
instantiates it at the given sizes, masking dynamic dimensions
(`vector.mask`, `vector.create_mask`, masked `vector.transfer_read`/
`transfer_write`). So:
- the body is Mojo's `body[w]`, with `w` left open;
- `inputVectorSizes` is Mojo's `simdwidthof`, supplied by the target;
- the masked tail is Mojo's remainder iteration, with no second body.

A closed shape needs no mask: `tensor<16xi8>` vectorizes to
`vector<16xi8>` straight. A shape smaller than the width, such as `Vect 5
Double`, vectorizes to `vector<5xf64>`, which is legal MLIR and which LLVM
widens with undefined padding lanes. That is how n-body's five bodies
become 8-lane operations with no padding logic of ours (benchmarks.md's
SoA experiment used explicit padding; the shape does it).

### 2.2 Horizontal and vertical are one rule

| Idris | fact | vector form | how |
|---|---|---|---|
| `Vect N a`, `a` scalar, N closed and small | closed index (R6) | `vector<N x a>`; chains fold to `vector.contract`, `vector.reduction` (ordered for `Double`) | static shape; e4 |
| `Vect N (Vect M a)` closed | regular by type | `vector<N x M x a>` | `vector.contract` for `mulV`/`matmul` |
| a record of k `Double`s used lane-wise, or a closed `Vect N Record` | one constructor, homogeneous fields; closed N | structure of arrays: one `vector<N x f64>` per field | Emit's decision (§4); n-body 1.36x over clang (measured) |
| `Vect n a`, n a ghost, R12's proofs | length before production; unique tails | `tensor<?xa>` → `linalg.generic` → masked `vector<W x a>` at target width W | the vectorizer |
| `LinArray a`, `IOArray a` | linear threading (One-Shot in place), or the world's order | `tensor<?xa>` / `memref<?xa>` loops → the same | task #101 |
| `[lo .. hi]`, `replicate n`, a `Nat`-driven builder, and their maps and folds | index space (fusion.md) | `linalg.generic` with `linalg.index` as the source | L1, then the vectorizer |
| `filter p` on an index space | purity of `p` | a `vector<W x i1>` mask; `select` in the consumers | fusion.md e5: one loop, no buffer |
| `Maybe a` elements | a two-constructor sum | an `i1` mask tensor beside the payload tensor (SoA) | §4 |
| a four-constructor enum (`Nucleotide`) | closed finite type | `i2` values in `vector<W x i8>`; k ≤ 32 of them packed in an `i64` key | R3/R4 packing; k-nucleotide |
| `Fin n` index | bound in the type | `index` with ValueBounds `< n`; no check | R5 |
| `Int` reduction | wrapping arithmetic | `vector.reduction <add>` over lanes: exact | the Idris semantics of `Int` |
| `Double` reduction | evaluation order is the meaning | per-lane accumulation in program order along a parallel dimension; along the only dimension, scalar | spectral-norm vs harmonic (measured) |

The two shapes Mojo expresses with one type are here two sources of the
same `vector` ops: a static shape (vertical) and a vectorized parallel
dimension (horizontal). The vectorizer and the lowering do not distinguish
them, and neither should any test: the property is "the hot loop computes
on vectors of the target width", not which source it came from.

### 2.3 Where the width lives

One place: the target entry that already decides the triple, the data
layout and the CPU (`Lower/Target.cc`, `idris-mlir-cc --cpu`). It gains
the vector width per element type (256 bits on x86-64-v3, so 4 × f64,
8 × i32, 32 × i8; 128 bits on arm64 NEON; 512 on x86-64-v4 when asked).
Every `inputVectorSizes` comes from it. No pass may hard-code a width, as
no pass may assume a page size. arm64's scalable vectors (SVE) are
expressible as `inputScalableVecDims`; macOS arm64 is NEON, fixed, so the
first arm64 target entry says 128 and nothing is scalable.

Mojo's autotuning has no equivalent here and should not: the width is the
register, and tile sizes are measured once per target and written into the
entry, as the CPU baseline is.

## 3. Legality: which facts license what

Each vectorization is a reordering or a speculation of the scalar program,
and each needs a fact. The table says which, and what happens without it.

| transformation | needs | the Idris fact that supplies it | without it |
|---|---|---|---|
| vectorizing a parallel dimension (iterations independent) | no dependence between iterations | `linalg.generic` with a parallel iterator, which raising emits only for recursion schemes whose step reads nothing another step writes (size-change on a field or an index; purity) | the dimension is a reduction or a stream: not vectorized along it |
| masked tails (computing lanes past `n`) | the body may run on an element that does not exist, as long as its result is discarded | purity and totality of the body (`#idr.effects<none>`, `idr.total`): no trap, no crash, no effect; a `div` by a lane that could be zero is a crash, so a body with a crash effect masks its loads and stores but not its arithmetic, or runs the tail scalar | the tail runs scalar |
| predication of a data-dependent inner loop (mandelbrot's `escapes`) | a lane may keep iterating after its own exit without changing its result; the exit is `any(mask)` | totality (the loop ends for every lane), purity (iterations past the exit are unobservable), and the per-lane result taken at the lane's own exit iteration (`select`) | scalar |
| reassociating a reduction across lanes | associativity | `Int`, `BitsN`, `Bool` (wrapping, exact); never `Double` | `Double`: ordered `vector.reduction` per lane along a parallel dimension; scalar along the only one |
| removing the bounds check from a vectorized access | the index is in range | `Fin n` against the same ghost `n` (R5); a loop over `[0, dim)` (ValueBounds); Idris's own `pos < max arr` test folding against `tensor.dim` | a masked access carries the check in the mask |
| in-place vectorized stores | the destination is nobody else's | One-Shot's in-place decision on a linear tensor; exclusivity for cells | a copy, or for `LinArray` the rejection (mutable-buffers §5) |
| gathers and scatters | indexable storage | contiguous arrays (`tensor`/`memref`), never cells | lists stay streams or loops |
| floating-point contraction (FMA) | permission to change rounding | never: `-ffp-contract=off`, `FPOpFusion::Strict`, the Chez diff | the fastest C's `rsqrt` route is off-limits too |

The lesson of the table: the facts that make vectorization *legal* are
exactly the ones Idris programmers already state (totality, purity,
lengths, bounds) and the ones the compiler already proves (uniqueness,
effects). A C vectorizer must infer every one and gives up on calls, traps
and aliasing. Mojo asks the programmer to assert them. We read them.

## 4. The structure-of-arrays decision

Futhark's footnote: arrays of tuples become tuples of arrays, early.
Mojo's SoA is the programmer's. Ours is a representation decision at the
array stage, made once from the facts:

- **Tensors of unboxed records and sums split by component.**
  `Layouts::components` already lists a value's runtime components. A
  `tensor<?x!idr.data<@Body>>` becomes one tensor per component; a
  `tensor<?x!idr.data<@Maybe[Int]>>` becomes a `tensor<?xi1>` and a
  `tensor<?xi64>`. Each component tensor vectorizes alone, and a loop that
  touches two components of each element gathers nothing.
- **Counted components stay a pointer tensor.** A `tensor<?x!idr.box<@T>>`
  is one tensor of references; its elements are counted on the way in and
  out, as the memref lowering does today. Vectorizing over pointers buys
  nothing and is not attempted.
- **`IOArray`'s `Maybe elem` slots** are the open question of
  mutable-buffers.md. With SoA inside the cell (the bitmap first, then the
  payload, two strides), a fill loop that writes every slot can prove the
  bitmap all-`Just` over `[0, dim)` and drop its test (conjecture: only
  for such loops). For `LinArray` on tensors the split is free, and the
  same proof applies.
- **Records as SoA vectors for closed `Vect N Record`** is the n-body
  case: five bodies become six `vector<5xf64>` and the pair updates run in
  rounds with `select` between roles, each lane in the scalar program's
  order (benchmarks-experiments.md, measured bit-identical).

What stays AoS: an `IOArray` of a record that is read whole by a borrowed
reader may be better AoS. The decision is per instance and lives in the
layout, never in a discardable attribute; measurement decides the default,
and the first default is SoA for every tensor of components.

## 5. What the pinned MLIR gives, and the residue

**Upstream, at the pin (read):**
- `linalg::vectorize` with `inputVectorSizes` and masking; a dynamic
  dimension vectorized at a fixed size gets `vector.mask`-wrapped
  transfers; `assumeDynamicDimsMatchVecSizes` for the cases a ValueBounds
  proof covers.
- The `vector` dialect: `contract`, `multi_reduction`, `reduction`,
  `shuffle` (static mask), `gather`, `scatter`, `maskedload`,
  `maskedstore`, `compressstore`, `expandload`, `scan`, `mask`,
  `create_mask`, `transfer_read`/`write` with masks, `broadcast`,
  `extract`/`insert`, `fma`. `arith` and `math` ops take vectors.
- `convert-vector-to-llvm` keeps floating reductions ordered unless
  `reassociate-fp-reductions` is set (Conversion/Passes.td:1624): the
  default is our semantics.
- The transform dialect for scripting all of this. We use the C++
  utilities directly; no schedules are shipped in the compiler.
- Target dialects: `X86`, `ArmNeon`, `ArmSVE`, `ArmSME`, `AMX`. The X86
  dialect has no dynamic byte shuffle (`pshufb`) at the pin
  (benchmarks.md), and neither has `vector`.

**The residue, each with why upstream cannot do it:**
1. **Raising to `linalg`** (fusion.md S3/S4). Upstream raises nothing from
   `scf` or from recursion; `affine-raise-from-memref` needs `affine.for`.
   The classifier of recursion schemes is ours, and it is the entry to
   everything else here.
2. **The SoA split** (§4): a representation decision from Idris types.
3. **Lane predication of a pure data-dependent loop** (mandelbrot's
   `escapes`): the vectorizer handles `linalg` bodies, not `scf.while`
   inside them; LLVM's loop vectorizer is inner-loop only. The pattern is
   small: an `scf.while` with scalar state and no memory effects inside a
   tiled parallel loop becomes an `scf.while` over `vector<W x ...>` state
   with an `i1` lane mask, `any(mask)` as the condition and `select` to
   freeze exited lanes. Totality bounds it; purity licenses it.
4. **A dynamic byte shuffle** (fannkuch's flip by `pshufb`, arm64's
   `tbl`). Not in `vector`, not in `X86`. The target-honest form is an
   LLVM intrinsic chosen by the target entry (`llvm.x86.ssse3.pshuf.b.128`
   or `llvm.aarch64.neon.tbl1`), behind a `vector`-level op of ours or,
   better, an upstream `vector.shuffle` with a dynamic mask. This is a
   feature report for `upstream/`; until then `scf.index_switch` over 16
   static shuffles is expressible and probably slower (conjecture).
5. **The width per target** (§2.3) and **the remarks and the demand**
   (§6).

## 6. "Default" as a checked property, not a hope

Mojo's default is the programmer's text. Ours has to be a guarantee of the
compiler, so it is stated as the other defaults in this repository are
(fusion.md §7.7, memory-theory.md §6.11):

- **Remarks.** Category `idr-vectorize`. `passed` names the loop, the
  dimension and the width; `missed vectorize(<reason>)` names one of:
  - `reduction-order(Double)`: the only dimension is a floating reduction;
  - `inner-loop(not predicable)`: an inner loop with effects or without
    totality;
  - `effects(<E>)`: a call in the body with effects;
  - `gather(<target>)`: an access pattern the target has no instruction
    for, left scalar;
  - `shape(unknown)`: no index space (a stream or a survivor).
- **Demand.** `--demand vectorized=Main.f` turns a miss reached from `f`
  into `unsupported (vectorize): <reason>`. No pragma; the language is
  unchanged.
- **Property.** `vector-loop=@f` for idr-expect, next to `word-loop`: some
  loop of `@f` (or a clone) computes on vectors of the target's width, and
  no scalar element op remains on that loop's path. The fixture states it
  once; op sequences are never matched.
- **Never a different number.** Every vectorized program is diffed against
  Chez as today. The floating-point rule above is what makes that diff
  pass by construction rather than by luck.

Being a subset is fine when it buys a static guarantee (the user's rule,
2026-10-01). Vectorization needs no subset: a miss is a slower program,
never a rejected one, unless demanded.

## 7. Evidence already in hand

| program | form | result | source |
|---|---|---|---|
| n-body | SoA `vector<8xf64>`, per-lane order kept by `select` | 0.232 s vs clang 0.311 s vs ours (records) 0.326 s; energies bit-identical | benchmarks-experiments.md |
| spectral-norm | `linalg.generic` [parallel, reduction], tile [4,1], vectorize, subset hoisting, int-range narrowing to i32, One-Shot | 0.032 s vs clang 0.055 s; same digits; clang cannot vectorize it (the vectorizable dimension is the outer one) | benchmarks-experiments.md |
| harmonic | `vector<4xf64>` with ordered reductions | 0.385 s vs scalar 0.257 s: the in-order `addsd` chain is the floor; `sitofp` of `vector<4xi64>` scalarized on AVX2 | benchmarks-experiments.md |
| `Vect 4 Double` chain | e4: fused generic, vectorized | `arith` on `vector<4xf64>` and one `vector.contract`; `llvm.vector.reduce.fadd` with no `reassoc` | fusion-experiments.md |
| `filter` as a mask | e5 | one loop, no buffer, 0.231 s at 1e8 vs C 0.249 s | fusion-experiments.md |
| fannkuch | `IOArray Int`, scalar | 0.563 s vs C 0.492 s; the game's fastest C is one `pshufb` per flip | this session |

Two of the six are faster than clang at equal floating-point semantics, one
is at the floor, and the three others wait on the raising. No experiment
needed a fact Idris does not prove.

## 8. The path

Ordered so that each step lands measured, and each is upstream where
upstream exists.

1. **Width in the target entry.** `Target.cc` names the vector width per
   element type for x86-64-v3; the arm64 entry will name NEON's. Nothing
   else may name one.
2. **`LinArray` on tensors (task #101)** and **`Vect` as tensors (fusion
   S4, R12)**: the index spaces that vectorization needs to exist.
3. **Raising to `linalg` (fusion S3)** for the index-space schemes: maps,
   folds, zips, fills over `[0, dim)`. The classifier is ours; from here
   on everything is upstream.
4. **Vectorize by default**: tile the parallel dimensions by the target
   width, `linalg::vectorize` with masking, `loop-invariant-subset-hoisting`,
   `int-range-optimizations` and narrowing, then One-Shot. The remark and
   the property land with it. spectral-norm is the gate: 0.032 s, same
   digits.
5. **SoA for tensors of components** (§4): n-body on `Vect 5 Body` at
   1.36x over clang is the gate; the `Maybe` bitmap proof for fill loops.
6. **Lane predication** for pure total inner loops: mandelbrot's 8 pixels
   per byte, exact per lane; the gate is bit-identical PBM output once
   byte I/O exists (task #96).
7. **The dynamic shuffle report** upstream, and a target-dispatched
   intrinsic behind it meanwhile, if fannkuch's remaining gap to the
   game's fastest C is wanted.

What this deletes: nothing of ours yet, since nothing of ours vectorizes
today. What it adds of ours: the classifier (already planned), one SoA
decision, one predication pattern, a width table, and remarks.

## Open questions

- **AVX-512 and masks.** x86-64-v3 has no lane-masked arithmetic;
  `vector.mask` lowers to masked loads/stores and selects, which is fine
  for tails. Is the 512-bit width worth a `--cpu x86-64-v4` entry, given
  that the default must run on v3 hardware? Measure on spectral and
  mandelbrot.
- **`vector<5xf64>` legalization.** LLVM widens odd shapes; does it do so
  without spills for the n-body shape, or should Emit round a closed
  `Vect N` up to the width itself? The benchmarks experiment padded by
  hand; the shape form is untested.
- **Where predication stops.** A pure loop with a crash effect (`div` by a
  lane value) cannot be speculated. Is "mask the division's divisor to 1
  on inactive lanes" worth a rule, or does such a loop stay scalar?
- **Gathers on x86.** `vector.gather` of bytes has no instruction on
  x86-64-v3 and lowers to scalar extracts; reverse-complement's reversed
  read is a reverse consecutive access that LLVM's loop vectorizer handles
  with shuffles. Which loops should the raising leave to LLVM rather than
  vectorize in MLIR? Rule for now: vectorize in MLIR only where the body
  has a parallel dimension LLVM cannot see (outer loops, SoA records);
  leave inner contiguous loops to LLVM's vectorizer, which already runs.
- **Programmer intent.** Mojo's lever is explicit. Should a closed
  `Vect 16 (Fin 16)` be *guaranteed* a `vector<16xi8>` representation (the
  README's "guaranteed costs"), or only remarked? The demand option covers
  it without a language change; a guarantee needs a decision on which
  shapes are promised.
