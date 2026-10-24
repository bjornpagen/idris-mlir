-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The runtime's C functions the lowering calls by itself, which no op
||| names as its meaning: a cell and the two array cells, the counted copy,
||| the counting of each kind of word, the two frees of a reuse token, the
||| release of a cell proved dead, the string being built, the crashes at a
||| site and running out of memory, the lifetimes allocated into by a bump,
||| the frame stack, the account of what a call holds that it no longer
||| needs, and the program's entry.
||| Each is its prototype and nothing more: its meaning is documented beside
||| its definition, in runtime/. Every pointer names the C type it points
||| to. The generator prints them into the runtime's declarations, which
||| runtime/idris_rt.h includes, so a definition that disagrees with its
||| record, a pointer's type included, does not compile, and into the table
||| the lowering calls through.
module IdrisMLIR.Spec.Runtime.Helpers

import IdrisMLIR.Spec.Core.Ods
import IdrisMLIR.Spec.Core.Text

%default total

------------------------------------------------------------------------------
-- The kinds of a counted word
------------------------------------------------------------------------------

||| What a word that holds a counted reference may be, which its type
||| decides once, at the lowering: a cell, never null or small; a slot of an
||| unboxed sum, a cell or null; a big, a cell or a small value; a slot a
||| cell and a big share, any of the three. They form a lattice, the cell
||| below the two others and their join the last, and each has its own
||| increment and decrement, testing exactly what the kind leaves open.
public export
data WordKind = CellWord | MaybeCellWord | BigWord | AnyWord

||| Every kind, in the order their entries are printed.
public export
words : List WordKind
words = [CellWord, MaybeCellWord, BigWord, AnyWord]

||| How a word of the kind is passed: a cell, or a cell or null, as the
||| cell's header; a big as its 64-bit word; a word that may be any of the
||| three as a word, which no pointee type is true of, since it may be no
||| address at all.
public export
passing : WordKind -> OperandKind
passing CellWord = TakesPointerTo "idris_rt_header"
passing MaybeCellWord = TakesPointerTo "idris_rt_header"
passing BigWord = TakesBig
passing AnyWord = TakesPointerTo "void"

||| One more or one less reference.
public export
data Count = Increment | Decrement

||| A counting entry's name in the lowering's table and its symbol.
entry : Count -> WordKind -> (Ident, Symbol)
entry Increment CellWord = (ident "incCell", symbol "inc_cell")
entry Increment MaybeCellWord = (ident "incMaybeCell", symbol "inc_maybe_cell")
entry Increment BigWord = (ident "incBig", symbol "inc_big")
entry Increment AnyWord = (ident "incAny", symbol "inc_any")
entry Decrement CellWord = (ident "decCell", symbol "dec_cell")
entry Decrement MaybeCellWord = (ident "decMaybeCell", symbol "dec_maybe_cell")
entry Decrement BigWord = (ident "decBig", symbol "dec_big")
entry Decrement AnyWord = (ident "decAny", symbol "dec_any")

||| A counting entry of a kind of word: one word, passed as its kind is.
counting : Count -> WordKind -> RuntimeHelper
counting c w =
  let (name, sym) = entry c w in
  MkRuntimeHelper name sym [(passing w, ident "word")] HelperNothing (doc c)
  where
    doc : Count -> Line
    doc Increment = line "one more owned reference to a word of its kind"
    doc Decrement = line "one owned reference less to a word of its kind, a cell released at 0"

------------------------------------------------------------------------------
-- The helpers
------------------------------------------------------------------------------

||| A crash's site, which every crash entry takes after what it says: the
||| function the site lies in, its file, its line and its column, each file
||| and function one static text of the program, shared by its sites.
site : List (OperandKind, Ident)
site = [(text, ident "function"), (text, ident "file"), (TakesInt32, ident "line"), (TakesInt32, ident "column")]
  where
    text : OperandKind
    text = TakesPointerTo "const idris_rt_text"

||| A cell, as the runtime and the lowering read it: its header.
cell : OperandKind
cell = TakesPointerTo "idris_rt_header"

||| An array cell.
array : ResultKind
array = GivesPointerTo "idris_rt_array"

||| A string being built in place, whose bytes are written.
building : OperandKind
building = TakesPointerTo "idris_rt_str"

||| A lifetime's cursor or mark: a byte of one of its chunks, where the next
||| cell goes.
cursor : OperandKind
cursor = TakesPointerTo "char"

||| A character's UTF-8 written into a string being built: what a list's
||| pack writes of each element.
public export
strPutChar : RuntimeHelper
strPutChar = MkRuntimeHelper (ident "strPutChar") (symbol "str_put_char")
  [(building, ident "s"), (TakesInt64, ident "offset"), (TakesInt32, ident "c")] (HelperReturns GivesInt64)
  (line "a character's UTF-8 written into a string being built, giving the next offset")

||| A string's bytes written into a string being built: what a list's
||| concat writes of each element.
public export
strPutStr : RuntimeHelper
strPutStr = MkRuntimeHelper (ident "strPutStr") (symbol "str_put_str")
  [(building, ident "s"), (TakesInt64, ident "offset"), (TakesStr, ident "part")] (HelperReturns GivesInt64)
  (line "a string's bytes written into a string being built, giving the next offset")

