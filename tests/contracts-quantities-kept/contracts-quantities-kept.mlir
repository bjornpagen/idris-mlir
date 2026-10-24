// RUN: idris-mlir-opt %s --idr-contracts --test-idr-break-contract=relation=quantities-kept -verify-diagnostics -o /dev/null
// A pass that gives a binder used once the identity of another, used many
// times, breaks what Idris proved of each, though every type and every
// signature stays as it was: linear-kept, which compares signatures by
// position, sees nothing, and quantities-kept, which holds each binder by
// its identity to the uses Idris proved, names the pass. The binder used
// once now carries an identity Idris proved used many times; its location
// is a name alone, so its error is at no line. Its own identity is carried
// by no binder, though its function stands, so that error is at the
// function, and the contract's at the module.
// expected-error @+1 {{contract quantities-kept broken by}}
module {
  idr.program @contracts root(@main) stage(first) {
    idr.func @main() {
      return
    }
    // expected-error @+1 {{expected quantities-kept: @keep keeps}}
    idr.func @keep(%x: !idr.graded<once, i64> loc(fused<#idr.binder<@keep, 0>>["x"]),
                   %n: i64 loc(fused<#idr.binder<@keep, 1>>["n"])) -> !idr.graded<once, i64> {
      return %x : !idr.graded<once, i64>
    }
  }
}
// expected-error @unknown {{expected quantities-kept: }}
