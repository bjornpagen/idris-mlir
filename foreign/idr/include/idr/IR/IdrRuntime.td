// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's C functions idr-lower calls that no op names: the cell,
// array, count, string-building, crash and start entries. An op's own
// function is its Idr_Runtime mark; these are records beside the ops, so
// that idris-mlir-tblgen reads every function the lowering calls in one
// reading of the records, refuses a symbol two of them declare, declares
// each in idris_rt_ops.h (which runtime/idris_rt.h includes, so a
// definition that disagrees with its record does not compile), and writes
// each into the table the lowering calls through
// (IdrRuntimeAbi.inc, idr::runtime::helper). Each record is the runtime's
// prototype exactly; its meaning is documented beside its definition.

#ifndef IDR_RUNTIME
#define IDR_RUNTIME

include "idr/IR/IdrOps.td"

// A C type as a runtime function's declaration spells it: `pattern`, a
// declarator with `{0}` where the declared name goes, so that one rule
// writes a parameter, a result and a function alike; and `kind`, how the
// lowering passes or reads a value of it (a case of idr::runtime's
// OperandKind for a parameter, of ResultKind for a result, by its
// spelling), which idris-mlir-tblgen checks at the record.
class Idr_CType<string pattern, string kind> {
  string cType = pattern;
  string abiKind = kind;
}

def Idr_CVoid : Idr_CType<"void {0}", "Void">;
def Idr_CNoReturn : Idr_CType<"IDRIS_RT_NORETURN void {0}", "NoReturn">;
def Idr_CInt : Idr_CType<"int {0}", "Int32">;
def Idr_CInt32 : Idr_CType<"int32_t {0}", "Int32">;
def Idr_CUInt32 : Idr_CType<"uint32_t {0}", "Int32">;
def Idr_CInt64 : Idr_CType<"int64_t {0}", "Int64">;
def Idr_CUInt64 : Idr_CType<"uint64_t {0}", "Int64">;
def Idr_CSize : Idr_CType<"size_t {0}", "Int64">;
def Idr_CBool : Idr_CType<"bool {0}", "Bool">;
def Idr_CCell : Idr_CType<"void *{0}", "Pointer">;
def Idr_CHeader : Idr_CType<"const idris_rt_header *{0}", "Pointer">;
def Idr_CArray : Idr_CType<"idris_rt_array *{0}", "Pointer">;
def Idr_CMemref : Idr_CType<"const idris_rt_memref *{0}", "Pointer">;
def Idr_CStrBuilt : Idr_CType<"idris_rt_str *{0}", "Pointer">;
def Idr_CStr : Idr_CType<"const idris_rt_str *{0}", "Str">;
def Idr_CChars : Idr_CType<"const char *{0}", "Pointer">;
def Idr_CArgv : Idr_CType<"char **{0}", "Pointer">;
def Idr_CBody : Idr_CType<"int64_t (*{0})(void)", "Pointer">;

// A runtime function the lowering calls by itself: its C symbol, its
// parameters in order, each a C type and its name, written
// `(ins Idr_CSize:$size, Idr_CUInt32:$info)`, its result, and a line on
// what it does. The table names it `helper::<symbol without idris_rt_,
// camel-cased>`.
class Idr_RuntimeFunction<string cSymbol, dag cParams, Idr_CType cResult, string cSummary> {
  string symbol = cSymbol;
  dag params = cParams;
  Idr_CType result = cResult;
  string summary = cSummary;
}

def Idr_RtCell : Idr_RuntimeFunction<"idris_rt_cell",
    (ins Idr_CSize:$size, Idr_CUInt32:$info), Idr_CCell,
    "a new cell of `size` bytes, its count 1 and its info `info`">;
def Idr_RtArrayNew : Idr_RuntimeFunction<"idris_rt_array_new",
    (ins Idr_CUInt64:$count, Idr_CUInt32:$info), Idr_CArray,
    "a new array cell of `count` elements, its header `info`">;
def Idr_RtMemrefCopy : Idr_RuntimeFunction<"idris_rt_memref_copy",
    (ins Idr_CInt64:$rank, Idr_CMemref:$from, Idr_CMemref:$to), Idr_CVoid,
    "memref.copy of `from` onto `to`, each of rank `rank`, counting each object copied">;
def Idr_RtInc : Idr_RuntimeFunction<"idris_rt_inc", (ins Idr_CCell:$o), Idr_CVoid,
    "one more owned reference">;
def Idr_RtDec : Idr_RuntimeFunction<"idris_rt_dec", (ins Idr_CCell:$o), Idr_CVoid,
    "one owned reference less, releasing the object at 0">;
def Idr_RtCafRelease : Idr_RuntimeFunction<"idris_rt_caf_release", (ins Idr_CCell:$cell),
    Idr_CVoid, "releases what a static memo cell holds, when the program ends">;
def Idr_RtIsUnique : Idr_RuntimeFunction<"idris_rt_is_unique", (ins Idr_CHeader:$cell),
    Idr_CBool, "whether a cell holds the only reference to itself">;
def Idr_RtFreeCell : Idr_RuntimeFunction<"idris_rt_free_cell", (ins Idr_CCell:$o), Idr_CVoid,
    "frees the memory of a counted heap cell whose contents were moved out">;
def Idr_RtMainReturn : Idr_RuntimeFunction<"idris_rt_main_return", (ins), Idr_CVoid,
    "what @main calls right before it returns">;
def Idr_RtStrAlloc : Idr_RuntimeFunction<"idris_rt_str_alloc",
    (ins Idr_CInt64:$bytes, Idr_CInt64:$scalars), Idr_CStrBuilt,
    "a new string of `bytes` bytes and `scalars` scalar values, to be written in place">;
def Idr_RtStrPutChar : Idr_RuntimeFunction<"idris_rt_str_put_char",
    (ins Idr_CStrBuilt:$s, Idr_CInt64:$offset, Idr_CInt32:$c), Idr_CInt64,
    "a character's UTF-8 written into a string being built, giving the next offset">;
def Idr_RtStrPutStr : Idr_RuntimeFunction<"idris_rt_str_put_str",
    (ins Idr_CStrBuilt:$s, Idr_CInt64:$offset, Idr_CStr:$part), Idr_CInt64,
    "a string's bytes written into a string being built, giving the next offset">;
def Idr_RtCrash : Idr_RuntimeFunction<"idris_rt_crash",
    (ins Idr_CChars:$cause, Idr_CSize:$len), Idr_CNoReturn,
    "ends the program with the `len` bytes of `cause`">;
def Idr_RtStart : Idr_RuntimeFunction<"idris_rt_start",
    (ins Idr_CBody:$body, Idr_CUInt64:$cpu_features, Idr_CInt:$argc, Idr_CArgv:$argv),
    Idr_CInt, "the program's entry, which @main calls with the program's body">;

#endif // IDR_RUNTIME
