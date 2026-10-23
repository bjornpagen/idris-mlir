// RUN: idris-mlir-opt %s --idr-contracts --test-idr-break-contract=relation=quantities-kept -verify-diagnostics -o /dev/null
// A pass that gives one binder's identity to another of other uses breaks
// what Idris proved of each, though every type and every signature stays
// as it was: linear-kept, which compares signatures by position, sees
// nothing, and quantities-kept, which holds each binder by its identity to
// the uses Idris proved, names the pass. The test pass trades the
// identities of a parameter used once and one used many; their locations
// are names alone, so the binders' own errors are at no line, and the
// contract's at the module.
// expected-error @+1 {{contract quantities-kept broken by}}
module {
  idr.program @contracts root(@main) stage(first) {
    idr.func @main() {
      return
    }
    idr.func @keep(%x: !idr.graded<once, i64> loc(fused<#idr.binder<@keep, 0>>["x"]),
                   %n: i64 loc(fused<#idr.binder<@keep, 1>>["n"])) -> !idr.graded<once, i64> {
      return %x : !idr.graded<once, i64>
    }
  }
}
// expected-error @unknown {{expected quantities-kept: }}
