-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The values the dialect's parameters hold that a wire lays out, read and
||| written by codecs printed from the wire: the composites a parameter
||| reaches, each once and after every composite it holds; and their C++
||| readers and writers, which the dialect's bytecode unit includes beside
||| the readers mlir-tblgen writes from the printed records; and the text
||| of a composite whose members are numbers alone, which its members fix.
||| The frontend's encoder of the same values is printed from the same
||| wires (`Spec.Generator.Idris`), so no layout is written twice and no
||| hand codec mirrors another.
module IdrisMLIR.Spec.Generator.Wire

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Generator.Render

import Data.List
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- What the parameters reach
------------------------------------------------------------------------------

mutual
  ||| The composites a wire reaches, each after every composite it holds. A
  ||| composite is a finite value, so none holds itself, and the order is a
  ||| reader's: what a codec calls is printed before it.
  wireComposites : Wire -> List Composite
  wireComposites (WireLeaf _) = []
  wireComposites (WireArray w) = wireComposites w
  wireComposites (WireOf (MkComposite n c b d)) = bodyComposites b ++ [MkComposite n c b d]

  bodyComposites : CompositeBody -> List Composite
  bodyComposites (Fields fs) = fieldsComposites fs
  bodyComposites (Flat _ _ cases) = casesComposites cases
  bodyComposites (Variant _ alternatives) = alternativesComposites alternatives

  fieldsComposites : List WireField -> List Composite
  fieldsComposites [] = []
  fieldsComposites (MkWireField _ w :: fs) = wireComposites w ++ fieldsComposites fs

  casesComposites : List (List WireField) -> List Composite
  casesComposites [] = []
  casesComposites (fs :: rest) = fieldsComposites fs ++ casesComposites rest

  alternativesComposites : List Composite -> List Composite
  alternativesComposites [] = []
  alternativesComposites (MkComposite n c b d :: rest) =
    bodyComposites b ++ [MkComposite n c b d] ++ alternativesComposites rest

||| The wired values a parameter holds, with the directive that names its
||| codec.
wiredOfKind : ParamKind -> List (Wired, Directive)
wiredOfKind (WiredValue w d) = [(w, d)]
wiredOfKind _ = []

paramsOf : List AnyTypeDef -> List AnyAttrDef -> List Parameter
paramsOf ts as = concatMap (\(SomeType t) => toList t.params) ts ++ concatMap (\(SomeAttr a) => toList a.params) as

||| Every wired parameter of the dialect's types and attributes, once per
||| directive, in first use's order: one codec each.
export
wiredOf : List AnyTypeDef -> List AnyAttrDef -> List (Wired, Directive)
wiredOf ts as = once [] (concatMap (\x => wiredOfKind x.kind) (paramsOf ts as))
  where
    once : List Ident -> List (Wired, Directive) -> List (Wired, Directive)
    once _ [] = []
    once seen ((w, d) :: rest) =
      if elem d.name seen then once seen rest else (w, d) :: once (d.name :: seen) rest

||| The composites a wired value reaches.
wiredComposites : Wired -> List Composite
wiredComposites (WiredArray w) = wireComposites w
wiredComposites (WiredOne _) = []
wiredComposites (WiredOf c) = wireComposites (WireOf c)

||| Every composite the dialect's parameters reach, once, each after every
||| composite it holds: one codec each, and one type on the frontend's side.
export
compositesOf : List AnyTypeDef -> List AnyAttrDef -> List Composite
compositesOf ts as = once [] (concatMap (\(w, _) => wiredComposites w) (wiredOf ts as))
  where
    once : List Ident -> List Composite -> List Composite
    once _ [] = []
    once seen (c :: rest) =
      if elem (compositeName c) seen then once seen rest else c :: once (compositeName c :: seen) rest

------------------------------------------------------------------------------
-- C++ types
------------------------------------------------------------------------------

||| A leaf's C++ type.
export
leafCpp : Leaf -> String
leafCpp LeafCount = "uint64_t"
leafCpp LeafWord32 = "uint32_t"
leafCpp (LeafCase e) = "::idr::" ++ identText e.enum.name
leafCpp LeafLabel = "::mlir::StringAttr"
leafCpp (LeafType c) = codeText c
leafCpp (LeafAttr c) = codeText c
leafCpp (LeafMaybeAttr c) = codeText c

