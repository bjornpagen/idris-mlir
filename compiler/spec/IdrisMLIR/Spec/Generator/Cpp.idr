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

||| The C++ type of a column's element.
export
columnType : ColumnType -> String
columnType Signed64 = "std::int64_t"
columnType Unsigned8 = "std::uint8_t"
columnType Unsigned32 = "std::uint32_t"
columnType Unsigned64 = "std::uint64_t"
columnType TextColumn = "std::string_view"
columnType TruthColumn = "bool"
columnType (EnumColumn e) = "::idr::" ++ identText e.name
columnType (SetColumn e) = "::idr::EnumSet<::idr::" ++ identText e.name ++ ">"

||| A cell as a C++ constant.
export
cellText : Cell -> String
cellText (IntCell i) = integer i
cellText (TextCell t) = quoted t
cellText (TruthCell True) = "true"
cellText (TruthCell False) = "false"
cellText (CaseCell c) = "::idr::" ++ identText c.enum.name ++ "::" ++ identText c.name
cellText (SetCell e cs) =
  "::idr::EnumSet<::idr::" ++ identText e.name ++ ">{"
    ++ joinWith ", " (map (\c => "::idr::" ++ identText e.name ++ "::" ++ identText c) cs) ++ "}"

||| A plain enum of a header, dense from zero.
export
enumDecl : EnumDef -> Lines
enumDecl e =
  slashComment [lineText e.doc.summary]
  ++ ["enum class " ++ identText e.name ++ " : std::uint8_t {"]
  ++ indent 2 (concatMap (\c => slashComment [lineText c.doc] ++ [identText c.name ++ ","]) (forget e.cases))
  ++ ["};", ""]

||| `EnumTraits<E>`: its count and its cases' printed names, read by every
||| table over it.
export
enumTraits : EnumDef -> Lines
enumTraits e =
  let n = decimal (length (forget e.cases))
  in [ "template <>"
     , "struct EnumTraits<::idr::" ++ identText e.name ++ "> {"
     , "  static constexpr std::size_t count = " ++ n ++ ";"
     , "  static constexpr std::array<std::string_view, " ++ n ++ "> names{{"
       ++ joinWith ", " (map (quoted . spellingText) (forget e.cases)) ++ "}};"
     , "};", "" ]

||| One column of a table: an `EnumArray` indexed by the table's enum, its
||| values in the cases' order.
export
columnDecl : EnumDef -> (Ident, ColumnType, List Cell, Line) -> Lines
columnDecl e (name, type, cells, doc) =
  slashComment [lineText doc]
  ++ ["inline constexpr ::idr::EnumArray<::idr::" ++ identText e.name ++ ", " ++ columnType type ++ "> "
      ++ identText name ++ "{{"]
  ++ indent 4 (braced (map cellText cells))
  ++ ["}};", ""]

export
cppDecl : CppDecl -> Lines
cppDecl (EnumOf e) = enumDecl e
cppDecl (TableOf t) = concatMap (columnDecl t.enum) t.columns
cppDecl (Array1 name type cells doc) =
  slashComment [lineText doc]
  ++ ["inline constexpr std::array<" ++ columnType type ++ ", " ++ decimal (length cells) ++ "> " ++ identText name ++ "{{"]
  ++ indent 4 (braced (map cellText cells))
  ++ ["}};", ""]
cppDecl (Array2 name type rows doc) =
  let width = case rows of
                [] => 0
                (r :: _) => length r
  in slashComment [lineText doc]
     ++ ["inline constexpr std::array<std::array<" ++ columnType type ++ ", " ++ decimal width ++ ">, "
         ++ decimal (length rows) ++ "> " ++ identText name ++ "{{"]
     ++ indent 4 (map (\r => "{{" ++ joinWith ", " (map cellText r) ++ "}},") rows)
     ++ ["}};", ""]
