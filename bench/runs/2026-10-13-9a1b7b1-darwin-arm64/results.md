Measured on 2026-10-13 at 18:37 UTC, at 9a1b7b12.

Host: Darwin 27.0.0 arm64, Apple M2 Max, 12 CPUs.
Stack: 65520 KiB (ulimit -s), the most this system allows.

- this compiler: 9a1b7b12, for arm64-apple-macosx14.0, CPU apple-m1; link flags: --target=arm64-apple-macosx14.0 -fuse-ld=lld -Wl,-dead_strip -Wl,--icf=all /Users/bjorn/Documents/idris-mlir/.toolchain/sysroot/usr/lib/libgmp.a
- Idris Chez: Idris 2, version 0.8.0-1c630e67c; Chez Scheme 10.4.1
- clang -O2: clang version 24.0.0git (https://github.com/llvm/llvm-project.git 7208ba24ca2894729cd394475a00d2a7b605e642)

Best of 5 runs, wall-clock seconds. Outputs agree.

| benchmark | input | this compiler | Idris Chez | clang -O2 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: |
| ack | 10 | 0.014 | 0.660 | 0.154 | 10.95x |
| ackdyn | 10 | 0.163 | 0.610 | 0.142 | 0.88x |
| binary-trees | 21 | 5.639 | 25.295 | 9.795 | 1.74x |
| cfold | 20 | 0.088 | 0.361 | 0.095 | 1.09x |
| collatz | 3000000 | 0.453 | 12.079 | 0.518 | 1.14x |
| deriv | 10 | 0.701 | 2.281 | 1.154 | 1.65x |
| fannkuch-linear | 12 | 49.205 | 497.403 | 31.001 | 0.63x |
| fannkuch-redux | 12 | 33.729 | 1218.731 | 25.553 | 0.76x |
| fasta | 25000000 | 6.248 | 22.552 | 2.682 | 0.43x |
| fasta-redux | 25000000 | 4.103 | 16.553 | 1.127 | 0.27x |
| fib | 38 | 0.130 | 2.345 | 0.143 | 1.09x |
| harmonic | 200000000 | 0.237 | 3.907 | 0.233 | 0.98x |
| k-nucleotide | fasta 25000000 | 3.067 | 151.061 | 2.385 | 0.78x |
| mandelbrot | 2000 | 0.247 | 3.136 | 0.230 | 0.93x |
| mandelbrot-pbm | 16000 | 13.624 | 209.098 | 15.079 | 1.11x |
| nbody | 50000000 | 1.763 | 48.406 | 1.970 | 1.12x |
| nqueens | 13 | 0.552 | 7.134 | 0.590 | 1.07x |
| pidigits | 10000 | 0.669 | 3.882 | 0.445 | 0.66x |
| qsort | 400 | 1.046 | 9.344 | 0.989 | 0.95x |
| rbtree | 4200000 | 0.422 | 1.506 | 0.721 | 1.71x |
| rbtree-ck | 4200000 | 1.083 | 3.852 | 1.222 | 1.13x |
| regex-redux | fasta 5000000 | 77.995 | 93.324 | 17.841 | 0.23x |
| reverse-complement | fasta 25000000 | 0.555 | 21.159 | 0.781 | 1.41x |
| spectral-norm | 5500 | 3.045 | 90.571 | 1.153 | 0.38x |
| spectral-norm-linear | 5500 | 0.606 | 93.106 | 1.154 | 1.90x |
| tak | 18 | 0.082 | 0.774 | 0.082 | 1.01x |
| unionfind | 3000000 | 0.096 | 1.358 | 0.108 | 1.12x |

Compile time of this compiler, wall-clock seconds, once: idris-mlir (frontend, pipeline and link).

| benchmark | compile |
| --- | ---: |
| ack | 0.916 |
| ackdyn | 0.882 |
| binary-trees | 1.005 |
| cfold | 1.282 |
| collatz | 1.059 |
| deriv | 1.432 |
| fannkuch-linear | 1.802 |
| fannkuch-redux | 3.543 |
| fasta | 1.839 |
| fasta-redux | 1.600 |
| fib | 0.985 |
| harmonic | 1.053 |
| k-nucleotide | 5.354 |
| mandelbrot | 1.307 |
| mandelbrot-pbm | 1.137 |
| nbody | 1.134 |
| nqueens | 0.900 |
| pidigits | 1.160 |
| qsort | 1.770 |
| rbtree | 1.068 |
| rbtree-ck | 1.306 |
| regex-redux | 2.017 |
| reverse-complement | 1.666 |
| spectral-norm | 1.993 |
| spectral-norm-linear | 3.681 |
| tak | 0.819 |
| unionfind | 1.231 |
