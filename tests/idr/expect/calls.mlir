// NEEDS-ACCEPTANCE: that each failing request of Calls.cpp reports exactly the one error checked, at the call or the function it names; idr.apply is the call through a value.
// RUN: idris-mlir-opt %s '--idr-expect=holds=call-order=@ordered:[@g,@h],calls-distinct=@ordered:@g,calls-read=@ordered:@g,calls-read=@ordered:@h,calls-only=@ordered:[@g,@h],direct-calls=@ordered' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=call-order=@ordered:[@h,@g],call-order=@through:[@g],calls-distinct=@again:@g,calls-read=@again:@h,calls-only=@again:[@g],direct-calls=@through' -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 6
// What a function asks of its callees, as the calls it makes: @ordered
// calls @g, then @h on what @g gave, each once and each read. @again calls
// @g twice on one operand and reads nothing @h gives; @through calls only
// through a closure it is given.
// CHECK-DAG: error: expected call-order: @ordered makes no call of {{.*}} after its call of {{.*}}
// CHECK-DAG: error: expected call-order: @through makes no call of {{.*}}
// CHECK-DAG: error: expected calls-distinct: @again calls {{.*}} again on what an earlier call took
// CHECK-DAG: error: expected calls-read: @again calls {{.*}} and reads nothing it gives
// CHECK-DAG: error: expected calls-only: @again calls {{.*}}, which the list does not name
// CHECK-DAG: error: expected direct-calls: {{.*}} in @through calls through a value
idr.program @calls root(@root) stage(higher) {
  idr.func @g(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @h(%x: i64) -> i64 {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func @ordered(%x: i64) -> i64 {
    %a = idr.call @g(%x) : (i64) -> i64
    %b = idr.call @h(%a) : (i64) -> i64
    return %b : i64
  }
  idr.func @again(%x: i64) -> i64 {
    %a = idr.call @g(%x) : (i64) -> i64
    %b = idr.call @g(%x) : (i64) -> i64
    %c = idr.call @h(%x) : (i64) -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
  idr.func @through(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
