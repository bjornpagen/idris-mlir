// An op of a dialect the writing tool does not load: its properties are
// kept as an attribute, which the bytecode writer stores as such in the
// properties section, flagging the op name as not registered. A reader that
// has the dialect loaded decodes that entry with the op's native reader.
//
//   mlir-opt -allow-unregistered-dialect -emit-bytecode written-unregistered.mlir -o x.mlirbc
//   idris-mlir-opt x.mlirbc
"idr.crash"() <{message = "boom"}> : () -> ()
