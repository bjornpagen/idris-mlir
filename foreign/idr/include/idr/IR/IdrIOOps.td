// The IO ops of the idr dialect: what the Prelude's IO and its buffers do.

#ifndef IDR_IO_OPS
#define IDR_IO_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"
include "idr/IR/IdrBigOps.td"

//===----------------------------------------------------------------------===//
// IO
//===----------------------------------------------------------------------===//

// Each IO op consumes one world and produces the next.
class Idr_IOOp<string mnemonic, list<Trait> traits = []> : Idr_Op<"io." # mnemonic,
    !listconcat(traits, [Idr_PerformsIO, Idr_CallsRuntime,
                         MemoryEffects<[MemRead<Idr_IOResource>,
                                        MemWrite<Idr_IOResource>]>])>;

def Idr_PutStrOp : Idr_IOOp<"put_str", [Idr_Primitive]> {
  let arguments = (ins Idr_StrType:$str, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$str `,` $world attr-dict";
  let hasCanonicalizer = 1;
}

// The UTF-8 encoding of a character, which is a Unicode scalar value: the
// Prelude's putChar, and what writing a one-character string writes, which
// output fusion makes of put_str.
def Idr_PutCharOp : Idr_IOOp<"put_char", [Idr_Primitive]> {
  let arguments = (ins I32:$ch, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$ch `,` $world attr-dict";
}

def Idr_PutIntOp : Idr_IOOp<"put_int"> {
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value `,` $world attr-dict `:` type($value)
  }];
}

def Idr_PutDoubleOp : Idr_IOOp<"put_double", [Idr_Primitive]> {
  let arguments = (ins F64:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$value `,` $world attr-dict";
}

// One byte of input, or 255 at its end.
def Idr_GetByteOp : Idr_IOOp<"get_byte", [Idr_Primitive]> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I32:$ch, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

// A line of input without its end (the Prelude's getLine): the bytes up to
// the next newline, which is consumed, without it or a carriage return
// right before it, decoded as UTF-8 (idris_rt_io_get_line); the empty
// string at the end of input. A new string, allocated like a builder's.
def Idr_GetLineOp : Idr_IOOp<"get_line", [Idr_Primitive]> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$str, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict custom<StrResult>(type($str))";
}

// A transfer of the bytes [offset, offset + count) of a buffer (an array of
// i8) between it and a handle. The range lies in the buffer: idr.check.range
// guards the offset. The op's effects are its own, as the array ops' are.
class Idr_IOTransferOp<string mnemonic> : Idr_Op<"io." # mnemonic,
    [Idr_PerformsIO, Idr_CallsRuntime, Idr_Primitive,
     DeclareOpInterfaceMethods<MemoryEffectsOpInterface>]> {
  let arguments = (ins I64:$handle, Idr_Rank1ArrayValue:$buffer, I64:$offset, I64:$count,
                       Idr_WorldType:$world);
  let assemblyFormat = [{
    $handle `,` $buffer `[` $offset `,` $count `]` `,` $world attr-dict `:` type($buffer)
  }];
  let hasVerifier = 1;
}

// Bytes of a buffer to a handle: 1 is standard output, through the output
// buffer and in order with every other write to it; 2 is standard error; any
// other is a file the program opened (idr.io.file_open). Gives the count
// written.
def Idr_WriteBytesOp : Idr_IOTransferOp<"write_bytes"> {
  let results = (outs I64:$written, Idr_WorldType:$next);
}

// Bytes from a handle into a buffer: 0 is standard input, through the
// runtime's input buffer, and any other a file the program opened. Gives the
// count read, 0 at the end of input, which it then records (idr.io.eof).
def Idr_ReadBytesOp : Idr_IOTransferOp<"read_bytes"> {
  let results = (outs I64:$read, Idr_WorldType:$next);
}

// 1 once a read on the handle met the end of its input, as C's feof reports
// it, else 0: standard input, or a file the program opened.
def Idr_EofOp : Idr_IOOp<"eof", [Idr_Primitive]> {
  let arguments = (ins I64:$handle, Idr_WorldType:$world);
  let results = (outs I64:$ended, Idr_WorldType:$next);
  let assemblyFormat = "$handle `,` $world attr-dict";
}

// How many processors are online, read when the program asks
// (idris_rt_io_n_processors). A system that does not say gives -1, which
// System.Info.getNProcessors turns into Nothing.
def Idr_NProcessorsOp : Idr_IOOp<"n_processors", [Idr_Primitive]> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I64:$count, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

