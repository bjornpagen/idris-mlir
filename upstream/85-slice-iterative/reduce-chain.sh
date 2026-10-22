#!/bin/sh
# reduce-chain.sh LENGTH: a function whose linalg reduction combines its
# accumulator with a value computed above it by a chain of LENGTH
# additions, and a transform script that vectorizes the reduction, on
# standard output. `mlir-opt -transform-interpreter` on it asks
# matchReduction whether the value depends on the accumulator, which takes
# the value's backward slice: at the pin one native frame per addition, so
# on a small stack (`ulimit -s 256`) a long enough chain overflows it
# (conjecture on the length: no overflowing length is measured). The chain
# is straight-line code in one block, which the textual parser and printer
# read and write without recursion.
length=${1:?usage: reduce-chain.sh LENGTH}
awk -v n="$length" 'BEGIN {
  printf "func.func @reduce(%%in: tensor<8xf32>, %%out: tensor<f32>, %%x: f32) -> tensor<f32> {\n"
  printf "  %%v0 = arith.addf %%x, %%x : f32\n"
  for (i = 1; i < n; i++) printf "  %%v%d = arith.addf %%v%d, %%x : f32\n", i, i - 1
  printf "  %%r = linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>, affine_map<(d0) -> ()>],\n"
  printf "      iterator_types = [\"reduction\"]} ins(%%in : tensor<8xf32>) outs(%%out : tensor<f32>) {\n"
  printf "  ^bb0(%%a: f32, %%acc: f32):\n"
  printf "    %%s = arith.addf %%acc, %%v%d : f32\n", n - 1
  printf "    linalg.yield %%s : f32\n"
  printf "  } -> tensor<f32>\n"
  printf "  return %%r : tensor<f32>\n}\n"
  printf "module attributes {transform.with_named_sequence} {\n"
  printf "  transform.named_sequence @__transform_main(%%root: !transform.any_op {transform.readonly}) {\n"
  printf "    %%g = transform.structured.match ops{[\"linalg.generic\"]} in %%root : (!transform.any_op) -> !transform.any_op\n"
  printf "    transform.structured.vectorize %%g : !transform.any_op\n"
  printf "    transform.yield\n  }\n}\n"
}'
