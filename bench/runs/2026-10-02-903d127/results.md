Measured on 2026-10-02, at 903d127.

Transcribed from the table bench/README.md held then, so each sample is
that run's best of 3, to the millisecond; k-nucleotide was measured in a
run of its own on the same container. No compile times were kept.

Host: development container, x86-64, 4 CPUs.

- this compiler: 903d127, for x86_64-unknown-linux-musl
- Idris Chez: Idris 2 on Chez Scheme 9.5
- clang -O2: the pinned clang, LLVM 23.1.2

One run each, wall-clock seconds. Outputs agree.

| benchmark | input | this compiler | Idris Chez | clang -O2 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: |
| ack | 10 | 0.004 | 1.207 | 0.253 | 63.25x |
| ackdyn | 10 | 0.266 | 1.205 | 0.254 | 0.95x |
| binary-trees | 21 | 6.522 | 46.112 | 31.746 | 4.87x |
| cfold | 20 | 0.187 | 0.588 | 0.477 | 2.55x |
| collatz | 3000000 | 0.589 | 23.318 | 0.634 | 1.08x |
| deriv | 10 | 1.258 | 3.067 | 3.935 | 3.13x |
| fannkuch-linear | 10 | 0.259 | 4.737 | 0.555 | 2.14x |
| fannkuch-redux | 10 | 0.722 | 12.686 | 0.522 | 0.72x |
| fasta | 250000 | 0.094 | 0.309 | 0.047 | 0.50x |
| fib | 38 | 0.130 | 3.589 | 0.124 | 0.95x |
| harmonic | 200000000 | 0.284 | 6.879 | 0.294 | 1.04x |
| k-nucleotide | fasta 250000 | 6.194 | 14.072 | 0.278 | 0.04x |
| mandelbrot | 2000 | 0.297 | 5.384 | 0.302 | 1.02x |
| mandelbrot-pbm | 4000 | 1.172 | 23.222 | 1.187 | 1.01x |
| nbody | 5000000 | 0.305 | 5.698 | 0.298 | 0.98x |
| nqueens | 13 | 1.023 | 14.859 | 1.303 | 1.27x |
| pidigits | 10000 | 1.165 | 6.235 | 1.220 | 1.05x |
| qsort | 400 | 1.495 | 16.288 | 1.511 | 1.01x |
| rbtree | 4200000 | 1.197 | 2.498 | 1.675 | 1.40x |
| rbtree-ck | 4200000 | 2.837 | 9.149 | 4.532 | 1.60x |
| regex-redux | fasta 250000 | 3.573 | 3.023 | n/a | n/a |
| reverse-complement | fasta 250000 | 0.155 | 0.714 | 0.013 | 0.08x |
| spectral-norm | 5500 | 2.259 | 191.642 | 1.749 | 0.77x |
| spectral-norm-linear | 5500 | 1.752 | 187.927 | 1.735 | 0.99x |
| tak | 18 | 0.124 | 1.386 | 0.130 | 1.05x |
| unionfind | 3000000 | 0.174 | 2.351 | 0.134 | 0.77x |