||| A wire's C++ type, as a composite's member holds it.
export
wireCpp : Wire -> String
wireCpp (WireLeaf l) = leafCpp l
wireCpp (WireArray w) = "::llvm::ArrayRef<" ++ wireCpp w ++ ">"
wireCpp (WireOf c) = codeText (compositeCpp c)

||| What a wired parameter's storage holds, which its writer is given.
export
wiredHeld : Wired -> String
wiredHeld (WiredArray w) = "::llvm::ArrayRef<" ++ wireCpp w ++ ">"
wiredHeld (WiredOne l) = leafCpp l
wiredHeld (WiredOf c) = codeText (compositeCpp c)

||| What a wired parameter's reader fills: an array's values with the arena
||| that keeps what they view, until the builder it is given to has made
||| the storage that copies them.
export
wiredRead : Wired -> String
wiredRead (WiredArray w) = "Kept<" ++ wireCpp w ++ ">"
wiredRead (WiredOne l) = leafCpp l
wiredRead (WiredOf c) = codeText (compositeCpp c)

------------------------------------------------------------------------------
-- C++ codecs
------------------------------------------------------------------------------

||| What a wired parameter's text parser gives: the vector that owns an
||| array's values, which the storage copies; or, where the values view
||| arrays of their own, the view of what the parser made to keep them, as
||| a family's parser makes the family.
export
wiredParsed : Wired -> String
wiredParsed (WiredArray w) = case wireKeeping w of
  KeepsArrays => "::llvm::ArrayRef<" ++ wireCpp w ++ ">"
  KeepsNothing => "::llvm::SmallVector<" ++ wireCpp w ++ ">"
wiredParsed (WiredOne l) = leafCpp l
wiredParsed (WiredOf c) = codeText (compositeCpp c)

||| A composite's codec's name, `read<Name>` and `write<Name>`.
codecName : Composite -> String
codecName c = identText (compositeName c)

||| The arguments a composite's reader takes after the reader: the arena,
||| where it keeps an array, then the value.
readArguments : Composite -> (arena : String) -> (dst : String) -> String
readArguments (MkComposite _ _ b _) arena dst = case bodyKeeping b of
  KeepsArrays => arena ++ ", " ++ dst
  KeepsNothing => dst

||| A local of a reading `depth` arrays deep, so an array's element read
||| inside it names nothing the array's own reading names.
local : String -> Nat -> String
local stem Z = stem
local stem k = stem ++ decimal k

-- Not `failing`, which Idris reserves as the keyword of its failing blocks.
||| A call that may fail, ending the function it stands in when it does.
returnsOnFailure : String -> Lines
returnsOnFailure call = ["if (::mlir::failed(" ++ call ++ "))", "  return ::mlir::failure();"]

||| A type or an attribute read at its class, then given to `dst`, whose
||| member may hold any of a wider class.
readAt : Nat -> Code -> String -> String -> Lines
readAt depth c method dst =
  let r = local "read" depth
  in ["{", "  " ++ codeText c ++ " " ++ r ++ ";"] ++ indent 2 (returnsOnFailure ("reader." ++ method ++ "(" ++ r ++ ")"))
     ++ ["  " ++ dst ++ " = " ++ r ++ ";", "}"]

||| The statements that read a leaf into `dst`.
leafReader : Nat -> Leaf -> String -> Lines
leafReader _ LeafCount dst = returnsOnFailure ("reader.readVarInt(" ++ dst ++ ")")
leafReader _ LeafWord32 dst = returnsOnFailure ("readWord32(reader, " ++ dst ++ ")")
leafReader _ (LeafCase _) dst = returnsOnFailure ("readCase(reader, " ++ dst ++ ")")
leafReader _ LeafLabel dst = returnsOnFailure ("readLabel(reader, " ++ dst ++ ")")
leafReader depth (LeafType c) dst = readAt depth c "readType" dst
leafReader depth (LeafAttr c) dst = readAt depth c "readAttribute" dst
leafReader depth (LeafMaybeAttr c) dst = readAt depth c "readOptionalAttribute" dst

