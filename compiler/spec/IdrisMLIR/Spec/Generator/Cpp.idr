-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The specification's facts that only our C++ reads, printed straight into
||| headers, never routed through ODS to a backend that would derive again
||| what the specification knew. Every per-op fact is a table indexed by a
||| generated enum or a class template specialized per op; the printer has
||| no branch over ops, so no `if`, `switch`, `isa` or concept body is ever
||| printed.
module IdrisMLIR.Spec.Generator.Cpp

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Generator.Render
import IdrisMLIR.Spec.Generator.Ods
import IdrisMLIR.Spec.Pipeline.Pass
import IdrisMLIR.Spec.Pipeline.Pipeline

import Data.Fin
import Data.List
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------------

||| A header's guard name from its file stem.
export
guardOf : String -> String
guardOf stem = "IDR_IR_GENERATED_" ++ pack (map up (unpack (snakeOf stem))) ++ "_H_INC"
  where
    up : Char -> Char
    up c = if lower c then chr (ord c - 32) else c

||| A blank line after a list of includes, if any.
export
blank : List String -> Lines
blank [] = []
blank _ = [""]

||| The C++ case of whether an op's regions' effects are its own.
export
bodiesText : OdsBodies -> String
bodiesText OwnOnly = "Bodies::Own"
bodiesText WithBodies = "Bodies::WithRegions"

||| A header's text: the banner, its guard, its includes, its body.
export
header : String -> List String -> Lines -> Lines
header stem includes body =
  banner slashComment
  ++ ["#ifndef " ++ guardOf stem, "#define " ++ guardOf stem, ""]
  ++ map (\i => "#include " ++ i) includes
  ++ blank includes
  ++ body
  ++ ["", "#endif // " ++ guardOf stem]

||| A namespace around lines.
export
inNamespace : String -> Lines -> Lines
inNamespace ns body = ["namespace " ++ ns ++ " {", ""] ++ body ++ ["", "} // namespace " ++ ns]

||| The name of a namespace without its leading `::`.
export
namespaceText : CppName -> String
namespaceText n = joinWith "::" (map identText (forget n))

||| A list of C++ expressions as a braced initializer, one per line.
export
braced : List String -> Lines
braced xs = map (++ ",") xs

------------------------------------------------------------------------------
-- Closed sets and their tables
------------------------------------------------------------------------------

||| Where a header's block prints: its namespace, and the enums it declares
||| there. A case, a column or a set of an enum the block declares is
||| spelled in the block's namespace; any other enum is the dialect's, in
||| `::idr`, where ODS declares it.
public export
record Scope where
  constructor MkScope
  space : String
  declared : List Ident

||| An enum's name from the global namespace, as the block's scope has it.
export
enumName : Scope -> EnumDef -> String
enumName sc e = (if elem e.name sc.declared then "::" ++ sc.space else "::idr") ++ "::" ++ identText e.name

||| The C++ type of a column's element.
export
columnType : Scope -> ColumnType -> String
columnType _ Signed64 = "std::int64_t"
columnType _ Unsigned8 = "std::uint8_t"
columnType _ Unsigned32 = "std::uint32_t"
columnType _ Unsigned64 = "std::uint64_t"
columnType _ TextColumn = "std::string_view"
columnType _ TruthColumn = "bool"
columnType sc (EnumColumn e) = enumName sc e
columnType sc (SetColumn e) = "::idr::EnumSet<" ++ enumName sc e ++ ">"

||| A cell as a C++ constant.
export
cellText : Scope -> Cell -> String
cellText _ (IntCell i) = integer i
cellText _ (TextCell t) = quoted t
cellText _ (TruthCell True) = "true"
cellText _ (TruthCell False) = "false"
cellText sc (CaseCell c) = enumName sc c.enum ++ "::" ++ identText c.name
cellText sc (SetCell e cs) =
  "::idr::EnumSet<" ++ enumName sc e ++ ">{" ++ joinWith ", " (map (\c => enumName sc e ++ "::" ++ identText c) cs) ++ "}"

||| A plain enum of a header, dense from zero.
export
enumDecl : EnumDef -> Lines
enumDecl e =
  slashComment [lineText e.doc.summary]
  ++ ["enum class " ++ identText e.name ++ " : std::uint8_t {"]
  ++ indent 2 (concatMap (\c => slashComment [lineText c.doc] ++ [identText c.name ++ ","]) (forget e.cases))
  ++ ["};", ""]

||| `EnumTraits<E>` for the enum spelled `qualified`: its count and its
||| cases' printed names, read by every table over it. A specialization of
||| the dialect's template, so it is printed in `::idr`.
export
enumTraits : String -> EnumDef -> Lines
enumTraits qualified e =
  let n = decimal (length (forget e.cases))
  in [ "template <>"
     , "struct EnumTraits<" ++ qualified ++ "> {"
     , "  static constexpr std::size_t count = " ++ n ++ ";"
     , "  static constexpr std::array<std::string_view, " ++ n ++ "> names{{"
       ++ joinWith ", " (map (quoted . spellingText) (forget e.cases)) ++ "}};"
     , "};", "" ]

||| A braced initializer of a `std::array`: empty, or one value per element.
export
arrayInit : List String -> String
arrayInit [] = "{}"
arrayInit xs = "{{" ++ joinWith ", " xs ++ "}}"

||| One column of a table: an `EnumArray` indexed by the table's enum, its
||| values in the cases' order.
export
columnDecl : Scope -> EnumDef -> (Ident, ColumnType, List Cell, Line) -> Lines
columnDecl sc e (name, type, cells, doc) =
  slashComment [lineText doc]
  ++ ["inline constexpr ::idr::EnumArray<" ++ enumName sc e ++ ", " ++ columnType sc type ++ "> "
      ++ identText name ++ "{{"]
  ++ indent 4 (braced (map (cellText sc) cells))
  ++ ["}};", ""]

||| A declaration of a block other than an enum.
export
cppDecl : Scope -> CppDecl -> Lines
cppDecl _ (EnumOf _) = []
cppDecl sc (TableOf t) = concatMap (columnDecl sc t.enum) t.columns
cppDecl sc (Array1 name type cells doc) =
  slashComment [lineText doc]
  ++ ["inline constexpr std::array<" ++ columnType sc type ++ ", " ++ decimal (length cells) ++ "> " ++ identText name ++ "{{"]
  ++ indent 4 (braced (map (cellText sc) cells))
  ++ ["}};", ""]
cppDecl sc (Array2 name type rows doc) =
  let width = case rows of
                [] => 0
                (r :: _) => length r
  in slashComment [lineText doc]
     ++ ["inline constexpr std::array<std::array<" ++ columnType sc type ++ ", " ++ decimal width ++ ">, "
         ++ decimal (length rows) ++ "> " ++ identText name ++ "{{"]
     ++ indent 4 (map (\r => "{{" ++ joinWith ", " (map (cellText sc) r) ++ "}},") rows)
     ++ ["}};", ""]
cppDecl sc (Scalar name type cell doc) =
  slashComment [lineText doc] ++ ["inline constexpr " ++ columnType sc type ++ " " ++ identText name ++ " = " ++ cellText sc cell ++ ";", ""]

||| Whether a block is in the dialect's own namespace, where ODS declares
||| the dialect's enums.
export
dialectNamespace : CppName -> Bool
dialectNamespace (n ::: []) = identText n == "idr"
dialectNamespace _ = False

