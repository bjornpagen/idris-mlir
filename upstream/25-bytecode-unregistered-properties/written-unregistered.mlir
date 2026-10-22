// An op of a dialect the writing tool does not load: its properties are
// kept as an attribute, which the bytecode writer stores as such in the
// properties section, flagging the op name as not registered. A reader that
// has the dialect loaded decodes that entry with the op's native reader.
// The program is the smallest the idr dialect verifies, in the generic form
// a tool without the dialect parses.
//
//   mlir-opt -allow-unregistered-dialect -emit-bytecode written-unregistered.mlir -o x.mlirbc
//   idris-mlir-opt x.mlirbc
"idr.program"() <{root = @main, stage = 1 : i32, sym_name = "written"}> ({
  "idr.func"() <{function_type = () -> i64, sym_name = "main"}> ({
    %c = "arith.constant"() <{value = 7 : i64}> : () -> i64
    "idr.return"(%c) : (i64) -> ()
  }) : () -> ()
}) : () -> ()
