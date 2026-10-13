// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A clone names itself, by the key every call of it was made for, so MLIR's
// interprocedural passes take a reference that is no call for the callers
// they cannot see yet. A key that specializes has one hole per parameter:
// the hole of a parameter is its position, so its holes are 0 to n-1 for n
// parameters. idr.func's verifier reads only
// the function's own attributes and type.

// expected-error @+1 {{expects clone to name the function and its key}}
idr.func private @f(%x: i64) -> i64
    attributes {clone = #idr.clone<@g, #idr.spec_key<"f", [#idr.key_hole<0>]>>} {
  return %x : i64
}

// -----

// expected-error @+1 {{expects clone to name the function and its key}}
idr.func private @f(%x: i64) -> i64 attributes {clone = #idr.clone<@f, "f">} {
  return %x : i64
}

// -----

// expected-error @+1 {{has a clone key with hole 1, but takes 1 parameters}}
idr.func private @f(%x: i64) -> i64
    attributes {clone = #idr.clone<@f, #idr.spec_key<"f", [#idr.key_hole<0>, #idr.key_hole<1>]>>} {
  return %x : i64
}

// -----

// expected-error @+1 {{has a clone key with no hole 0, but takes 2 parameters}}
idr.func private @f(%x: i64, %y: i64) -> i64
    attributes {clone = #idr.clone<@f, #idr.spec_key<"f", [#idr.key_hole<1>, #idr.key_hole<1>]>>} {
  return %x : i64
}

// -----

// The keys that fit: a specialization with its holes inside a closure, and
// a raised callee.
idr.func private @apply.spec1(%x: i64) -> i64
    attributes {clone = #idr.clone<@apply.spec1, #idr.spec_key<"apply", [#idr.key_closure<"neg", []>, #idr.key_hole<0>]>>} {
  return %x : i64
}
idr.func private @count.raise1(%k: i64, %w: !idr.world) -> !idr.world
    attributes {clone = #idr.clone<@count.raise1, #idr.key_apply<"count", 1>>} {
  return %w : !idr.world
}