cppDecl (Scalar name type cell doc) =
  slashComment [lineText doc] ++ ["inline constexpr " ++ columnType type ++ " " ++ identText name ++ " = " ++ cellText cell ++ ";", ""]

||| The enums a header declares, whose traits it prints after them.
export
declaredEnums : List CppDecl -> List EnumDef
declaredEnums [] = []
declaredEnums (EnumOf e :: ds) = e :: declaredEnums ds
declaredEnums (_ :: ds) = declaredEnums ds

||| A header's declarations other than its enums.
otherDecls : List CppDecl -> List CppDecl
otherDecls [] = []
otherDecls (EnumOf _ :: ds) = otherDecls ds
otherDecls (d :: ds) = d :: otherDecls ds

||| An area's header: its enums first, each with its traits, which every
||| table over it needs, then its tables, arrays and constants by namespace.
||| A header's enums are the dialect's, in `::idr`, as every reference to a
||| case spells them.
export
areaHeader : Header -> (Path, String)
areaHeader h =
  let stem = identText h.name
      enums = concatMap (\(_, ds) => declaredEnums ds) h.blocks
      declared = case enums of
                   [] => []
                   es => inNamespace "idr" (concatMap enumDecl es ++ concatMap enumTraits es)
      blocks = concatMap block h.blocks
  in ( generatedPath (stem ++ ".h.inc")
     , render (header stem ["\"idr/Support/Enum.h\"", "<array>", "<cstdint>", "<string_view>"]
                      (slashComment (lineText h.doc.summary :: proseLines h.doc.description) ++ [""] ++ declared ++ blocks)) )
  where
    generatedPath : String -> Path
    generatedPath f = "foreign" ::: ["idr", "include", "idr", "IR", "Generated", f]
    block : (CppName, List CppDecl) -> Lines
    block (ns, ds) = case otherDecls ds of
      [] => []
      rest => inNamespace (namespaceText ns) (concatMap cppDecl rest)

||| The traits of the dialect's ODS enums, which mlir-tblgen declares.
export
odsEnumTraits : List EnumDef -> Lines
odsEnumTraits es =
  header "EnumTraits" ["\"idr/Support/Enum.h\"", "<array>", "<cstddef>", "<string_view>"]
    (inNamespace "idr" (concatMap enumTraits es))

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
takesC TakesPointer = "void *"
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
givesC GivesPointer = "void *"
givesC GivesBool = "bool"

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
takesName TakesPointer = "Pointer"
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
givesName GivesPointer = "Pointer"
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

||| The C prototypes of an op's runtime functions: its operands by their
||| groups' names, its results through pointers where it gives several; one
||| per case where its meaning is one function per case.
export
prototypeOf : AnyOp -> Lines
prototypeOf (SomeOp op) = case (callOf op, callsByCase op) of
  (Just c, _) => ["// " ++ opName op, signature c (symbolText c.symbol)]
  (Nothing, Just (c, symbols)) => ("// " ++ opName op) :: map (signature c) symbols
  (Nothing, Nothing) => []
  where
    gives : Gives o -> List Result -> (String, List String)
    gives NoResult _ = ("void", [])
    gives NeverReturns _ = ("IDRIS_RT_NORETURN void", [])
    gives (Returns k) _ = (givesC k, [])
    gives (ThroughPointers ks) rs = ("void", zipWith (\k, x => declarator (givesC k ++ " *") (identText x.name)) (toList ks) rs)
    signature : RuntimeCall i o -> String -> String
    signature c name =
      let params = zipWith (\k, x => declarator (takesC k) (identText x.name)) (toList c.takes) (toList op.ins)
          (result, outs) = gives c.gives (toList op.outs)
      in result ++ " " ++ name ++ "(" ++ cParams (params ++ outs) ++ ");"

