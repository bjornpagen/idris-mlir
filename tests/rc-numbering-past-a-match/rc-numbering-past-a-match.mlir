// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// One function whose match holds more blocks than the op-numbering
// map starts with, and whose block goes on past the match: numbering
// the match's cases must not disturb the numbering of the ops the
// block still holds after it. A cell built before the match is read
// after it and dies there, so where counting releases it is read
// off those later ops' places. The root prints case 42 and the
// cell's field 7: "49".
// STDIN: \0000
// A match of seventy cases in a block that goes on past it is
// numbered whole when counting asks where its ops sit.
!W = !idr.data<"W">
!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@MkP(i64, !idr.box<!W>)],
  "W" = plain [@C0(), @C1(), @C2(), @C3(), @C4(), @C5(), @C6(), @C7(), @C8(), @C9(), @C10(), @C11(), @C12(), @C13(), @C14(), @C15(), @C16(), @C17(), @C18(), @C19(), @C20(), @C21(), @C22(), @C23(), @C24(), @C25(), @C26(), @C27(), @C28(), @C29(), @C30(), @C31(), @C32(), @C33(), @C34(), @C35(), @C36(), @C37(), @C38(), @C39(), @C40(), @C41(), @C42(), @C43(), @C44(), @C45(), @C46(), @C47(), @C48(), @C49(), @C50(), @C51(), @C52(), @C53(), @C54(), @C55(), @C56(), @C57(), @C58(), @C59(), @C60(), @C61(), @C62(), @C63(), @C64(), @C65(), @C66(), @C67(), @C68(), @C69()]
