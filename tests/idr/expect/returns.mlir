// NEEDS-ACCEPTANCE: that returns, returns-argument and returns-on-paths hold of what each function returns and that the -verify-diagnostics run passes: one error for each result misstated, returns-on-paths one for the constant not written and one for the written one on no path; the default of @choice binds its scrutinee (this wave's printed form).
// RUN: idris-mlir-opt %s --idr-expect=holds=returns=@seven:7,returns=@computed:_,returns-argument=@second:1,returns-on-paths=@choice:1+3 -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=returns=@computed:4,returns=@seven:_,returns-argument=@second:0,returns-on-paths=@choice:1+2 -verify-diagnostics -o /dev/null
// What a function returns, as a value: a constant (@seven), one computed
// at run time (@computed, `_`), a parameter (@second), or on each path
// through a match one of the constants written (@choice, 1 or 3).
idr.program @returns root(@root) stage(first) {
  idr.func @seven() -> i64 {
    %c = arith.constant 7 : i64
    // expected-error @below {{expected returns: result 0 of @seven is not the constant _}}
    return %c : i64
  }
  idr.func @computed(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    // expected-error @below {{expected returns: result 0 of @computed is not the constant 4}}
    return %y : i64
  }
  idr.func @second(%x: i64, %y: i64) -> i64 {
    // expected-error @below {{expected returns-argument: result 0 of @second is not its parameter 0}}
    return %y : i64
  }
  // expected-error @below {{expected returns-on-paths: @choice returns 2 on no path}}
  idr.func @choice(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default(%d: i64) {
      // expected-error @below {{expected returns-on-paths: @choice may return a constant not among 1+2}}
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
