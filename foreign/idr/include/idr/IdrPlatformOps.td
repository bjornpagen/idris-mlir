// Base's surface beyond the Prelude's IO, as runtime primitives: files,
// directories, the process, the terminal, errors and clocks (System.File,
// System.Directory, System, System.Term, System.Errno, System.Clock), and the
// handles that stand for pointers. Included at the end of IdrOps.td.
//
// Each op's one meaning is the runtime function it calls, named after it
// (`idr.io.file_open` calls `idris_rt_io_file_open`), and documented beside
// that function, for both targets. A failing call sets the runtime's saved
// errno, which idr.io.errno and idr.io.file_errno read.
//
// A pointer is a handle, an i64: 0, 1 and 2 are the standard streams, -1 (all
// ones) is null, and any other value is a slot of the runtime's handle table,
// which holds a file, a directory, a file time or a string. No address
// reaches the program: user code declares no foreign function, so every
// pointer it can hold comes from one of these ops. An OSClock is an i64 too,
// seconds << 30 | nanoseconds, or -1 when it is not valid: a clock reading
// allocates nothing.

#ifndef IDR_PLATFORM_OPS
#define IDR_PLATFORM_OPS

// An IO primitive of base: it takes the world and gives the next, and calls
// its runtime function with its other operands.
class Idr_PlatformIOOp<string mnemonic, list<Trait> traits = []>
    : Idr_IOOp<mnemonic, !listconcat(traits, [Idr_Primitive])>;

// An op of a handle and the world, giving an Int: `fileSize`, `fflush`, a
// field of a file time, and their kin.
class Idr_HandleQueryOp<string mnemonic, string what>
    : Idr_PlatformIOOp<mnemonic> {
  let summary = what;
  let arguments = (ins I64:$handle, Idr_WorldType:$world);
  let results = (outs I64:$result, Idr_WorldType:$next);
  let assemblyFormat = "$handle `,` $world attr-dict";
}

// An op of a path and the world, giving an Int: 0 on success, as the C
// function it stands for gives it.
class Idr_PathOp<string mnemonic, string what> : Idr_PlatformIOOp<mnemonic> {
  let summary = what;
  let arguments = (ins Idr_StrType:$path, Idr_WorldType:$world);
  let results = (outs I64:$result, Idr_WorldType:$next);
  let assemblyFormat = "$path `,` $world attr-dict";
}

