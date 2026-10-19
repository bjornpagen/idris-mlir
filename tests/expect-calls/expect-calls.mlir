// RUN: idris-mlir-opt %s '--idr-expect=holds=call-order=@ordered:[@g,@h],calls-distinct=@ordered:@g,calls-read=@ordered:@g,calls-read=@ordered:@h,calls-only=@ordered:[@g,@h],direct-calls=@ordered' -o /dev/null
// RUN: idris-mlir-opt %s '--idr-expect=holds=call-order=@ordered:[@h,@g],call-order=@through:[@g],calls-distinct=@again:@g,calls-read=@again:@h,calls-only=@again:[@g],direct-calls=@through' -verify-diagnostics -o /dev/null
// What a function asks of its callees, as the calls it makes: @ordered
// calls @g, then @h on what @g gave, each once and each read. @again calls
// @g twice on one operand and reads nothing @h gives; @through calls only
// through a closure it is given.
idr.program @calls root(@root) stage(higher) {
  idr.func @g(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @h(%x: i64) -> i64 {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  // expected-error @below {{expected call-order: }}
  idr.func @ordered(%x: i64) -> i64 {
    %a = idr.call @g(%x) : (i64) -> i64
    %b = idr.call @h(%a) : (i64) -> i64
    return %b : i64
  }
  idr.func @again(%x: i64) -> i64 {
    %a = idr.call @g(%x) : (i64) -> i64
    // expected-error @below {{expected calls-distinct: }}
    %b = idr.call @g(%x) : (i64) -> i64
    // expected-error @below {{expected calls-read: }}
    // expected-error @below {{expected calls-only: }}
    %c = idr.call @h(%x) : (i64) -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
  // expected-error @below {{expected call-order: }}
  idr.func @through(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    // expected-error @below {{expected direct-calls: }}
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
