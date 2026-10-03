Measured on 2026-10-03 at 14:57 UTC, at 861acdc.

Host: Linux 6.18.44-fc-v64 x86_64, Intel(R) Xeon(R) Processor @ 2.10GHz, 4 CPUs.
Stack: unlimited (ulimit -s), the most this system allows.

- this compiler: 861acdc, for x86_64-unknown-linux-musl, CPU x86-64-v3; link flags: --target=x86_64-unknown-linux-musl -fuse-ld=lld -static-pie -Wl,--gc-sections -Wl,--icf=all -lgmp
- Idris Chez: Idris 2, version 0.8.0-1c630e67c; Chez Scheme 10.4.1
- MLton: MLton 20210117+dfsg-3
- clang -O2: clang version 23.1.2 (https://github.com/llvm/llvm-project.git 85ac560262434c9ccfc0c183ec22d4138ed647fb)
- Koka: Koka 3.2.9, 05:27:08 Sep 18 2026 (ghc release version)
- Lean 4: Lean (version 4.34.1, x86_64-unknown-linux-gnu, commit 5045d0056413266e57c625dcd7c365b10e377c52, Release)

Best of 5 runs, wall-clock seconds. Outputs agree.

| benchmark | input | this compiler | Idris Chez | MLton | clang -O2 | Koka | Lean 4 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ack | 10 | 0.004 | 1.117 | 0.069 | 0.251 | n/a | n/a | 56.57x |
| ackdyn | 10 | 0.257 | 1.112 | 0.084 | 0.250 | n/a | n/a | 0.97x |
| binary-trees | 21 | 6.834 | 41.936 | 7.490 | 29.839 | 12.058 | 7.329 | 4.37x |
| cfold | 20 | 0.222 | 0.654 | 0.442 | 0.542 | 0.257 | 0.360 | 2.45x |
| collatz | 3000000 | 0.596 | 22.899 | 2.318 | 0.639 | n/a | n/a | 1.07x |
| deriv | 10 | 1.126 | 3.583 | 1.158 | 4.233 | 1.109 | 1.357 | 3.76x |
| fannkuch-linear | 10 | 0.250 | 4.440 | n/a | 0.542 | n/a | n/a | 2.17x |
| fannkuch-redux | 10 | 0.333 | 12.456 | n/a | 0.546 | n/a | n/a | 1.64x |
| fasta | 250000 | 0.084 | 0.289 | n/a | 0.047 | n/a | n/a | 0.56x |
| fib | 38 | 0.130 | 3.700 | 0.276 | 0.111 | n/a | n/a | 0.85x |
| harmonic | 200000000 | 0.288 | 6.660 | 0.749 | 0.293 | n/a | n/a | 1.02x |
| k-nucleotide | fasta 250000 | 4.807 | 11.555 | n/a | 0.260 | n/a | n/a | 0.05x |
| mandelbrot | 2000 | 0.292 | 5.145 | 0.518 | 0.291 | n/a | n/a | 1.00x |
| mandelbrot-pbm | 4000 | 1.146 | 21.824 | n/a | 1.154 | n/a | n/a | 1.01x |
| nbody | 5000000 | 0.297 | 5.195 | 1.481 | 0.292 | n/a | n/a | 0.98x |
| nqueens | 13 | 1.034 | 13.967 | 1.139 | 1.297 | 1.023 | 2.243 | 1.26x |
| pidigits | 10000 | 1.137 | 5.485 | n/a | 1.204 | n/a | n/a | 1.06x |
| qsort | 400 | 1.509 | 14.712 | 1.727 | 1.436 | 24.865 | 2.473 | 0.95x |
| rbtree | 4200000 | 1.146 | 2.581 | 6.128 | 1.643 | 0.938 | 2.643 | 1.43x |
| rbtree-ck | 4200000 | 2.855 | 9.514 | 6.915 | 4.437 | 2.257 | 4.891 | 1.55x |
| regex-redux | fasta 250000 | 3.723 | 3.094 | n/a | n/a | n/a | n/a | n/a |
| reverse-complement | fasta 250000 | 0.134 | 0.829 | n/a | 0.016 | n/a | n/a | 0.12x |
| spectral-norm | 5500 | 2.237 | 174.752 | n/a | 1.738 | n/a | n/a | 0.78x |
| spectral-norm-linear | 5500 | 0.874 | 182.346 | n/a | 1.740 | n/a | n/a | 1.99x |
| tak | 18 | 0.127 | 1.321 | 0.176 | 0.122 | n/a | n/a | 0.97x |
| unionfind | 3000000 | 0.187 | 2.406 | 0.324 | 0.158 | 2.352 | 2.343 | 0.85x |

Compile time of this compiler, wall-clock seconds, once: idris-mlir, idris-mlir-cc and the link.

| benchmark | compile |
| --- | ---: |
| ack | 1.943 |
| ackdyn | 1.796 |
| binary-trees | 2.886 |
| cfold | 2.871 |
| collatz | 2.664 |
| deriv | 3.595 |
| fannkuch-linear | 3.527 |
| fannkuch-redux | 8.335 |
| fasta | 5.239 |
| fib | 1.802 |
| harmonic | 1.987 |
| k-nucleotide | 11.235 |
| mandelbrot | 2.109 |
| mandelbrot-pbm | 3.204 |
| nbody | 2.905 |
| nqueens | 2.365 |
| pidigits | 3.639 |
| qsort | 3.823 |
| rbtree | 3.039 |
| rbtree-ck | 3.924 |
| regex-redux | 9.684 |
| reverse-complement | 2.985 |
| spectral-norm | 7.443 |
| spectral-norm-linear | 10.280 |
| tak | 2.002 |
| unionfind | 3.337 |

Against the previous record (measured on 2026-10-02, at 903d127): clang's time
over this compiler's in each run, and how it moved.

| benchmark | before | now | change |
| --- | ---: | ---: | ---: |
| ack | 63.25x | 56.57x | -11% |
| ackdyn | 0.95x | 0.97x | +2% |
| binary-trees | 4.87x | 4.37x | -10% |
| cfold | 2.55x | 2.45x | -4% |
| collatz | 1.08x | 1.07x | -0% |
| deriv | 3.13x | 3.76x | +20% |
| fannkuch-linear | 2.14x | 2.17x | +1% |
| fannkuch-redux | 0.72x | 1.64x | +127% |
| fasta | 0.50x | 0.56x | +12% |
| fib | 0.95x | 0.85x | -11% |
| harmonic | 1.04x | 1.02x | -2% |
| k-nucleotide | 0.04x | 0.05x | +20% |
| mandelbrot | 1.02x | 1.00x | -2% |
| mandelbrot-pbm | 1.01x | 1.01x | -1% |
| nbody | 0.98x | 0.98x | +1% |
| nqueens | 1.27x | 1.26x | -1% |
| pidigits | 1.05x | 1.06x | +1% |
| qsort | 1.01x | 0.95x | -6% |
| rbtree | 1.40x | 1.43x | +2% |
| rbtree-ck | 1.60x | 1.55x | -3% |
| reverse-complement | 0.08x | 0.12x | +45% |
| spectral-norm | 0.77x | 0.78x | +0% |
| spectral-norm-linear | 0.99x | 1.99x | +101% |
| tak | 1.05x | 0.97x | -8% |
| unionfind | 0.77x | 0.85x | +10% |