>
idr.program @"fixture" root(@root) stage(first) types #types {
  idr.func @pick(%w: !idr.box<!W>) -> i64 attributes {total} {
    %k = arith.constant 7 : i64
    %cw = idr.constant !idr.box<!W> #idr.con<!W, @C3, []>
    %p = idr.con !idr.box<!P> @MkP(%k : i64, %cw : !idr.box<!W>)
    %r = idr.match %w : !idr.box<!W> -> (i64) {
    case @C0() {
      %v0 = arith.constant 0 : i64
      idr.yield %v0 : i64
    }
    case @C1() {
      %v1 = arith.constant 1 : i64
      idr.yield %v1 : i64
    }
    case @C2() {
      %v2 = arith.constant 2 : i64
      idr.yield %v2 : i64
    }
    case @C3() {
      %v3 = arith.constant 3 : i64
      idr.yield %v3 : i64
    }
    case @C4() {
      %v4 = arith.constant 4 : i64
      idr.yield %v4 : i64
    }
    case @C5() {
      %v5 = arith.constant 5 : i64
      idr.yield %v5 : i64
    }
    case @C6() {
      %v6 = arith.constant 6 : i64
      idr.yield %v6 : i64
    }
    case @C7() {
      %v7 = arith.constant 7 : i64
      idr.yield %v7 : i64
    }
    case @C8() {
      %v8 = arith.constant 8 : i64
      idr.yield %v8 : i64
    }
    case @C9() {
      %v9 = arith.constant 9 : i64
      idr.yield %v9 : i64
    }
    case @C10() {
      %v10 = arith.constant 10 : i64
      idr.yield %v10 : i64
    }
    case @C11() {
      %v11 = arith.constant 11 : i64
      idr.yield %v11 : i64
    }
    case @C12() {
      %v12 = arith.constant 12 : i64
      idr.yield %v12 : i64
    }
    case @C13() {
      %v13 = arith.constant 13 : i64
      idr.yield %v13 : i64
    }
    case @C14() {
      %v14 = arith.constant 14 : i64
      idr.yield %v14 : i64
    }
    case @C15() {
      %v15 = arith.constant 15 : i64
      idr.yield %v15 : i64
    }
    case @C16() {
      %v16 = arith.constant 16 : i64
      idr.yield %v16 : i64
    }
    case @C17() {
      %v17 = arith.constant 17 : i64
      idr.yield %v17 : i64
    }
    case @C18() {
      %v18 = arith.constant 18 : i64
      idr.yield %v18 : i64
    }
    case @C19() {
      %v19 = arith.constant 19 : i64
      idr.yield %v19 : i64
    }
    case @C20() {
      %v20 = arith.constant 20 : i64
      idr.yield %v20 : i64
    }
    case @C21() {
      %v21 = arith.constant 21 : i64
      idr.yield %v21 : i64
    }
    case @C22() {
      %v22 = arith.constant 22 : i64
      idr.yield %v22 : i64
    }
    case @C23() {
      %v23 = arith.constant 23 : i64
      idr.yield %v23 : i64
    }
    case @C24() {
      %v24 = arith.constant 24 : i64
      idr.yield %v24 : i64
    }
    case @C25() {
      %v25 = arith.constant 25 : i64
      idr.yield %v25 : i64
    }
    case @C26() {
      %v26 = arith.constant 26 : i64
      idr.yield %v26 : i64
    }
    case @C27() {
      %v27 = arith.constant 27 : i64
      idr.yield %v27 : i64
    }
    case @C28() {
      %v28 = arith.constant 28 : i64
      idr.yield %v28 : i64
    }
    case @C29() {
      %v29 = arith.constant 29 : i64
      idr.yield %v29 : i64
    }
    case @C30() {
      %v30 = arith.constant 30 : i64
      idr.yield %v30 : i64
    }
    case @C31() {
      %v31 = arith.constant 31 : i64
      idr.yield %v31 : i64
    }
    case @C32() {
      %v32 = arith.constant 32 : i64
      idr.yield %v32 : i64
    }
    case @C33() {
      %v33 = arith.constant 33 : i64
      idr.yield %v33 : i64
    }
    case @C34() {
      %v34 = arith.constant 34 : i64
      idr.yield %v34 : i64
    }
    case @C35() {
      %v35 = arith.constant 35 : i64
      idr.yield %v35 : i64
    }
    case @C36() {
      %v36 = arith.constant 36 : i64
      idr.yield %v36 : i64
    }
    case @C37() {
      %v37 = arith.constant 37 : i64
      idr.yield %v37 : i64
    }
    case @C38() {
      %v38 = arith.constant 38 : i64
      idr.yield %v38 : i64
    }
    case @C39() {
      %v39 = arith.constant 39 : i64
      idr.yield %v39 : i64
    }
    case @C40() {
      %v40 = arith.constant 40 : i64
      idr.yield %v40 : i64
    }
    case @C41() {
      %v41 = arith.constant 41 : i64
      idr.yield %v41 : i64
    }
    case @C42() {
      %v42 = arith.constant 42 : i64
      idr.yield %v42 : i64
    }
    case @C43() {
      %v43 = arith.constant 43 : i64
      idr.yield %v43 : i64
    }
    case @C44() {
      %v44 = arith.constant 44 : i64
      idr.yield %v44 : i64
    }
    case @C45() {
      %v45 = arith.constant 45 : i64
      idr.yield %v45 : i64
    }
    case @C46() {
      %v46 = arith.constant 46 : i64
      idr.yield %v46 : i64
    }
    case @C47() {
      %v47 = arith.constant 47 : i64
      idr.yield %v47 : i64
    }
    case @C48() {
      %v48 = arith.constant 48 : i64
      idr.yield %v48 : i64
    }
    case @C49() {
      %v49 = arith.constant 49 : i64
      idr.yield %v49 : i64
    }
    case @C50() {
      %v50 = arith.constant 50 : i64
      idr.yield %v50 : i64
    }
    case @C51() {
      %v51 = arith.constant 51 : i64
      idr.yield %v51 : i64
    }
    case @C52() {
      %v52 = arith.constant 52 : i64
      idr.yield %v52 : i64
    }
    case @C53() {
      %v53 = arith.constant 53 : i64
      idr.yield %v53 : i64
    }
    case @C54() {
      %v54 = arith.constant 54 : i64
      idr.yield %v54 : i64
    }
    case @C55() {
      %v55 = arith.constant 55 : i64
      idr.yield %v55 : i64
    }
    case @C56() {
      %v56 = arith.constant 56 : i64
      idr.yield %v56 : i64
    }
    case @C57() {
      %v57 = arith.constant 57 : i64
      idr.yield %v57 : i64
    }
    case @C58() {
      %v58 = arith.constant 58 : i64
      idr.yield %v58 : i64
    }
    case @C59() {
      %v59 = arith.constant 59 : i64
      idr.yield %v59 : i64
    }
    case @C60() {
      %v60 = arith.constant 60 : i64
      idr.yield %v60 : i64
    }
    case @C61() {
      %v61 = arith.constant 61 : i64
      idr.yield %v61 : i64
    }
    case @C62() {
      %v62 = arith.constant 62 : i64
      idr.yield %v62 : i64
    }
    case @C63() {
      %v63 = arith.constant 63 : i64
      idr.yield %v63 : i64
    }
    case @C64() {
      %v64 = arith.constant 64 : i64
      idr.yield %v64 : i64
    }
    case @C65() {
      %v65 = arith.constant 65 : i64
      idr.yield %v65 : i64
    }
    case @C66() {
      %v66 = arith.constant 66 : i64
      idr.yield %v66 : i64
    }
    case @C67() {
      %v67 = arith.constant 67 : i64
      idr.yield %v67 : i64
    }
    case @C68() {
      %v68 = arith.constant 68 : i64
      idr.yield %v68 : i64
    }
    case @C69() {
      %v69 = arith.constant 69 : i64
      idr.yield %v69 : i64
    }
    }
    %f = idr.field %p : !idr.box<!P> @MkP[0] -> i64
    %s = arith.addi %r, %f : i64
    return %s : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %v = idr.constant !idr.box<!W> #idr.con<!W, @C42, []>
    %r = idr.call @pick(%v) : (!idr.box<!W>) -> i64
    %s = idr.str.show_sint %r : i64
    %w1 = idr.io.put_str %s, %w0
    return %w1 : !idr.world
  }
}