||| The enums a block declares, each once, in order: every enum it names
||| by itself; and, in a namespace of its own, the enum of every table, so
||| a reader that includes the header alone (the runtime) needs nothing of
||| the dialect's. In the dialect's namespace a table's enum is the
||| dialect's or one the block names by itself.
export
blockEnums : CppName -> List CppDecl -> List EnumDef
blockEnums ns ds = go [] ds
  where
    owns : List EnumDef -> EnumDef -> Bool
    owns seen e = any (\x => x.name == e.name) seen
    go : List EnumDef -> List CppDecl -> List EnumDef
    go seen [] = reverse seen
    go seen (EnumOf e :: rest) = go (if owns seen e then seen else e :: seen) rest
    go seen (TableOf t :: rest) =
      go (if dialectNamespace ns || owns seen t.enum then seen else t.enum :: seen) rest
    go seen (_ :: rest) = go seen rest

||| One block of an area's header: its enums in its namespace, their traits
||| in the dialect's (the template's), then its tables, arrays and
||| constants, which name the enums by the block's scope.
export
headerBlock : (CppName, List CppDecl) -> Lines
headerBlock (ns, ds) =
  let ownEnums = blockEnums ns ds
      sc = MkScope (namespaceText ns) (map (.name) ownEnums)
      enums = case ownEnums of
                [] => []
                es => inNamespace sc.space (concatMap enumDecl es) ++ [""]
                      ++ inNamespace "idr" (concatMap (\e => enumTraits (enumName sc e) e) es) ++ [""]
      rest = case concatMap (cppDecl sc) ds of
               [] => []
               ls => inNamespace sc.space ls ++ [""]
  in enums ++ rest

||| An area's header, block by block, printed under
||| `foreign/idr/include/idr/IR/Generated/<name>.h.inc`.
export
areaHeader : Header -> (Path, String)
areaHeader h =
  let stem = identText h.name
  in ( "foreign" ::: ["idr", "include", "idr", "IR", "Generated", stem ++ ".h.inc"]
     , render (header stem ["\"idr/Support/Enum.h\"", "<array>", "<cstddef>", "<cstdint>", "<string_view>"]
                      (slashComment (lineText h.doc.summary :: proseLines h.doc.description) ++ [""]
                       ++ concatMap headerBlock h.blocks)) )

||| The traits of the dialect's ODS enums, which mlir-tblgen declares.
export
odsEnumTraits : List EnumDef -> Lines
odsEnumTraits es =
  header "EnumTraits" ["\"idr/Support/Enum.h\"", "<array>", "<cstddef>", "<string_view>"]
    (inNamespace "idr" (concatMap (\e => enumTraits ("::idr::" ++ identText e.name) e) es))

------------------------------------------------------------------------------
-- Op identity
------------------------------------------------------------------------------

||| Every op of ours and every admitted upstream op, in declaration order:
||| the dense index every per-op table is keyed by.
public export
data OpKey = OurOp AnyOp | AdmittedOp Admitted

export
keyName : OpKey -> String
keyName (OurOp (SomeOp op)) = opClass op
keyName (AdmittedOp a) = identText a.upstreamRecord

export
keyClass : OpKey -> String
keyClass (OurOp (SomeOp op)) = opQualifiedClass op
keyClass (AdmittedOp a) = admittedAlias a

export
opIndexHeader : List OpKey -> Lines
opIndexHeader keys =
  header "OpIndex" ["\"idr/Support/Enum.h\"", "\"idr/IR/IdrAdmittedClasses.h.inc\"", "<array>", "<cstdint>", "<string_view>", "<type_traits>"]
    (inNamespace "idr"
      ( slashComment ["Every op of the dialect and every admitted upstream op, the key of every per-op table."]
        ++ ["enum class OpIndex : std::uint16_t {"] ++ indent 2 (map (\k => keyName k ++ ",") keys) ++ ["};", ""]
        ++ [ "template <>", "struct EnumTraits<OpIndex> {"
           , "  static constexpr std::size_t count = " ++ decimal (length keys) ++ ";"
           , "};", "" ]
        ++ slashComment ["The index of an op's class; no primary definition, so a class outside the set has none."]
        ++ ["template <class OpT>", "struct IndexOf;", ""]
        ++ concatMap (\k => [ "template <>", "struct IndexOf<" ++ keyClass k ++ "> : std::integral_constant<OpIndex, OpIndex::" ++ keyName k ++ "> {};" ]) keys
        ++ ["", "template <class OpT>", "inline constexpr OpIndex indexOf = IndexOf<OpT>::value;"] ))

------------------------------------------------------------------------------
-- Specializations: families' constants, word ops
------------------------------------------------------------------------------

export
constantMember : (Ident, Constant) -> String
constantMember (n, EnumConstant c) =
  "static constexpr ::idr::" ++ identText c.enum.name ++ " " ++ identText n ++ " = ::idr::" ++ identText c.enum.name ++ "::" ++ identText c.name ++ ";"
constantMember (n, IntConstant i) = "static constexpr std::int64_t " ++ identText n ++ " = " ++ integer i ++ ";"
constantMember (n, UpstreamClass a) = "using " ++ identText n ++ " = " ++ admittedAlias a ++ ";"
constantMember (n, NoClass) = "using " ++ identText n ++ " = void;"

||| The members of one template: each op that specializes it, with its
||| constants.
export
membersOf : Ident -> List AnyOp -> List (String, List (Ident, Constant))
membersOf t [] = []
membersOf t (SomeOp op :: ops) = case find (\s => s.template == t) op.specializations of
  Just s => (opQualifiedClass op, s.constants) :: membersOf t ops
  Nothing => membersOf t ops

||| Every template some op specializes, once each, in first use's order.
export
templatesOf : List AnyOp -> List Ident
templatesOf ops = nub (concatMap (\(SomeOp op) => map (.template) op.specializations) ops)

||| A template's header: under `GET_<TEMPLATE>_LIST` the member classes,
||| separated by commas, for a pack over all of them; else the
||| specializations.
export
specializationHeader : Ident -> List AnyOp -> Lines
specializationHeader t ops =
  let members = membersOf t ops
      macro = "GET_" ++ pack (map up (unpack (snakeOf (identText t)))) ++ "_LIST"
  in banner slashComment
     ++ ["#ifdef " ++ macro, "#undef " ++ macro, ""]
     ++ zipWith (++) (map fst members) (replicate (pred (length members)) "," ++ [""])
     ++ ["", "#else"]
     ++ header (identText t) ["\"idr/IR/IdrAdmittedClasses.h.inc\"", "<cstdint>"]
          (inNamespace "idr"
             ( ["template <class OpT>", "struct " ++ identText t ++ ";", ""]
               ++ concatMap (\(cls, cs) => ["template <>", "struct " ++ identText t ++ "<" ++ cls ++ "> {"]
                                          ++ indent 2 (map constantMember cs) ++ ["};", ""]) members ))
     ++ ["#endif"]
  where
    up : Char -> Char
    up c = if lower c then chr (ord c - 32) else c

------------------------------------------------------------------------------
-- Inline meanings
------------------------------------------------------------------------------

||| Every inline meaning an op of the dialect has, each once, in first use's
||| order: the function objects of the numeric template, as a list of types
||| a test folds over, so a meaning an op gains is one it checks.
export
inlineMeaningsHeader : List AnyOp -> Lines
inlineMeaningsHeader ops =
  header "InlineMeanings" ["<tuple>"]
    (inNamespace "idr::numeric"
      ( slashComment ["Every inline meaning of the dialect's ops, each once."]
        ++ ["using Meanings = std::tuple<" ++ joinWith ", " (map (\f => "::idr::numeric::" ++ identText f) (once [] (concatMap meaningOf ops))) ++ ">;"] ))
  where
    meaningOf : AnyOp -> List Ident
    meaningOf (SomeOp op) = case op.meaning of
      Inline fn => [fn]
      _ => []
    once : List Ident -> List Ident -> List Ident
    once _ [] = []
    once seen (f :: fs) = if elem f seen then once seen fs else f :: once (f :: seen) fs

------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------