// The operating system the target triple names, in the spelling Idris's
// Scheme backends share and base tests for: "darwin", "unix", "windows",
// or "unknown". Folded to that string. The triple is the module's
// #llvm.target, which idr-target writes from the target entry.
def Idr_OsOp : Idr_Op<"os", [Pure, Idr_Primitive]> {
  let summary = "the operating system the target triple names";
  let results = (outs Idr_StrValue:$result);
  let assemblyFormat = "attr-dict custom<StrResult>(type($result))";
  let hasFolder = 1;
}

// A machine word in a buffer of bytes, at a byte offset. The span is
// `sizeof` the word, and it lies in the buffer: idr.check.range guards the
// offset, as it guards a byte transfer's. The load and the store are the
// target's own, at alignment 1, so the endianness is the machine's and an
// offset need not be aligned. Not a runtime call: the value's width is the
// op's type.
class Idr_BufferAccessOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<"io." # mnemonic, !listconcat(traits, [
        Idr_PerformsIO, Idr_Primitive,
        DeclareOpInterfaceMethods<MemoryEffectsOpInterface>])>;

def Idr_BufferLoadOp : Idr_BufferAccessOp<"buffer_load"> {
  let summary = "a machine word read from a buffer at a byte offset";
  let arguments = (ins Idr_Rank1ArrayValue:$buffer, I64:$offset, Idr_WorldType:$world);
  let results = (outs AnyTypeOf<[I8, I16, I32, I64, F64]>:$value, Idr_WorldType:$next);
  let assemblyFormat = [{
    $buffer `[` $offset `]` `,` $world attr-dict `:` type($buffer) `->` type($value)
  }];
  let hasVerifier = 1;
}

def Idr_BufferStoreOp : Idr_BufferAccessOp<"buffer_store"> {
  let summary = "a machine word written into a buffer at a byte offset";
  let arguments = (ins Idr_Rank1ArrayValue:$buffer, I64:$offset,
                       AnyTypeOf<[I8, I16, I32, I64, F64]>:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    $buffer `[` $offset `]` `,` $value `,` $world attr-dict `:` type($buffer) `,` type($value)
  }];
  let hasVerifier = 1;
}

// Bytes copied from one buffer into another. The two spans each lie in
// their buffer, each guarded by idr.check.range. Overlap is allowed: the
// copy is memmove.
def Idr_BufferCopyOp : Idr_BufferAccessOp<"buffer_copy", [Idr_CallsRuntime]> {
  let summary = "bytes copied from one buffer into another";
  let arguments = (ins Idr_Rank1ArrayValue:$src, I64:$src_offset, I64:$len,
                       Idr_Rank1ArrayValue:$dst, I64:$dst_offset, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    $src `[` $src_offset `,` $len `]` `,` $dst `[` $dst_offset `]` `,` $world attr-dict
    `:` type($src) `,` type($dst)
  }];
  let hasVerifier = 1;
}

// A string's UTF-8 written at an offset. The span is the string's byte
// length, interior zeros included, and lies in the buffer.
def Idr_BufferSetStringOp : Idr_BufferAccessOp<"buffer_set_string", [Idr_CallsRuntime]> {
  let summary = "a string's bytes written into a buffer";
  let arguments = (ins Idr_Rank1ArrayValue:$buffer, I64:$offset, Idr_StrType:$str,
                       Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    $buffer `[` $offset `]` `,` $str `,` $world attr-dict `:` type($buffer)
  }];
  let hasVerifier = 1;
}

// A buffer's bytes read as a string. Ill-formed UTF-8 is replaced as
// idris_rt_str_from_bytes replaces it. A new string.
def Idr_BufferGetStringOp : Idr_BufferAccessOp<"buffer_get_string", [Idr_CallsRuntime]> {
  let summary = "a buffer's bytes read as a string";
  let arguments = (ins Idr_Rank1ArrayValue:$buffer, I64:$offset, I64:$len, Idr_WorldType:$world);
  let results = (outs Idr_StrValue:$str, Idr_WorldType:$next);
  let assemblyFormat = [{
    $buffer `[` $offset `,` $len `]` `,` $world attr-dict `:` type($buffer)
    custom<StrResult>(type($str))
  }];
  let hasVerifier = 1;
}

// A world forged where a trusted library runs an IO action for a pure
// value (`unsafePerformIO`): the first world of a chain of its own, which
// orders that chain; between chains, the effects order the ops, as they
// order any two IO ops. It opens the IO resource, so no pass merges two,
// moves one past an IO op, or deletes one, and every function that reaches
// one performs IO (idr-effects). It has no runtime form.
def Idr_WorldNewOp : Idr_Op<"world.new", [Idr_PerformsIO, Idr_Primitive,
    MemoryEffects<[MemWrite<Idr_IOResource>]>]> {
  let summary = "a forged world, the first of a chain of its own";
  let results = (outs Idr_WorldType:$world);
  let assemblyFormat = "attr-dict";
}

#endif // IDR_IO_OPS
