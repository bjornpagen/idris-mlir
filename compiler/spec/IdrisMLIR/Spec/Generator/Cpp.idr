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
import IdrisMLIR.Spec.Generator.Wire
import IdrisMLIR.Spec.Ops.Checks
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Pipeline.Pass
import IdrisMLIR.Spec.Pipeline.Pipeline
import IdrisMLIR.Spec.Runtime.Helpers

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

||| The name of a block's namespace without its leading `::`.
export
namespaceText : Namespace -> String
namespaceText DialectNamespace = "idr"
namespaceText (Nested path) = joinWith "::" ("idr" :: map identText (forget path))

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

-- Named qualified wherever it is used: the rules' `Scope`, where a rule is
-- decided, is in scope here too, and both are types.
||| An enum's name from the global namespace, as the block's scope has it.
export
enumName : Cpp.Scope -> EnumDef -> String
enumName sc e = (if elem e.name sc.declared then "::" ++ sc.space else "::idr") ++ "::" ++ identText e.name

||| The C++ type of a column's element.
export
columnType : Cpp.Scope -> ColumnType -> String
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
cellText : Cpp.Scope -> Cell -> String
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
columnDecl : Cpp.Scope -> EnumDef -> (Ident, ColumnType, List Cell, Line) -> Lines
columnDecl sc e (name, type, cells, doc) =
  slashComment [lineText doc]
  ++ ["inline constexpr ::idr::EnumArray<" ++ enumName sc e ++ ", " ++ columnType sc type ++ "> "
      ++ identText name ++ "{{"]
  ++ indent 4 (braced (map (cellText sc) cells))
  ++ ["}};", ""]

||| A declaration of a block other than an enum.
export
cppDecl : Cpp.Scope -> CppDecl -> Lines
cppDecl _ (EnumOf _) = []
cppDecl sc (TableOf t) = concatMap (columnDecl sc t.enum) t.columns
cppDecl sc (Array1 name type cells doc) =
  slashComment [lineText doc]
  ++ ["inline constexpr std::array<" ++ columnType sc type ++ ", " ++ decimal (length cells) ++ "> " ++ identText name ++ "{{"]
  ++ indent 4 (braced (map (cellText sc) cells))
  ++ ["}};", ""]
cppDecl sc (Array2 name type rows doc) =
  let width : Nat = case rows of
                      [] => 0
                      (r :: _) => length r
  in slashComment [lineText doc]
     ++ ["inline constexpr std::array<std::array<" ++ columnType sc type ++ ", " ++ decimal width ++ ">, "
         ++ decimal (length rows) ++ "> " ++ identText name ++ "{{"]
     ++ indent 4 (map (\r => "{{" ++ joinWith ", " (map (cellText sc) r) ++ "}},") rows)
     ++ ["}};", ""]
cppDecl sc (Scalar name type cell doc) =
  slashComment [lineText doc] ++ ["inline constexpr " ++ columnType sc type ++ " " ++ identText name ++ " = " ++ cellText sc cell ++ ";", ""]
cppDecl _ (SumOf e name members doc) =
  let alternatives = zip (forget e.cases) members
  in concatMap struct alternatives
     ++ slashComment [lineText doc]
     ++ ["using " ++ identText name ++ " = std::variant<" ++ joinWith ", " (map (identText . (.name) . fst) alternatives) ++ ">;", ""]
  where
    struct : (Case, List WireField) -> Lines
    struct (c, fs) =
      slashComment [lineText c.doc]
      ++ ["struct " ++ identText c.name ++ " {"]
      ++ indent 2 (map (\f => wireCpp (fieldWire f) ++ " " ++ identText (fieldName f) ++ ";") fs
                   ++ ["bool operator==(const " ++ identText c.name ++ " &) const = default;"])
      ++ ["};", ""]

||| The enums a block declares, each once, in order: every enum it names
||| by itself; and, in a namespace of its own, the enum of every table, so
||| a reader that includes the header alone (the runtime) needs nothing of
||| the dialect's. In the dialect's namespace a table's enum is the
||| dialect's or one the block names by itself.
export
blockEnums : Namespace -> List CppDecl -> List EnumDef
blockEnums ns ds = go [] ds
  where
    owns : List EnumDef -> EnumDef -> Bool
    owns seen e = any (\x => x.name == e.name) seen
    tableEnum : List EnumDef -> EnumDef -> List EnumDef
    tableEnum seen e = case ns of
      DialectNamespace => seen
      Nested _ => if owns seen e then seen else e :: seen
    go : List EnumDef -> List CppDecl -> List EnumDef
    go seen [] = reverse seen
    go seen (EnumOf e :: rest) = go (if owns seen e then seen else e :: seen) rest
    go seen (TableOf t :: rest) = go (tableEnum seen t.enum) rest
    go seen (SumOf e _ _ _ :: rest) = go (if owns seen e then seen else e :: seen) rest
    go seen (_ :: rest) = go seen rest

||| One block of an area's header: its enums in its namespace, their traits
||| in the dialect's (the template's), then its tables, arrays, constants
||| and sums, which name the enums by the block's scope.
export
headerBlock : (Namespace, List CppDecl) -> Lines
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

||| The standard header a declaration needs beyond every area header's: a
||| sum's `std::variant`.
declIncludes : CppDecl -> List String
declIncludes (SumOf _ _ _ _) = ["<variant>"]
declIncludes _ = []

||| An area's header, block by block, printed under
||| `foreign/idr/include/idr/IR/Generated/<name>.h.inc`.
export
areaHeader : Header -> (Path, String)
areaHeader h =
  let stem = identText h.name
      needed = concatMap (\(_, ds) => concatMap declIncludes ds) h.blocks
  in ( "foreign" ::: ["idr", "include", "idr", "IR", "Generated", stem ++ ".h.inc"]
     , render (header stem (["\"idr/Support/Enum.h\"", "<array>", "<cstddef>", "<cstdint>", "<string_view>"]
                            ++ nub needed)
                      (slashComment (lineText h.doc.summary :: proseLines h.doc.description) ++ [""]
                       ++ concatMap headerBlock h.blocks)) )

