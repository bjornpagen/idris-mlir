// RUN: idris-mlir-opt %s '--idr-expect=holds=crash-sites=@f:x,calls=@f,labels=@f:res:[@g],effects=@f:sometimes,stage=later,contified=@f,returns=@f,call-order=@f:x,signature=@f,loops=@f:x,apart=@f,largest-function=-1,crash-sites=@f:-1,effects=@f:io+sometimes' -verify-diagnostics -o /dev/null
// A request's argument is read once, at the request, into its property's
// shape, before the property runs; one that does not have the shape is
// refused there, in the one wording every property shares, whatever the
// module holds, and the property does not run. A property that takes no
// argument shows its name alone. Each shape is refused: a count that is
// no number or is negative, a pair without its second function, a list
// that is no list, a position or an effect or a stage of no name (one
// among known effects too), a type missing, a value list missing.
// expected-error @-10 {{idr-expect: crash-sites=@f:x does not read as crash-sites=@f:<n>}}
// expected-error @-11 {{idr-expect: calls=@f does not read as calls=@f:@g}}
// expected-error @-12 {{idr-expect: labels=@f:res:[@g] does not read as labels=@f:<position>:[@g, ...]}}
// expected-error @-13 {{idr-expect: effects=@f:sometimes does not read as effects=@f:<e>+<e>...}}
// expected-error @-14 {{idr-expect: stage=later does not read as stage=<stage>}}
// expected-error @-15 {{idr-expect: contified=@f does not read as contified}}
// expected-error @-16 {{idr-expect: returns=@f does not read as returns=@f:<v>/<v>...}}
// expected-error @-17 {{idr-expect: call-order=@f:x does not read as call-order=@f:[@g, ...]}}
// expected-error @-18 {{idr-expect: signature=@f does not read as signature=@f:<type>}}
// expected-error @-19 {{idr-expect: loops=@f:x does not read as loops=@f[:<n>]}}
// expected-error @-20 {{idr-expect: apart=@f does not read as apart=@f:@g}}
// expected-error @-21 {{idr-expect: largest-function=-1 does not read as largest-function=<n>}}
// expected-error @-22 {{idr-expect: crash-sites=@f:-1 does not read as crash-sites=@f:<n>}}
// expected-error @-23 {{idr-expect: effects=@f:io+sometimes does not read as effects=@f:<e>+<e>...}}
idr.program @malformed root(@root) stage(first) types #idr.types<> {
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
