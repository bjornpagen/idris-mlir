Measured on 2026-10-05 at 17:04 UTC, at 2cb1436-dirty.

Host: Darwin 27.0.0 arm64, Apple M2 Max, 12 CPUs.
Stack: 65520 KiB (ulimit -s), the most this system allows.

- this compiler: 2cb1436-dirty, for arm64-apple-macosx14.0, CPU apple-m1; link flags: --target=arm64-apple-macosx14.0 -Wl,-dead_strip /Users/bjorn/Documents/idris-mlir/.toolchain/sysroot/usr/lib/libgmp.a
- Idris Chez: Idris 2, version 0.8.0-1c630e67c; Chez Scheme 10.4.1
- clang -O2: clang version 23.1.2 (https://github.com/llvm/llvm-project.git 85ac560262434c9ccfc0c183ec22d4138ed647fb)

Best of 5 runs, wall-clock seconds. Outputs agree.

| benchmark | input | this compiler | Idris Chez | clang -O2 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: |
| ack | 10 | 0.012 | 0.595 | 0.142 | 11.85x |
| ackdyn | 10 | 0.152 | 0.607 | 0.138 | 0.91x |
| binary-trees | 21 | 4.379 | 22.626 | 12.357 | 2.82x |
| cfold | 20 | 0.083 | 0.316 | 0.100 | 1.21x |
| collatz | 3000000 | 0.437 | 11.554 | 0.435 | 1.00x |
| deriv | 10 | 0.604 | 1.887 | 1.222 | 2.02x |
| fannkuch-linear | 10 | 0.164 | 2.285 | 0.174 | 1.06x |
| fannkuch-redux | 10 | 0.221 | 6.319 | 0.176 | 0.80x |
| fasta | 250000 | 0.077 | 0.192 | 0.041 | 0.54x |
| fib | 38 | 0.112 | 1.974 | 0.122 | 1.09x |
| harmonic | 200000000 | 0.199 | 3.357 | 0.194 | 0.98x |
| k-nucleotide | fasta 250000 | 0.130 | 4.886 | 0.045 | 0.35x |
| mandelbrot | 2000 | 0.234 | 3.273 | 0.239 | 1.02x |
| mandelbrot-pbm | 4000 | 0.904 | 12.956 | 0.958 | 1.06x |
| nbody | 5000000 | 0.183 | 4.850 | 0.202 | 1.11x |
| nqueens | 13 | 0.538 | 7.027 | 0.615 | 1.14x |
| pidigits | 10000 | 0.665 | 3.924 | 0.436 | 0.66x |
| qsort | 400 | 1.020 | 8.130 | 0.996 | 0.98x |
| rbtree | 4200000 | 0.418 | 1.437 | 0.631 | 1.51x |
| rbtree-ck | 4200000 | 1.081 | 3.978 | 1.301 | 1.20x |
| regex-redux | fasta 250000 | 4.170 | 4.392 | n/a | n/a |
| reverse-complement | fasta 250000 | 0.075 | 3.090 | 0.019 | 0.26x |
| spectral-norm | 5500 | 1.518 | 87.920 | 1.131 | 0.75x |
| spectral-norm-linear | 5500 | 0.589 | 89.596 | 1.113 | 1.89x |
| tak | 18 | 0.076 | 0.747 | 0.076 | 0.99x |
| unionfind | 3000000 | 0.091 | 1.257 | 0.102 | 1.12x |

Compile time of this compiler, wall-clock seconds, once: idris-mlir, idris-mlir-cc and the link.

| benchmark | compile |
| --- | ---: |
| ack | 1.498 |
| ackdyn | 1.096 |
| binary-trees | 1.651 |
| cfold | 1.740 |
| collatz | 1.454 |
| deriv | 2.338 |
| fannkuch-linear | 2.285 |
| fannkuch-redux | 5.820 |
| fasta | 3.763 |
| fib | 1.098 |
| harmonic | 1.261 |
| k-nucleotide | 16.372 |
| mandelbrot | 1.463 |
| mandelbrot-pbm | 2.198 |
| nbody | 2.317 |
| nqueens | 1.418 |
| pidigits | 1.947 |
| qsort | 2.415 |
| rbtree | 2.068 |
| rbtree-ck | 2.466 |
| regex-redux | 7.052 |
| reverse-complement | 2.022 |
| spectral-norm | 5.063 |
| spectral-norm-linear | 5.742 |
| tak | 1.128 |
| unionfind | 1.977 |

Against the previous record (measured on 2026-10-04 at 15:42 UTC, at 15f1a53): clang's time
over this compiler's in each run, and how it moved.

| benchmark | before | now | change |
| --- | ---: | ---: | ---: |
| ack | 11.93x | 11.85x | -1% |
| ackdyn | 0.91x | 0.91x | -1% |
| binary-trees | 2.82x | 2.82x | -0% |
| cfold | 1.33x | 1.21x | -9% |
| collatz | 0.99x | 1.00x | +0% |
| deriv | 2.05x | 2.02x | -1% |
| fannkuch-linear | 1.06x | 1.06x | +1% |
| fannkuch-redux | 0.77x | 0.80x | +4% |
| fasta | 0.54x | 0.54x | -0% |
| fib | 1.16x | 1.09x | -6% |
| harmonic | 0.99x | 0.98x | -1% |
| k-nucleotide | 0.01x | 0.35x | +2273% |
| mandelbrot | 0.99x | 1.02x | +3% |
| mandelbrot-pbm | 1.07x | 1.06x | -1% |
| nbody | 1.15x | 1.11x | -3% |
| nqueens | 1.13x | 1.14x | +1% |
| pidigits | 0.67x | 0.66x | -2% |
| qsort | 0.94x | 0.98x | +4% |
| rbtree | 1.97x | 1.51x | -23% |
| rbtree-ck | 1.21x | 1.20x | -0% |
| reverse-complement | 0.24x | 0.26x | +10% |
| spectral-norm | 0.73x | 0.75x | +2% |
| spectral-norm-linear | 1.93x | 1.89x | -2% |
| tak | 1.00x | 0.99x | -1% |
| unionfind | 1.12x | 1.12x | +0% |
