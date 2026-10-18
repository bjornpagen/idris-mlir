// NEEDS-ACCEPTANCE: that each request whose argument does not have its property's shape is refused once, at the module (line 0, the implicit module's location), in the one wording `idr-expect: <name>=<text> does not read as <name>=<form>`, the next request still read, and the run passes under -verify-diagnostics.
// RUN: idris-mlir-opt %s '--idr-expect=holds=crash-sites=@f:x,calls=@f,labels=@f:res:[@g],effects=@f:sometimes,stage=later,contified=@f' -verify-diagnostics -o /dev/null
// A request's argument is read once, at the request, into its property's
// shape, before the property runs; one that does not have the shape is
// refused there, in the one wording every property shares, whatever the
// module holds, and the property does not run. A property that takes no
// argument shows its name alone.
// expected-error @-8 {{idr-expect: crash-sites=@f:x does not read as crash-sites=@f:<n>}}
// expected-error @-9 {{idr-expect: calls=@f does not read as calls=@f:@g}}
// expected-error @-10 {{idr-expect: labels=@f:res:[@g] does not read as labels=@f:<position>:[@g, ...]}}
// expected-error @-11 {{idr-expect: effects=@f:sometimes does not read as effects=@f:<e>+<e>...}}
// expected-error @-12 {{idr-expect: stage=later does not read as stage=<stage>}}
// expected-error @-13 {{idr-expect: contified=@f does not read as contified}}
idr.program @malformed root(@root) stage(first) {
  idr.func @f(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @g(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