export
guardText : Guard i -> String
guardText g = "::idr::Guard<::idr::" ++ opRefClass g.check ++ ", " ++ joinWith ", " (map (decimal . finToNat) (forget g.given)) ++ ">"

export
guardedOf : AnyOp -> Lines
guardedOf (SomeOp op) = case op.guards of
  [] => []
  gs => [ "template <>", "struct Guarded<" ++ opQualifiedClass op ++ "> {"
        , "  using Guards = std::tuple<" ++ joinWith ", " (map guardText gs) ++ ">;"
        , "};", "" ]

||| Each partial op's guards, `Guarded<Op>`, which its folder and its
||| speculation read (Traits.h).
export
guardsHeader : List AnyOp -> Lines
guardsHeader ops = header "Guards" ["<tuple>"] (inNamespace "idr" (concatMap guardedOf ops))

------------------------------------------------------------------------------
-- The runtime's C ABI
------------------------------------------------------------------------------

export
takesC : OperandKind -> String
takesC TakesInt32 = "int32_t"
takesC TakesInt64 = "int64_t"
takesC TakesDouble = "double"
takesC TakesSigned = "int64_t"
takesC TakesUnsigned = "uint64_t"
takesC TakesStr = "const idris_rt_str *"
takesC TakesBig = "idris_rt_big"
takesC TakesBuffer = "idris_rt_array *"
takesC (TakesPointerTo c) = codeText c ++ " *"
takesC TakesBool = "bool"

export
givesC : ResultKind -> String
givesC GivesInt32 = "int32_t"
givesC GivesInt64 = "int64_t"
givesC GivesDouble = "double"
givesC GivesWrapped = "int64_t"
givesC GivesOrder = "int32_t"
givesC GivesStr = "const idris_rt_str *"
givesC GivesBig = "idris_rt_big"
givesC (GivesPointerTo c) = codeText c ++ " *"
givesC GivesBool = "bool"

||| How the lowering passes an operand: by the word LLVM gives it, so every
||| pointer, whatever it points to, is one kind.
export
takesName : OperandKind -> String
takesName TakesInt32 = "Int32"
takesName TakesInt64 = "Int64"
takesName TakesDouble = "Double"
takesName TakesSigned = "Signed"
takesName TakesUnsigned = "Unsigned"
takesName TakesStr = "Str"
takesName TakesBig = "Big"
takesName TakesBuffer = "Buffer"
takesName (TakesPointerTo _) = "Pointer"
takesName TakesBool = "Bool"

export
givesName : ResultKind -> String
givesName GivesInt32 = "Int32"
givesName GivesInt64 = "Int64"
givesName GivesDouble = "Double"
givesName GivesWrapped = "Wrapped"
givesName GivesOrder = "Order"
givesName GivesStr = "Str"
givesName GivesBig = "Big"
givesName (GivesPointerTo _) = "Pointer"
givesName GivesBool = "Bool"

||| A C declarator: the type, then the name, `const idris_rt_str *s`.
export
declarator : String -> String -> String
declarator type name = if isSuffixOf "*" type then type ++ name else type ++ " " ++ name

||| An op's runtime call, if its meaning is one function.
export
callOf : Op i o a r -> Maybe (RuntimeCall i o)
callOf op = case op.meaning of
  CallsRuntime c => Just c
  ComputedByRuntime c => Just c
  _ => Nothing

||| An op's runtime calls by case, if its meaning is one function per case
||| of an enum: each case's symbol, the call's stem and the case's spelling.
export
callsByCase : Op i o a r -> Maybe (RuntimeCall i o, List String)
callsByCase op = case op.meaning of
  CallsRuntimeByCase e c => Just (c, map (\k => symbolText c.symbol ++ "_" ++ joinWith "_" (map wordText (forget k.spelling))) (forget e.cases))
  _ => Nothing

||| One C function of the runtime, as its prototype and its row of the ABI
||| table are printed: its symbol, its parameters (each kind and name), what
||| it returns, the results it gives through pointers, and its comment.
public export
record CFunction where
  constructor MkCFunction
  cSymbol : String
  cTakes : List (OperandKind, String)
  cReturns : HelperGives
  cOuts : List (ResultKind, String)
  cComment : String

||| Every C function an op names as its meaning: its operands by their
||| groups' names, its results through pointers where it gives several; one
||| per case where its meaning is one function per case.
export
functionsOf : AnyOp -> List CFunction
functionsOf (SomeOp op) = case (callOf op, callsByCase op) of
  (Just c, _) => [made c (symbolText c.symbol)]
  (Nothing, Just (c, symbols)) => map (made c) symbols
  (Nothing, Nothing) => []
  where
    params : RuntimeCall i o -> List (OperandKind, String)
    params c = zipWith (\k, x => (k, identText x.name)) (toList c.takes) (toList op.ins)
    made : RuntimeCall i o -> String -> CFunction
    made c sym = case c.gives of
      NoResult => MkCFunction sym (params c) HelperNothing [] (opName op)
      NeverReturns => MkCFunction sym (params c) HelperNeverReturns [] (opName op)
      Returns k => MkCFunction sym (params c) (HelperReturns k) [] (opName op)
      ThroughPointers ks =>
        MkCFunction sym (params c) HelperNothing
          (zipWith (\k, x => (k, identText x.name)) (toList ks) (toList op.outs)) (opName op)

||| A helper the lowering calls by itself, as a C function.
export
helperFunction : RuntimeHelper -> CFunction
helperFunction h = MkCFunction (symbolText h.symbol) (map (\(k, n) => (k, identText n)) h.params) h.gives [] (lineText h.doc)

||| The functions, each symbol once, the first that names it kept: two ops
||| may share a function, which is declared once.
export
distinctFunctions : List CFunction -> List CFunction
distinctFunctions = go []
  where
    go : List String -> List CFunction -> List CFunction
    go _ [] = []
    go seen (f :: fs) = if elem f.cSymbol seen then go seen fs else f :: go (f.cSymbol :: seen) fs

export
prototype : CFunction -> Lines
prototype f =
  let result = case f.cReturns of
                 HelperNothing => "void"
                 HelperNeverReturns => "IDRIS_RT_NORETURN void"
                 HelperReturns k => givesC k
      ps = map (\(k, n) => declarator (takesC k) n) f.cTakes
           ++ map (\(k, n) => declarator (givesC k ++ " *") n) f.cOuts
  in ["// " ++ f.cComment, result ++ " " ++ f.cSymbol ++ "(" ++ cParams ps ++ ");"]

||| The runtime's prototypes of every function an op or the lowering calls,
||| each pointer typed by what it points to, which the runtime includes, so
||| a definition that disagrees does not compile.
export
runtimeOps : List AnyOp -> List RuntimeHelper -> Lines
runtimeOps ops helpers =
  banner slashComment
  ++ ["#ifndef IDRIS_RT_OPS_H", "#define IDRIS_RT_OPS_H", "", "#ifdef __cplusplus", "extern \"C\" {", "#endif", ""]
  ++ concatMap prototype (distinctFunctions (concatMap functionsOf ops))
  ++ [""]
  ++ concatMap prototype (distinctFunctions (map helperFunction helpers))
  ++ ["", "#ifdef __cplusplus", "}", "#endif", "", "#endif // IDRIS_RT_OPS_H"]

||| What a function returns, as the table spells it.
export
resultKindOf : HelperGives -> String
resultKindOf HelperNothing = "ResultKind::Void"
resultKindOf HelperNeverReturns = "ResultKind::NoReturn"
resultKindOf (HelperReturns k) = "ResultKind::" ++ givesName k

||| The kinds of a function's operands, as a table's initializer.
operandKinds : CFunction -> List String
operandKinds f = map (\(k, _) => "OperandKind::" ++ takesName k) f.cTakes