mutual
  ||| The statements that read a wire's value into `dst`, `depth` arrays
  ||| deep, keeping every array in `arena`. An array of types or of
  ||| attributes is read by the reader's own list of them, as upstream's
  ||| records read one.
  wireReader : Nat -> (arena : String) -> Wire -> (dst : String) -> Lines
  wireReader depth _ (WireLeaf l) dst = leafReader depth l dst
  wireReader depth arena (WireArray w) dst =
    let r = local "read" depth
        e = wireCpp w
    in ["{", "  ::llvm::SmallVector<" ++ e ++ "> " ++ r ++ ";"]
       ++ indent 2 (elementsReader depth arena w r)
       ++ ["  " ++ dst ++ " = keep(" ++ arena ++ ", ::llvm::ArrayRef<" ++ e ++ ">(" ++ r ++ "));", "}"]
  wireReader _ arena (WireOf c) dst = returnsOnFailure ("read" ++ codecName c ++ "(reader, " ++ readArguments c arena dst ++ ")")

  ||| The statements that read an array's elements into the vector `into`.
  elementsReader : Nat -> (arena : String) -> Wire -> (into : String) -> Lines
  elementsReader _ _ (WireLeaf (LeafType _)) into = returnsOnFailure ("reader.readTypes(" ++ into ++ ")")
  elementsReader _ _ (WireLeaf (LeafAttr _)) into = returnsOnFailure ("reader.readAttributes(" ++ into ++ ")")
  elementsReader depth arena w into =
    let each = local "each" depth
        element = local "element" depth
    in ["auto " ++ each ++ " = [&](" ++ wireCpp w ++ " &" ++ element ++ ") -> ::mlir::LogicalResult {"]
       ++ indent 2 (wireReader (S depth) arena w element)
       ++ ["  return ::mlir::success();", "};"]
       ++ returnsOnFailure ("reader.readList(" ++ into ++ ", " ++ each ++ ")")

||| The statements that write a leaf `src`.
leafWriter : Leaf -> String -> Lines
leafWriter LeafCount src = ["writer.writeVarInt(" ++ src ++ ");"]
leafWriter LeafWord32 src = ["writer.writeVarInt(" ++ src ++ ");"]
leafWriter (LeafCase _) src = ["writeCase(writer, " ++ src ++ ");"]
leafWriter LeafLabel src = ["writer.writeOwnedString(" ++ src ++ ".getValue());"]
leafWriter (LeafType _) src = ["writer.writeType(" ++ src ++ ");"]
leafWriter (LeafAttr _) src = ["writer.writeAttribute(" ++ src ++ ");"]
leafWriter (LeafMaybeAttr _) src = ["writer.writeOptionalAttribute(" ++ src ++ ");"]

||| The statements that write a wire's value `src`, `depth` arrays deep. An
||| array of types or of attributes is written by the writer's own list of
||| them.
wireWriter : Nat -> Wire -> String -> Lines
wireWriter _ (WireLeaf l) src = leafWriter l src
wireWriter _ (WireArray (WireLeaf (LeafType _))) src = ["writer.writeTypes(" ++ src ++ ");"]
wireWriter _ (WireArray (WireLeaf (LeafAttr _))) src = ["writer.writeAttributes(" ++ src ++ ");"]
wireWriter depth (WireArray w) src =
  let element = local "element" depth
  in ["writer.writeList(" ++ src ++ ", [&](const " ++ wireCpp w ++ " &" ++ element ++ ") {"]
     ++ indent 2 (wireWriter (S depth) w element)
     ++ ["});"]
wireWriter _ (WireOf c) src = ["write" ++ codecName c ++ "(writer, " ++ src ++ ");"]

||| A field's reader and writer, by its member of `value`.
fieldReader : WireField -> Lines
fieldReader (MkWireField n w) = wireReader Z "arena" w ("value." ++ identText n)

fieldWriter : WireField -> Lines
fieldWriter (MkWireField n w) = wireWriter Z w ("value." ++ identText n)

||| A case of a closed set in C++.
caseName : EnumDef -> Case -> String
caseName e c = "::idr::" ++ identText e.name ++ "::" ++ identText c.name

||| The members a case gives meaning to, read or written, then the case done.
caseArm : EnumDef -> (WireField -> Lines) -> (Case, List WireField) -> Lines
caseArm e each (c, fs) = ["case " ++ caseName e c ++ ":"] ++ indent 2 (concatMap each fs ++ ["break;"])

||| A variant's alternative read into `value`.
alternativeReader : EnumDef -> (Case, Composite) -> Lines
alternativeReader e (c, alternative) =
  [ "case " ++ caseName e c ++ ": {"
  , "  " ++ codeText (compositeCpp alternative) ++ " alternative;" ]
  ++ indent 2 (returnsOnFailure ("read" ++ codecName alternative ++ "(reader, " ++ readArguments alternative "arena" "alternative" ++ ")"))
  ++ [ "  value = alternative;", "  break;", "}" ]

