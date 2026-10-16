// NEEDS-ACCEPTANCE: that returns, returns-argument and returns-on-paths hold of what each function returns and fail once for each result they misstate, returns-on-paths once for the constant not listed and once for the listed one on no path.
// RUN: idris-mlir-opt %s --idr-expect=holds=returns=@seven:7,returns=@computed:_,returns-argument=@second:1,returns-on-paths=@choice:1+3 -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=returns=@computed:4,returns=@seven:_,returns-argument=@second:0,returns-on-paths=@choice:1+2 -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 5
// What a function returns, as a value: a constant (@seven), one computed
// at run time (@computed, `_`), a parameter (@second), or on each path
// through a match one of the constants written (@choice, 1 or 3).
// CHECK-DAG: error: expected returns: result {{.*}} of @computed is not the constant {{.*}}
// CHECK-DAG: error: expected returns: result {{.*}} of @seven is not the constant {{.*}}
// CHECK-DAG: error: expected returns-argument: result {{.*}} of @second is not its parameter {{.*}}
// CHECK-DAG: error: expected returns-on-paths: @choice may return a constant not among {{.*}}
// CHECK-DAG: error: expected returns-on-paths: @choice returns {{.*}} on no path
idr.program @returns root(@root) stage(first) {
  idr.func @seven() -> i64 {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  idr.func @computed(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @second(%x: i64, %y: i64) -> i64 {
    return %y : i64
  }
  idr.func @choice(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %three = arith.constant 3 : i64
      idr.yield %three : i64
    }
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
