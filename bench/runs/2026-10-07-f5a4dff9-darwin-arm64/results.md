Measured on 2026-10-07 at 05:56 UTC, at f5a4dff9.

Host: Darwin 27.0.0 arm64, Apple M2 Max, 12 CPUs.
Stack: 65520 KiB (ulimit -s), the most this system allows.

- this compiler: f5a4dff9, for arm64-apple-macosx14.0, CPU apple-m1; link flags: --target=arm64-apple-macosx14.0 -fuse-ld=lld -Wl,-dead_strip -Wl,--icf=all /Users/bjorn/Documents/idris-mlir/.toolchain/sysroot/usr/lib/libgmp.a
- Idris Chez: Idris 2, version 0.8.0-1c630e67c; Chez Scheme 10.4.1
- clang -O2: clang version 23.1.2 (https://github.com/llvm/llvm-project.git 85ac560262434c9ccfc0c183ec22d4138ed647fb)

Best of 5 runs, wall-clock seconds. Outputs agree.

| benchmark | input | this compiler | Idris Chez | clang -O2 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: |
| ack | 10 | 0.013 | 0.640 | 0.152 | 12.03x |
| ackdyn | 10 | 0.166 | 0.643 | 0.148 | 0.89x |
| binary-trees | 21 | 4.767 | 23.298 | 12.746 | 2.67x |
| cfold | 20 | 0.078 | 0.340 | 0.098 | 1.26x |
| collatz | 3000000 | 0.432 | 11.644 | 0.442 | 1.02x |
| deriv | 10 | 0.615 | 1.959 | 1.251 | 2.03x |
| fannkuch-linear | 12 | 24.155 | 383.179 | 25.711 | 1.06x |
| fannkuch-redux | 12 | 32.542 | 1163.295 | 25.350 | 0.78x |
| fasta | 25000000 | 6.164 | 13.174 | 2.858 | 0.46x |
| fasta-redux | 25000000 | 3.718 | 9.955 | 0.921 | 0.25x |
| fib | 38 | 0.111 | 1.968 | 0.123 | 1.11x |
| harmonic | 200000000 | 0.201 | 3.291 | 0.198 | 0.98x |
| k-nucleotide | fasta 25000000 | 9.657 | 522.836 | 2.164 | 0.22x |
| mandelbrot | 2000 | 0.229 | 3.144 | 0.231 | 1.01x |
| mandelbrot-pbm | 16000 | 13.345 | 206.354 | 14.415 | 1.08x |
| nbody | 50000000 | 1.655 | 47.291 | 1.924 | 1.16x |
| nqueens | 13 | 0.534 | 6.941 | 0.604 | 1.13x |
| pidigits | 10000 | 0.650 | 3.824 | 0.434 | 0.67x |
| qsort | 400 | 0.991 | 7.977 | 0.929 | 0.94x |
| rbtree | 4200000 | 0.409 | 1.400 | 0.718 | 1.76x |
| rbtree-ck | 4200000 | 1.051 | 3.729 | 1.275 | 1.21x |
| regex-redux | fasta 5000000 | 81.695 | 91.186 | 17.542 | 0.21x |
| reverse-complement | fasta 25000000 | 6.229 | 309.447 | 0.753 | 0.12x |
| spectral-norm | 5500 | 1.515 | 88.392 | 1.126 | 0.74x |
| spectral-norm-linear | 5500 | 0.596 | 90.307 | 1.108 | 1.86x |
| tak | 18 | 0.079 | 0.753 | 0.078 | 1.00x |
| unionfind | 3000000 | 0.093 | 1.273 | 0.104 | 1.12x |

Compile time of this compiler, wall-clock seconds, once: idris-mlir, idris-mlir-cc and the link.

| benchmark | compile |
| --- | ---: |
| ack | 1.676 |
| ackdyn | 1.119 |
| binary-trees | 1.693 |
| cfold | 1.616 |
| collatz | 1.407 |
| deriv | 2.231 |
| fannkuch-linear | 2.325 |
| fannkuch-redux | 5.420 |
| fasta | 2.990 |
| fasta-redux | 3.768 |
| fib | 1.019 |
| harmonic | 1.169 |
| k-nucleotide | 14.006 |
| mandelbrot | 1.655 |
| mandelbrot-pbm | 1.937 |
| nbody | 1.797 |
| nqueens | 1.318 |
| pidigits | 1.926 |
| qsort | 2.524 |
| rbtree | 1.796 |
| rbtree-ck | 2.323 |
| regex-redux | 5.264 |
| reverse-complement | 1.614 |
| spectral-norm | 4.607 |
| spectral-norm-linear | 5.703 |
| tak | 1.128 |
| unionfind | 2.078 |

Against the previous record (measured on 2026-10-05 at 17:04 UTC, at 2cb1436-dirty): clang's time
over this compiler's in each run, and how it moved.

| benchmark | before | now | change |
| --- | ---: | ---: | ---: |
| ack | 11.85x | 12.03x | +2% |
| ackdyn | 0.91x | 0.89x | -2% |
| binary-trees | 2.82x | 2.67x | -5% |
| cfold | 1.21x | 1.26x | +3% |
| collatz | 1.00x | 1.02x | +3% |
| deriv | 2.02x | 2.03x | +1% |
| fannkuch-linear | 1.06x | 1.06x | +0% |
| fannkuch-redux | 0.80x | 0.78x | -2% |
| fasta | 0.54x | 0.46x | -14% |
| fasta-redux | n/a | 0.25x | new |
| fib | 1.09x | 1.11x | +1% |
| harmonic | 0.98x | 0.98x | +1% |
| k-nucleotide | 0.35x | 0.22x | -36% |
| mandelbrot | 1.02x | 1.01x | -1% |
| mandelbrot-pbm | 1.06x | 1.08x | +2% |
| nbody | 1.11x | 1.16x | +5% |
| nqueens | 1.14x | 1.13x | -1% |
| pidigits | 0.66x | 0.67x | +2% |
| qsort | 0.98x | 0.94x | -4% |
| rbtree | 1.51x | 1.76x | +16% |
| rbtree-ck | 1.20x | 1.21x | +1% |
| regex-redux | n/a | 0.21x | new |
| reverse-complement | 0.26x | 0.12x | -53% |
| spectral-norm | 0.75x | 0.74x | -0% |
| spectral-norm-linear | 1.89x | 1.86x | -2% |
| tak | 0.99x | 1.00x | +0% |
| unionfind | 1.12x | 1.12x | -1% |
