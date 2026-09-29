# Benchmarks stream: experiments

The runs behind `findings/benchmarks.md`. All of them are in
`$R = scratchpad/research/bm/`, run with the built compiler under the shared
lock. Nothing in the repository was changed. Timings are wall clock, the
best of 5 or 7 runs (`date +%s.%N`), on the 4-CPU development container.
They include process start-up (about 1 ms).

## How

```sh
. $R/env.sh      # ROOT, R, CC=pinned clang, ICC=idris-mlir-cc, OBJDUMP, comp()
comp() { flock -s $ROOT/build/.tree.lock timeout 600 $ROOT/tools/compile.sh "$@"; }
# ours (x86-64-v3, LLVM O3 with the runtime linked)
(cd $R/b/nbody && comp --io Main.idr nbody)           # -p base for the kernels that need it
# clang, as bench/run.sh builds it, and at equal ISA and FP semantics
$CC -O2 bench/c/nbody.c -o c.exe -lm
$CC -O2 -march=x86-64-v3 -ffp-contract=off bench/c/nbody.c -o c3s.exe -lm
# the IR after every step, and the LLVM before O3
mkdir dump; $ICC build/exec/nbody.mlir --emit=mlir -o nbody.final.mlir --dump-after=all --dump-dir=dump
.toolchain/llvm-musl/bin/mlir-translate --mlir-to-llvmir nbody.final.mlir -o nbody.pre.ll
# assembly
$OBJDUMP -d --no-show-raw-insn --no-leading-addr --symbolize-operands --disassemble-symbols=main build/exec/nbody
# Chez
idris2 --cg chez -p base --build-dir chez/build --output-dir chez/out -o nbody Main.idr
```

The steps of the pipeline (from `--dump-after=all`):
1. `idr-simplify`
2. `idr-defunctionalize`
3. `canonicalize`
4. `idr-stack`
5. `idr-rc`
6. `idr-tail-loops`
7. `idr-lower`
8. `canonicalize`
9. `convert-scf-to-cf`

`--dump-dir` must exist: the tool reports "cannot write dump/01-…" and
exits 0 with no dump otherwise.

## Part B: the seven benchmarks

### Timings (seconds, best of 7)

| | ours | clang -O2 | clang -O2 v3 strict | clang -O2 v3 (fp-contract on) | clang -O3 v3 strict |
|---|---:|---:|---:|---:|---:|
| nbody | 0.326 | 0.329 | 0.311 | 0.269 (different digits) | 0.342 |
| mandelbrot | 0.346 | 0.378 | 0.358 | 0.332 | 0.361 |
| fib | 0.114 | 0.114 | 0.113 | 0.115 | 0.116 |
| tak | 0.119 | 0.119 | 0.119 | 0.120 | 0.125 |
| collatz | 0.477 | 0.473 | 0.467 | 0.473 | 0.467 |
| ackdyn | 0.179 | 0.174 | 0.169 | 0.174 | 0.176 |
| harmonic | 0.257 | 0.263 | 0.260 | 0.257 | 0.262 |

The outputs are all equal to ours, with two exceptions:
- the FMA build of nbody prints `-0.16908313397885641` where everyone
  else prints `-0.16908313397892985`;
- harmonic's C `printf("%.17g")` prints more digits than our shortest
  round-trip form (`19.691043591914379` against `19.69104359191438`), the
  same double.

### fib and tak: byte-identical bodies

`Main.fib` and C's `fib` are the same 18 instructions:

```
push r14; push rbx; push rax; xor ebx,ebx; cmp $2,rdi; jl L2
L1: mov rdi,r14; dec rdi; call fib; lea -2(r14),rdi; add rax,rbx; cmp $3,r14; ja L1
L2: add rdi,rbx; mov rbx,rax; add $8,rsp; pop rbx; pop r14; ret
```

LLVM turns one recursive call into the loop in both, as bench/README
says. `Main.tak` and `tak` are also identical (37 instructions: three
calls per iteration, five callee-saved registers).

### collatz: the same inner loop