||| The headers of the dialects each pass's generated definition names,
||| under the macro that selects it, `GEN_PASS_DEF_<PASS>`: the anchor's,
||| whose op its base runs on, and those its `getDependentDialects` loads.
||| A unit defines the macro and includes this at file scope, before it
||| includes the definitions. No guard and no `#undef`, since the
||| definitions read the macro after it.
export
passDialectsHeader : List Pass -> Lines
passDialectsHeader ps = banner slashComment ++ concatMap section ps
  where
    section : Pass -> Lines
    section p = case definitionDialects p of
      [] => []
      ls =>
        let macro = "GEN_PASS_DEF_" ++ pack (map toUpper (unpack (passRecord p)))
        in ["", "#ifdef " ++ macro]
           ++ map (\l => "#include " ++ quoted (loadsHeader l)) ls
           ++ ["#endif // " ++ macro]

||| The hand storage classes, `::idr::detail::<Class>Storage`, declared
||| before the generated classes that name them as their storage: ODS
||| declares no class it does not define. And every type class, declared
||| before the attributes, whose parameters and members may name a type
||| that mlir-tblgen declares only after them.
export
storagesHeader : List AnyTypeDef -> List AnyAttrDef -> Lines
storagesHeader ts as =
  header "Storages" []
    (inNamespace "idr::detail"
       (map (\c => "struct " ++ c ++ "Storage;") (concatMap typeStorage ts ++ concatMap attrStorage as))
     ++ [""]
     ++ inNamespace "idr" (map (\(SomeType t) => "class " ++ typeClass t ++ ";") ts))
  where
    typeStorage : AnyTypeDef -> List String
    typeStorage (SomeType t) = case t.storage of
      HandStorage => [typeClass t]
      GeneratedStorage => []
    attrStorage : AnyAttrDef -> List String
    attrStorage (SomeAttr a) = case a.storage of
      HandStorage => [attrClass a]
      GeneratedStorage => []

||| The traits of the dialect's ODS enums, which mlir-tblgen declares.
export
odsEnumTraits : List EnumDef -> Lines
odsEnumTraits es =
  header "EnumTraits" ["\"idr/Support/Enum.h\"", "<array>", "<cstddef>", "<string_view>"]
    (inNamespace "idr" (concatMap (\e => enumTraits ("::idr::" ++ identText e.name) e) es))

------------------------------------------------------------------------------
-- Upstream classes
------------------------------------------------------------------------------

||| Each upstream dialect that admits an op, in the dialects' order, has the
||| classes of its admitted ops aliased by one run of the backend over its
||| admitted record file (`IdrAdmitted<Name>Classes.h.inc`), one run per
||| file since two dialects' records may share a name; this header includes
||| each after the header that declares the classes it aliases, so a reader
||| of an admitted op's class includes this alone.
export
admittedClassesHeader : List Dialect -> Lines
admittedClassesHeader ds =
  header "AdmittedClasses" (concatMap includes ds) []
  where
    includes : Dialect -> List String
    includes d = [ quoted (cppHeader d)
                 , quoted ("idr/IR/IdrAdmitted" ++ identText (dialectName d) ++ "Classes.h.inc") ]

||| The upstream dialects the frontend writes an op of, as their C++ classes:
||| one list type, which the driver registers and tells a module's ops by,
||| so no reader names one by its namespace or keeps a list of its own; each
||| class is held to the namespace the specification gives its dialect when
||| the compiler is built.
export
writtenDialectsHeader : List Dialect -> Lines
writtenDialectsHeader ds =
  header "WrittenDialects"
    (["\"mlir/IR/Dialect.h\""] ++ map (quoted . cppDialectHeader) ds ++ ["<concepts>", "<string_view>"])
    (inNamespace "idr"
      ( slashComment ["A list of dialects, by their classes."]
        ++ ["template <std::derived_from<::mlir::Dialect>... Dialects>", "struct DialectList {};", ""]
        ++ slashComment ["The upstream dialects the frontend writes an op of, in the specification's order."]
        ++ ["using WrittenDialects = DialectList<" ++ joinWith ", " (map cppDialect ds) ++ ">;", ""]
        ++ slashComment ["Each class is the dialect of the namespace the specification gives it."]
        ++ map namespaceHeld ds ))
  where
    namespaceHeld : Dialect -> String
    namespaceHeld d =
      "static_assert(std::string_view(" ++ cppDialect d ++ "::getDialectNamespace()) == "
        ++ quoted (wordText (namespaceWord d)) ++ ");"

------------------------------------------------------------------------------
-- Specializations: families' constants, word ops
------------------------------------------------------------------------------

||| The namespace an enum of the specification is declared in: the block of
||| the header that declares it, or the dialect's, where ODS declares the
||| dialect's enums.
export
enumHome : List Header -> EnumDef -> String
enumHome hs e = case List.find declares (concatMap (.blocks) hs) of
  Just (ns, _) => namespaceText ns
  Nothing => namespaceText DialectNamespace
  where
    declares : (Namespace, List CppDecl) -> Bool
    declares (ns, ds) = any (\x => x.name == e.name) (blockEnums ns ds)

export
constantMember : List Header -> (Ident, Constant) -> String
constantMember hs (n, EnumConstant c) =
  let enum = "::" ++ enumHome hs c.enum ++ "::" ++ identText c.enum.name
  in "static constexpr " ++ enum ++ " " ++ identText n ++ " = " ++ enum ++ "::" ++ identText c.name ++ ";"