export
helperPrototype : RuntimeHelper -> Lines
helperPrototype h =
  let result = case h.gives of
                 HelperNothing => "void"
                 HelperNeverReturns => "IDRIS_RT_NORETURN void"
                 HelperReturns k => givesC k
      params = map (\(k, n) => declarator (takesC k) (identText n)) h.params
  in ["// " ++ lineText h.doc, result ++ " " ++ symbolText h.symbol ++ "(" ++ cParams params ++ ");"]

||| The runtime's prototypes of every function an op or the lowering calls,
||| which the runtime includes, so a definition that disagrees does not
||| compile.
export
runtimeOps : List AnyOp -> List RuntimeHelper -> Lines
runtimeOps ops helpers =
  banner slashComment
  ++ ["#ifndef IDRIS_RT_OPS_H", "#define IDRIS_RT_OPS_H", "", "#ifdef __cplusplus", "extern \"C\" {", "#endif", ""]
  ++ concatMap prototypeOf ops
  ++ [""]
  ++ concatMap helperPrototype helpers
  ++ ["", "#ifdef __cplusplus", "}", "#endif", "", "#endif // IDRIS_RT_OPS_H"]

export
||| How a runtime function gives an op's results, as the table spells it.
resultKindOf : Gives o -> String
resultKindOf NoResult = "ResultKind::Void"
resultKindOf NeverReturns = "ResultKind::NoReturn"
resultKindOf (Returns k) = "ResultKind::" ++ givesName k
resultKindOf (ThroughPointers _) = "ResultKind::Void"

abiRow : AnyOp -> Lines
abiRow (SomeOp op) = case (callOf op, callsByCase op) of
  (Just c, _) =>
    let operands = map (\k => "OperandKind::" ++ takesName k) (toList c.takes)
    in [ "template <>", "struct Abi<" ++ opQualifiedClass op ++ "> {"
       , "  static constexpr std::array<OperandKind, " ++ decimal (length operands) ++ "> operands{{" ++ joinWith ", " operands ++ "}};"
       , "  static constexpr Function entry{" ++ quoted (symbolText c.symbol) ++ ", operands, " ++ resultKindOf c.gives ++ "};"
       , "  static constexpr auto *function = &" ++ symbolText c.symbol ++ ";"
       , "};", "" ]
  (Nothing, Just (c, symbols)) =>
    let operands = map (\k => "OperandKind::" ++ takesName k) (toList c.takes)
    in [ "template <>", "struct AbiByCase<" ++ opQualifiedClass op ++ "> {"
       , "  static constexpr std::array<OperandKind, " ++ decimal (length operands) ++ "> operands{{" ++ joinWith ", " operands ++ "}};"
       , "  // One entry per case of the op's enum, in the cases' order."
       , "  static constexpr std::array<Function, " ++ decimal (length symbols) ++ "> entries{{"
         ++ joinWith ", " (map (\sym => "Function{" ++ quoted sym ++ ", operands, " ++ resultKindOf c.gives ++ "}") symbols) ++ "}};"
       , "};", "" ]
  (Nothing, Nothing) => []

export
helperRow : RuntimeHelper -> Lines
helperRow h =
  let operands = map (\(k, _) => "OperandKind::" ++ takesName k) h.params
      result = case h.gives of
                 HelperNothing => "ResultKind::Void"
                 HelperNeverReturns => "ResultKind::NoReturn"
                 HelperReturns k => "ResultKind::" ++ givesName k
  in [ "inline constexpr std::array<OperandKind, " ++ decimal (length operands) ++ "> " ++ identText h.name ++ "Operands{{" ++ joinWith ", " operands ++ "}};"
     , "inline constexpr Function " ++ identText h.name ++ "{" ++ quoted (symbolText h.symbol) ++ ", " ++ identText h.name ++ "Operands, " ++ result ++ "};" ]

