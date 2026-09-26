R"mlir(
// Helpers that idr-lower copies into a module (LOW-IO-*, LOW-CRASH-1). They
// use static storage and the stack only; the only external symbols are write,
// read and _exit (LOW-EXT-1). Byte copies use volatile stores so that LLVM does
// not turn them into calls to memcpy.
module {
  llvm.func @write(i32, !llvm.ptr, i64) -> i64
  llvm.func @read(i32, !llvm.ptr, i64) -> i64
  llvm.func @_exit(i32) attributes {passthrough = ["noreturn", "nounwind"]}

  llvm.mlir.global internal @__idr_obuf() : !llvm.array<4096 x i8> {
    %z = llvm.mlir.zero : !llvm.array<4096 x i8>
    llvm.return %z : !llvm.array<4096 x i8>
  }
  llvm.mlir.global internal @__idr_olen(0 : i64) : i64
  llvm.mlir.global internal @__idr_ibuf() : !llvm.array<4096 x i8> {
    %z = llvm.mlir.zero : !llvm.array<4096 x i8>
    llvm.return %z : !llvm.array<4096 x i8>
  }
  llvm.mlir.global internal @__idr_ipos(0 : i64) : i64
  llvm.mlir.global internal @__idr_ilen(0 : i64) : i64

  // Writes n bytes to fd, looping over partial writes. A failed write
  // abandons the rest (SEM-IO-6).
  func.func private @__idr_write_all(%fd: i32, %p: !llvm.ptr, %n: i64) {
    %c0 = arith.constant 0 : i64
    %r:2 = scf.while (%q = %p, %m = %n) : (!llvm.ptr, i64) -> (!llvm.ptr, i64) {
      %more = arith.cmpi sgt, %m, %c0 : i64
      scf.condition(%more) %q, %m : !llvm.ptr, i64
    } do {
    ^bb0(%q: !llvm.ptr, %m: i64):
      %w = llvm.call @write(%fd, %q, %m) : (i32, !llvm.ptr, i64) -> i64
      %ok = arith.cmpi sgt, %w, %c0 : i64
      %step = arith.select %ok, %w, %m : i64
      %q2 = llvm.getelementptr %q[%step] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %m2 = arith.subi %m, %step : i64
      scf.yield %q2, %m2 : !llvm.ptr, i64
    }
    return
  }

  func.func private @__idr_flush() {
    %lp = llvm.mlir.addressof @__idr_olen : !llvm.ptr
    %len = llvm.load %lp : !llvm.ptr -> i64
    %buf = llvm.mlir.addressof @__idr_obuf : !llvm.ptr
    %fd = arith.constant 1 : i32
    func.call @__idr_write_all(%fd, %buf, %len) : (i32, !llvm.ptr, i64) -> ()
    %c0 = arith.constant 0 : i64
    llvm.store %c0, %lp : i64, !llvm.ptr
    return
  }

  func.func private @__idr_put_bytes(%p: !llvm.ptr, %n: i64) {
    %cap = arith.constant 4096 : i64
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %lp = llvm.mlir.addressof @__idr_olen : !llvm.ptr
    %len = llvm.load %lp : !llvm.ptr -> i64
    %sum = arith.addi %len, %n : i64
    %over = arith.cmpi sgt, %sum, %cap : i64
    scf.if %over {
      func.call @__idr_flush() : () -> ()
    }
    %big = arith.cmpi sgt, %n, %cap : i64
    scf.if %big {
      %fd = arith.constant 1 : i32
      func.call @__idr_write_all(%fd, %p, %n) : (i32, !llvm.ptr, i64) -> ()
    } else {
      %len2 = llvm.load %lp : !llvm.ptr -> i64
      %buf = llvm.mlir.addressof @__idr_obuf : !llvm.ptr
      scf.for %i = %c0 to %n step %c1 : i64 {
        %src = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %b = llvm.load %src : !llvm.ptr -> i8
        %off = arith.addi %len2, %i : i64
        %dst = llvm.getelementptr %buf[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        llvm.store volatile %b, %dst : i8, !llvm.ptr
      }
      %len3 = arith.addi %len2, %n : i64
      llvm.store %len3, %lp : i64, !llvm.ptr
    }
    return
  }

  // The UTF-8 encoding of a scalar value (SEM-IO-2).
  func.func private @__idr_put_char(%c: i32) {
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32
    %c3 = arith.constant 3 : i32
    %c4 = arith.constant 4 : i32
    %c6 = arith.constant 6 : i32
    %x80 = arith.constant 128 : i32
    %x800 = arith.constant 2048 : i32
    %x10000 = arith.constant 65536 : i32
    %x3f = arith.constant 63 : i32
    %xc0 = arith.constant 192 : i32
    %xe0 = arith.constant 224 : i32
    %xf0 = arith.constant 240 : i32
    %lt1 = arith.cmpi ult, %c, %x80 : i32
    %lt2 = arith.cmpi ult, %c, %x800 : i32
    %lt3 = arith.cmpi ult, %c, %x10000 : i32
    %n34 = arith.select %lt3, %c3, %c4 : i32
    %n234 = arith.select %lt2, %c2, %n34 : i32
    %n = arith.select %lt1, %c1, %n234 : i32
    %p34 = arith.select %lt3, %xe0, %xf0 : i32
    %prefix = arith.select %lt2, %xc0, %p34 : i32
    %four = arith.constant 4 : i64
    %buf = llvm.alloca %four x i8 : (i64) -> !llvm.ptr
    %nm1 = arith.subi %n, %c1 : i32
    %leadShift = arith.muli %nm1, %c6 : i32
    %leadBits = arith.shrui %c, %leadShift : i32
    %leadMulti = arith.ori %prefix, %leadBits : i32
    %lead = arith.select %lt1, %c, %leadMulti : i32
    %lead8 = arith.trunci %lead : i32 to i8
    llvm.store volatile %lead8, %buf : i8, !llvm.ptr
    %k0 = arith.constant 1 : i32
    scf.for %k = %k0 to %n step %c1 : i32 {
      %rest = arith.subi %nm1, %k : i32
      %shift = arith.muli %rest, %c6 : i32
      %bits = arith.shrui %c, %shift : i32
      %low = arith.andi %bits, %x3f : i32
      %cont = arith.ori %low, %x80 : i32
      %cont8 = arith.trunci %cont : i32 to i8
      %k64 = arith.extui %k : i32 to i64
      %dst = llvm.getelementptr %buf[%k64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      llvm.store volatile %cont8, %dst : i8, !llvm.ptr
    }
    %n64 = arith.extui %n : i32 to i64
    func.call @__idr_put_bytes(%buf, %n64) : (!llvm.ptr, i64) -> ()
    return
  }

  // Decimal digits of an unsigned value, formatted on the stack.
  func.func private @__idr_put_int_u(%v: i64) {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %c10 = arith.constant 10 : i64
    %c20 = arith.constant 20 : i64
    %c48 = arith.constant 48 : i64
    %buf = llvm.alloca %c20 x i8 : (i64) -> !llvm.ptr
    %r:2 = scf.while (%x = %v, %i = %c20) : (i64, i64) -> (i64, i64) {
      %i1 = arith.subi %i, %c1 : i64
      %d = arith.remui %x, %c10 : i64
      %ch = arith.addi %d, %c48 : i64
      %ch8 = arith.trunci %ch : i64 to i8
      %dst = llvm.getelementptr %buf[%i1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      llvm.store volatile %ch8, %dst : i8, !llvm.ptr
      %x1 = arith.divui %x, %c10 : i64
      %more = arith.cmpi ne, %x1, %c0 : i64
      scf.condition(%more) %x1, %i1 : i64, i64
    } do {
    ^bb0(%x1: i64, %i1: i64):
      scf.yield %x1, %i1 : i64, i64
    }
    %start = llvm.getelementptr %buf[%r#1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %len = arith.subi %c20, %r#1 : i64
    func.call @__idr_put_bytes(%start, %len) : (!llvm.ptr, i64) -> ()
    return
  }

  func.func private @__idr_put_int_s(%v: i64) {
    %c0 = arith.constant 0 : i64
    %neg = arith.cmpi slt, %v, %c0 : i64
    %mag = scf.if %neg -> i64 {
      %minus = arith.constant 45 : i32
      func.call @__idr_put_char(%minus) : (i32) -> ()
      %m = arith.subi %c0, %v : i64
      scf.yield %m : i64
    } else {
      scf.yield %v : i64
    }
    func.call @__idr_put_int_u(%mag) : (i64) -> ()
    return
  }

  // The next input byte (0-255), or -1 at end of input. Output is flushed
  // before blocking on input (SEM-IO-4).
  func.func private @__idr_peek() -> i32 {
    %c0 = arith.constant 0 : i64
    %cap = arith.constant 4096 : i64
    %pp = llvm.mlir.addressof @__idr_ipos : !llvm.ptr
    %lp = llvm.mlir.addressof @__idr_ilen : !llvm.ptr
    %buf = llvm.mlir.addressof @__idr_ibuf : !llvm.ptr
    %pos = llvm.load %pp : !llvm.ptr -> i64
    %len = llvm.load %lp : !llvm.ptr -> i64
    %empty = arith.cmpi sge, %pos, %len : i64
    scf.if %empty {
      func.call @__idr_flush() : () -> ()
      %fd = arith.constant 0 : i32
      %r = llvm.call @read(%fd, %buf, %cap) : (i32, !llvm.ptr, i64) -> i64
      %ok = arith.cmpi sgt, %r, %c0 : i64
      %n = arith.select %ok, %r, %c0 : i64
      llvm.store %n, %lp : i64, !llvm.ptr
      llvm.store %c0, %pp : i64, !llvm.ptr
    }
    %pos2 = llvm.load %pp : !llvm.ptr -> i64
    %len2 = llvm.load %lp : !llvm.ptr -> i64
    %have = arith.cmpi slt, %pos2, %len2 : i64
    %b = scf.if %have -> i32 {
      %src = llvm.getelementptr %buf[%pos2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %byte = llvm.load %src : !llvm.ptr -> i8
      %wide = arith.extui %byte : i8 to i32
      scf.yield %wide : i32
    } else {
      %eof = arith.constant -1 : i32
      scf.yield %eof : i32
    }
    return %b : i32
  }

  func.func private @__idr_advance() {
    %c1 = arith.constant 1 : i64
    %pp = llvm.mlir.addressof @__idr_ipos : !llvm.ptr
    %pos = llvm.load %pp : !llvm.ptr -> i64
    %next = arith.addi %pos, %c1 : i64
    llvm.store %next, %pp : i64, !llvm.ptr
    return
  }

  // One UTF-8 encoded scalar value from stdin (SEM-IO-3): '\0' at end of
  // input, U+FFFD for each maximal invalid subsequence.
  func.func private @__idr_get_char() -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32
    %c3 = arith.constant 3 : i32
    %c4 = arith.constant 4 : i32
    %c6 = arith.constant 6 : i32
    %fffd = arith.constant 65533 : i32
    %x80 = arith.constant 128 : i32
    %x3f = arith.constant 63 : i32
    %b0 = func.call @__idr_peek() : () -> i32
    %eof = arith.cmpi slt, %b0, %c0 : i32
    %result = scf.if %eof -> i32 {
      scf.yield %c0 : i32
    } else {
      func.call @__idr_advance() : () -> ()
      %ascii = arith.cmpi slt, %b0, %x80 : i32
      %r2 = scf.if %ascii -> i32 {
        scf.yield %b0 : i32
      } else {
        %xc2 = arith.constant 194 : i32
        %xdf = arith.constant 223 : i32
        %xe0 = arith.constant 224 : i32
        %xed = arith.constant 237 : i32
        %xef = arith.constant 239 : i32
        %xf0 = arith.constant 240 : i32
        %xf4 = arith.constant 244 : i32
        %x1f = arith.constant 31 : i32
        %x0f = arith.constant 15 : i32
        %x07 = arith.constant 7 : i32
        %x90 = arith.constant 144 : i32
        %x8f = arith.constant 143 : i32
        %x9f = arith.constant 159 : i32
        %xa0 = arith.constant 160 : i32
        %xbf = arith.constant 191 : i32
        %geC = arith.cmpi uge, %b0, %xc2 : i32
        %leC = arith.cmpi ule, %b0, %xdf : i32
        %isC = arith.andi %geC, %leC : i1
        %geE = arith.cmpi uge, %b0, %xe0 : i32
        %leE = arith.cmpi ule, %b0, %xef : i32
        %isE = arith.andi %geE, %leE : i1
        %geF = arith.cmpi uge, %b0, %xf0 : i32
        %leF = arith.cmpi ule, %b0, %xf4 : i32
        %isF = arith.andi %geF, %leF : i1
        %ce = arith.ori %isC, %isE : i1
        %valid = arith.ori %ce, %isF : i1
        %r3 = scf.if %valid -> i32 {
          %n34 = arith.select %isE, %c3, %c4 : i32
          %n = arith.select %isC, %c2, %n34 : i32
          %isE0 = arith.cmpi eq, %b0, %xe0 : i32
          %isF0 = arith.cmpi eq, %b0, %xf0 : i32
          %isED = arith.cmpi eq, %b0, %xed : i32
          %isF4 = arith.cmpi eq, %b0, %xf4 : i32
          %lo0 = arith.select %isF0, %x90, %x80 : i32
          %lo = arith.select %isE0, %xa0, %lo0 : i32
          %hi0 = arith.select %isF4, %x8f, %xbf : i32
          %hi = arith.select %isED, %x9f, %hi0 : i32
          %m34 = arith.select %isE, %x0f, %x07 : i32
          %mask = arith.select %isC, %x1f, %m34 : i32
          %init = arith.andi %b0, %mask : i32
          %false = arith.constant false
          %true = arith.constant true
          %s:3 = scf.while (%k = %c1, %acc = %init, %bad = %false) : (i32, i32, i1) -> (i32, i32, i1) {
            %lt = arith.cmpi slt, %k, %n : i32
            %good = arith.xori %bad, %true : i1
            %go = arith.andi %lt, %good : i1
            scf.condition(%go) %k, %acc, %bad : i32, i32, i1
          } do {
          ^bb0(%k: i32, %acc: i32, %bad: i1):
            %b = func.call @__idr_peek() : () -> i32
            %first = arith.cmpi eq, %k, %c1 : i32
            %lok = arith.select %first, %lo, %x80 : i32
            %hik = arith.select %first, %hi, %xbf : i32
            %ge = arith.cmpi sge, %b, %lok : i32
            %le = arith.cmpi sle, %b, %hik : i32
            %ok = arith.andi %ge, %le : i1
            scf.if %ok {
              func.call @__idr_advance() : () -> ()
            }
            %sh = arith.shli %acc, %c6 : i32
            %low = arith.andi %b, %x3f : i32
            %acc2 = arith.ori %sh, %low : i32
            %k2 = arith.addi %k, %c1 : i32
            %bad2 = arith.xori %ok, %true : i1
            scf.yield %k2, %acc2, %bad2 : i32, i32, i1
          }
          %decoded = arith.select %s#2, %fffd, %s#1 : i32
          scf.yield %decoded : i32
        } else {
          scf.yield %fffd : i32
        }
        scf.yield %r3 : i32
      }
      scf.yield %r2 : i32
    }
    return %result : i32
  }

  func.func private @__idr_exit(%code: i64) {
    func.call @__idr_flush() : () -> ()
    %c = arith.trunci %code : i64 to i32
    llvm.call @_exit(%c) : (i32) -> ()
    return
  }

  // Flushes stdout, writes the message to stderr, exits with status 1
  // (SEM-CRASH-1).
  func.func private @__idr_crash(%p: !llvm.ptr, %n: i64) {
    func.call @__idr_flush() : () -> ()
    %fd = arith.constant 2 : i32
    func.call @__idr_write_all(%fd, %p, %n) : (i32, !llvm.ptr, i64) -> ()
    %one = arith.constant 1 : i32
    llvm.call @_exit(%one) : (i32) -> ()
    return
  }
}
)mlir"