constantMember _ (n, IntConstant i) = "static constexpr std::int64_t " ++ identText n ++ " = " ++ integer i ++ ";"
constantMember _ (n, UpstreamClass a) = "using " ++ identText n ++ " = " ++ admittedAlias a ++ ";"
constantMember _ (n, NoClass) = "using " ++ identText n ++ " = void;"
constantMember _ (n, HelperConstant h) =
  "static constexpr const ::idr::runtime::Function &" ++ identText n ++ " = ::idr::runtime::helper::" ++ identText h.name ++ ";"
constantMember _ (n, OpEntry m) =
  "static constexpr const ::idr::runtime::Function &" ++ identText n ++ " = ::idr::runtime::Abi<::idr::" ++ opRefClass m ++ ">::entry;"

||| A declaration a template's constant names beyond the dialect's own
||| classes and enums, which the template's includer declares first: an
||| admitted op's class, a runtime function's row, or a fixed-width integer.
data Named = AdmittedClass | RuntimeRow | FixedWidth

Eq Named where
  AdmittedClass == AdmittedClass = True
  RuntimeRow == RuntimeRow = True
  FixedWidth == FixedWidth = True
  _ == _ = False

||| What a constant names: an enum's case names one of the dialect's own
||| enums, and no class names nothing.
namedBy : Constant -> List Named
namedBy (EnumConstant _) = []
namedBy (IntConstant _) = [FixedWidth]
namedBy (UpstreamClass _) = [AdmittedClass]
namedBy NoClass = []
namedBy (HelperConstant _) = [RuntimeRow]
namedBy (OpEntry _) = [RuntimeRow]

||| The header that declares what is named.
namedHeader : Named -> String
namedHeader AdmittedClass = "\"idr/IR/Generated/AdmittedClasses.h.inc\""
namedHeader RuntimeRow = "\"idr/IR/Generated/RuntimeAbi.h.inc\""
namedHeader FixedWidth = "<cstdint>"

||| The headers a template's constants need, each once, ours before the
||| standard library's, and none they do not.
headersOf : List (Ident, Constant) -> List String
headersOf cs =
  let named = concatMap (namedBy . snd) cs
  in map namedHeader (filter (\n => elem n named) [AdmittedClass, RuntimeRow, FixedWidth])

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
specializationHeader : List Header -> Ident -> List AnyOp -> Lines
specializationHeader hs t ops =
  let members = membersOf t ops
      macro = "GET_" ++ pack (map up (unpack (snakeOf (identText t)))) ++ "_LIST"
  in banner slashComment
     ++ ["#ifdef " ++ macro, "#undef " ++ macro, ""]
     ++ zipWith (++) (map fst members) (replicate (pred (length members)) "," ++ [""])
     ++ ["", "#else"]
     ++ header (identText t) (headersOf (concatMap snd members))
          (inNamespace "idr"
             ( ["template <class OpT>", "struct " ++ identText t ++ ";", ""]
               ++ concatMap (\(cls, cs) => ["template <>", "struct " ++ identText t ++ "<" ++ cls ++ "> {"]
                                          ++ indent 2 (map (constantMember hs) cs) ++ ["};", ""]) members ))
     ++ ["#endif"]
  where
    up : Char -> Char
    up c = if lower c then chr (ord c - 32) else c

------------------------------------------------------------------------------
-- Inline meanings
------------------------------------------------------------------------------

||| Every inline meaning an op of the dialect has, one per op that has one,
||| in the ops' order, a guard's condition among them, each named here,
||| where it is printed: the function objects of the numeric template, as a
||| list of types a test folds over, so a meaning an op gains is one it
||| checks.
export
inlineMeaningsHeader : List AnyOp -> Lines
inlineMeaningsHeader ops =
  header "InlineMeanings" ["<tuple>"]
    (inNamespace "idr::numeric"
      ( slashComment ["Every inline meaning of the dialect's ops, one per op that has one."]
        ++ ["using Meanings = std::tuple<" ++ joinWith ", " (concatMap meaningOf ops) ++ ">;"] ))
  where
    numeric : Ident -> String
    numeric f = "::idr::numeric::" ++ identText f
    meaningOf : AnyOp -> List String
    meaningOf (SomeOp op) = case op.meaning of
      Inline m => [numeric (inlineName m)]
      InlineCondition c => [numeric (conditionName c)]
      _ => []

------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------

||| A guard as its op's class, which its kind gives, and the positions of
||| the groups it is given.
export
guardText : Guard (Fin i) -> String
guardText g = "::idr::Guard<" ++ opQualifiedClass (guardOpOf g.check) ++ ", " ++ joinWith ", " (map (decimal . finToNat) (toList g.given)) ++ ">"

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
takesC TakesUInt8 = "uint8_t"
takesC TakesDouble = "double"
takesC TakesSigned = "int64_t"
takesC TakesUnsigned = "uint64_t"
takesC TakesStr = "const idris_rt_str *"
takesC TakesBig = "idris_rt_big"
takesC TakesBuffer = "idris_rt_array *"
takesC (TakesPointerTo c) = codeText c ++ " *"

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
takesName TakesUInt8 = "UInt8"
takesName TakesDouble = "Double"
takesName TakesSigned = "Signed"
takesName TakesUnsigned = "Unsigned"
takesName TakesStr = "Str"
takesName TakesBig = "Big"
takesName TakesBuffer = "Buffer"
takesName (TakesPointerTo _) = "Pointer"

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
declarator type name = if isSuffixOf ['*'] (unpack type) then type ++ name else type ++ " " ++ name

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
||| it returns, and its comment.
public export
record CFunction where
  constructor MkCFunction
  cSymbol : String
  cTakes : List (OperandKind, String)
  cReturns : HelperGives
  cComment : String

||| Every C function an op names as its meaning: its operands by their
||| groups' names; one per case where its meaning is one function per case.
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
      NoResult => MkCFunction sym (params c) HelperNothing (opName op)
      NeverReturns => MkCFunction sym (params c) HelperNeverReturns (opName op)
      Returns k => MkCFunction sym (params c) (HelperReturns k) (opName op)