||| Each op's row of the runtime's ABI, `Abi<Op>`, and each helper the
||| lowering calls, read by the lowering and the one runtime fold.
export
runtimeAbi : List AnyOp -> List RuntimeHelper -> Lines
runtimeAbi ops helpers =
  header "RuntimeAbi" ["\"idris_rt.h\"", "<array>", "<span>", "<string_view>"]
    (inNamespace "idr::runtime"
      ( [ "enum class OperandKind : unsigned char { Int32, Int64, Double, Signed, Unsigned, Str, Big, Buffer, Pointer, Bool };"
        , "enum class ResultKind : unsigned char { Void, NoReturn, Int32, Int64, Double, Wrapped, Order, Str, Big, Pointer, Bool };"
        , ""
        , "struct Function {"
        , "  std::string_view symbol;"
        , "  std::span<const OperandKind> operands;"
        , "  ResultKind result;"
        , "};"
        , ""
        , "template <class OpT>"
        , "struct Abi;"
        , ""
        , "// An op whose meaning is one runtime function per case of its enum."
        , "template <class OpT>"
        , "struct AbiByCase;"
        , "" ]
        ++ concatMap abiRow ops
        ++ ["namespace helper {"] ++ concatMap helperRow helpers ++ ["} // namespace helper"] ))

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
    rulesOf 2 Associative = [MkFlatRule c 3 [two, two, FVar 0, FVar 1, FVar 2] [two, FVar 0, two, FVar 1, FVar 2] [] Equal]
    rulesOf 2 (Identity k) = [MkFlatRule c 1 [two, FVar 0, FLit k] [FVar 0] [] Simplify]
    rulesOf 2 (Annihilator k) = [MkFlatRule c 1 [two, FVar 0, FLit k] [FLit k] [] Simplify]
    rulesOf 2 Idempotent = [MkFlatRule c 1 [two, FVar 0, FVar 0] [FVar 0] [] Simplify]
    rulesOf 1 Involution = [MkFlatRule c 1 [FNode c 0 1, FNode c 0 1, FVar 0] [FVar 0] [] Simplify]
    rulesOf _ _ = []

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

||| The e-graph's rules as the engine reads them: the patterns in preorder,
||| the conditions, the rules grouped by root kind with each kind's offset,
||| the kinds, the skeleton rules, and the budget, all compile-time
||| constants, so nothing is built per function.
export
rewritesHeader : List AnyRewrite -> List AnyOp -> List SkeletonRule -> Lines
rewritesHeader rws ops skeleton =
  let rules = map fromRewrite rws ++ concatMap lawRules ops
      kinds = kindsOf rules
      groups = byKind kinds rules
      laid = layRules kinds (concat groups)
  in header "Rewrites" ["\"idr/Transforms/EGraph.h\"", "\"idr/IR/IdrAdmittedClasses.h.inc\"", "<cstdint>"]
       (inNamespace "idr::egraph::generated"
         ( ["using Kinds = table::OpList<" ++ joinWith ", " kinds ++ ">;", ""]
           ++ ["inline constexpr table::PatternNode patterns[] = {"] ++ indent 2 (braced laid.patterns) ++ ["};", ""]
           ++ ["inline constexpr table::Condition conditions[] = {"] ++ indent 2 (braced laid.conditions) ++ ["};", ""]
           ++ ["inline constexpr table::Rule rules[] = {"] ++ indent 2 (braced laid.rules) ++ ["};", ""]
           ++ ["inline constexpr std::uint32_t rulesOfKind[] = {" ++ joinWith ", " (map decimal (offsets groups)) ++ "};", ""]
           ++ ["using SkeletonRules = table::RuleList<" ++ joinWith ", " (map (\s => "::idr::egraph::" ++ identText s.name) skeleton) ++ ">;", ""]
           ++ slashComment ["Nodes per op of a function's e-graph: its arena, known before its search starts, is this times its ops."]
           ++ ["inline constexpr std::uint32_t nodesPerOp = 64;"] ))

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

