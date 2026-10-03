Measured on 2026-10-02, at 903d127.

Transcribed from the table bench/README.md held then, so each sample is
that run's best of 3, to the millisecond; k-nucleotide was measured in a
run of its own on the same container. No compile times were kept.

Host: development container, x86-64, 4 CPUs.

- this compiler: 903d127, for x86_64-unknown-linux-musl
- Idris Chez: Idris 2 on Chez Scheme 9.5
- MLton: 20210117
- clang -O2: the pinned clang, LLVM 23.1.2
- Koka: 3.2.9
- Lean 4: 4.34.1

One run each, wall-clock seconds. Outputs agree.

| benchmark | input | this compiler | Idris Chez | MLton | clang -O2 | Koka | Lean 4 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ack | 10 | 0.004 | 1.207 | 0.068 | 0.253 | n/a | n/a | 63.25x |
| ackdyn | 10 | 0.266 | 1.205 | 0.086 | 0.254 | n/a | n/a | 0.95x |
| binary-trees | 21 | 6.522 | 46.112 | 7.606 | 31.746 | 12.557 | 7.221 | 4.87x |
| cfold | 20 | 0.187 | 0.588 | 0.412 | 0.477 | 0.360 | 0.370 | 2.55x |
| collatz | 3000000 | 0.589 | 23.318 | 2.379 | 0.634 | n/a | n/a | 1.08x |
| deriv | 10 | 1.258 | 3.067 | 1.122 | 3.935 | 1.166 | 1.307 | 3.13x |
| fannkuch-linear | 10 | 0.259 | 4.737 | n/a | 0.555 | n/a | n/a | 2.14x |
| fannkuch-redux | 10 | 0.722 | 12.686 | n/a | 0.522 | n/a | n/a | 0.72x |
| fasta | 250000 | 0.094 | 0.309 | n/a | 0.047 | n/a | n/a | 0.50x |
| fib | 38 | 0.130 | 3.589 | 0.282 | 0.124 | n/a | n/a | 0.95x |
| harmonic | 200000000 | 0.284 | 6.879 | 0.784 | 0.294 | n/a | n/a | 1.04x |
| k-nucleotide | fasta 250000 | 6.194 | 14.072 | n/a | 0.278 | n/a | n/a | 0.04x |
| mandelbrot | 2000 | 0.297 | 5.384 | 0.519 | 0.302 | n/a | n/a | 1.02x |
| mandelbrot-pbm | 4000 | 1.172 | 23.222 | n/a | 1.187 | n/a | n/a | 1.01x |
| nbody | 5000000 | 0.305 | 5.698 | 1.553 | 0.298 | n/a | n/a | 0.98x |
| nqueens | 13 | 1.023 | 14.859 | 1.211 | 1.303 | 1.076 | 2.422 | 1.27x |
| pidigits | 10000 | 1.165 | 6.235 | n/a | 1.220 | n/a | n/a | 1.05x |
| qsort | 400 | 1.495 | 16.288 | 1.774 | 1.511 | 26.342 | 2.505 | 1.01x |
| rbtree | 4200000 | 1.197 | 2.498 | 5.933 | 1.675 | 0.949 | 2.937 | 1.40x |
| rbtree-ck | 4200000 | 2.837 | 9.149 | 9.354 | 4.532 | 2.157 | 4.851 | 1.60x |
| regex-redux | fasta 250000 | 3.573 | 3.023 | n/a | n/a | n/a | n/a | n/a |
| reverse-complement | fasta 250000 | 0.155 | 0.714 | n/a | 0.013 | n/a | n/a | 0.08x |
| spectral-norm | 5500 | 2.259 | 191.642 | n/a | 1.749 | n/a | n/a | 0.77x |
| spectral-norm-linear | 5500 | 1.752 | 187.927 | n/a | 1.735 | n/a | n/a | 0.99x |
| tak | 18 | 0.124 | 1.386 | 0.173 | 0.130 | n/a | n/a | 1.05x |
| unionfind | 3000000 | 0.174 | 2.351 | 0.345 | 0.134 | 2.313 | 2.271 | 0.77x |