||| A variant's alternative written: its case's position, then itself.
alternativeWriter : EnumDef -> (Case, Composite) -> Lines
alternativeWriter e (c, alternative) =
  [ "[&](const " ++ codeText (compositeCpp alternative) ++ " &alternative) {"
  , "  writeCase(writer, " ++ caseName e c ++ ");"
  , "  write" ++ codecName alternative ++ "(writer, alternative);"
  , "}" ]

||| A group of lines, its last ended by `end`.
endedBy : String -> Lines -> Lines
endedBy end [] = [end]
endedBy end [l] = [l ++ end]
endedBy end (l :: ls) = l :: endedBy end ls

||| Groups of lines as the arguments of a call: each group but the last
||| ended by a comma, the last by the call's close.
arguments : List Lines -> Lines
arguments [] = [");"]
arguments [g] = endedBy ");" g
arguments (g :: gs) = endedBy "," g ++ arguments gs

||| The statements that read a composite's parts into `value`.
bodyReader : String -> CompositeBody -> Lines
bodyReader _ (Fields fs) = concatMap fieldReader fs
bodyReader cls (Flat e tag cases) =
  ["value = " ++ cls ++ "{};"]
  ++ returnsOnFailure ("readCase(reader, value." ++ identText tag ++ ")")
  ++ ["switch (value." ++ identText tag ++ ") {"]
  ++ concatMap (caseArm e fieldReader) (zip (forget e.cases) cases)
  ++ ["}"]
bodyReader _ (Variant e alternatives) =
  ["::idr::" ++ identText e.name ++ " kind{};"]
  ++ returnsOnFailure "readCase(reader, kind)"
  ++ ["switch (kind) {"]
  ++ concatMap (alternativeReader e) (zip (forget e.cases) alternatives)
  ++ ["}"]

||| The statements that write a composite's parts from `value`.
bodyWriter : CompositeBody -> Lines
bodyWriter (Fields fs) = concatMap fieldWriter fs
bodyWriter (Flat e tag cases) =
  ["writeCase(writer, value." ++ identText tag ++ ");", "switch (value." ++ identText tag ++ ") {"]
  ++ concatMap (caseArm e fieldWriter) (zip (forget e.cases) cases)
  ++ ["}"]
bodyWriter (Variant e alternatives) =
  ["::idr::match(", "    value,"]
  ++ indent 4 (arguments (map (alternativeWriter e) (zip (forget e.cases) alternatives)))

||| A composite's reader and writer. A reader keeps every array it reads in
||| the arena it is given, which the value's arrays view.
compositeCodec : Composite -> Lines
compositeCodec (MkComposite n cpp body doc) =
  let cls = codeText cpp
      arena = case bodyKeeping body of
                KeepsArrays => "::llvm::BumpPtrAllocator &arena, "
                KeepsNothing => ""
  in slashComment [lineText doc.summary]
     ++ [ "::mlir::LogicalResult read" ++ identText n ++ "(::mlir::DialectBytecodeReader &" ++ named body "reader" ++ ", "
          ++ arena ++ cls ++ " &" ++ named body "value" ++ ") {" ]
     ++ indent 2 (bodyReader cls body)
     ++ [ "  return ::mlir::success();", "}", ""
        , "void write" ++ identText n ++ "(::mlir::DialectBytecodeWriter &" ++ named body "writer" ++ ", const " ++ cls
          ++ " &" ++ named body "value" ++ ") {" ]
     ++ indent 2 (bodyWriter body)
     ++ [ "}", "" ]
  where
    -- A composite of no parts (a case of a variant that carries nothing)
    -- reads and writes nothing, so its codec's parameters are unnamed.
    named : CompositeBody -> String -> String
    named (Fields []) _ = ""
    named _ binder = binder

||| Who writes the text of one composite's value: the generator, where its
||| members are numbers alone, one or more, each written as its member's
||| name and then its number, which a hand spelling could only restate; or
||| the hand C++ its directive names.
public export
data Spelling = ByMembers (List1 Ident) | ByHand

||| A composite's spelling: one of numbers alone is spelled by its members.
export
spellingOf : Composite -> Spelling
spellingOf (MkComposite _ _ (Fields (f :: fs)) _) = maybe ByHand ByMembers (traverse number (f ::: fs))
  where
    number : WireField -> Maybe Ident
    number (MkWireField n (WireLeaf LeafCount)) = Just n
    number (MkWireField n (WireLeaf LeafWord32)) = Just n
    number _ = Nothing