||| The kinds of the results a function gives through pointers.
outKinds : CFunction -> List String
outKinds f = map (\(k, _) => "ResultKind::" ++ givesName k) f.cOuts

||| The array a function's row names for its outs: its own, or the shared
||| empty one.
outsArray : CFunction -> String
outsArray f = case f.cOuts of
  [] => "noOuts"
  _ => "outs"

export
abiRow : AnyOp -> Lines
abiRow (SomeOp op) = case (functionsOf (SomeOp op), callsByCase op) of
  ([f], Nothing) =>
    [ "template <>", "struct Abi<" ++ opQualifiedClass op ++ "> {"
    , "  static constexpr std::array<OperandKind, " ++ decimal (length f.cTakes) ++ "> operands" ++ arrayInit (operandKinds f) ++ ";" ]
    ++ outsDecl f
    ++ [ "  static constexpr Function entry{" ++ quoted f.cSymbol ++ ", operands, " ++ resultKindOf f.cReturns ++ ", " ++ outsArray f ++ "};"
       , "  static constexpr auto *function = &" ++ f.cSymbol ++ ";"
       , "};", "" ]
  (f :: fs, Just _) =>
    [ "template <>", "struct AbiByCase<" ++ opQualifiedClass op ++ "> {"
    , "  static constexpr std::array<OperandKind, " ++ decimal (length f.cTakes) ++ "> operands" ++ arrayInit (operandKinds f) ++ ";" ]
    ++ outsDecl f
    ++ [ "  // One entry per case of the op's enum, in the cases' order."
       , "  static constexpr std::array<Function, " ++ decimal (length (f :: fs)) ++ "> entries{{"
         ++ joinWith ", " (map (\g => "Function{" ++ quoted g.cSymbol ++ ", operands, " ++ resultKindOf g.cReturns ++ ", " ++ outsArray g ++ "}") (f :: fs)) ++ "}};"
       , "};", "" ]
  _ => []
  where
    outsDecl : CFunction -> Lines
    outsDecl f = case f.cOuts of
      [] => []
      _ => ["  static constexpr std::array<ResultKind, " ++ decimal (length f.cOuts) ++ "> outs" ++ arrayInit (outKinds f) ++ ";"]

||| Where a table names each function of an op: its `Abi<Op>`'s entry, or
||| each of its `AbiByCase<Op>`'s entries.
entriesOf : AnyOp -> List (String, String)
entriesOf (SomeOp op) = case (functionsOf (SomeOp op), callsByCase op) of
  ([f], Nothing) => [(f.cSymbol, "&Abi<" ++ opQualifiedClass op ++ ">::entry")]
  (fs, Just _) => zipWith (\f, k => (f.cSymbol, "&AbiByCase<" ++ opQualifiedClass op ++ ">::entries[" ++ decimal k ++ "]")) fs [0 .. length fs]
  _ => []

export
helperRow : RuntimeHelper -> Lines
helperRow h =
  let f = helperFunction h
  in [ "inline constexpr std::array<OperandKind, " ++ decimal (length f.cTakes) ++ "> " ++ identText h.name ++ "Operands" ++ arrayInit (operandKinds f) ++ ";"
     , "inline constexpr Function " ++ identText h.name ++ "{" ++ quoted f.cSymbol ++ ", " ++ identText h.name ++ "Operands, " ++ resultKindOf f.cReturns ++ ", noOuts};" ]

||| Each op's row of the runtime's ABI, `Abi<Op>`, each helper the lowering
||| calls, and every function once in `functions`, which the lowering
||| declares: read by the lowering and the one runtime fold.
export
runtimeAbi : List AnyOp -> List RuntimeHelper -> Lines
runtimeAbi ops helpers =
  let named = concatMap entriesOf ops ++ map (\h => (symbolText h.symbol, "&helper::" ++ identText h.name)) helpers
      every = distinct [] named
  in header "RuntimeAbi" ["\"idris_rt.h\"", "<array>", "<span>", "<string_view>"]
       (inNamespace "idr::runtime"
         ( [ "enum class OperandKind : unsigned char { Int32, Int64, Double, Signed, Unsigned, Str, Big, Buffer, Pointer, Bool };"
           , "enum class ResultKind : unsigned char { Void, NoReturn, Int32, Int64, Double, Wrapped, Order, Str, Big, Pointer, Bool };"
           , "" ]
           ++ slashComment [ "A runtime function as the lowering calls it: its symbol, how it takes each operand,"
                           , "what it returns, and, where it returns nothing, the kinds of the results it gives"
                           , "through the pointers its caller passes after the operands." ]
           ++ [ "struct Function {"
              , "  std::string_view symbol;"
              , "  std::span<const OperandKind> operands;"
              , "  ResultKind result;"
              , "  std::span<const ResultKind> outs;"
              , "};"
              , ""
              , "inline constexpr std::array<ResultKind, 0> noOuts{};"
              , ""
              , "template <class OpT>"
              , "struct Abi;"
              , ""
              , "// An op whose meaning is one runtime function per case of its enum."
              , "template <class OpT>"
              , "struct AbiByCase;"
              , "" ]
           ++ concatMap abiRow ops
           ++ ["namespace helper {"] ++ concatMap helperRow helpers ++ ["} // namespace helper", ""]
           ++ slashComment ["Every function of the runtime lowered code calls, each once."]
           ++ ["inline constexpr std::array<const Function *, " ++ decimal (length every) ++ "> functions{{"]
           ++ indent 4 (braced every)
           ++ ["}};"] ))
  where
    distinct : List String -> List (String, String) -> List String
    distinct _ [] = []
    distinct seen ((sym, ref) :: rest) = if elem sym seen then distinct seen rest else ref :: distinct (sym :: seen) rest

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------

export
resourceId : OdsResource -> String
resourceId UpstreamRoot = "::idr::effects::ResourceId::Root"
resourceId UpstreamFrame = "::idr::effects::ResourceId::Frame"
resourceId (OurResource r) = "::idr::effects::ResourceId::" ++ identText r.name

export
kindId : EffectKind -> String
kindId MemRead = "::idr::effects::Kind::Read"
kindId MemWrite = "::idr::effects::Kind::Write"
kindId MemAlloc = "::idr::effects::Kind::Allocate"
kindId MemFree = "::idr::effects::Kind::Free"

export
subjectText : Subject i o -> String
subjectText OfOp = "::idr::effects::Subject::op()"
subjectText (OfOperand k) = "::idr::effects::Subject::operand(" ++ decimal (finToNat k) ++ ")"
subjectText (OfResult k) = "::idr::effects::Subject::result(" ++ decimal (finToNat k) ++ ")"

export
effectRow : OdsEffect i o -> String
effectRow e = "{" ++ kindId e.kind ++ ", " ++ resourceId e.resource ++ ", " ++ subjectText e.subject ++ "}"

export
ruleType : OdsRule i o -> String
ruleType r = "::idr::effects::" ++ identText r.rule ++ "<" ++ subjectText' r.subject ++ ">"
  where
    subjectText' : Subject i o -> String
    subjectText' OfOp = "::idr::effects::OnOp"
    subjectText' (OfOperand k) = "::idr::effects::OnOperand<" ++ decimal (finToNat k) ++ ">"
    subjectText' (OfResult k) = "::idr::effects::OnResult<" ++ decimal (finToNat k) ++ ">"

export
declaredOf : AnyOp -> Lines
declaredOf (SomeOp op) = case ods op.effects of
  EveryEffect =>
    [ "template <>", "struct Declared<" ++ opQualifiedClass op ++ "> {"
    , "  static constexpr Form form = Form::Everything;", "};", "" ]
  Declares es rules bodies =>
    [ "template <>", "struct Declared<" ++ opQualifiedClass op ++ "> {"
    , "  static constexpr Form form = Form::Declares;"
    , "  static constexpr std::array<Static, " ++ decimal (length es) ++ "> effects{{" ++ joinWith ", " (map effectRow es) ++ "}};"
    , "  using Rules = std::tuple<" ++ joinWith ", " (map ruleType rules) ++ ">;"
    , "  static constexpr Bodies bodies = " ++ bodiesText bodies ++ ";"
    , "};", "" ]