||| A helper the lowering calls by itself, as a C function.
export
helperFunction : RuntimeHelper -> CFunction
helperFunction h = MkCFunction (symbolText h.symbol) (map (\(k, n) => (k, identText n)) h.params) h.gives (lineText h.doc)

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

export
abiRow : AnyOp -> Lines
abiRow (SomeOp op) = case (functionsOf (SomeOp op), callsByCase op) of
  ([f], Nothing) =>
    [ "template <>", "struct Abi<" ++ opQualifiedClass op ++ "> {"
    , "  static constexpr std::array<OperandKind, " ++ decimal (length f.cTakes) ++ "> operands" ++ arrayInit (operandKinds f) ++ ";"
    , "  static constexpr Function entry{" ++ quoted f.cSymbol ++ ", operands, " ++ resultKindOf f.cReturns ++ "};"
    , "  static constexpr auto *function = &" ++ f.cSymbol ++ ";"
    , "};", "" ]
  (f :: fs, Just _) =>
    [ "template <>", "struct AbiByCase<" ++ opQualifiedClass op ++ "> {"
    , "  static constexpr std::array<OperandKind, " ++ decimal (length f.cTakes) ++ "> operands" ++ arrayInit (operandKinds f) ++ ";"
    , "  // One entry per case of the op's enum, in the cases' order."
    , "  static constexpr std::array<Function, " ++ decimal (length (f :: fs)) ++ "> entries{{"
      ++ joinWith ", " (map (\g => "Function{" ++ quoted g.cSymbol ++ ", operands, " ++ resultKindOf g.cReturns ++ "}") (f :: fs)) ++ "}};"
    , "};", "" ]
  _ => []

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
     , "inline constexpr Function " ++ identText h.name ++ "{" ++ quoted f.cSymbol ++ ", " ++ identText h.name ++ "Operands, " ++ resultKindOf f.cReturns ++ "};" ]

||| The entries that count a word of each counted kind, one table per
||| count, printed from `entry`, each kind's entry at the kind's place in
||| `words`, the order the kinds of a component's word list the counted
||| kinds in: what the lowering counts a word by.
countingEntries : Lines
countingEntries =
  slashComment [ "The entries that count one more reference, and one less, to a word of each counted"
               , "kind, each at its kind's place among the counted kinds." ]
  ++ [table "increments" Helpers.Increment, table "decrements" Helpers.Decrement, ""]
  where
    table : String -> Count -> String
    table name c =
      "inline constexpr std::array<const Function *, " ++ decimal (length Helpers.words) ++ "> " ++ name
      ++ arrayInit (map (\w => "&helper::" ++ identText (fst (Helpers.entry c w))) Helpers.words) ++ ";"

