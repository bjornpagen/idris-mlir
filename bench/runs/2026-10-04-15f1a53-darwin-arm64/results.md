Measured on 2026-10-04 at 15:42 UTC, at 15f1a53.

Host: Darwin 27.0.0 arm64, Apple M2 Max, 12 CPUs.
Stack: 65520 KiB (ulimit -s), the most this system allows.

- this compiler: 15f1a53, for arm64-apple-macosx14.0, CPU apple-m1; link flags: --target=arm64-apple-macosx14.0 -Wl,-dead_strip /Users/bjorn/Documents/idris-mlir/.toolchain/sysroot/usr/lib/libgmp.a
- Idris Chez: Idris 2, version 0.8.0-1c630e67c; Chez Scheme 10.4.1
- clang -O2: clang version 23.1.2 (https://github.com/llvm/llvm-project.git 85ac560262434c9ccfc0c183ec22d4138ed647fb)

Best of 5 runs, wall-clock seconds. Outputs agree.

| benchmark | input | this compiler | Idris Chez | clang -O2 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: |
| ack | 10 | 0.011 | 0.584 | 0.134 | 11.93x |
| ackdyn | 10 | 0.145 | 0.585 | 0.132 | 0.91x |
| binary-trees | 21 | 4.278 | 22.144 | 12.080 | 2.82x |
| cfold | 20 | 0.075 | 0.341 | 0.100 | 1.33x |
| collatz | 3000000 | 0.426 | 11.381 | 0.424 | 0.99x |
| deriv | 10 | 0.586 | 1.809 | 1.200 | 2.05x |
| fannkuch-linear | 10 | 0.162 | 2.230 | 0.172 | 1.06x |
| fannkuch-redux | 10 | 0.224 | 6.265 | 0.172 | 0.77x |
| fasta | 250000 | 0.072 | 0.182 | 0.039 | 0.54x |
| fib | 38 | 0.106 | 1.953 | 0.123 | 1.16x |
| harmonic | 200000000 | 0.200 | 3.365 | 0.197 | 0.99x |
| k-nucleotide | fasta 250000 | 2.754 | 8.200 | 0.040 | 0.01x |
| mandelbrot | 2000 | 0.226 | 3.134 | 0.225 | 0.99x |
| mandelbrot-pbm | 4000 | 0.861 | 12.948 | 0.923 | 1.07x |
| nbody | 5000000 | 0.178 | 4.722 | 0.204 | 1.15x |
| nqueens | 13 | 0.532 | 6.949 | 0.600 | 1.13x |
| pidigits | 10000 | 0.644 | 3.833 | 0.430 | 0.67x |
| qsort | 400 | 0.998 | 7.901 | 0.936 | 0.94x |
| rbtree | 4200000 | 0.401 | 1.400 | 0.789 | 1.97x |
| rbtree-ck | 4200000 | 1.046 | 3.651 | 1.261 | 1.21x |
| regex-redux | fasta 250000 | 4.061 | 4.338 | n/a | n/a |
| reverse-complement | fasta 250000 | 0.073 | 3.033 | 0.017 | 0.24x |
| spectral-norm | 5500 | 1.508 | 86.811 | 1.100 | 0.73x |
| spectral-norm-linear | 5500 | 0.578 | 88.573 | 1.114 | 1.93x |
| tak | 18 | 0.076 | 0.748 | 0.076 | 1.00x |
| unionfind | 3000000 | 0.091 | 1.255 | 0.102 | 1.12x |

Compile time of this compiler, wall-clock seconds, once: idris-mlir, idris-mlir-cc and the link.

| benchmark | compile |
| --- | ---: |
| ack | 1.431 |
| ackdyn | 1.043 |
| binary-trees | 1.559 |
| cfold | 1.608 |
| collatz | 1.423 |
| deriv | 2.263 |
| fannkuch-linear | 2.205 |
| fannkuch-redux | 5.445 |
| fasta | 3.612 |
| fib | 1.032 |
| harmonic | 1.261 |
| k-nucleotide | 7.117 |
| mandelbrot | 1.376 |
| mandelbrot-pbm | 2.010 |
| nbody | 2.212 |
| nqueens | 1.392 |
| pidigits | 1.862 |
| qsort | 2.351 |
| rbtree | 1.799 |
| rbtree-ck | 2.377 |
| regex-redux | 6.834 |
| reverse-complement | 1.950 |
| spectral-norm | 5.015 |
| spectral-norm-linear | 5.591 |
| tak | 1.118 |
| unionfind | 1.966 |

Against the previous record (measured on 2026-10-03 at 14:57 UTC, at 861acdc): clang's time
over this compiler's in each run, and how it moved.

| benchmark | before | now | change |
| --- | ---: | ---: | ---: |
| ack | 56.57x | 11.93x | -79% |
| ackdyn | 0.97x | 0.91x | -6% |
| binary-trees | 4.37x | 2.82x | -35% |
| cfold | 2.45x | 1.33x | -45% |
| collatz | 1.07x | 0.99x | -7% |
| deriv | 3.76x | 2.05x | -46% |
| fannkuch-linear | 2.17x | 1.06x | -51% |
| fannkuch-redux | 1.64x | 0.77x | -53% |
| fasta | 0.56x | 0.54x | -4% |
| fib | 0.85x | 1.16x | +36% |
| harmonic | 1.02x | 0.99x | -3% |
| k-nucleotide | 0.05x | 0.01x | -73% |
| mandelbrot | 1.00x | 0.99x | -0% |
| mandelbrot-pbm | 1.01x | 1.07x | +6% |
| nbody | 0.98x | 1.15x | +16% |
| nqueens | 1.26x | 1.13x | -10% |
| pidigits | 1.06x | 0.67x | -37% |
| qsort | 0.95x | 0.94x | -1% |
| rbtree | 1.43x | 1.97x | +37% |
| rbtree-ck | 1.55x | 1.21x | -22% |
| reverse-complement | 0.12x | 0.24x | +94% |
| spectral-norm | 0.78x | 0.73x | -6% |
| spectral-norm-linear | 1.99x | 1.93x | -3% |
| tak | 0.97x | 1.00x | +3% |
| unionfind | 0.85x | 1.12x | +33% |