// An op of the world alone, giving an Int.
class Idr_ReadingOp<string mnemonic, string what> : Idr_PlatformIOOp<mnemonic> {
  let summary = what;
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I64:$result, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

// An op of the world alone, giving nothing else.
class Idr_ActionOp<string mnemonic, string what> : Idr_PlatformIOOp<mnemonic> {
  let summary = what;
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

//===----------------------------------------------------------------------===//
// Files (System.File)
//===----------------------------------------------------------------------===//

def Idr_FileOpenOp : Idr_PlatformIOOp<"file_open"> {
  let summary = "opens the file at a path in a mode, as fopen does: a file handle, or null";
  let arguments = (ins Idr_StrType:$path, Idr_StrType:$mode, Idr_WorldType:$world);
  let results = (outs I64:$file, Idr_WorldType:$next);
  let assemblyFormat = "$path `,` $mode `,` $world attr-dict";
}

def Idr_FileCloseOp : Idr_PlatformIOOp<"file_close"> {
  let summary = "closes a file and frees its handle";
  let arguments = (ins I64:$file, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$file `,` $world attr-dict";
}

def Idr_FileErrorOp : Idr_HandleQueryOp<"file_error",
    "whether a file's stream has an error, as ferror says">;

def Idr_FileErrnoOp : Idr_ReadingOp<"file_errno",
    "the saved errno of the last failing file operation">;

// The line is a string handle the program owns: base frees it
// (getStringAndFree), through idr.io.handle_free. So are read_chars'.
def Idr_FileReadLineOp : Idr_HandleQueryOp<"file_read_line",
    "the next line of a file, as a string handle, or null">;

def Idr_FileReadCharsOp : Idr_PlatformIOOp<"file_read_chars"> {
  let summary = "at most `max` characters of a file, as a string handle, or null";
  let arguments = (ins I64:$max, I64:$file, Idr_WorldType:$world);
  let results = (outs I64:$chars, Idr_WorldType:$next);
  let assemblyFormat = "$max `,` $file `,` $world attr-dict";
}

def Idr_FileReadCharOp : Idr_HandleQueryOp<"file_read_char",
    "the next character of a file">;

def Idr_FileWriteLineOp : Idr_PlatformIOOp<"file_write_line"> {
  let summary = "writes a string to a file";
  let arguments = (ins I64:$file, Idr_StrType:$line, Idr_WorldType:$world);
  let results = (outs I64:$result, Idr_WorldType:$next);
  let assemblyFormat = "$file `,` $line `,` $world attr-dict";
}

def Idr_FileFlushOp : Idr_HandleQueryOp<"file_flush",
    "writes what is pending of a file, as fflush does">;

def Idr_FileSeekLineOp : Idr_HandleQueryOp<"file_seek_line",
    "skips a file past its next line">;

def Idr_FileRemoveOp : Idr_PathOp<"file_remove", "removes the file at a path">;

def Idr_FileSizeOp : Idr_HandleQueryOp<"file_size", "the size of a file in bytes">;

def Idr_FilePollOp : Idr_HandleQueryOp<"file_poll",
    "whether a file has input ready to read">;

def Idr_FileIsTtyOp : Idr_HandleQueryOp<"file_is_tty",
    "whether a file is a terminal">;

// A file time is a handle of its own, which holds the file's three times
// read at once.
def Idr_FileTimeOp : Idr_HandleQueryOp<"file_time",
    "the access, modification and status change times of a file, as a file-time handle">;

def Idr_FileAtimeSecOp : Idr_HandleQueryOp<"file_atime_sec",
    "the seconds of a file time's access time">;
def Idr_FileAtimeNsecOp : Idr_HandleQueryOp<"file_atime_nsec",
    "the nanoseconds of a file time's access time">;
def Idr_FileMtimeSecOp : Idr_HandleQueryOp<"file_mtime_sec",
    "the seconds of a file time's modification time">;
def Idr_FileMtimeNsecOp : Idr_HandleQueryOp<"file_mtime_nsec",
    "the nanoseconds of a file time's modification time">;
def Idr_FileCtimeSecOp : Idr_HandleQueryOp<"file_ctime_sec",
    "the seconds of a file time's status change time">;
def Idr_FileCtimeNsecOp : Idr_HandleQueryOp<"file_ctime_nsec",
    "the nanoseconds of a file time's status change time">;

def Idr_FileChmodOp : Idr_PlatformIOOp<"file_chmod"> {
  let summary = "sets the mode of the file at a path";
  let arguments = (ins Idr_StrType:$path, I64:$mode, Idr_WorldType:$world);
  let results = (outs I64:$result, Idr_WorldType:$next);
  let assemblyFormat = "$path `,` $mode `,` $world attr-dict";
}

//===----------------------------------------------------------------------===//
// Directories (System.Directory)
//===----------------------------------------------------------------------===//

// The directory's path is a string handle the program owns: base's
// currentDir frees it, through idr.io.handle_free.
def Idr_DirCurrentOp : Idr_ReadingOp<"dir_current",
    "the current directory's path, as a string handle, or null">;

def Idr_DirChangeOp : Idr_PathOp<"dir_change", "makes a path the current directory">;

def Idr_DirCreateOp : Idr_PathOp<"dir_create", "creates a directory at a path">;

def Idr_DirRemoveOp : Idr_PlatformIOOp<"dir_remove"> {
  let summary = "removes the directory at a path";
  let arguments = (ins Idr_StrType:$path, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$path `,` $world attr-dict";
}

def Idr_DirOpenOp : Idr_PlatformIOOp<"dir_open"> {
  let summary = "opens the directory at a path: a directory handle, or null";
  let arguments = (ins Idr_StrType:$path, Idr_WorldType:$world);
  let results = (outs I64:$dir, Idr_WorldType:$next);
  let assemblyFormat = "$path `,` $world attr-dict";
}

def Idr_DirCloseOp : Idr_PlatformIOOp<"dir_close"> {
  let summary = "closes a directory, its handle and the entry it last gave";
  let arguments = (ins I64:$dir, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$dir `,` $world attr-dict";
}

// The entry's name is a string the runtime owns, as readdir's bytes are the
// C library's: the next entry of the directory replaces it, and closing the
// directory releases it.
def Idr_DirEntryOp : Idr_HandleQueryOp<"dir_entry",
    "the name of a directory's next entry, as a string handle, or null at its end">;

//===----------------------------------------------------------------------===//
// The process (System)
//===----------------------------------------------------------------------===//

def Idr_ArgCountOp : Idr_ReadingOp<"arg_count",
    "the number of the program's arguments, its name included">;

def Idr_ArgOp : Idr_PlatformIOOp<"arg"> {
  let summary = "the program's argument at an index, a new string";
  let arguments = (ins I64:$index, Idr_WorldType:$world);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$str, Idr_WorldType:$next);
  let assemblyFormat = "$index `,` $world attr-dict custom<StrResult>(type($str))";
}

// The value is a string the runtime owns, as getenv's bytes are the C
// library's: the next environment operation replaces it.
def Idr_EnvGetOp : Idr_PlatformIOOp<"env_get"> {
  let summary = "the value of an environment variable, as a string handle, or null";
  let arguments = (ins Idr_StrType:$name, Idr_WorldType:$world);
  let results = (outs I64:$value, Idr_WorldType:$next);
  let assemblyFormat = "$name `,` $world attr-dict";
}

def Idr_EnvPairOp : Idr_PlatformIOOp<"env_pair"> {
  let summary = "the environment's `name=value` at an index, as a string handle, or null past its end";
  let arguments = (ins I64:$index, Idr_WorldType:$world);
  let results = (outs I64:$pair, Idr_WorldType:$next);
  let assemblyFormat = "$index `,` $world attr-dict";
}

def Idr_EnvSetOp : Idr_PlatformIOOp<"env_set"> {
  let summary = "sets an environment variable, unless it is set and `overwrite` is 0";
  let arguments = (ins Idr_StrType:$name, Idr_StrType:$value, I64:$overwrite,
                       Idr_WorldType:$world);
  let results = (outs I64:$result, Idr_WorldType:$next);
  let assemblyFormat = "$name `,` $value `,` $overwrite `,` $world attr-dict";
}

def Idr_EnvUnsetOp : Idr_PlatformIOOp<"env_unset"> {
  let summary = "removes an environment variable";
  let arguments = (ins Idr_StrType:$name, Idr_WorldType:$world);
  let results = (outs I64:$result, Idr_WorldType:$next);
  let assemblyFormat = "$name `,` $world attr-dict";
}

def Idr_SleepOp : Idr_PlatformIOOp<"sleep"> {
  let summary = "waits a number of seconds";
  let arguments = (ins I64:$seconds, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$seconds `,` $world attr-dict";
}

def Idr_UsleepOp : Idr_PlatformIOOp<"usleep"> {
  let summary = "waits a number of microseconds";
  let arguments = (ins I64:$microseconds, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$microseconds `,` $world attr-dict";
}

def Idr_TimeOp : Idr_ReadingOp<"time", "the seconds since the epoch">;

def Idr_PidOp : Idr_ReadingOp<"pid", "the process's id">;

// Base's exitWith, which the registry recognizes by name, follows it with
// ub.unreachable.
def Idr_ExitOp : Idr_PlatformIOOp<"exit"> {
  let summary = "writes pending output and ends the process with a status; does not return";
  let arguments = (ins I64:$status, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$status `,` $world attr-dict";
}

//===----------------------------------------------------------------------===//
// The terminal (System, System.Term)
//===----------------------------------------------------------------------===//

def Idr_TermRawOp : Idr_ReadingOp<"term_raw",
    "puts the terminal in raw mode: 0 on success">;

def Idr_TermResetOp : Idr_ActionOp<"term_reset",
    "puts the terminal back in the mode it had before raw mode">;

def Idr_TermSetupOp : Idr_ActionOp<"term_setup", "prepares the terminal, as base's setupTerm asks">;

def Idr_TermColsOp : Idr_ReadingOp<"term_cols", "the terminal's number of columns">;

def Idr_TermLinesOp : Idr_ReadingOp<"term_lines", "the terminal's number of lines">;

//===----------------------------------------------------------------------===//
// Errors (System.Errno)
//===----------------------------------------------------------------------===//

def Idr_ErrnoOp : Idr_ReadingOp<"errno", "the saved errno of the last failing call">;

def Idr_StrerrorOp : Idr_PlatformIOOp<"strerror"> {
  let summary = "the text of an error number, a new string";
  let arguments = (ins I64:$code, Idr_WorldType:$world);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$str, Idr_WorldType:$next);
  let assemblyFormat = "$code `,` $world attr-dict custom<StrResult>(type($str))";
}

//===----------------------------------------------------------------------===//
// Clocks (System.Clock)
//===----------------------------------------------------------------------===//

// A reading is an OSClock, or -1 when the clock cannot be read. No
// collector runs, so the two GC clocks are never valid.
def Idr_ClockMonotonicOp : Idr_ReadingOp<"clock_monotonic", "a reading of the monotonic clock">;
def Idr_ClockUtcOp : Idr_ReadingOp<"clock_utc", "a reading of the real-time clock">;
def Idr_ClockProcessOp : Idr_ReadingOp<"clock_process", "a reading of the process's CPU time">;
def Idr_ClockThreadOp : Idr_ReadingOp<"clock_thread", "a reading of the thread's CPU time">;
def Idr_ClockGcCpuOp : Idr_ReadingOp<"clock_gc_cpu", "the collector's CPU time: never valid">;
def Idr_ClockGcRealOp : Idr_ReadingOp<"clock_gc_real", "the collector's real time: never valid">;

// An op of an OSClock and the world, giving an Int.
class Idr_ClockQueryOp<string mnemonic, string what> : Idr_PlatformIOOp<mnemonic> {
  let summary = what;
  let arguments = (ins I64:$clock, Idr_WorldType:$world);
  let results = (outs I64:$result, Idr_WorldType:$next);
  let assemblyFormat = "$clock `,` $world attr-dict";
}

def Idr_ClockValidOp : Idr_ClockQueryOp<"clock_valid", "1 when an OSClock is valid, else 0">;
def Idr_ClockSecondOp : Idr_ClockQueryOp<"clock_second", "the seconds of an OSClock">;
def Idr_ClockNanosecondOp : Idr_ClockQueryOp<"clock_nanosecond",
    "the nanoseconds of an OSClock">;

//===----------------------------------------------------------------------===//
// Handles
//===----------------------------------------------------------------------===//

// Base's nullPtr and nullAnyPtr.
def Idr_HandleIsNullOp : Idr_Op<"handle.is_null", [Pure, Idr_CallsRuntime, Idr_Primitive]> {
  let summary = "1 when a handle is null, else 0";
  let arguments = (ins I64:$handle);
  let results = (outs I64:$is_null);
  let assemblyFormat = "$handle attr-dict";
}

// Base's getString. It reads the slot, so it stays before the slot's release
// in the order of IO.
def Idr_HandleStringOp : Idr_Op<"handle.string", [Idr_CallsRuntime, Idr_Primitive,
    MemoryEffects<[MemRead<Idr_IOResource>]>]> {
  let summary = "the string a string handle holds, with a reference of its own";
  let arguments = (ins I64:$handle);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$str);
  let assemblyFormat = "$handle attr-dict custom<StrResult>(type($str))";
}

// Base's free of a pointer (System.FFI). The string a program-owned string
// handle holds loses its reference; a string the runtime owns stays.
def Idr_HandleFreeOp : Idr_PlatformIOOp<"handle_free"> {
  let summary = "releases a handle's slot";
  let arguments = (ins I64:$handle, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$handle `,` $world attr-dict";
}

#endif // IDR_PLATFORM_OPS