||| Each op's declared effects as compile-time constants, `Declared<Op>`,
||| which the one query API and the generated `getEffects` read.
export
effectsHeader : List AnyOp -> Lines
effectsHeader ops =
  header "Effects" ["\"idr/IR/Effects/Vocabulary.h\"", "<array>", "<tuple>"]
    (inNamespace "idr::effects" (concatMap declaredOf ops))

export
hasRules : AnyOp -> Bool
hasRules (SomeOp op) = case ods op.effects of
  Declares _ (_ :: _) _ => True
  _ => False

||| The definitions of `getEffects` for the ops whose effects follow from
||| types, each the one query API's, which reads the op's table.
export
effectsDefinitions : List AnyOp -> Lines
effectsDefinitions ops =
  banner slashComment
  ++ concatMap def (filter hasRules ops)
  where
    def : AnyOp -> Lines
    def (SomeOp op) =
      [ "void " ++ opQualifiedClass op ++ "::getEffects("
      , "    ::llvm::SmallVectorImpl<::mlir::SideEffects::EffectInstance<::mlir::MemoryEffects::Effect>> &effects) {"
      , "  ::idr::effects::declare(*this, effects);"
      , "}", "" ]

||| Each state of the effect tree by its name, `::idr::effects::Heap` and kin,
||| the names the printed ODS's effects use: the one class template of the
||| effect system's header, at the state's case, whose facts its tables hold.
export
resourcesHeader : List ResourceDef -> Lines
resourcesHeader rs =
  header "Resources" []
    (inNamespace "idr::effects" (map alias rs))
  where
    alias : ResourceDef -> String
    alias r = "using " ++ identText r.name ++ " = ::idr::effects::State<::idr::ResourceId::" ++ identText r.name ++ ">;"

------------------------------------------------------------------------------
-- The e-graph's rules
------------------------------------------------------------------------------

||| A pattern node flattened, its op named by its class: a variable, an op
||| at one of its results with its arity, or a literal.
public export
data FlatNode = FVar Nat | FNode String Nat Nat | FLit Integer

||| A rule flattened: its root's class, its variables, its two sides in
||| preorder, its conditions as printed rows, its direction.
public export
record FlatRule where
  constructor MkFlatRule
  root : String
  vars : Nat
  lhs : List FlatNode
  rhs : List FlatNode
  conds : List String
  direction : Direction

mutual
  flatPat : Pat n -> List FlatNode
  flatPat (Var v) = [FVar (finToNat v)]
  flatPat (Node op res args) = FNode (opQualifiedClass op) (finToNat res) (length args) :: flatVect args
  flatPat (UpstreamNode a args) = FNode (admittedAlias a) 0 (length args) :: flatList args
  flatPat (Literal l) = [FLit l]

  flatVect : Vect k (Pat n) -> List FlatNode
  flatVect [] = []
  flatVect (p :: ps) = flatPat p ++ flatVect ps

  flatList : List (Pat n) -> List FlatNode
  flatList [] = []
  flatList (p :: ps) = flatPat p ++ flatList ps

export
flatRoot : Root n -> (String, List FlatNode)
flatRoot (RootedAt op res args) =
  (opQualifiedClass op, FNode (opQualifiedClass op) (finToNat res) (length args) :: flatVect args)
flatRoot (RootedAtUpstream a args) =
  (admittedAlias a, FNode (admittedAlias a) 0 (length args) :: flatList args)

export
condRow : Cond n -> String
condRow (IsConstant v) = "{table::ConditionKind::IsConstant, " ++ decimal (finToNat v) ++ ", 0, 0}"
condRow (PowerOfTwo v) = "{table::ConditionKind::PowerOfTwo, " ++ decimal (finToNat v) ++ ", 0, 0}"
condRow (InRange v lo hi) = "{table::ConditionKind::InRange, " ++ decimal (finToNat v) ++ ", " ++ integer lo ++ ", " ++ integer hi ++ "}"
condRow (Clean v) = "{table::ConditionKind::Clean, " ++ decimal (finToNat v) ++ ", 0, 0}"

export
fromRewrite : AnyRewrite -> FlatRule
fromRewrite (SomeRewrite rw) =
  let (root, lhs) = flatRoot rw.lhs
  in MkFlatRule root (length (toList rw.vars)) lhs (flatPat rw.rhs) (map condRow rw.conds) rw.direction

||| The rules of a binary operation's associativity and identity, on the
||| operation's class.
associativeRule : String -> FlatRule
associativeRule c =
  let two = FNode c 0 2
  in MkFlatRule c 3 [two, two, FVar 0, FVar 1, FVar 2] [two, FVar 0, two, FVar 1, FVar 2] [] Equal

identityRule : String -> Integer -> FlatRule
identityRule c k = MkFlatRule c 1 [FNode c 0 2, FVar 0, FLit k] [FVar 0] [] Simplify

||| The rules an op's laws give: the law is the one fact, so its rules are
||| derived here and never written beside it. Binary laws need two
||| operands, an involution one; a law on an op of another arity gives none.
export
lawRules : AnyOp -> List FlatRule
lawRules (SomeOp op) = concatMap (rulesOf (length (toList op.ins))) op.laws
  where
    c : String
    c = opQualifiedClass op
    two : FlatNode
    two = FNode c 0 2
    rulesOf : Nat -> Law -> List FlatRule
    rulesOf 2 Commutative = [MkFlatRule c 2 [two, FVar 0, FVar 1] [two, FVar 1, FVar 0] [] Equal]
    rulesOf 2 Associative = [associativeRule c]
    rulesOf 2 (Identity k) = [identityRule c k]
    rulesOf 2 (Annihilator k) = [MkFlatRule c 1 [two, FVar 0, FLit k] [FLit k] [] Simplify]
    rulesOf 2 Idempotent = [MkFlatRule c 1 [two, FVar 0, FVar 0] [FVar 0] [] Simplify]
    rulesOf 1 Involution = [MkFlatRule c 1 [FNode c 0 1, FNode c 0 1, FVar 0] [FVar 0] [] Simplify]
    rulesOf _ _ = []

||| The rules an admitted upstream op's laws give, on its class: every law
||| upstream has no trait for is binary.
export
admittedLawRules : Admitted -> List FlatRule
admittedLawRules a = map ruleOf a.laws
  where
    ruleOf : UpLaw -> FlatRule
    ruleOf UpAssociative = associativeRule (admittedAlias a)
    ruleOf (UpIdentity k) = identityRule (admittedAlias a) k

||| The classes a node of the rules names, each once, in first use's order:
||| a kind's number is its position.
export
kindsOf : List FlatRule -> List String
kindsOf rules = nub (concatMap (\r => classes (r.lhs ++ r.rhs)) rules)
  where
    classes : List FlatNode -> List String
    classes [] = []
    classes (FNode k _ _ :: ns) = k :: classes ns
    classes (_ :: ns) = classes ns

||| The position of a class among the kinds.
export
kindNumber : List String -> String -> Nat
kindNumber kinds k = go 0 kinds
  where
    go : Nat -> List String -> Nat
    go n [] = n
    go n (x :: xs) = if x == k then n else go (S n) xs

export
nodeRow : List String -> FlatNode -> String
nodeRow _ (FVar v) = "{table::PatternKind::Var, 0, 0, 0, " ++ decimal v ++ ", 0}"
nodeRow kinds (FNode k res arity) =
  "{table::PatternKind::Node, " ++ decimal (kindNumber kinds k) ++ ", " ++ decimal res ++ ", " ++ decimal arity ++ ", 0, 0}"