spellingOf _ = ByHand

||| One composite's hash and text where its members spell it, each its
||| members' own, its text's hooks named for its directive as its bytecode
||| is: `component 3`, the hash what its storage keys by.
spelledCodec : Composite -> Directive -> Lines
spelledCodec c d = case spellingOf c of
  ByHand => []
  ByMembers ms =>
    let cls = codeText (compositeCpp c)
        name = identText d.name
        names = map identText (forget ms)
    in [ "::llvm::hash_code hash_value(const " ++ cls ++ " &value) {"
       , "  return ::llvm::hash_combine(" ++ joinWith ", " (map ("value." ++) names) ++ ");"
       , "}", ""
       , "::mlir::FailureOr<" ++ cls ++ "> parse" ++ name ++ "(::mlir::AsmParser &parser) {"
       , "  " ++ cls ++ " value{};" ]
       ++ indent 2 (concatMap (\m => returnsOnFailure ("parser.parseKeyword(" ++ quoted m ++ ")")
                                     ++ returnsOnFailure ("parser.parseInteger(value." ++ m ++ ")")) names)
       ++ [ "  return value;", "}", ""
          , "void print" ++ name ++ "(::mlir::AsmPrinter &printer, " ++ cls ++ " value) {"
          , "  printer << " ++ joinWith " << \" \" << " (map (\m => quoted (m ++ " ") ++ " << value." ++ m) names) ++ ";"
          , "}", "" ]

||| A wired parameter's reader and writer, named for its directive, which
||| the printed bytecode records call: an array's values read into what the
||| reader fills, each array they view kept in its arena.
wiredCodec : (Wired, Directive) -> Lines
wiredCodec (WiredArray w, d) =
  let name = identText d.name
  in slashComment [lineText d.doc.summary]
     ++ [ "::mlir::LogicalResult read" ++ name ++ "(::mlir::DialectBytecodeReader &reader, " ++ wiredRead (WiredArray w) ++ " &value) {" ]
     ++ indent 2 (elementsReader Z "value.arena" w "value.items")
     ++ [ "  return ::mlir::success();", "}", ""
        , "void write" ++ name ++ "(::mlir::DialectBytecodeWriter &writer, " ++ wiredHeld (WiredArray w) ++ " value) {" ]
     ++ indent 2 (wireWriter Z (WireArray w) "value")
     ++ [ "}", "" ]
wiredCodec (WiredOne l, d) =
  let name = identText d.name
  in slashComment [lineText d.doc.summary]
     ++ [ "::mlir::LogicalResult read" ++ name ++ "(::mlir::DialectBytecodeReader &reader, " ++ leafCpp l ++ " &value) {" ]
     ++ indent 2 (leafReader Z l "value")
     ++ [ "  return ::mlir::success();", "}", ""
        , "void write" ++ name ++ "(::mlir::DialectBytecodeWriter &writer, " ++ leafCpp l ++ " value) {" ]
     ++ indent 2 (leafWriter l "value")
     ++ [ "}", "" ]
-- One composite's value is read and written by its own codec, which holds
-- no array, so its reader takes no arena.
wiredCodec (WiredOf c, d) =
  let name = identText d.name
      cls = codeText (compositeCpp c)
  in slashComment [lineText d.doc.summary]
     ++ [ "::mlir::LogicalResult read" ++ name ++ "(::mlir::DialectBytecodeReader &reader, " ++ cls ++ " &value) {"
        , "  return read" ++ codecName c ++ "(reader, value);", "}", ""
        , "void write" ++ name ++ "(::mlir::DialectBytecodeWriter &writer, " ++ cls ++ " value) {"
        , "  write" ++ codecName c ++ "(writer, value);", "}", "" ]
     ++ spelledCodec c d

||| Every composite's codec, then every wired parameter's, with the hash
||| and text of one its members spell, as the dialect's bytecode unit
||| includes them before the readers mlir-tblgen writes: the parts every
||| codec reads (`Kept`, `keep`, `readCase`, `writeCase`, `readWord32`,
||| `readLabel`) are that unit's, declared before.
export
wireDefinitions : List AnyTypeDef -> List AnyAttrDef -> Lines
wireDefinitions ts as =
  banner slashComment
  ++ concatMap compositeCodec (compositesOf ts as)
  ++ concatMap wiredCodec (wiredOf ts as)
