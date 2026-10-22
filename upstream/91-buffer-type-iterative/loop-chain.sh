#!/bin/sh
# loop-chain.sh PAIRS: a function whose scf.for carries a tensor through a
# chain of PAIRS pairs of tensor.cast ops, each to tensor<?xf32> and back to
# tensor<4xf32>, on standard output. `mlir-opt -one-shot-bufferize` computes
# the buffer type of the loop's iter_arg before it bufferizes the body: from
# the yielded value back along the chain to the iter_arg, a call of
# bufferization::getBufferType and of the cast's getBufferType per value at
# the pin, so on a small stack (`ulimit -s 256`) a few thousand casts
# overflow it (conjecture on the length: no overflowing length is measured).
# The chain is flat, so the textual parser and printer do not recurse on it.
pairs=${1:?usage: loop-chain.sh PAIRS}
awk -v n="$pairs" 'BEGIN {
  printf "func.func @chain(%%t: tensor<4xf32>, %%n: index) -> tensor<4xf32> {\n"
  printf "  %%c0 = arith.constant 0 : index\n  %%c1 = arith.constant 1 : index\n"
  printf "  %%r = scf.for %%i = %%c0 to %%n step %%c1 iter_args(%%v0 = %%t) -> (tensor<4xf32>) {\n"
  for (i = 0; i < 2 * n; i++) {
    if (i % 2 == 0)
      printf "    %%v%d = tensor.cast %%v%d : tensor<4xf32> to tensor<?xf32>\n", i + 1, i
    else
      printf "    %%v%d = tensor.cast %%v%d : tensor<?xf32> to tensor<4xf32>\n", i + 1, i
  }
  printf "    scf.yield %%v%d : tensor<4xf32>\n  }\n  return %%r : tensor<4xf32>\n}\n", 2 * n
}'
