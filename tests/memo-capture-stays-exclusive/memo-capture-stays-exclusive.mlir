// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned},idr-expect{holds=tests-nothing=@force})' -o /dev/null
// A memo cell's force moves each capture out of its field with the
// reference the field held, and the field holds nothing from then on: the
// capture holds what was moved into the field, whoever else holds the cell.
// @main builds a list cell, moves it into the one capture of a suspension
// and forces the suspension once. @force, the suspension's dispatch, takes
// the cell as a view, as every memo cell is taken, so nothing is known of
// the cell's sharing there; in the pending state its exchange runs the
// label's code in place, which reads the head of the captured list, its
// last use, so counting takes the list apart there. The list was fresh
// when it moved into the field, so the capture is proved unshared, though
// nothing is known of the cell: the take reads no count and its token
// holds the list's cell, from the graded stage to the owned stage, each
// step of which the module verifies after.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!List = !idr.data<#List>
!Nil = !idr.data<#List @Nil>
!Cons = !idr.data<#List @Cons>
#Lazy = #idr.family<"Lazy" memo [] {
    @head fn @head (!List)
  } forced (i64)>
!Lazy = !idr.data<#Lazy>
!Pending = !idr.data<#Lazy @head>
!Running = !idr.data<#Lazy @running>
!Forced = !idr.data<#Lazy @forced>
idr.program @memo root(@main) stage(graded) {
  idr.func @main() {
    %one = arith.constant 1 : i64
    %nil = idr.data.con() : !Nil
    %c = idr.cell.new : !idr.cell<!Cons>
    %xs = idr.cell.init %c : !idr.cell<!Cons> (%one : i64, %nil : !Nil) -> !Cons
    %s = idr.cell.new : !idr.cell<!Pending>
    %t = idr.cell.init %s : !idr.cell<!Pending> (%xs : !Cons) -> !Pending
    %l = idr.data.reindex %t : !Pending to !Lazy
    %h = idr.call @force(%l) : (!Lazy) -> i64
    idr.return
  }
  idr.func @head(%xs: !List) -> i64 {
    %h = idr.data.match %xs : !List -> (i64) {
    case @Nil(%n: !Nil) {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    case @Cons(%y: !Cons) {
      %x = idr.data.field %y[0] : !Cons -> i64
      idr.yield %x : i64
    }
    }
    idr.return %h : i64
  }
  idr.func @force(%cell: !Lazy) -> i64 {
    %v = idr.data.match %cell : !Lazy -> (i64) {
    case @head(%p: !Pending) {
      %x = idr.memo.run %p : !Pending -> i64 {
      ^bb0(%xs: !List):
        %h = idr.data.match %xs : !List -> (i64) {
        case @Nil(%n: !Nil) {
          %zero = arith.constant 0 : i64
          idr.yield %zero : i64
        }
        case @Cons(%y: !Cons) {
          %first = idr.data.field %y[0] : !Cons -> i64
          idr.yield %first : i64
        }
        }
        idr.memo.yield %h : i64 then %h : i64
      }
      idr.yield %x : i64
    }
    case @running(%r: !Running) {
      idr.crash.cause suspension_forced_itself at #idr.site<"Main.idr", 1, 1, "Main.force">
    }
    case @forced(%f: !Forced) {
      %x = idr.data.field %f[0] : !Forced -> i64
      idr.yield %x : i64
    }
    }
    idr.return %v : i64
  }
}