nodeRow _ (FLit l) = "{table::PatternKind::Literal, 0, 0, 0, 0, " ++ integer l ++ "}"

export
directionRow : Direction -> String
directionRow Simplify = "table::Direction::Simplify"
directionRow Equal = "table::Direction::Equal"

||| The rules grouped by their root's kind, in the kinds' order and, within
||| a kind, in declaration order: a grouping, never a sort.
export
byKind : List String -> List FlatRule -> List (List FlatRule)
byKind kinds rules = map (\k => filter (\r => r.root == k) rules) kinds

||| The rows of the rule table, with each side's and the conditions'
||| offsets into the pattern and condition arrays.
public export
record Laid where
  constructor MkLaid
  patterns : List String
  conditions : List String
  rules : List String

export
layRules : List String -> List FlatRule -> Laid
layRules kinds = go (MkLaid [] [] [])
  where
    go : Laid -> List FlatRule -> Laid
    go acc [] = acc
    go acc (r :: rs) =
      let p = length acc.patterns
          q = length acc.conditions
          lhs = map (nodeRow kinds) r.lhs
          rhs = map (nodeRow kinds) r.rhs
          row = "{" ++ decimal r.vars ++ ", " ++ decimal p ++ ", " ++ decimal (length lhs) ++ ", "
                ++ decimal (p + length lhs) ++ ", " ++ decimal (length rhs) ++ ", " ++ decimal q ++ ", "
                ++ decimal (length r.conds) ++ ", " ++ directionRow r.direction ++ "}"
      in go (MkLaid (acc.patterns ++ lhs ++ rhs) (acc.conditions ++ r.conds) (acc.rules ++ [row])) rs

||| Offsets of each kind's first rule, and one past the last.
export
offsets : List (List FlatRule) -> List Nat
offsets groups = go 0 groups
  where
    go : Nat -> List (List FlatRule) -> List Nat
    go n [] = [n]
    go n (g :: gs) = n :: go (n + length g) gs

||| The skeleton rules' classes, each once though it be rooted at several
||| ops, in first declaration's order.
export
skeletonClasses : List SkeletonRule -> List Ident
skeletonClasses = go []
  where
    go : List Ident -> List SkeletonRule -> List Ident
    go _ [] = []
    go seen (r :: rs) = if elem r.name seen then go seen rs else r.name :: go (r.name :: seen) rs

||| The headers that declare the skeleton rules, each once, in first
||| declaration's order: what the engine includes to name every rule.
export
skeletonRulesHeader : List SkeletonRule -> Lines
skeletonRulesHeader rules =
  header "SkeletonRules" (map (\p => quoted (pathText p)) (headers [] rules))
    (slashComment ["Every header that declares a skeleton rule the specification names."])
  where
    headers : List String -> List SkeletonRule -> List Path
    headers _ [] = []
    headers seen (r :: rs) =
      let p = pathText r.declaredIn
      in if elem p seen then headers seen rs else r.declaredIn :: headers (p :: seen) rs

||| The e-graph's rules as the engine reads them: the patterns in preorder,
||| the conditions, the rules grouped by root kind with each kind's offset,
||| the kinds, the skeleton rules, and the budget, all compile-time
||| constants, so nothing is built per function. The rules are the
||| specification's, its ops' laws' and its admitted ops' laws'.
export
rewritesHeader : List AnyRewrite -> List AnyOp -> List Admitted -> List SkeletonRule -> Lines
rewritesHeader rws ops admitted skeleton =
  let rules = map fromRewrite rws ++ concatMap lawRules ops ++ concatMap admittedLawRules admitted
      kinds = kindsOf rules
      groups = byKind kinds rules
      laid = layRules kinds (concat groups)
  in header "Rewrites" ["\"idr/Transforms/EGraph.h\"", "\"idr/IR/IdrAdmittedClasses.h.inc\"", "\"idr/IR/Generated/SkeletonRules.h.inc\"", "<cstdint>"]
       (inNamespace "idr::egraph::generated"
         ( ["using Kinds = table::OpList<" ++ joinWith ", " kinds ++ ">;", ""]
           ++ ["inline constexpr table::PatternNode patterns[] = {"] ++ indent 2 (braced laid.patterns) ++ ["};", ""]
           ++ ["inline constexpr table::Condition conditions[] = {"] ++ indent 2 (braced laid.conditions) ++ ["};", ""]
           ++ ["inline constexpr table::Rule rules[] = {"] ++ indent 2 (braced laid.rules) ++ ["};", ""]
           ++ ["inline constexpr std::uint32_t rulesOfKind[] = {" ++ joinWith ", " (map decimal (offsets groups)) ++ "};", ""]
           ++ ["using SkeletonRules = table::RuleList<" ++ joinWith ", " (map (\n => "::idr::egraph::" ++ identText n) (skeletonClasses skeleton)) ++ ">;", ""]
           ++ slashComment ["Nodes per op of a function's e-graph: its arena, known before its search starts, is this times its ops."]
           ++ ["inline constexpr std::uint32_t nodesPerOp = 64;"] ))

------------------------------------------------------------------------------
-- Laws
------------------------------------------------------------------------------

||| An op the specification calls exactly associative with an identity, by
||| its class, with that identity: of ours by its laws, admitted by its
||| upstream laws. Associativity alone or an identity alone is not enough:
||| an accumulator combines on the way down what the call combined on the
||| way back, which needs both.
export
unitsOf : List AnyOp -> List Admitted -> List (String, Integer)
unitsOf ops admitted = concatMap ours ops ++ concatMap upstream admitted
  where
    identityIn : List Law -> Maybe Integer
    identityIn [] = Nothing
    identityIn (Identity k :: _) = Just k
    identityIn (_ :: ls) = identityIn ls
    isAssociative : Law -> Bool
    isAssociative Associative = True
    isAssociative _ = False
    associative : List Law -> Bool
    associative = any isAssociative
    ours : AnyOp -> List (String, Integer)
    ours (SomeOp op) = case (associative op.laws, identityIn op.laws) of
      (True, Just k) => [(opQualifiedClass op, k)]
      _ => []
    upIdentity : List UpLaw -> Maybe Integer
    upIdentity [] = Nothing
    upIdentity (UpIdentity k :: _) = Just k
    upIdentity (_ :: ls) = upIdentity ls
    isUpAssociative : UpLaw -> Bool
    isUpAssociative UpAssociative = True
    isUpAssociative _ = False
    upAssociative : List UpLaw -> Bool
    upAssociative = any isUpAssociative
    upstream : Admitted -> List (String, Integer)
    upstream a = case (upAssociative a.laws, upIdentity a.laws) of
      (True, Just k) => [(admittedAlias a, k)]
      _ => []

||| The operations an accumulator may combine on the way down, as a list of
||| types the hand `laws::identityOf` folds over: each a class and its
||| identity, compile-time constants.
export
lawsHeader : List AnyOp -> List Admitted -> Lines
lawsHeader ops admitted =
  header "Laws" ["\"idr/IR/IdrAdmittedClasses.h.inc\"", "<cstdint>", "<tuple>"]
    (inNamespace "idr::laws"
      ( slashComment ["An operation the specification calls exactly associative, and its identity."]
        ++ [ "template <class OpT, std::int64_t Identity>"
           , "struct Unit {"
           , "  using Op = OpT;"
           , "  static constexpr std::int64_t identity = Identity;"
           , "};", "" ]
        ++ slashComment ["Every such operation, ours first, then the admitted upstream ones."]
        ++ ["using Units = std::tuple<" ++ joinWith ", " (map (\(c, k) => "Unit<" ++ c ++ ", " ++ integer k ++ ">") (unitsOf ops admitted)) ++ ">;"] ))

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