||| Each op's row of the runtime's ABI, `Abi<Op>`, each helper the lowering
||| calls, the counting entries of each kind of word, and every function
||| once in `functions`, which the lowering declares: read by the lowering
||| and the one runtime fold.
export
runtimeAbi : List AnyOp -> List RuntimeHelper -> Lines
runtimeAbi ops helpers =
  let named = concatMap entriesOf ops ++ map (\h => (symbolText h.symbol, "&helper::" ++ identText h.name)) helpers
      every = distinct [] named
  in header "RuntimeAbi" ["\"idris_rt.h\"", "<array>", "<span>", "<string_view>"]
       (inNamespace "idr::runtime"
         ( [ "enum class OperandKind : unsigned char { Int32, Int64, UInt8, Double, Signed, Unsigned, Str, Big, Buffer, Pointer };"
           , "enum class ResultKind : unsigned char { Void, NoReturn, Int32, Int64, Double, Wrapped, Order, Str, Big, Pointer, Bool };"
           , "" ]
           ++ slashComment [ "A runtime function as the lowering calls it: its symbol, how it takes each operand,"
                           , "and what it returns." ]
           ++ [ "struct Function {"
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
           ++ ["namespace helper {"] ++ concatMap helperRow helpers ++ ["} // namespace helper", ""]
           ++ countingEntries
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

||| A typed rule as the table names it: its class over what it reads, one
||| group or an operand group and a result group.
export
ruleType : OdsRule i o -> String
ruleType r = "::idr::effects::" ++ identText r.rule ++ "<" ++ readsText r.reads ++ ">"
  where
    subjectText' : Subject i o -> String
    subjectText' OfOp = "::idr::effects::OnOp"
    subjectText' (OfOperand k) = "::idr::effects::OnOperand<" ++ decimal (finToNat k) ++ ">"
    subjectText' (OfResult k) = "::idr::effects::OnResult<" ++ decimal (finToNat k) ++ ">"
    readsText : RuleReads i o -> String
    readsText (ReadsOne s) = subjectText' s
    readsText (ReadsPair g h) = subjectText' (OfOperand g) ++ ", " ++ subjectText' (OfResult h)

||| A pair rule over a group that may hold other than one value, which the
||| generator refuses: the C++ pairs each operand with the result at its
||| position, so a group of any number, or of none, has no partner to read.
||| Each is the op's name and the rule's.
export
unpairedRules : List AnyOp -> List (String, Ident)
unpairedRules ops = concatMap unpaired ops
  where
    refused : Op i o a r -> OdsRule i o -> List (String, Ident)
    refused op r = case r.reads of
      ReadsOne _ => []
      ReadsPair g h => case ((index g op.ins).arity, (index h op.outs).arity) of
        (Single, Single) => []
        _ => [(opName op, r.rule)]
    unpaired : AnyOp -> List (String, Ident)
    unpaired (SomeOp op) = case ods op.effects of
      EveryEffect => []
      Declares _ rules _ => concatMap (refused op) rules

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

||| Where a kind's node gets its interval when a rule built it and no op
||| stands for it: the range function upstream has for an admitted op, an
||| op of ours's inline meaning over intervals, or nowhere.
public export
data RangeSource = ByUpstream RangeFunction | ByMeaning InlineMeaning | NoRange

||| The range source an op of ours's meaning gives: only an inline meaning
||| of values computes over intervals. A condition is a truth, and every
||| other meaning is the runtime's or hand C++, which needs an op to ask.
rangeOfMeaning : Meaning i o -> RangeSource
rangeOfMeaning (Inline m) = ByMeaning m
rangeOfMeaning (InlineCondition _) = NoRange
rangeOfMeaning (CallsRuntime _) = NoRange
rangeOfMeaning (CallsRuntimeByCase _ _) = NoRange
rangeOfMeaning (ComputedByRuntime _) = NoRange
rangeOfMeaning HandFolder = NoRange
rangeOfMeaning NoFold = NoRange

||| An op kind a pattern names: its class, which is its identity, and its
||| range source, read off the op's declaration where the pattern is
||| flattened and carried with it, so no table is searched by class for it.
public export
record OpKind where
  constructor MkOpKind
  cls : String
  rangeSource : RangeSource

export
kindOfOp : Op i o a r -> OpKind
kindOfOp op = MkOpKind (opQualifiedClass op) (rangeOfMeaning op.meaning)

export
kindOfAdmitted : Admitted -> OpKind
kindOfAdmitted a = MkOpKind (admittedAlias a) (maybe NoRange ByUpstream a.range)

||| Two kinds are one where their classes are.
export
sameKind : OpKind -> OpKind -> Bool
sameKind k l = k.cls == l.cls

||| A pattern node flattened: a variable, an op's kind at one of its
||| results with its arity, or a literal.
public export
data FlatNode = FVar Nat | FNode OpKind Nat Nat | FLit Integer

||| A rule flattened: its root's kind, its variables, its two sides in
||| preorder, its conditions as printed rows.
public export
record FlatRule where
  constructor MkFlatRule
  root : OpKind
  vars : Nat
  lhs : List FlatNode
  rhs : List FlatNode
  conds : List String

mutual
  flatPat : Pat n -> List FlatNode
  flatPat (Var v) = [FVar (finToNat v)]
  flatPat (Node op res args) = FNode (kindOfOp op) (finToNat res) (length args) :: flatVect args
  flatPat (UpstreamNode a args) = FNode (kindOfAdmitted a) 0 (length args) :: flatList args
  flatPat (Literal l) = [FLit l]

  flatVect : Vect k (Pat n) -> List FlatNode
  flatVect [] = []
  flatVect (p :: ps) = flatPat p ++ flatVect ps

  flatList : List (Pat n) -> List FlatNode
  flatList [] = []
  flatList (p :: ps) = flatPat p ++ flatList ps

export
flatRoot : Root n -> (OpKind, List FlatNode)
flatRoot (RootedAt op res args) =
  (kindOfOp op, FNode (kindOfOp op) (finToNat res) (length args) :: flatVect args)

export
condRow : Cond n -> String
condRow (IsConstant v) = "{table::ConditionKind::IsConstant, " ++ decimal (finToNat v) ++ ", 0, 0}"
condRow (InRange v lo hi) = "{table::ConditionKind::InRange, " ++ decimal (finToNat v) ++ ", " ++ integer lo ++ ", " ++ integer hi ++ "}"
condRow (Clean v) = "{table::ConditionKind::Clean, " ++ decimal (finToNat v) ++ ", 0, 0}"

export
fromRewrite : AnyRewrite -> FlatRule
fromRewrite (SomeRewrite rw) =
  let (root, lhs) = flatRoot rw.lhs
  in MkFlatRule root (length (toList rw.vars)) lhs (flatPat rw.rhs) (map condRow rw.conds)

||| The rules a binary operation's associativity gives, on its kind: a
||| chain's two constants combined, `(x . c0) . c1` to `x . (c0 . c1)` and
||| `c0 . (c1 . x)` to `(c0 . c1) . x`, which the op's fold then computes.
||| Each fires only on two constants. Reassociation alone, which only
||| connects equal forms, is no rule: on real code it found nothing
||| extraction kept and made every budget stop.
associativeRules : OpKind -> List FlatRule
associativeRules c =
  let two = FNode c 0 2
      constants : Fin 3 -> Fin 3 -> List String
      constants a b = [condRow (IsConstant a), condRow (IsConstant b)]
  in [ MkFlatRule c 3 [two, two, FVar 0, FVar 1, FVar 2] [two, FVar 0, two, FVar 1, FVar 2] (constants 1 2)
     , MkFlatRule c 3 [two, FVar 0, two, FVar 1, FVar 2] [two, two, FVar 0, FVar 1, FVar 2] (constants 0 1) ]

||| The rule of a binary operation's identity on its right, on its kind.
identityRule : OpKind -> Integer -> FlatRule
identityRule c k = MkFlatRule c 1 [FNode c 0 2, FVar 0, FLit k] [FVar 0] []

||| The rules an op's laws give: the law is the one fact, so its rules are
||| derived here and never written beside it, each triggered narrowly (a
||| constant, a nested op). Both laws are binary; a law on an op of another
||| arity gives none.
export
lawRules : AnyOp -> List FlatRule
lawRules (SomeOp op) = concatMap (rulesOf (length (toList op.ins))) op.laws
  where
    c : OpKind
    c = kindOfOp op
    rulesOf : Nat -> Law -> List FlatRule
    rulesOf 2 Associative = associativeRules c
    rulesOf 2 (Identity (IntegerConstant k)) = [identityRule c k]
    rulesOf 2 (Identity (StringConstant _)) = []
    rulesOf _ _ = []

||| The rules an admitted upstream op's laws give, on its kind: every law
||| upstream has no trait for is binary.
export
admittedLawRules : Admitted -> List FlatRule
admittedLawRules a = concatMap rulesOf a.laws
  where
    rulesOf : UpLaw -> List FlatRule
    rulesOf UpAssociative = associativeRules (kindOfAdmitted a)
    rulesOf (UpIdentity (UpExactly k)) = [identityRule (kindOfAdmitted a) k]
    -- A width's signed bound is no one literal, which a rule's pattern
    -- matches, so it gives the accumulator its start and no rule.
    rulesOf (UpIdentity UpSignedLeast) = []
    rulesOf (UpIdentity UpSignedGreatest) = []

||| The kinds a node of the rules names, each once, in first use's order:
||| a kind's number is its position.
export
kindsOf : List FlatRule -> List OpKind
kindsOf rules = nubBy sameKind (concatMap (\r => named (r.lhs ++ r.rhs)) rules)
  where
    named : List FlatNode -> List OpKind
    named [] = []
    named (FNode k _ _ :: ns) = k :: named ns
    named (_ :: ns) = named ns

||| The position of a kind among the kinds.
export
kindNumber : List OpKind -> OpKind -> Nat
kindNumber kinds k = go 0 kinds
  where
    go : Nat -> List OpKind -> Nat
    go n [] = n
    go n (x :: xs) = if sameKind x k then n else go (S n) xs

export
nodeRow : List OpKind -> FlatNode -> String
nodeRow _ (FVar v) = "{table::PatternKind::Var, 0, 0, 0, " ++ decimal v ++ ", 0}"
nodeRow kinds (FNode k res arity) =
  "{table::PatternKind::Node, " ++ decimal (kindNumber kinds k) ++ ", " ++ decimal res ++ ", " ++ decimal arity ++ ", 0, 0}"
nodeRow _ (FLit l) = "{table::PatternKind::Literal, 0, 0, 0, 0, " ++ integer l ++ "}"

||| The rules grouped by their root's kind, in the kinds' order and, within
||| a kind, in declaration order: a grouping, never a sort.
export
byKind : List OpKind -> List FlatRule -> List (List FlatRule)
byKind kinds rules = map (\k => filter (\r => sameKind r.root k) rules) kinds

||| The rows of the rule table, with each side's and the conditions'
||| offsets into the pattern and condition arrays.
public export
record Laid where
  constructor MkLaid
  patterns : List String
  conditions : List String
  rules : List String

export
layRules : List OpKind -> List FlatRule -> Laid
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
                ++ decimal (length r.conds) ++ "}"
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

||| A kind's entry in the range table: the engine's adaptor at upstream's
||| range function, or at an inline meaning's trait's function over
||| intervals; none where the kind has neither.
export
rangeEntry : RangeSource -> String
rangeEntry (ByUpstream f) = "table::rangeBy<&::mlir::intrange::" ++ identText f.name ++ ">"
rangeEntry (ByMeaning m) = "table::rangeBy<&::idr::numeric::InlineArith<::idr::numeric::" ++ identText (inlineName m) ++ ">::inferRanges>"
rangeEntry NoRange = "std::nullopt"

||| Whether upstream's fold of an admitted op is never run at compile time.
neverFolded : Admitted -> Bool
neverFolded a = case a.folding of
  NeverFolded => True
  ComputedOnDoubles => False
  UpstreamFold => False

||| Whether the e-graph computes an admitted op on its own Double values.
computedOnDoubles : Admitted -> Bool
computedOnDoubles a = case a.folding of
  ComputedOnDoubles => True
  NeverFolded => False
  UpstreamFold => False

||| The e-graph's rules as the engine reads them: the patterns in preorder,
||| the conditions, the rules grouped by root kind with each kind's offset,
||| the kinds and each one's range function, the admitted ops never folded
||| and those computed on Doubles, the skeleton rules, and the budget, all
||| compile-time constants, so nothing is built per function.
||| The rules are the specification's, its ops' laws' and its admitted ops'
||| laws'.
export
rewritesHeader : List AnyRewrite -> List AnyOp -> List Admitted -> List SkeletonRule -> Lines
rewritesHeader rws ops admitted skeleton =
  let rules = map fromRewrite rws ++ concatMap lawRules ops ++ concatMap admittedLawRules admitted
      kinds = kindsOf rules
      groups = byKind kinds rules
      laid = layRules kinds (concat groups)
  in header "Rewrites" ["\"idr/Transforms/EGraph.h\"", "\"idr/IR/Generated/AdmittedClasses.h.inc\"", "\"idr/IR/Generated/SkeletonRules.h.inc\"", "\"idr/IR/Numeric/Trait.h\"", "\"mlir/Interfaces/Utils/InferIntRangeCommon.h\"", "<cstdint>", "<optional>"]
       (inNamespace "idr::egraph::generated"
         ( ["using Kinds = table::OpList<" ++ joinWith ", " (map (.cls) kinds) ++ ">;", ""]
           ++ slashComment [ "The admitted ops whose fold would compute on the compiling machine, which the graph never folds." ]
           ++ ["using NeverFolded = table::OpList<" ++ joinWith ", " (map admittedAlias (filter neverFolded admitted)) ++ ">;", ""]
           ++ slashComment [ "The admitted ops on Doubles whose result IEEE 754 fixes, which the graph computes on its own Double"
                           , "values by the operation each one's upstream fold applies." ]
           ++ ["using ComputedOnDoubles = table::OpList<" ++ joinWith ", " (map admittedAlias (filter computedOnDoubles admitted)) ++ ">;", ""]
           ++ slashComment [ "Each kind's interval from its operands', by the kind's number, for a node a rule built, where no op"
                           , "stands to be asked: upstream's range function for an admitted op, an inline meaning over intervals for"
                           , "one of ours, none for any other kind." ]
           ++ ["inline constexpr std::optional<table::IntRangeFn> intRanges[] = {"] ++ indent 2 (braced (map (rangeEntry . (.rangeSource)) kinds)) ++ ["};", ""]
           ++ ["inline constexpr table::PatternNode patterns[] = {"] ++ indent 2 (braced laid.patterns) ++ ["};", ""]
           ++ ["inline constexpr table::Condition conditions[] = {"] ++ indent 2 (braced laid.conditions) ++ ["};", ""]
           ++ ["inline constexpr table::Rule rules[] = {"] ++ indent 2 (braced laid.rules) ++ ["};", ""]
           ++ ["inline constexpr std::uint32_t rulesOfKind[] = {" ++ joinWith ", " (map decimal (offsets groups)) ++ "};", ""]
           ++ ["using SkeletonRules = table::RuleList<" ++ joinWith ", " (map (\n => "::idr::egraph::" ++ identText n) (skeletonClasses skeleton)) ++ ">;", ""]
           ++ slashComment ["Nodes per op of a function's e-graph: its arena, known before its search starts, is this times its ops."]
           ++ ["inline constexpr std::uint32_t nodesPerOp = " ++ decimal nodesPerOp ++ ";"] ))

------------------------------------------------------------------------------
-- Laws
------------------------------------------------------------------------------

||| An operation's unit as the C++ names it: an integer identity's, or a
||| string identity's, the string a template argument.
unitText : (String, LawConstant) -> String
unitText (c, IntegerConstant k) = "Unit<" ++ c ++ ", " ++ integer k ++ ">"
unitText (c, StringConstant t) = "StringUnit<" ++ c ++ ", " ++ quoted t ++ ">"

||| An op the specification calls exactly associative with an identity, by
||| its class, with that identity: of ours by its laws, admitted by its
||| upstream laws, as the C++ names its unit; an upstream identity relative
||| to the op's width a unit of its bound, which the C++ computes at the
||| width it is asked at. Associativity alone or an identity alone is not enough:
||| an accumulator combines on the way down what the call combined on the
||| way back, which needs both.
export
unitsOf : List AnyOp -> List Admitted -> List String
unitsOf ops admitted = concatMap ours ops ++ concatMap upstream admitted
  where
    identityIn : List Law -> Maybe LawConstant
    identityIn [] = Nothing
    identityIn (Identity k :: _) = Just k
    identityIn (_ :: ls) = identityIn ls
    isAssociative : Law -> Bool
    isAssociative Associative = True
    isAssociative _ = False
    associative : List Law -> Bool
    associative = any isAssociative
    ours : AnyOp -> List String
    ours (SomeOp op) = case (associative op.laws, identityIn op.laws) of
      (True, Just k) => [unitText (opQualifiedClass op, k)]
      _ => []
    upIdentity : List UpLaw -> Maybe UpIdentityValue
    upIdentity [] = Nothing
    upIdentity (UpIdentity k :: _) = Just k
    upIdentity (_ :: ls) = upIdentity ls
    isUpAssociative : UpLaw -> Bool
    isUpAssociative UpAssociative = True
    isUpAssociative _ = False
    upAssociative : List UpLaw -> Bool
    upAssociative = any isUpAssociative
    upstreamUnit : String -> UpIdentityValue -> String
    upstreamUnit c (UpExactly k) = unitText (c, IntegerConstant k)
    upstreamUnit c UpSignedLeast = "WidthUnit<" ++ c ++ ", WidthBound::SignedLeast>"
    upstreamUnit c UpSignedGreatest = "WidthUnit<" ++ c ++ ", WidthBound::SignedGreatest>"
    upstream : Admitted -> List String
    upstream a = case (upAssociative a.laws, upIdentity a.laws) of
      (True, Just k) => [upstreamUnit (admittedAlias a) k]
      _ => []

||| The operations an accumulator may combine on the way down, as a list of
||| types the hand `laws::identityOf` folds over: each a class and its
||| identity, compile-time constants, an integer or a string.
export
lawsHeader : List AnyOp -> List Admitted -> Lines
lawsHeader ops admitted =
  header "Laws" ["\"idr/IR/Generated/AdmittedClasses.h.inc\"", "<algorithm>", "<cstddef>", "<cstdint>", "<string_view>", "<tuple>"]
    (inNamespace "idr::laws"
      ( slashComment ["An operation the specification calls exactly associative, and its identity."]
        ++ [ "template <class OpT, std::int64_t Identity>"
           , "struct Unit {"
           , "  using Op = OpT;"
           , "  static constexpr std::int64_t identity = Identity;"
           , "};", "" ]
        ++ slashComment ["A string a unit names, as a template argument."]
        ++ [ "template <std::size_t N>"
           , "struct Text {"
           , "  char chars[N];"
           , "  constexpr Text(const char (&text)[N]) { std::copy_n(text, N, chars); }"
           , "  constexpr std::string_view view() const { return {chars, N - 1}; }"
           , "};", "" ]
        ++ slashComment ["An operation the specification calls exactly associative, and its identity, a string."]
        ++ [ "template <class OpT, Text Identity>"
           , "struct StringUnit {"
           , "  using Op = OpT;"
           , "  static constexpr std::string_view identity = Identity.view();"
           , "};", "" ]
        ++ slashComment ["The least or greatest signed value of a width: an identity no one integer is."]
        ++ [ "enum class WidthBound { SignedLeast, SignedGreatest };", "" ]
        ++ slashComment ["An operation the specification calls exactly associative, and its identity, a bound of its width."]
        ++ [ "template <class OpT, WidthBound Identity>"
           , "struct WidthUnit {"
           , "  using Op = OpT;"
           , "  static constexpr WidthBound identity = Identity;"
           , "};", "" ]
        ++ slashComment ["Every such operation, ours first, then the admitted upstream ones."]
        ++ ["using Units = std::tuple<" ++ joinWith ", " (unitsOf ops admitted) ++ ">;"] ))

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
  in slashComment [lineText p.doc.summary] ++ ["bool " ++ identText p.name ++ "(" ++ subject ++ " value);", ""]

||| A wired value's parser and printer of its text, and, for one spelled
||| by its members, the hash its storage keys by: their definitions are a
||| hand unit's, or, for one spelled by its members, printed from the wire
||| beside its bytecode (Generated/Wire.cpp.inc). An array is parsed into
||| the vector that owns its elements, and printed from its view.
export
textCodecDecls : (Wired, Directive) -> Lines
textCodecDecls (w, d) =
  hashDecl w
  ++ [ "::mlir::FailureOr<" ++ wiredParsed w ++ "> parse" ++ identText d.name ++ "(::mlir::AsmParser &parser);"
     , "void print" ++ identText d.name ++ "(::mlir::AsmPrinter &printer, " ++ wiredHeld w ++ " value);", "" ]
  where
    hashDecl : Wired -> Lines
    hashDecl (WiredOf c) = case spellingOf c of
      ByMembers _ => ["::llvm::hash_code hash_value(const " ++ codeText (compositeCpp c) ++ " &value);"]
      ByHand => []
    hashDecl _ = []

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
        in [ "// The default of " ++ identText d.name ++ "::" ++ identText m.name ++ "."
           , codeText m.result ++ " " ++ identText fn ++ "("
             ++ joinWith ", " (given ++ map (\p => codeText p.type ++ " " ++ identText p.name) m.params) ++ ");", "" ]

||| Where the dialect's header puts an interface's generated declaration
||| against the types and attributes: a type's or an attribute's interface
||| before them, since they implement it; an op's after them, since its
||| methods name them. mlir-tblgen prints a default's body where it defines
||| the interface, and the default's qualified call is looked up there, so
||| the function it calls is declared ahead of the interface: with the hooks
||| for an op's, in the defaults' own header for the others, which comes
||| before every generated class.
public export
data InterfacePlace = BeforeValues | AfterValues

placeOf : InterfaceSubject -> InterfacePlace
placeOf OverOps = AfterValues
placeOf OverTypes = BeforeValues
placeOf OverAttributes = BeforeValues

||| The functions the defaults of the interfaces at `place` call.
delegatesAt : InterfacePlace -> List InterfaceDef -> Lines
delegatesAt place = concatMap at
  where
    at : InterfaceDef -> Lines
    at d = case (place, placeOf d.subject) of
      (BeforeValues, BeforeValues) => delegateDecls d
      (AfterValues, AfterValues) => delegateDecls d
      _ => []

||| The hand functions the defaults of the type and attribute interfaces
||| call, which the dialect's header includes before those interfaces, so
||| each signature names only what is declared before every generated
||| class.
export
defaultsHeader : List InterfaceDef -> Lines
defaultsHeader is =
  header "Defaults" ["\"mlir/IR/Attributes.h\"", "\"mlir/IR/Types.h\"", "<cstdint>", "<optional>"]
    (inNamespace "idr" (delegatesAt BeforeValues is))

||| The declarations of every hand hook the specification names: custom
||| directives, predicates, parameter codecs, property hooks and the
||| functions the op interfaces' defaults call. Their definitions are hand
||| C++; a missing one is a link error.
export
hooksHeader : List Directive -> List Predicate -> List InterfaceDef -> List AnyTypeDef -> List AnyAttrDef
           -> List AnyOp -> Lines
hooksHeader ds ps is ts as ops =
  header "Hooks" ["\"mlir/Bytecode/BytecodeImplementation.h\"", "\"mlir/IR/OpImplementation.h\"", "\"llvm/ADT/Hashing.h\"", "<memory>", "<optional>"]
    (inNamespace "idr" (enumReader ++ concatMap directiveDecls ds ++ concatMap predicateDecl ps
                        ++ delegatesAt AfterValues is ++ concatMap textCodecDecls (wiredOf ts as)
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
    own (RunDeciding q _ _ rest) = q.adds ++ own rest

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
stepsOf here path (RunDeciding p why _ rest) =
  let next = leaves p.stages here
      (more, end) = stepsOf next path rest
  in (MkStep here next (nestPath path ++ ".addPass(" ++ passConstructor p [] ++ ");") why :: more, end)
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

||| A decide step's apply group, which the step runs nested in itself: the
||| step, and the steps that add the group to a manager on the program,
||| bracketed by the rows' widening and writing as any nest is.
public export
record ApplyGroup where
  constructor MkApplyGroup
  decider : Pass
  steps : List Step

||| Every decide step's apply group in a pipeline that starts at `here`, in
||| order: the pipeline adds each decide step alone, and the step runs its
||| group.
export
groupsOf : (here : Stage) -> Pipeline a s t -> List ApplyGroup
groupsOf _ Done = []
groupsOf here (Run p _ rest) = groupsOf (leaves p.stages here) rest
groupsOf here (RunUpstream _ _ rest) = groupsOf here rest
groupsOf here (Nest _ first rest) = groupsOf here first ++ groupsOf (snd (stepsOf here [] first)) rest
groupsOf here (RunDeciding p _ group rest) =
  let next = leaves p.stages here
  in MkApplyGroup p (fst (stepsOf next [] (Nest {a = OnProgram} OnFunction group Done))) :: groupsOf next rest

||| The function that adds a decide step's apply group to a manager on the
||| program: `applyGroupOfIdrNarrow`.
export
applyGroupName : Pass -> String
applyGroupName p = "applyGroupOf" ++ passRecord p

||| Each decide step's apply group as a function the step calls on a
||| manager on the program it runs on. A group holds function passes of
||| ours alone, since no upstream pass runs on our functions, so the
||| header needs the pipeline's declarations and nothing upstream's.
export
applyGroupsHeader : List ApplyGroup -> Lines
applyGroupsHeader groups =
  header "ApplyGroups" ["\"idr/Transforms/Pipeline.h\""]
    (inNamespace "idr::pipeline" (concatMap applyGroup groups))
  where
    applyGroup : ApplyGroup -> Lines
    applyGroup g =
      slashComment ["The apply group " ++ passArgument g.decider ++ " runs on the program's functions nested in itself, while it holds its decision."]
      ++ ["inline void " ++ applyGroupName g.decider ++ "(::mlir::OpPassManager &pm) { " ++ joinWith " " (map (.add) g.steps) ++ " }", ""]

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