Both inner loops (`steps`, and C's `while (m != 1)`):

```
movl %esi,%edi ; leaq (%rsi,%rsi,2),%r8 ; incq %r8 ; sarq %rsi ; testb $1,%dil
cmovneq %r8,%rsi ; incq %rdx ; cmpq $1,%rsi ; jne <loop>
```

Ours has the outer `longest` loop unrolled by 2, with the inner loop
duplicated (`L7`, `L9`, `L11`). That is O3's runtime unroll against
clang's O2, and it makes no difference in time.

### mandelbrot: the same inner loop

C's `L6` and our `L9` are both 22 instructions for two iterations of
`go`/`escapes`, unrolled by 2, and exit through `vucomisd; ja`. They differ
only in register assignment and in the commuted operands of
`vaddsd %xmm8,%xmm9` against `%xmm9,%xmm8`.

### ackdyn: layout

```
ours:  L1: dec rax; mov rbx,rdi; mov rax,rsi; call ack; dec rbx; je L3
       L2: test rax,rax; jne L1; mov $1,eax; dec rbx; jne L2
C:     L1: mov $1,eax; dec rbx; je L3
       L2: test rax,rax; je L1; dec rax; mov rbx,rdi; mov rax,rsi; call ack; dec rbx; jne L2
```

The instructions are the same; which path falls through differs.

Sensitivity test with `__builtin_expect` on `n == 0`:

| build | time (s) |
|---|---:|
| C, expect 1 (our layout) | 0.183 |
| C, expect 0 | 0.171 |
| C, no hint | 0.168 |
| ours | 0.178 |

`ackdyn.pre.ll` lowers each `match_lit` to `switch i64 %x, label %default
[i64 0, label %case]`, with no `!prof`. There is also a `call void
@llvm.sideeffect()` in the loop header (`ack` is partial on `Int`), which
emits no instruction.

### harmonic

The IR after `idr-tail-loops` (`$R/b/harmonic/dump/06-idr-tail-loops.mlir:57-107`):
- `Main.series` compares `i > n`, then calls
  `Main.case$32$block$32$831$32$in$32$series(%a, %h, %n, %i, %True|%False)`
  from both arms of a `match_lit`;
- the case block `idr.match`es the `Bool`, computes `1/cast i`, and calls
  `Main.series` back;
- neither function contains an `scf.while`.

After O3 the loop exists:

```
L7: vcvtsi2sd %rax,%xmm15,%xmm3 ; vdivsd %xmm3,%xmm1,%xmm3 ; testb $1,%al ; jne L5
    vxorpd %xmm2,%xmm3,%xmm4 ; jmp L6
L5: vmovapd %xmm3,%xmm4
L6: vaddsd %xmm4,%xmm5,%xmm5 ; incq %rax ; vaddsd %xmm3,%xmm0,%xmm0 ; cmpq %r12,%rax ; jg L9
```

Clang unrolled by 2 at O2, with the parity known in each half
(`addsd`/`subsd`, no branch).

**The ordered-vector experiment** (`$R/mlir/harm.mlir`):
- the loop runs `scf.for` step 4, with `vector<4xi64>` for i, `sitofp`
  and `divf` on vectors;
- `h` and `a` are accumulated with `vector.reduction <add>, %x, %acc`
  (with no fastmath, which `convert-vector-to-llvm` lowers to an ordered
  `llvm.vector.reduce.fadd`);
- `a` uses `x * [-1, 1, -1, 1]` negated.

Lowered with `--convert-vector-to-llvm --convert-scf-to-cf
--convert-cf-to-llvm --convert-arith-to-llvm --convert-func-to-llvm`,
compiled with clang `-O2 -march=x86-64-v3 -ffp-contract=off`, and driven
by a C main:
- the output is `19.691043591914379 0.69314717806064752`, identical;
- it runs 0.385 s: `vdivpd ymm` is used, but the i64→f64 conversion is
  scalarized (AVX2 has no `vcvtqq2pd`), and the reduction is 4 dependent
  `vaddsd` per 4 i's, the same chain as the scalar loop.

### nbody

Per step:

| | ours (`L7` to the back edge) | clang, equal ISA |
|---|---|---|
| instructions | 489 | about 420 dynamic, estimated from the loop nest: `L2` 38 + `L3` 9 + 5×`L5` + 10×`L6` 30 + 5×`L4` |
| mix | 158 `vmovsd`, 155 `vmulsd`, 79 `vaddsd`, 60 `vsubsd`, 10 `vsqrtsd`, 10 `vdivsd` | `L6` has `vsubpd`/`vmulpd` on (x,y) pairs plus scalar z |
| other | 176 instructions reference `%rsp` | loads and stores to `bs` |

In ours the masses are constant-pool operands. `offset initial` was
evaluated at compile time, so the mass fields carried by the loop are
invariant.

The IR, in `$R/b/nbody/dump/06-idr-tail-loops.mlir:64-415`:
- `Main.run` is one `scf.while` over `(i64, !idr.data<@Main.System>)`;
- each iteration does 35 `idr.field`s, the pair arithmetic in `arith`
  and `math.sqrt`, five `idr.con @Main.Body` and one
  `idr.con @Main.System`.

**The SoA experiment** (`$R/mlir/nbody.mlir`, generated by a short Python
script and kept there):
- the state is `px, py, pz, vx, vy, vz` as `vector<8xf64>` `iter_args`,
  plus the masses; bodies are in lanes 0–4 and lanes 5–7 are padding
  (mass 1);
- per step:
  - `dX = shuffle(pX, I) - shuffle(pX, J)` on `vector<12xf64>`, where
    `I`/`J` are the 10 pairs plus 2 padding pairs (0,1);
  - `d2 = dx*dx + dy*dy + dz*dz`, `mag = 0.01 / (d2 * sqrt d2)`;
  - `mb = mass[J] * mag`, `ma = mass[I] * mag`;
  - in round k = 0..3, body b's partner is `p = k < b ? k : k+1`, and the
    pair is `q(b,p)`;
    - the coefficient is `shuffle(mb, ma, [b<p ? q : 12+q])`;
    - the term is `shuffle(dX, q) * coef`;
    - `vX = select(b<p, vX - term, vX + term)`;
    - this is each body's pair order, so each lane does exactly the
      scalar program's operations in the scalar program's order;
  - then `pX = pX + 0.01 * vX`.
- The driver is the C bench's `offset` and `energy`
  (`$R/mlir/ndrv.c`).

Results:
- energies `-0.16907516382852447 / -0.16908760523460609` (1000 steps) and
  `-0.16907516382852447 / -0.16908313397892985` (5M steps), identical
  to clang and to ours;
- time 0.232 s, against clang v3 strict 0.311 s and ours 0.326 s;
- 330 instructions per step, including 3 `vsqrtpd`, 3 `vdivpd` and 28
  `vpermpd`; 78 `vmovupd` are spills of the 12-wide pair vectors.

## Part A: the CLBG kernels (`$R/k/`)

Every kernel reads its size with the bench's `readInt` (`getChar`).
Line-oriented input uses a `getLn` over `getChar`, because `getLine` is
rejected. At end of input, `getChar` returns `'\255'` on both our backend
and Chez (**measured**, `$R/k/t0`), not `'\0'`: the Prelude's primitive
reads a byte (`Registry/Primitives.idr:72-74`).

| dir | program | compile | results |
|---|---|---|---|
| `bt` | binary-trees, ADT | ok | depth 16: 0.35 s; 18: 1.18 s; 20: 3.48 s; 21: 9.25 s. `IDRIS_RT_LIVE=1`: live cells 0 |
| `fk` | fannkuch, lists + `Data.List` (base) | ok | n=7: 16 flips (correct); n=8: 0.193 s (Chez 0.35, C 0.020); n=9 and n=10: **SIGSEGV** after 0.16 s and 0.30 s (Chez n=9: 1.24 s) |
| `fkarr` | fannkuch, `Data.IOArray` | **rejected** | `Main.main: unsupported (escape hatch): %extern Data.IOArray.Prims.prim__newArray (reached through Main.main)` |
| `fasta` | fasta, lists and strings | ok after rewrites | `strIndex` → "Calls non covering function Data.String.strIndex"; `assert_total` → `unsupported (escape hatch): the escape hatch Builtin.assert_total`. n=1000 and n=250k: byte-identical to C; 250k: 1.11 s against C 0.249 s |
| `knuc` | k-nucleotide, `Data.SortedMap` | **rejected** | `Data.SortedMap.Dependent.lookup: unsupported (runtime closure): an implementation chosen at runtime: [__]` |
| `mpbm` | mandelbrot, PBM with `putChar` | ok | n=4000: 2.36 s (C 2.24, Chez 51.5). **Output differs**: ours 2,794,999 bytes, Chez and C 2,000,013 bytes (UTF-8 `c2 80` for byte 0x80) |
| `nbv` | n-body, `Vect 5 Body`, `Fin 5` pairs | ok | 1000 steps: same as Chez (`-0.1690751638285245 / -0.16908760523460603`; the order of `sum` differs from the records version); 5M steps: **10.56 s** |
| `pidig` | pidigits, `Integer` | ok | 200, 2000 and 10,000 digits equal to C/GMP; 10,000: 2.32 s (C with musl malloc: 5.31 s; Chez at 2000: 0.83 s) |
| `regex` | one variant, hand matcher | ok | 100 KB: 0.063 s (Chez 0.256); 2.5 MB: **SIGSEGV** (Chez 1.85 s, 18 matches, agrees with `grep -o`) |
| `revc` | reverse-complement, `List Char` | ok | 100 KB: 0.096 s (Chez 0.297), identical output; 2.5 MB: **SIGSEGV** (Chez 1.31 s) |
| `spec` | spectral-norm, lists | ok | n=100: 1.2742199912349306; n=1000: 3.10 s, `1.2742241481294836` (C 0.055, Chez 15.5) |
| `vn` | spectral-norm core over `Vect n Double`, runtime n | **rejected** | `Main.main: unsupported (runtime closure): an implementation chosen at runtime: ($resolved441 ($resolved2948 Int …))` |
| `buf` | `Data.Buffer` | **rejected** | `unsupported (escape hatch): %foreign Data.Buffer.prim__setBits8` |
| `ref` | `Data.IORef` | **rejected** | `main: unsupported (program): loads System.Concurrency, which is neither a user module nor a trusted module` |
| (all) | `import System.File` | **rejected** | `unsupported (program): imports System.File, which is neither a user module nor a trusted module` |
| (all) | `getLine` | **rejected** | `unsupported (escape hatch): %foreign Prelude.IO.prim__getStr` |
| (all) | `concat`/`fastConcat` of strings | **rejected** | `unsupported (escape hatch): %foreign Prelude.Types.fastConcat` |

Side observations:
- **An internal error after a failed elaboration.** When Idris reports an
  elaboration error, the `-o` flow still runs the backend, which then
  prints `mlir backend: internal error: a reference to Main.flipCount`
  (and similar), or `Undefined name unsafePerformIO` at
  `(Interactive):1:1`. The exit status is 1 either way. It is harmless,
  but the message sends the user looking for a compiler bug.
- **Quadratic `concat`.** The Prelude's `concat` on `List (List a)` is
  quadratic (`foldMap` via `foldl` of `++`) on Chez as on ours:
  - 10,000-line input: 1.47 s with `concat`, 0.063 s with
    `foldr (++) []`;
  - it is a library property, not ours.

### The putChar divergence (`$R/k/t1`)

```idris
main = do
  putChar (chr 200)
  putStr (pack [chr 201])
  c <- getChar          -- input byte 0xca
  putChar c
```

| backend | bytes out |
|---|---|
| ours | `c3 88 c3 89 c3 8a` |
| Chez | `c8 c3 89 ca` |

`runtime/io.cc:121-124`: `idris_rt_io_put_char` calls
`rt::encodeUtf8(c, bytes)`. The registry entry is
`ioPrimitive (MkSpec "C" "putchar") "prim__putChar"`
(`compiler/src/IdrisMLIR/Registry/Primitives.idr:70-71`), and Chez's
`put-char` writes one byte here.

### C baselines (`$R/c/`)

All built with `-O2 -march=x86-64-v3` (plus `-ffp-contract=off` for
floating point):
- `bt.c`: malloc/free per node;
- `btpool.c`: a bump pool per tree, the shape of the fastest C
  single-threaded;
- `fk.c`: the classic single-thread count/rotate/flip;
- `fasta.c`: the same LCG and linear pick as the Idris kernel;
- `pidig.c`: GMP, the same spigot with in-place `mpz` ops;
- `spec.c`: scalar, same order;
- `mpbm.c`: same algorithm, `putchar` per byte.

| program | size | time (s) |
|---|---|---:|
| bt | depth 16 / 18 / 21 | 0.65 / 3.84 / 36.4 |
| btpool | depth 18 / 20 / 21 | 0.43 / 1.98 / 4.73 |
| fk | n = 7 / 9 / 10 | 0.006 / 0.053 / 0.49 |
| pidig | 2000 / 10,000 digits | 0.050 / 5.31 |
| spec | n = 1000 | 0.055–0.069 across runs |
| mpbm | n = 4000 | 2.24 |

pidig's times are GMP through musl's malloc, the slow part.

## Part A: the spectral-norm linalg experiment (`$R/mlir/spec*.mlir`)

The payload (`spec1k.pay.mlir`) is one `linalg.generic`:
- `iterator_types = ["parallel", "reduction"]`;
- `ins(v: tensor<1000xf64>)`, `outs(o)`, `(i,j) -> (j)` and
  `(i,j) -> (i)`;
- the body computes `A(i,j) * v[j]` from `linalg.index`, with a transpose
  flag, and yields `acc + m`.

`spec2.pay.mlir` has two copies with the flag constant, as Idris's
`mulAv`/`mulAtv`.

The schedule (`vec.mlir`, loaded with `--transform-preload-library`,
because the stage-2 `mlir-opt` has no test passes):

```mlir
%g = transform.structured.match ops{["linalg.generic"]} in %root
%tiled, %loops:2 = transform.structured.tile_using_for %g tile_sizes [4, 1]
transform.structured.vectorize %tiled vector_sizes [4, 1]
```

The pipeline:

```sh
mlir-opt spec2.pay.mlir --canonicalize \
  --transform-preload-library="transform-library-paths=vec.mlir" --transform-interpreter \
  --canonicalize --cse --loop-invariant-subset-hoisting --canonicalize \
  --int-range-optimizations --arith-int-range-narrowing="int-bitwidths-supported=32" --canonicalize \
  --one-shot-bufferize="bufferize-function-boundaries function-boundary-type-conversion=identity-layout-map" \
  --drop-equivalent-buffer-results --canonicalize --cse
mlir-opt … --convert-vector-to-scf --lower-affine --expand-strided-metadata --finalize-memref-to-llvm \
  --convert-vector-to-llvm --convert-ub-to-llvm --convert-scf-to-cf --convert-cf-to-llvm \
  --convert-arith-to-llvm --convert-math-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts
```

What each stage showed:
- **Vectorization** gives `scf.for i step 4 { scf.for j step 1 { … vector<4x1xf64> … arith.addf %acc, %m } }`.
  Each lane accumulates in j order, which is exact.
- **`transform.structured.hoist_redundant_vector_transfers` after
  bufferization did not fire.** Bufferization left a self
  `memref.copy %subview, %subview` inside the j loop, which blocks
  hoisting, and `cse` + `canonicalize` did not remove it.
  **`--loop-invariant-subset-hoisting` on tensors, before bufferization,
  did**: the accumulator becomes a `vector<4xf64>` `iter_arg`. A
  self-copy of the same subview survives after the loop; it is harmless.
- **Without narrowing**, the i64 `muli`/`divsi`/`sitofp` on
  `vector<4xi64>` are scalarized on AVX2. With narrowing: `vpmulld`,
  `vpsrld`, then `vpmovzxdq` plus the magic-constant `vsubpd` trick for
  u32→f64, then `vdivpd %ymm`.
- **The transpose flag as a runtime `i64`** leaves `select`s and scalar
  `cmov`s in the loop (0.067 s). With it specialized away (two
  functions), the result is 0.032 s.
- **The result** is `1.2742241481294836` for every variant, the same as
  clang's and Chez's.

The driver is `sdrv2.c`, which calls `_mlir_ciface_av0/av1`
(`llvm.emit_c_interface`) for AᵀA, 10 rounds, with the final norm in C.

## Sources consulted

- The pinned MLIR:
  - `include/mlir/Dialect/Vector/IR/VectorOps.td:248-280`
    (`vector.reduction`, fastmath);
  - `lib/Conversion/VectorToLLVM/ConvertVectorToLLVM.cpp:800-900`
    (`reassociateFPReductions` default off);
  - `include/mlir/Interfaces/ControlFlowInterfaces.td:515-610`
    (`WeightedBranchOpInterface`, `WeightedRegionBranchOpInterface`);
  - `include/mlir/Dialect/ControlFlow/IR/ControlFlowOps.td:119-172`
    (`cf.cond_br` weights);
  - `include/mlir/Dialect/X86/` (no `pshufb`);
  - no SLP vectorizer anywhere in `lib/`, apart from affine
    super-vectorization.
- The repository:
  - `bench/run.sh:114-118`;
  - `foreign/idr/tools/idris-mlir-cc.cc:99-104`;
  - `foreign/idr/lib/Lower/Target.cc:9,28`;
  - `foreign/idr/lib/Lower/Runtime.cc:106-109`;
  - `runtime/io.cc:121-124,156-160`;
  - `runtime/gmp.cc:10-31`;
  - `compiler/src/IdrisMLIR/Registry/Primitives.idr:68-74`.
- The CLBG programs' specifications and their fastest entries are
  recalled (benchmarksgame-team.pages.debian.net is unreachable from
  here).