export
parseArg : DirectiveArg -> String
parseArg OperandArg = "::mlir::OpAsmParser::UnresolvedOperand &"
parseArg VariadicOperandArg = "::llvm::SmallVectorImpl<::mlir::OpAsmParser::UnresolvedOperand> &"
parseArg OptionalOperandArg = "std::optional<::mlir::OpAsmParser::UnresolvedOperand> &"
parseArg TypeArg = "::mlir::Type &"
parseArg VariadicTypeArg = "::llvm::SmallVectorImpl<::mlir::Type> &"
parseArg (AttrArg c) = codeText c ++ " &"
parseArg RegionArg = "::mlir::Region &"
parseArg VariadicRegionArg = "::llvm::SmallVectorImpl<std::unique_ptr<::mlir::Region>> &"
parseArg RefTypeArg = "::mlir::Type"
parseArg (RefAttrArg c) = codeText c
parseArg RefVariadicTypeArg = "::mlir::TypeRange"

export
printArg : DirectiveArg -> String
printArg OperandArg = "::mlir::Value"
printArg VariadicOperandArg = "::mlir::OperandRange"
printArg OptionalOperandArg = "::mlir::Value"
printArg TypeArg = "::mlir::Type"
printArg VariadicTypeArg = "::mlir::TypeRange"
printArg (AttrArg c) = codeText c
printArg RegionArg = "::mlir::Region &"
printArg VariadicRegionArg = "::llvm::MutableArrayRef<::mlir::Region>"
printArg RefTypeArg = "::mlir::Type"
printArg (RefAttrArg c) = codeText c
printArg RefVariadicTypeArg = "::mlir::TypeRange"

export
directiveDecls : Directive -> Lines
directiveDecls d =
  slashComment [lineText d.doc.summary]
  ++ [ "::mlir::ParseResult parse" ++ identText d.name ++ "(::mlir::OpAsmParser &parser"
         ++ concatMap (\a => ", " ++ parseArg a) d.args ++ ");"
     , "void print" ++ identText d.name ++ "(::mlir::OpAsmPrinter &printer, ::mlir::Operation *op"
         ++ concatMap (\a => ", " ++ printArg a) d.args ++ ");", "" ]

export
predicateDecl : Predicate -> Lines
predicateDecl p =
  let subject = case p.subject of
                  OnType => "::mlir::Type"
                  OnAttribute => "::mlir::Attribute"
  in slashComment [lineText p.doc.summary] ++ ["bool " ++ identText p.name ++ "(" ++ subject ++ " value);", ""]

||| A hand codec a type or an attribute names: of one value of a hand class
||| (its spelling), or of an array of a hand class's elements (the
||| element's spelling), each with its directive.
public export
data Codec = ValueCodec Code Directive | ArrayCodec Code Directive

codecDirective : Codec -> Directive
codecDirective (ValueCodec _ d) = d
codecDirective (ArrayCodec _ d) = d

||| Every hand codec the types and attributes name, a list's elements' too,
||| once per directive, in first use's order.
export
codecsOf : List AnyTypeDef -> List AnyAttrDef -> List Codec
codecsOf ts as = once [] (concatMap fromType ts ++ concatMap fromAttr as)
  where
    hand : ParamKind -> List Codec
    hand (HandValue c d) = [ValueCodec c d]
    hand (HandArray c d) = [ArrayCodec c d]
    hand (ListOf k) = hand k
    hand _ = []
    fromType : AnyTypeDef -> List Codec
    fromType (SomeType t) = concatMap (\x => hand x.kind) (toList t.params)
    fromAttr : AnyAttrDef -> List Codec
    fromAttr (SomeAttr a) = concatMap (\x => hand x.kind) (toList a.params)
    once : List Ident -> List Codec -> List Codec
    once _ [] = []
    once seen (c :: cs) =
      let n = (codecDirective c).name
      in if elem n seen then once seen cs else c :: once (n :: seen) cs

||| A codec's declarations: a parser and a printer of the value, and its
||| reader and writer in bytecode. An array is parsed and read into the
||| vector that owns its elements, and printed and written from its view.
export
codecDecls : Codec -> Lines
codecDecls codec =
  let (held, owned, d) = case codec of
        ValueCodec c d => (codeText c, codeText c, d)
        ArrayCodec c d => ("::llvm::ArrayRef<" ++ codeText c ++ ">", "::llvm::SmallVector<" ++ codeText c ++ ">", d)
  in [ "::mlir::FailureOr<" ++ owned ++ "> parse" ++ identText d.name ++ "(::mlir::AsmParser &parser);"
     , "void print" ++ identText d.name ++ "(::mlir::AsmPrinter &printer, " ++ held ++ " value);"
     , "::mlir::LogicalResult read" ++ identText d.name ++ "(::mlir::DialectBytecodeReader &reader, " ++ owned ++ " &value);"
     , "void write" ++ identText d.name ++ "(::mlir::DialectBytecodeWriter &writer, " ++ held ++ " value);", "" ]

||| Every hand property the ops hold, once per directive: its class and its
||| directive.
export
propertiesOf : List AnyOp -> List (Code, Directive)
propertiesOf ops = once [] (concatMap fromOp ops)
  where
    hand : Attr -> List (Code, Directive)
    hand x = case x.kind of
      AProperty (HandProperty c d _) => [(c, d)]
      _ => []
    fromOp : AnyOp -> List (Code, Directive)
    fromOp (SomeOp op) = concatMap hand (toList op.attrs)
    once : List Ident -> List (Code, Directive) -> List (Code, Directive)
    once _ [] = []
    once seen ((c, d) :: rest) =
      if elem d.name seen then once seen rest else (c, d) :: once (d.name :: seen) rest

||| A hand property's hooks: its attribute form both ways, its hash, and
||| its bytecode, as ODS's property calls them.
export
propertyDecls : (Code, Directive) -> Lines
propertyDecls (c, d) =
  let t = codeText c
      n = identText d.name
  in slashComment [lineText d.doc.summary]
     ++ [ "::mlir::Attribute convert" ++ n ++ "ToAttribute(::mlir::MLIRContext *context, " ++ t ++ " value);"
        , "::mlir::LogicalResult convert" ++ n ++ "FromAttribute(" ++ t ++ " &value, ::mlir::Attribute attribute,"
        , "    ::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError);"
        , "::llvm::hash_code hash" ++ n ++ "(" ++ t ++ " value);"
        , "::mlir::LogicalResult read" ++ n ++ "(::mlir::DialectBytecodeReader &reader, " ++ t ++ " &value);"
        , "void write" ++ n ++ "(::mlir::DialectBytecodeWriter &writer, " ++ t ++ " value);", "" ]

||| The hand function an interface method's default calls, given the object
||| (an op, a type or an attribute) and the method's arguments. A default by
||| class calls a template a hand header declares, so nothing is printed
||| for it.
delegateDecls : InterfaceDef -> Lines
delegateDecls d = concatMap decl d.methods
  where
    self : List String
    self = case d.subject of
      OverOps => ["::mlir::Operation *self"]
      OverTypes => ["::mlir::Type self"]
      OverAttributes => ["::mlir::Attribute self"]
    decl : Method -> Lines
    decl m = case m.fallback of
      EveryImplementer => []
      DelegatesByClass _ => []
      Delegates fn =>
        let given = case m.binding of
                      PerObject => self
                      PerClass => []
        in [ "// The default of " ++ identText d.name ++ "::" ++ identText m.name ++ "."
           , codeText m.result ++ " " ++ identText fn ++ "("
             ++ joinWith ", " (given ++ map (\p => codeText p.type ++ " " ++ identText p.name) m.params) ++ ");", "" ]