||| Every hand parameter codec the types name: a parser and a printer of the
||| parameter's C++ value.
export
codecsOf : List AnyTypeDef -> List AnyAttrDef -> List (Code, Directive)
codecsOf ts as = concatMap fromType ts ++ concatMap fromAttr as
  where
    hand : List Parameter -> List (Code, Directive)
    hand [] = []
    hand (x :: xs) = case x.kind of
      HandValue c d => (c, d) :: hand xs
      _ => hand xs
    fromType : AnyTypeDef -> List (Code, Directive)
    fromType (SomeType t) = hand (toList t.params)
    fromAttr : AnyAttrDef -> List (Code, Directive)
    fromAttr (SomeAttr a) = hand (toList a.params)

export
codecDecls : (Code, Directive) -> Lines
codecDecls (c, d) =
  [ "::mlir::FailureOr<" ++ codeText c ++ "> parse" ++ identText d.name ++ "(::mlir::AsmParser &parser);"
  , "void print" ++ identText d.name ++ "(::mlir::AsmPrinter &printer, " ++ codeText c ++ " value);"
  , "::mlir::LogicalResult read" ++ identText d.name ++ "(::mlir::DialectBytecodeReader &reader, " ++ codeText c ++ " &value);"
  , "void write" ++ identText d.name ++ "(::mlir::DialectBytecodeWriter &writer, " ++ codeText c ++ " value);", "" ]

||| The hand function an interface method's default calls, given the object
||| (an op, a type or an attribute) and the method's arguments.
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
      Delegates fn =>
        let given = case m.binding of
                      PerObject => self
                      PerClass => []
        in [ "// The default of " ++ identText d.name ++ "::" ++ identText m.name ++ "."
           , codeText m.result ++ " " ++ identText fn ++ "("
             ++ joinWith ", " (given ++ map (\p => codeText p.type ++ " " ++ identText p.name) m.params) ++ ");", "" ]

||| The declarations of every hand hook the specification names: custom
||| directives, predicates, parameter codecs and the functions interface
||| defaults call. Their definitions are hand C++; a missing one is a link
||| error.
export
hooksHeader : List Directive -> List Predicate -> List InterfaceDef -> List AnyTypeDef -> List AnyAttrDef -> Lines
hooksHeader ds ps is ts as =
  header "Hooks" ["\"mlir/Bytecode/BytecodeImplementation.h\"", "\"mlir/IR/OpImplementation.h\"", "<memory>", "<optional>"]
    (inNamespace "idr" (enumReader ++ concatMap directiveDecls ds ++ concatMap predicateDecl ps
                        ++ concatMap delegateDecls is ++ concatMap codecDecls (codecsOf ts as)))
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

export
passConstructor : Pass -> String
passConstructor p = "::idr::create" ++ passRecord p ++ "()"

||| The steps of a pipeline that starts at `here`, under the nests that
||| lead to it (innermost first), with the stage it ends at. The stage is
||| carried as a value beside the pipeline, whose index the type checker
||| already held: each pass's record says where it leaves the program.
export
stepsOf : (here : Stage) -> List Anchor -> Pipeline a s t -> (List Step, Stage)
stepsOf here _ Done = ([], here)
stepsOf here path (Run p why rest) =
  let next = leaves p.stages here
      (more, end) = stepsOf next path rest
  in (MkStep here next (nestPath path ++ ".addPass(" ++ passConstructor p ++ ");") why :: more, end)
stepsOf here path (RunUpstream u why rest) =
  let (more, end) = stepsOf here path rest
  in (MkStep here here (nestPath path ++ ".addPass(" ++ upstreamMake u ++ ");") why :: more, end)
stepsOf here path (Nest inner first rest) =
  let (inside, middle) = stepsOf here (inner :: path) first
      (after, end) = stepsOf middle path rest
  in (inside ++ after, end)

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
            ++ ["}};"] ))
  where
    stageValue : Case -> String
    stageValue c = "clEnumValN(::idr::Stage::" ++ identText c.name ++ ", " ++ quoted (spellingText c) ++ ", " ++ quoted (lineText c.doc) ++ ")"
