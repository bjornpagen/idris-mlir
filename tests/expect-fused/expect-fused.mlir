// RUN: idris-mlir-opt %s --idr-expect=holds=fused=@one -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=fused=@two,fused=@none -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(linalg-fuse-elementwise-ops)))' -o %t.fused.mlir
// RUN: idris-mlir-opt %t.fused.mlir --idr-expect=holds=fused=@two -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=fused=@shared -o /dev/null
// No array is made only to be read by the next loop: map f (map g x) is
// one loop (@one). Two loops with an array between them that only the
// second reads fail (@two), until upstream's elementwise fusion makes
// them one. An array two loops read is no intermediate of one of them, so
// it holds (@shared). A function with no structured op fails.
#map = affine_map<(d0) -> (d0)>
idr.program @fused root(@root) stage(first) types #idr.types<> {
  idr.func @one(%x: tensor<?xi64>) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    %y = linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel"]}
        ins(%x : tensor<?xi64>) outs(%e : tensor<?xi64>) {
    ^bb0(%a: i64, %b: i64):
      %s = arith.addi %a, %a : i64
      %t = arith.muli %s, %s : i64
      linalg.yield %t : i64
    } -> tensor<?xi64>
    return %y : tensor<?xi64>
  }
  idr.func @two(%x: tensor<?xi64>) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    // expected-error @below {{expected fused: }}
    %y = linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel"]}
        ins(%x : tensor<?xi64>) outs(%e : tensor<?xi64>) {
    ^bb0(%a: i64, %b: i64):
      %s = arith.addi %a, %a : i64
      linalg.yield %s : i64
    } -> tensor<?xi64>
    %f = tensor.empty(%n) : tensor<?xi64>
    %z = linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel"]}
        ins(%y : tensor<?xi64>) outs(%f : tensor<?xi64>) {
    ^bb0(%a: i64, %b: i64):
      %t = arith.muli %a, %a : i64
      linalg.yield %t : i64
    } -> tensor<?xi64>
    return %z : tensor<?xi64>
  }
  idr.func @shared(%x: tensor<?xi64>) -> (tensor<?xi64>, tensor<?xi64>) {
    %c0 = arith.constant 0 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    %y = linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel"]}
        ins(%x : tensor<?xi64>) outs(%e : tensor<?xi64>) {
    ^bb0(%a: i64, %b: i64):
      %s = arith.addi %a, %a : i64
      linalg.yield %s : i64
    } -> tensor<?xi64>
    %f = tensor.empty(%n) : tensor<?xi64>
    %z = linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel"]}
        ins(%y : tensor<?xi64>) outs(%f : tensor<?xi64>) {
    ^bb0(%a: i64, %b: i64):
      %t = arith.muli %a, %a : i64
      linalg.yield %t : i64
    } -> tensor<?xi64>
    return %y, %z : tensor<?xi64>, tensor<?xi64>
  }
  // expected-error @below {{expected fused: }}
  idr.func @none(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
