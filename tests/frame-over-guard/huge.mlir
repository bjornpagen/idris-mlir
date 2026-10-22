module {
  llvm.func @huge(%n: i64) -> i8 {
    %size = llvm.mlir.constant(67108864 : i64) : i64
    %buffer = llvm.alloca %size x i8 : (i64) -> !llvm.ptr
    %at = llvm.getelementptr %buffer[%n] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %byte = llvm.load %at : !llvm.ptr -> i8
    llvm.return %byte : i8
  }
  llvm.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    %n = llvm.sext %argc : i32 to i64
    %byte = llvm.call @huge(%n) : (i64) -> i8
    %status = llvm.zext %byte : i8 to i32
    llvm.return %status : i32
  }
}