||| Every helper, in the order the generator prints them.
public export
helpers : List RuntimeHelper
helpers =
  [ MkRuntimeHelper (ident "cell") (symbol "cell")
      [(TakesInt64, ident "size"), (TakesInt32, ident "info")] (HelperReturns (GivesPointerTo "idris_rt_header"))
      (line "a new counted cell of size bytes, its count 1 and its info the one given")
  , MkRuntimeHelper (ident "arrayNewUnwritten") (symbol "array_new_unwritten")
      [(TakesInt64, ident "count"), (TakesInt32, ident "info")] (HelperReturns array)
      (line "a new array cell of count elements, unwritten, for a maker that writes every element before anything reads, releases or frees the cell")
  , MkRuntimeHelper (ident "memrefCopy") (symbol "memref_copy")
      [(TakesInt64, ident "rank"), (TakesPointerTo "const idris_rt_memref", ident "from"), (TakesPointerTo "const idris_rt_memref", ident "to")] HelperNothing
      (line "memref.copy of one view onto another, counting each object copied")
  ]
  ++ [counting c w | c <- [Increment, Decrement], w <- words]
  ++
  [ MkRuntimeHelper (ident "isUnique") (symbol "is_unique")
      [(TakesPointerTo "const idris_rt_header", ident "cell")] (HelperReturns GivesBool)
      (line "whether a counted cell holds the only reference to itself: its count is 1")
  , MkRuntimeHelper (ident "freeToken") (symbol "free_token")
      [(cell, ident "cell")] HelperNothing
      (line "frees the memory of a reuse token proved exclusive, whose fields were moved out")
  , MkRuntimeHelper (ident "freeMaybeToken") (symbol "free_maybe_token")
      [(cell, ident "cell")] HelperNothing
      (line "frees the memory of a reuse token that may be null, whose fields were moved out")
  , MkRuntimeHelper (ident "releaseDead") (symbol "release_dead")
      [(cell, ident "cell")] HelperNothing
      (line "releases the references of a cell proved dead, whose own count nothing reads, and every cell that dies in turn, and frees them")
  , MkRuntimeHelper (ident "handleHoldsString") (symbol "handle_holds_string")
      [(TakesInt64, ident "handle")] (HelperReturns GivesBool)
      (line "whether a handle holds a string, the program's or the runtime's: what check.holds_string asks")
  , MkRuntimeHelper (ident "strAlloc") (symbol "str_alloc")
      [(TakesInt64, ident "bytes"), (TakesInt64, ident "scalars")] (HelperReturns (GivesPointerTo "idris_rt_str"))
      (line "a new string of bytes bytes and scalars scalar values, to be written in place")
  , strPutChar
  , strPutStr
  , MkRuntimeHelper (ident "crashAt") (symbol "crash_at")
      ((TakesInt32, ident "cause") :: site) HelperNeverReturns
      (line "ends the program as a crash of a cause of the closed set, at its site")
  , MkRuntimeHelper (ident "crashMessageAt") (symbol "crash_message_at")
      ((TakesStr, ident "message") :: site) HelperNeverReturns
      (line "ends the program as a crash of the text a trusted library gave idris_crash, at its site")
  , MkRuntimeHelper (ident "outOfMemory") (symbol "out_of_memory")
      [] HelperNeverReturns
      (line "ends the program as out of memory, for a size no allocation can meet")
  , MkRuntimeHelper (ident "arenaOpen") (symbol "arena_open")
      [(TakesInt64, ident "size_hint")] (HelperReturns (GivesPointerTo "char"))
      (line "a chain's first cursor, its first chunk at least the bytes its callee puts; null for a hint of 0")
  , MkRuntimeHelper (ident "arenaChunk") (symbol "arena_chunk")
      [(cursor, ident "cursor"), (TakesInt64, ident "bytes")] (HelperReturns (GivesPointerTo "char"))
      (line "where a cell of bytes goes in a cursor's chain: the cursor itself when its chunk has room, else a new chunk's first byte; null starts a chain")
  , MkRuntimeHelper (ident "arenaClose") (symbol "arena_close")
      [(cursor, ident "cursor")] HelperNothing
      (line "every chunk of a cursor's chain given back; null gives back none")
  , MkRuntimeHelper (ident "stackReset") (symbol "stack_reset")
      [(cursor, ident "mark")] HelperNothing
      (line "the chunks of a stack's chain past the one its mark is in given back, the mark its cursor again")
  , MkRuntimeHelper (ident "framePush") (symbol "frame_push")
      [(TakesInt64, ident "bytes")] (HelperReturns (GivesPointerTo "idris_rt_header"))
      (line "the next frame's bytes on the thread's frame stack, contiguous within a chunk, laid out as a cell")
  , MkRuntimeHelper (ident "framePop") (symbol "frame_pop")
      [(cell, ident "frame")] HelperNothing
      (line "the frame stack back to a frame it pushed, the chunks past it given back but the one spare")
  , MkRuntimeHelper (ident "peakEnter") (symbol "peak_enter")
      [(TakesPointerTo "const idris_rt_text", ident "function"), (TakesInt64, ident "bound")] HelperNothing
      (line "an activation of a function that may hold bytes it no longer needs begins, the compiler's bound on them given")
  , MkRuntimeHelper (ident "peakHeld") (symbol "peak_held")
      [(TakesInt64, ident "change")] HelperNothing
      (line "the innermost such activation holds change more bytes it no longer needs, fewer where change is negative")
  , MkRuntimeHelper (ident "peakLeave") (symbol "peak_leave")
      [] HelperNothing
      (line "the innermost such activation ends")
  , MkRuntimeHelper (ident "start") (symbol "start")
      [(TakesPointerTo "const idris_rt_program", ident "program"), (TakesInt32, ident "argc"), (TakesPointerTo "char *", ident "argv")] HelperNeverReturns
      (line "the program's entry, which main calls with the program's static facts")
  ]
