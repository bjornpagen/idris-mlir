// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A memo cell's force moves each capture out of its field with the
// reference the field held, and the field holds nothing from then on, so
// the capture holds a reference of its own, whatever holds the cell.
// @main builds a list, moves it into the one capture of a suspension and
// keeps it for a call after the forces, so the list is shared, and forces
// the suspension twice. @force, the suspension's dispatch as
// defunctionalization builds it, takes the cell as a view, as every memo
// cell is taken; in the pending state its exchange runs the label's
// function on the captured list. The capture is counted, which the view
// the cell is held at does not make it, and claims nothing, since
// exclusivity finds the list shared. The slice from the graded stage to
// the owned stage is verified after every pass, so it verifies, with
// nothing expected, only where the exchange binds its capture at the
// capture's own hold, never at the cell's.
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
    %ys = idr.cell.init %c : !idr.cell<!Cons> (%one : i64, %nil : !Nil) -> !Cons
    %xs = idr.data.reindex %ys : !Cons to !List
    %s = idr.cell.new : !idr.cell<!Pending>
    %t = idr.cell.init %s : !idr.cell<!Pending> (%xs : !List) -> !Pending
    %l = idr.data.reindex %t : !Pending to !Lazy
    %a = idr.call @force(%l) : (!Lazy) -> i64
    %b = idr.call @force(%l) : (!Lazy) -> i64
    %h = idr.call @head(%xs) : (!List) -> i64
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
        %h = idr.call @head(%xs) : (!List) -> i64
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