||| The declarations of every hand hook the specification names: custom
||| directives, predicates, parameter codecs, property hooks and the
||| functions interface defaults call. Their definitions are hand C++; a
||| missing one is a link error.
export
hooksHeader : List Directive -> List Predicate -> List InterfaceDef -> List AnyTypeDef -> List AnyAttrDef
           -> List AnyOp -> Lines
hooksHeader ds ps is ts as ops =
  header "Hooks" ["\"mlir/Bytecode/BytecodeImplementation.h\"", "\"mlir/IR/OpImplementation.h\"", "\"llvm/ADT/Hashing.h\"", "<memory>", "<optional>"]
    (inNamespace "idr" (enumReader ++ concatMap directiveDecls ds ++ concatMap predicateDecl ps
                        ++ concatMap delegateDecls is ++ concatMap codecDecls (codecsOf ts as)
                        ++ concatMap propertyDecls (propertiesOf ops)))
  where
    enumReader : Lines
    enumReader =
      slashComment ["Reads an enum of the dialect written as its case's number, refusing a number that is no case."]
      ++ [ "template <typename E>"
         , "::mlir::LogicalResult readEnum(::mlir::DialectBytecodeReader &reader, E &result,"
         , "                               std::optional<E> (*symbolize)(uint32_t));", "" ]

------------------------------------------------------------------------------
-- The pipeline
------------------------------------------------------------------------------

||| One step of the pipeline as the C++ adds it: the stage it runs at, the
||| one it leaves, and the statement that adds it from the module's manager.
public export
record Step where
  constructor MkStep
  at : Stage
  after : Stage
  add : String
  why : Line

||| A manager's expression for a path of nests from the module's.
export
nestPath : List Anchor -> String
nestPath [] = "pm"
nestPath (a :: as) = nestPath as ++ ".nest<" ++ anchorClass a ++ ">()"

||| The expression that makes a pass: its generated constructor, or the
||| hand factory its maker calls, given `args`.
export
passConstructor : Pass -> List String -> String
passConstructor p args = case p.construction of
  Registered => "::idr::create" ++ passRecord p ++ "()"
  MadeBy fn _ => cppText fn ++ "(" ++ joinWith ", " args ++ ")"

||| Whether two atoms are one: their places in the row's order.
sameAtom : Atom -> Atom -> Bool
sameAtom x y = position atomClosed x == position atomClosed y

||| The atoms the passes of a pipeline add to rows, each once, in the row's
||| order: its own passes only, since a nest inside it is bracketed by its
||| own steps.
export
addedBy : Pipeline a s t -> List Atom
addedBy p = filter (\x => any (sameAtom x) (own p)) (forget atomClosed.every)
  where
    own : Pipeline b u v -> List Atom
    own Done = []
    own (Run q _ rest) = q.adds ++ own rest
    own (RunUpstream _ _ rest) = own rest
    own (Nest _ _ rest) = own rest

||| A row as a C++ constant: its atoms, each a case of the atoms' enum.
export
rowText : List Atom -> String
rowText atoms = "::idr::effects::Row{" ++ joinWith ", " (map (\x => "::idr::Atom::" ++ identText (atomClosed.describe x).name) atoms) ++ "}"

||| The steps of a pipeline that starts at `here`, under the nests that
||| lead to it (innermost first), with the stage it ends at. The stage is
||| carried as a value beside the pipeline, whose index the type checker
||| already held: each pass's record says where it leaves the program. A
||| nest whose passes add atoms to rows runs between the widening of every
||| row by them and the writing of every row after it.
export
stepsOf : (here : Stage) -> List Anchor -> Pipeline a s t -> (List Step, Stage)
stepsOf here _ Done = ([], here)
stepsOf here path (Run p why rest) =
  let next = leaves p.stages here
      (more, end) = stepsOf next path rest
  in (MkStep here next (nestPath path ++ ".addPass(" ++ passConstructor p [] ++ ");") why :: more, end)
stepsOf here path (RunUpstream u why rest) =
  let (more, end) = stepsOf here path rest
  in (MkStep here here (nestPath path ++ ".addPass(" ++ upstreamMake u ++ ");") why :: more, end)
stepsOf here path (Nest inner first rest) =
  let (inside, middle) = stepsOf here (inner :: path) first
      (after, end) = stepsOf middle path rest
  in (bracketed (addedBy first) inside middle ++ after, end)
  where
    bracketed : List Atom -> List Step -> Stage -> List Step
    bracketed [] steps _ = steps
    bracketed atoms steps done =
      MkStep here here (nestPath path ++ ".addPass(" ++ passConstructor widenRows [rowText atoms] ++ ");")
        "every row covers what the nest after it adds while its functions run"
      :: steps
      ++ [MkStep done done (nestPath path ++ ".addPass(" ++ passConstructor writeRows [] ++ ");")
            "every row exact again once the nest is done"]

------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------

||| An action's constant in C++: its tag's words in lower camel case,
||| `optimizeNode` for `idr-optimize-node`.
export
actionName : Action -> String
actionName a = case unpack (concat (map camel (forget a.tag))) of
  [] => ""
  (c :: cs) => pack ((if upper c then chr (ord c + 32) else c) :: cs)

||| The tag of every action a pass takes: a constant each, which the
||| action's class names, and the list a test draws the actions it skips
||| from.
export
actionsHeader : List Action -> Lines
actionsHeader as =
  header "Actions" ["<array>", "<string_view>"]
    (inNamespace "idr::actions"
      ( concatMap (\a => slashComment [lineText a.doc] ++ ["inline constexpr std::string_view " ++ actionName a ++ " = " ++ quoted (actionTag a) ++ ";"]) as
        ++ ["", "inline constexpr std::array<std::string_view, " ++ decimal (length as) ++ "> tags{{" ++ joinWith ", " (map actionName as) ++ "}};"] ))

export
stageCase : Stage -> String
stageCase s = "::idr::Stage::" ++ identText (stageClosed.describe s).name

||| The pipeline's steps as a table: each a function adding one pass, with
||| the stages it runs between, which the hand builder reads to build the
||| whole pipeline or a slice of it between two stages.
export
pipelineHeader : List Step -> Lines
pipelineHeader steps =
  let numbered = zip [0 .. length steps] steps
  in header "Pipeline" ["\"mlir/Pass/PassManager.h\"", "\"llvm/Support/CommandLine.h\"", "<array>"]
       (slashComment ["The stages a slice of the pipeline is named by, as the command line reads them."]
        ++ ["#define IDR_STAGE_OPTION_VALUES " ++ joinWith ", " (map stageValue (forget (enumDef stageClosed).cases)), ""]
        ++ inNamespace "idr::pipeline"
          ( [ "struct Step {"
            , "  ::idr::Stage at;"
            , "  ::idr::Stage after;"
            , "  void (*add)(::mlir::OpPassManager &pm);"
            , "};", "" ]
            ++ concatMap (\(k, st) => slashComment [lineText st.why]
                                      ++ ["inline void step" ++ decimal k ++ "(::mlir::OpPassManager &pm) { " ++ st.add ++ " }", ""]) numbered
            ++ ["inline constexpr std::array<Step, " ++ decimal (length steps) ++ "> steps{{"]
            ++ indent 4 (map (\(k, st) => "{" ++ stageCase st.at ++ ", " ++ stageCase st.after ++ ", &step" ++ decimal k ++ "},") numbered)
            ++ ["}};", ""]
            ++ slashComment ["Every upstream pass the pipeline runs, registered so a pipeline's text can name it."]
            ++ ["inline void registerUpstream() {"]
            ++ indent 2 (map (\u => upstreamRegister u ++ ";") upstreamPasses)
            ++ ["}"] ))
  where
    stageValue : Case -> String
    stageValue c = "clEnumValN(::idr::Stage::" ++ identText c.name ++ ", " ++ quoted (spellingText c) ++ ", " ++ quoted (lineText c.doc) ++ ")"
