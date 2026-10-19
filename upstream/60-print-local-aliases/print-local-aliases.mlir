// RUN: mlir-opt %s -allow-unregistered-dialect -mlir-print-ir-after-all \
// RUN:   -pass-pipeline='builtin.module(func.func(canonicalize))' -o /dev/null 2>&1 \
// RUN:   | FileCheck %s --check-prefix=INLINE
// RUN: mlir-opt %s -allow-unregistered-dialect -mlir-print-ir-after-all \
// RUN:   -mlir-print-local-aliases \
// RUN:   -pass-pipeline='builtin.module(func.func(canonicalize))' -o /dev/null 2>&1 \
// RUN:   | FileCheck %s --check-prefix=ALIASES

// A nested operation printed by the IR printer has local scope: by default
// its attributes and types are written inline at every use; with
// -mlir-print-local-aliases its aliases come first, as at module scope.

// INLINE-LABEL: IR Dump After Canonicalizer
// INLINE-NOT: #map =
// INLINE: func.func @f()
// INLINE: m = affine_map<(d0) -> (d0 + 1)>
// INLINE: n = affine_map<(d0) -> (d0 + 1)>

// ALIASES-LABEL: IR Dump After Canonicalizer
// ALIASES: #map = affine_map<(d0) -> (d0 + 1)>
// ALIASES: func.func @f()
// ALIASES: m = #map
// ALIASES: n = #map
func.func @f() {
  "test.op"() {m = affine_map<(d0) -> (d0 + 1)>} : () -> ()
  "test.op"() {n = affine_map<(d0) -> (d0 + 1)>} : () -> ()
  return
}
