// NEEDS-ACCEPTANCE: idr.delay of the world is refused by its operand's constraint (Idr_Capture), whose message names the world's type.
// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// An evaluated suspension holds its value, and a world is never held: it
// passes only as an argument or a result.

idr.program @"delay-world" root(@f) stage(higher) {
  idr.func @f(%w: !idr.world) {
    // expected-error @+1 {{operand #0 must be a value other than the world, but got '!idr.world'}}
    %t = idr.delay %w : !idr.world -> !idr.lazy<!idr.world>
    return
  }
}
