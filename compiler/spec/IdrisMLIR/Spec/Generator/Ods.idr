-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The specification printed as ODS, the input of upstream's mlir-tblgen,
||| which interprets it as it always has: one printer per construct, each
||| spec constructor one ODS construct, so a printed `def` reads like hand
||| ODS. No fact is computed here that the specification does not hold;
||| names come from positions through the op's own groups.
module IdrisMLIR.Spec.Generator.Ods

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Generator.Render
import IdrisMLIR.Spec.Generator.Wire
import IdrisMLIR.Spec.Pipeline.Pass

import Data.Fin
import Data.List
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------

||| A record of ours: `Idr_<name>`.
export
idrRecord : String -> String
idrRecord n = "Idr_" ++ n

||| The record of the dialect an op, type or attribute of ours is defined
||| in, as upstream's ODS names it.
dialectRecord : Dialect -> String
dialectRecord d = identText (odsDialect d)

||| An enum's records: its info and its attribute.
export
enumRecord : EnumDef -> String
enumRecord e = idrRecord (identText e.name)

export
enumAttrRecord : EnumDef -> String
enumAttrRecord e = idrRecord (identText e.name ++ "Attr")

||| An enum's attribute mnemonic: its name in snake case, `RuleCategory` is
||| `rule_category`.
export
snakeOf : String -> String
snakeOf s = pack (go True (unpack s))
  where
    low : Char -> Char
    low c = if upper c then chr (ord c + 32) else c
    go : Bool -> List Char -> List Char
    go _ [] = []
    go start (c :: cs) =
      if upper c && not start then '_' :: low c :: go False cs else low c :: go False cs

export
typeRecord : TypeDef p -> String
typeRecord t = idrRecord (typeClass t)

export
attrRecord : AttrDef p -> String
attrRecord a = idrRecord (attrClass a)

export
opRecord : Op i o a r -> String
opRecord op = case op.home of
  InIdr => idrRecord (opClass op)
  InTransform _ => opClass op

export
interfaceRecord : InterfaceDef -> String
interfaceRecord d = idrRecord (identText d.name)

export
traitRecord : TraitDef -> String
traitRecord d = idrRecord (identText d.name ++ "Trait")

export
resourceRecord : ResourceDef -> String
resourceRecord r = idrRecord (identText r.name ++ "Resource")

------------------------------------------------------------------------------
-- Docs
------------------------------------------------------------------------------

export
summaryField : Doc -> Lines
summaryField d = ["let summary = " ++ quoted (lineText d.summary) ++ ";"]

export
descriptionField : Doc -> Lines
descriptionField d = case proseLines d.description of
  [] => []
  ls => ["let description = [{"] ++ indent 2 ls ++ ["}];"]

export
docFields : Doc -> Lines
docFields d = summaryField d ++ descriptionField d

------------------------------------------------------------------------------
-- Enums
------------------------------------------------------------------------------

||| The width every enum of the dialect is stored at, an enum property's
||| storage too (upstream's `EnumProp` holds an integer of its enum's width),
||| which the frontend's builders encode a property at.
export
enumBits : Nat
enumBits = 32

export
caseLine : EnumShape -> Nat -> Case -> String
caseLine OneOf n c =
  "I" ++ decimal enumBits ++ "EnumAttrCase<" ++ quoted (identText c.name) ++ ", " ++ decimal n ++ ", " ++ quoted (spellingText c) ++ ">"
caseLine SetOf n c =
  "I" ++ decimal enumBits ++ "BitEnumAttrCaseBit<" ++ quoted (identText c.name) ++ ", " ++ decimal n ++ ", " ++ quoted (spellingText c) ++ ">"

export
numbered : List a -> List (Nat, a)
numbered = go 0
  where
    go : Nat -> List a -> List (Nat, a)
    go _ [] = []
    go n (x :: xs) = (n, x) :: go (S n) xs

||| Whether any case spells more than one word, which the parser then reads
||| as a string.
export
spacedSpelling : EnumDef -> Bool
spacedSpelling e = any (\c => length (forget c.spelling) > 1) (forget e.cases)

||| An enum of the dialect: its info record, dense from zero, and its
||| attribute `#idr.<snake>`.
export
enumOds : EnumDef -> Lines
enumOds e =
  let kind = case e.shape of
               OneOf => "I" ++ decimal enumBits ++ "EnumAttr"
               SetOf => "I" ++ decimal enumBits ++ "BitEnumAttr"
      cases = map (\(n, c) => caseLine e.shape n c) (numbered (forget e.cases))
      name = identText e.name
      printer = if spacedSpelling e
                  then [ "let parameterPrinter = \"$_printer.printKeywordOrString(::idr::stringify" ++ name ++ "($_self))\";"
                       , "let parameterParser = [{ [&]() -> ::mlir::FailureOr<::idr::" ++ name ++ "> {"
                       , "  std::string spelled;"
                       , "  if (::mlir::failed($_parser.parseKeywordOrString(&spelled))) return ::mlir::failure();"
                       , "  if (auto known = ::idr::symbolize" ++ name ++ "(spelled)) return *known;"
                       , "  return $_parser.emitError($_parser.getCurrentLocation(), \"expects a case of " ++ name ++ "\");"
                       , "}() }];" ]
                  else []
  in slashComment [lineText e.doc.summary]
     ++ ["def " ++ enumRecord e ++ " : " ++ kind ++ "<" ++ quoted name ++ ", " ++ quoted (lineText e.doc.summary) ++ ", ["]
     ++ indent 4 (zipWith (++) cases (replicate (pred (length cases)) "," ++ [""]))
     ++ ["  ]> {", "  let cppNamespace = \"::idr\";", "  let genSpecializedAttr = 0;"]
     ++ indent 2 printer
     ++ ["}", "def " ++ enumAttrRecord e ++ " : EnumAttr<" ++ dialectRecord Idr ++ ", " ++ enumRecord e ++ ", " ++ quoted (snakeOf name) ++ ">;", ""]

------------------------------------------------------------------------------
-- Constraints
------------------------------------------------------------------------------

export
typeRecordOf : AnyTypeDef -> String
typeRecordOf (SomeType t) = typeRecord t

export
attrRecordOf : AnyAttrDef -> String
attrRecordOf (SomeAttr a) = attrRecord a

mutual
  export
  typeC : TypeC -> String
  typeC (UpstreamType u) = identText (upTypeRecord u)
  typeC (OurType t) = typeRecordOf t
  typeC (AnyOfTypes ts s) = "AnyTypeOf<[" ++ joinWith ", " (typeCs ts) ++ "], " ++ quoted (lineText s) ++ ">"
  typeC (AllOfTypes ts s) =
    "Type<And<[" ++ joinWith ", " (map (++ ".predicate") (typeCs ts)) ++ "]>, " ++ quoted (lineText s) ++ ", \"::mlir::Type\">"
  typeC (SatisfiesType p) =
    "Type<CPred<\"::idr::" ++ identText p.name ++ "($_self)\">, " ++ quoted (lineText p.doc.summary) ++ ", \"::mlir::Type\">"

  ||| The records of a run of constraints, matched on the run itself and
  ||| never on a conversion of it, so every call is on a part of the
  ||| constraint and the recursion is structural.
  typeCs : List1 TypeC -> List String
  typeCs (t ::: ts) = typeC t :: restTypeCs ts

  restTypeCs : List TypeC -> List String
  restTypeCs [] = []
  restTypeCs (t :: ts) = typeC t :: restTypeCs ts

export
attrC : AttrC -> String
attrC (UpstreamAttr u) = identText (upAttrRecord u)
attrC (OurAttr a) = attrRecordOf a
attrC (EnumAttrOf e) = enumAttrRecord e
attrC (TypeAttrOf t) = "TypeAttrOf<" ++ typeC t ++ ">"
attrC (Confined base cs) = "ConfinedAttr<" ++ attrC base ++ ", [" ++ joinWith ", " (map confinementRecord (forget cs)) ++ "]>"
attrC (SatisfiesAttr p) =
  "Attr<CPred<\"::idr::" ++ identText p.name ++ "($_self)\">, " ++ quoted (lineText p.doc.summary) ++ ">"

export
propertyC : PropertyC -> String
propertyC (EnumProperty e) = "EnumProp<" ++ enumRecord e.enum ++ ">"
propertyC (DefaultedEnumProperty e c) = "DefaultValuedProp<EnumProp<" ++ enumRecord e.enum ++ ">, " ++ quoted (codeText c) ++ ">"
propertyC (CountProperty dflt) = "DefaultValuedProp<IntProp<\"uint64_t\">, " ++ quoted (decimal dflt) ++ ">"
propertyC (HandProperty c d dflt) =
  "Idr_HandProperty<" ++ quoted (codeText c) ++ ", " ++ quoted (identText d.name) ++ ", "
    ++ quoted (codeText dflt) ++ ", " ++ quoted (lineText d.doc.summary) ++ ">"

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------

export
resourceOds : OdsResource -> String
resourceOds UpstreamRoot = "DefaultResource"
resourceOds UpstreamFrame = "AutomaticAllocationScopeResource"
resourceOds (OurResource r) = resourceRecord r

export
kindOds : EffectKind -> String
kindOds MemRead = "MemRead"
kindOds MemWrite = "MemWrite"
kindOds MemAlloc = "MemAlloc"
kindOds MemFree = "MemFree"

export
effectOds : OdsEffect i o -> String
effectOds e = kindOds e.kind ++ "<" ++ resourceOds e.resource ++ ">"

export
onOp : OdsEffect i o -> Bool
onOp e = case e.subject of
  OfOp => True
  _ => False

export
onOperand : Fin i -> OdsEffect i o -> Bool
onOperand k e = case e.subject of
  OfOperand j => j == k
  _ => False

export
onResult : Fin o -> OdsEffect i o -> Bool
onResult k e = case e.subject of
  OfResult j => j == k
  _ => False

||| The effects printed as decorators on the op's values, when the op's
||| effects are static: upstream generates `getEffects` from them.
export
decoratorsOf : OdsEffects i o -> (OdsEffect i o -> Bool) -> List String
decoratorsOf (Declares es [] _) keep = map effectOds (filter keep es)
decoratorsOf _ _ = []

||| The traits an op's effects print: static effects on the op as
||| `MemoryEffects`, none at all as `NoMemoryEffect`, typed rules as a
||| declared `getEffects` the generated table defines, and its regions'
||| effects as `RecursiveMemoryEffects`, and the effect system's own
||| interface, through which the one query API reads the op's table. An op
||| that declares every effect prints nothing: upstream reads an op without
||| the interface as one that may do anything.
export
effectTraits : OdsEffects i o -> List String
effectTraits EveryEffect = []
effectTraits (Declares es rules bodies) =
  let own = case rules of
              [] => case es of
                      [] => ["NoMemoryEffect"]
                      _ => case filter onOp es of
                             [] => []
                             ops => ["MemoryEffects<[" ++ joinWith ", " (map effectOds ops) ++ "]>"]
              _ => ["DeclareOpInterfaceMethods<MemoryEffectsOpInterface>"]
      recursive = case bodies of
                    OwnOnly => []
                    WithBodies => ["RecursiveMemoryEffects"]
  in own ++ recursive ++ ["Idr_DeclaredEffectsOpInterface"]

------------------------------------------------------------------------------
-- Ops
------------------------------------------------------------------------------

export
traitOds : Trait i o -> String
traitOds Terminator = "Terminator"
traitOds ReturnLike = "ReturnLike"
traitOds IsolatedFromAbove = "IsolatedFromAbove"
traitOds SingleBlock = "SingleBlock"
traitOds NoTerminator = "NoTerminator"
traitOds NoRegionArguments = "NoRegionArguments"
traitOds SymbolTable = "SymbolTable"
traitOds SymbolOp = "Symbol"
traitOds AffineScope = "AffineScope"
traitOds AutomaticAllocationScope = "AutomaticAllocationScope"
traitOds ConstantLike = "ConstantLike"
traitOds SameOperandsAndResultType = "SameOperandsAndResultType"
traitOds SameTypeOperands = "SameTypeOperands"
traitOds PropagateControlFlowBreak = "PropagateControlFlowBreak"
traitOds ReportTrackingListenerFailures = "ReportTrackingListenerFailuresOpTrait"
traitOds TokenProducer = "TokenProducerTrait"
traitOds TokenConsumer = "TokenConsumerTrait"
traitOds (HasNestedTerminator ps) = "HasNestedTerminator<[" ++ joinWith ", " (map (\p => quoted ("::idr::" ++ opRefClass p)) (forget ps)) ++ "]>"
traitOds (OurTrait d) = traitRecord d
traitOds (HasParent (p ::: [])) = "HasParent<" ++ quoted ("::idr::" ++ opRefClass p) ++ ">"
traitOds (HasParent ps) = "ParentOneOf<[" ++ joinWith ", " (map (\p => quoted ("::idr::" ++ opRefClass p)) (forget ps)) ++ "]>"
traitOds (HasUpstreamParent cls) = "HasParent<" ++ quoted (cppText cls) ++ ">"
traitOds (ImplicitTerminator p) = "SingleBlockImplicitTerminator<" ++ quoted ("::idr::" ++ opRefClass p) ++ ">"
traitOds (ResultUsesMaxOf res from) =
  "Idr_ResultUsesMax<\"" ++ joinWith ", " (decimal (finToNat res) :: map (decimal . finToNat) from) ++ "\">"

||| ODS's class that declares an interface's methods on a class of what it
||| is over: an op's, a type's or an attribute's.
export
declareMethods : InterfaceSubject -> String
declareMethods OverOps = "DeclareOpInterfaceMethods"
declareMethods OverTypes = "DeclareTypeInterfaceMethods"
declareMethods OverAttributes = "DeclareAttrInterfaceMethods"

||| An interface taken by a declaration over `subject`, with the methods its
||| class declares.
export
interfaceUseOds : InterfaceSubject -> InterfaceUse -> String
interfaceUseOds _ (InfersTypes InferredOnly) = "InferTypeOpAdaptor"
interfaceUseOds _ (InfersTypes AlsoCompatible) = "InferTypeOpAdaptorWithIsCompatible"
interfaceUseOds _ (Declares u []) = identText (upInterfaceRecord u)
interfaceUseOds subject (Declares u ms) =
  declareMethods subject ++ "<" ++ identText (upInterfaceRecord u) ++ ", [" ++ joinWith ", " (map (quoted . identText) ms) ++ "]>"
interfaceUseOds _ (Implements d []) = interfaceRecord d
interfaceUseOds subject (Implements d ms) =
  declareMethods subject ++ "<" ++ interfaceRecord d ++ ", [" ++ joinWith ", " (map (quoted . identText) ms) ++ "]>"

export
speculationOds : Speculation -> List String
speculationOds NotSpeculatable = []
speculationOds AlwaysSpeculatable = ["AlwaysSpeculatable"]
speculationOds RecursivelySpeculatable = ["RecursivelySpeculatable"]
speculationOds Conditionally = ["DeclareOpInterfaceMethods<ConditionallySpeculatable>"]

export
lawOds : Law -> List String
lawOds Commutative = ["Commutative"]
lawOds Idempotent = ["Idempotent"]
lawOds Involution = ["Involution"]
lawOds _ = []

export
meaningTraits : Meaning i o -> List String
meaningTraits (ComputedByRuntime _) = ["Idr_RuntimeFolds"]
meaningTraits (Inline fn) = ["Idr_InlineArith<\"::idr::numeric::" ++ identText fn ++ "\">"]
meaningTraits _ = []

||| The segment traits an op's groups call for: its operands' and its
||| results' sizes, where its groups need them stated.
segmentTraits : Op i o a r -> List String
segmentTraits op =
  stated (segmentsOf (map (.arity) (toList op.ins))) "AttrSizedOperandSegments"
  ++ stated (segmentsOf (map (.arity) (toList op.outs))) "AttrSizedResultSegments"
  where
    stated : Segments -> String -> List String
    stated FixedByCount _ = []
    stated SizesStated t = [t]

||| The traits from which upstream's ODS infers an op's result types and
||| generates their inference, one per result its rule reads off an operand:
||| the operand's own type, or its element type or itself as MLIR's
||| `getElementTypeOrSelf` gives it. A fixed type is the result's own
||| constraint, which ODS builds, so it needs none.
typingTraits : Op i o a r -> List String
typingTraits op = case op.typing of
  StatedTypes => []
  InferredTypes rules => concatMap matching (toList (zip op.outs rules))
  where
    matchWith : String -> Operand -> Result -> String -> String
    matchWith what x y transform =
      "TypesMatchWith<" ++ quoted (identText y.name ++ " has the " ++ what ++ " of " ++ identText x.name) ++ ", "
        ++ quoted (identText x.name) ++ ", " ++ quoted (identText y.name) ++ ", " ++ quoted transform ++ ">"
    matching : (Result, TypeRule i) -> List String
    matching (y, OperandType g) = [matchWith "type" (index g op.ins) y "$_self"]
    matching (y, ElementTypeOf g) = [matchWith "element type" (index g op.ins) y "::mlir::getElementTypeOrSelf($_self)"]
    matching (_, FixedType _) = []

||| Every trait of an op, in one list: its own, its groups' segments', its
||| result types' rules', its laws', its effects', its speculation's, its
||| interfaces', its meaning's, and the guarded op's when it takes guards.
export
opTraits : Op i o a r -> OdsEffects i o -> List String
opTraits op effs =
  map traitOds op.traits
  ++ segmentTraits op
  ++ typingTraits op
  ++ concatMap lawOds op.laws
  ++ effectTraits effs
  ++ speculationOds op.speculation
  ++ map (interfaceUseOds OverOps) op.interfaces
  ++ meaningTraits op.meaning
  ++ (case op.guards of
        [] => []
        _ => ["Idr_GuardedOp"])

export
arityOds : Arity -> String -> String
arityOds Single c = c
arityOds Optional c = "Optional<" ++ c ++ ">"
arityOds Variadic c = "Variadic<" ++ c ++ ">"

||| A value with decorators, `Arg<C, "", [MemRead<R>]>`, or the plain one.
export
decorated : String -> String -> List String -> String
decorated _ c [] = c
decorated wrapper c ds = wrapper ++ "<" ++ c ++ ", \"\", [" ++ joinWith ", " ds ++ "]>"

export
operandOds : OdsEffects i o -> (Fin i, Operand) -> String
operandOds effs (k, x) =
  decorated "Arg" (arityOds x.arity (typeC x.type)) (decoratorsOf effs (onOperand k)) ++ ":$" ++ identText x.name

export
resultOds : OdsEffects i o -> (Fin o, Result) -> String
resultOds effs (k, x) =
  decorated "Res" (arityOds x.arity (typeC x.type)) (decoratorsOf effs (onResult k)) ++ ":$" ++ identText x.name

export
attrOds : Attr -> String
attrOds x = case x.kind of
  AnAttribute c Required => attrC c ++ ":$" ++ identText x.name
  AnAttribute c MayBeAbsent => "OptionalAttr<" ++ attrC c ++ ">:$" ++ identText x.name
  AnAttribute c (DefaultValued d) => "DefaultValuedAttr<" ++ attrC c ++ ", " ++ quoted (codeText d) ++ ">:$" ++ identText x.name
  AProperty p => propertyC p ++ ":$" ++ identText x.name

export
regionOds : Region -> String
regionOds x =
  let one = case x.blocks of
              AnyBlocks => "AnyRegion"
              Sized n => "SizedRegion<" ++ decimal n ++ ">"
              AtMost n => "MaxSizedRegion<" ++ decimal n ++ ">"
      group = case x.arity of
                OneRegion => one
                AnyRegions => "VariadicRegion<" ++ one ++ ">"
  in group ++ ":$" ++ identText x.name

||| The positions of a vector, with its elements, by its own structure, so
||| no length is needed at run time.
export
indexed : Vect n a -> List (Fin n, a)
indexed [] = []
indexed (x :: xs) = (FZ, x) :: map (\(k, y) => (FS k, y)) (indexed xs)

||| `(kind a, b, c)`, a dag of arguments.
export
dag : String -> List String -> String
dag kind [] = "(" ++ kind ++ ")"
dag kind xs = "(" ++ kind ++ " " ++ joinWith ", " xs ++ ")"

------------------------------------------------------------------------------
-- Assembly formats
------------------------------------------------------------------------------

export
refName : Op i o a r -> Ref i o a r -> String
refName op (OperandRef k) = "$" ++ identText (index k op.ins).name
refName op (ResultRef k) = "$" ++ identText (index k op.outs).name
refName op (AttrRef k) = "$" ++ identText (index k op.attrs).name
refName op (RegionRef k) = "$" ++ identText (index k op.regions).name

export
sourceName : Op i o a r -> TypeSource i o a r -> String
sourceName op (OfGroup g) = refName op g
sourceName _ OfOperands = "operands"
sourceName _ OfResults = "results"

export
directiveIn : Op i o a r -> DirectiveIn i o a r -> String
directiveIn op (Group g) = refName op g
directiveIn op (TypeOfGroup g) = "type(" ++ refName op g ++ ")"
directiveIn op (Again g) = "ref(" ++ refName op g ++ ")"
directiveIn op (TypeAgain g) = "ref(type(" ++ refName op g ++ "))"

mutual
  itemText : Op i o a r -> Item i o a r -> String
  itemText _ (Lit l) = "`" ++ lineText l ++ "`"
  itemText op (ValueOf g) = refName op g
  itemText op (TypeOf s) = "type(" ++ sourceName op s ++ ")"
  itemText op (QualifiedTypeOf s) = "qualified(type(" ++ sourceName op s ++ "))"
  itemText op (FunctionalType f t) = "functional-type(" ++ sourceName op f ++ ", " ++ sourceName op t ++ ")"
  itemText _ AttrDict = "attr-dict"
  itemText _ AttrDictWithKeyword = "attr-dict-with-keyword"
  itemText _ PropDict = "prop-dict"
  itemText _ Regions = "regions"
  itemText op (Custom d args) = "custom<" ++ identText d.name ++ ">(" ++ joinWith ", " (map (directiveIn op) args) ++ ")"
  itemText op (OptionalGroup before anchor after) =
    "(" ++ joinWith " " (itemTexts op before ++ [itemText op anchor ++ "^"] ++ itemTexts op after) ++ ")?"

  itemTexts : Op i o a r -> List (Item i o a r) -> List String
  itemTexts _ [] = []
  itemTexts op (x :: xs) = itemText op x :: itemTexts op xs

export
formatFields : Op i o a r -> Lines
formatFields op = case op.format of
  HandFormat => ["let hasCustomAssemblyFormat = 1;"]
  Declared items => ["let assemblyFormat = [{ " ++ joinWith " " (itemTexts op items) ++ " }];"]

------------------------------------------------------------------------------
-- An op's other fields
------------------------------------------------------------------------------

export
verifyFields : Verify -> Lines
verifyFields DeclarationOnly = []
verifyFields VerifiesOp = ["let hasVerifier = 1;"]
verifyFields VerifiesRegions = ["let hasRegionVerifier = 1;"]
verifyFields VerifiesOpAndRegions = ["let hasVerifier = 1;", "let hasRegionVerifier = 1;"]

export
folderFields : Meaning i o -> Lines
folderFields HandFolder = ["let hasFolder = 1;"]
folderFields (InlineCondition _) = ["let hasFolder = 1;"]
folderFields _ = []

export
paramText : Param -> String
paramText p = quoted (codeText p.type) ++ ":$" ++ identText p.name

export
builderFields : List Builder -> DefaultBuilders -> Lines
builderFields bs d =
  let skip = case d of
               WithDefaults => []
               DeclaredOnly => ["let skipDefaultBuilders = 1;"]
      decls = case bs of
                [] => []
                _ => ["let builders = ["]
                     ++ indent 2 (map (\b => "OpBuilder<" ++ dag "ins" (map paramText b.params) ++ ">,") bs)
                     ++ ["];"]
  in skip ++ decls

||| A member function's declaration, after its template head if any.
export
functionDecl : Binding -> Code -> Ident -> List Param -> String
functionDecl binding result name ps =
  let params = joinWith ", " (map (\p => codeText p.type ++ " " ++ identText p.name) ps)
      head = case binding of
               OnClass => "static " ++ codeText result
               _ => codeText result
      tail = case binding of
               OnObjectConst => ") const;"
               _ => ");"
  in head ++ " " ++ identText name ++ "(" ++ params ++ tail

||| A member's C++ declaration: a function, or a function template whose
||| every type parameter its concept constrains.
export
memberDecl : Member -> String
memberDecl (MkMember binding result name ps) = functionDecl binding result name ps
memberDecl (MkTemplateMember tps binding result name ps) =
  "template <" ++ joinWith ", " (map (\t => codeText t.concept ++ " " ++ identText t.name) (forget tps)) ++ "> "
    ++ functionDecl binding result name ps

export
membersField : List Member -> Lines
membersField [] = []
membersField ms = ["let extraClassDeclaration = [{"] ++ indent 2 (map memberDecl ms) ++ ["}];"]

||| An op's record.
export
opOds : Op i o a r -> Lines
opOds op =
  let effs = ods op.effects
      base = case op.home of
               InIdr => "Idr_Op<" ++ quoted (mnemonicText op.mnemonic) ++ ", ["
               InTransform _ => "Op<" ++ dialectRecord (homeDialect op.home) ++ ", " ++ quoted (mnemonicText op.mnemonic) ++ ", ["
      traits = opTraits op effs
      namespace' = case op.home of
                     InIdr => []
                     InTransform cls => ["let cppNamespace = " ++ quoted (cppText (fromMaybe cls (fromList (Data.List1.init cls)))) ++ ";"]
      args = map (operandOds effs) (indexed op.ins) ++ map attrOds (toList op.attrs)
      outs = map (resultOds effs) (indexed op.outs)
      regions = map regionOds (toList op.regions)
  in ["def " ++ opRecord op ++ " : " ++ base]
     ++ indent 4 (zipWith (++) traits (replicate (pred (length traits)) "," ++ [""]))
     ++ ["  ]> {"]
     ++ indent 2 (namespace'
                  ++ docFields op.doc
                  ++ ["let arguments = " ++ dag "ins" args ++ ";"]
                  ++ ["let results = " ++ dag "outs" outs ++ ";"]
                  ++ (case regions of
                        [] => []
                        _ => ["let regions = " ++ dag "region" regions ++ ";"])
                  ++ formatFields op
                  ++ verifyFields op.verify
                  ++ folderFields op.meaning
                  ++ builderFields op.builders op.defaultBuilders
                  ++ membersField op.members)
     ++ ["}", ""]

||| An op of any counts.
export
anyOpOds : AnyOp -> Lines
anyOpOds (SomeOp op) = opOds op

------------------------------------------------------------------------------
-- Types and attributes
------------------------------------------------------------------------------

||| A parameter's C++ type.
export
paramCppType : ParamKind -> String
paramCppType TypeValue = "::mlir::Type"
paramCppType (OptionalCase _ c) = "::std::optional<" ++ codeText c ++ ">"
paramCppType AttrValue = "::mlir::Attribute"
paramCppType (EnumValue e) = "::idr::" ++ identText e.enum.name
paramCppType StringValue = "::llvm::StringRef"
paramCppType IntegerValue = "::llvm::APInt"
paramCppType CountValue = "uint64_t"
paramCppType (ListOf k) = "::llvm::ArrayRef<" ++ paramCppType k ++ ">"
paramCppType (WiredValue w _) = wiredHeld w

export
paramKindOds : ParamKind -> String
paramKindOds TypeValue = "\"::mlir::Type\""
paramKindOds (OptionalCase _ c) = quoted ("::std::optional<" ++ codeText c ++ ">")
paramKindOds AttrValue = "\"::mlir::Attribute\""
paramKindOds (EnumValue e) = "EnumParameter<" ++ enumRecord e.enum ++ ">"
paramKindOds StringValue = "StringRefParameter<>"
paramKindOds IntegerValue = "APIntParameter<\"\">"
paramKindOds CountValue = "\"uint64_t\""
paramKindOds (ListOf k) = "ArrayRefParameter<" ++ quoted (paramCppType k) ++ ", \"\">"
paramKindOds (WiredValue (WiredArray w) d) =
  "Idr_HandArrayParameter<" ++ quoted (wireCpp w) ++ ", " ++ quoted (identText d.name) ++ ">"
paramKindOds (WiredValue (WiredOne l) d) =
  "Idr_HandParameter<" ++ quoted (leafCpp l) ++ ", " ++ quoted (identText d.name) ++ ">"
paramKindOds (WiredValue (WiredOf c) d) =
  "Idr_HandParameter<" ++ quoted (codeText (compositeCpp c)) ++ ", " ++ quoted (identText d.name) ++ ">"

export
parameterOds : Parameter -> String
parameterOds x = case x.presence of
  AlwaysWritten => paramKindOds x.kind ++ ":$" ++ identText x.name
  DefaultsTo d => "DefaultValuedParameter<" ++ paramKindOds x.kind ++ ", " ++ quoted (codeText d) ++ ">:$" ++ identText x.name

export
typedParameterOds : Typed p -> (Fin p, Parameter) -> String
typedParameterOds (TypedBy k) (j, x) =
  if k == j then "AttributeSelfTypeParameter<\"\">:$" ++ identText x.name else parameterOds x
typedParameterOds Untyped (_, x) = parameterOds x

mutual
  paramItem : Vect p Parameter -> ParamItem p -> String
  paramItem _ (Keyword l) = "`" ++ lineText l ++ "`"
  paramItem ps (ParamAt k) = "$" ++ identText (index k ps).name
  paramItem ps (Struct ks) = "struct(" ++ joinWith ", " (map (\k => "$" ++ identText (index k ps).name) ks) ++ ")"
  paramItem ps (CustomParams d ks) =
    "custom<" ++ identText d.name ++ ">(" ++ joinWith ", " (map (\k => "$" ++ identText (index k ps).name) ks) ++ ")"
  paramItem ps (OptionalParams items) = "(" ++ joinWith " " (paramItems ps items) ++ ")?"

  paramItems : Vect p Parameter -> List (ParamItem p) -> List String
  paramItems _ [] = []
  paramItems ps (x :: xs) = paramItem ps x :: paramItems ps xs

export
syntaxFields : Vect p Parameter -> Syntax p -> Lines
syntaxFields _ HandSyntax = ["let hasCustomAssemblyFormat = 1;"]
syntaxFields ps (Declarative items) = ["let assemblyFormat = [{ " ++ joinWith " " (paramItems ps items) ++ " }];"]

export
verifierFields : ParamVerifier -> Lines
verifierFields AnyParameters = []
verifierFields VerifiesParameters = ["let genVerifyDecl = 1;"]

export
interfaceTraits : InterfaceSubject -> List InterfaceUse -> List String
interfaceTraits subject = map (interfaceUseOds subject)

||| A hand storage: ODS declares the class and the hand unit defines it.
export
storageFields : Storage -> Lines
storageFields GeneratedStorage = []
storageFields HandStorage = ["let genStorageClass = 0;"]

||| A fact's answer, printed as the method's one return.
export
truth : Bool -> String
truth True = "true"
truth False = "false"

||| The answers a type gives the value facts, as the methods' definitions:
||| each one return of a constant, so nothing is decided here.
export
factsDefinition : ValueFacts -> Lines
factsDefinition f =
  [ "let extraClassDefinition = [{"
  , "  bool $cppClass::holdsReferences() const { return " ++ truth (holds f.holding) ++ "; }"
  , "  bool $cppClass::isLinearByType() const { return " ++ truth (once f.byType) ++ "; }"
  , "  bool $cppClass::isCounted() const { return " ++ truth (counted f.counting) ++ "; }"
  , "  bool $cppClass::isCellPointer() const { return " ++ truth (cell f.word) ++ "; }"
  , "}];" ]
  where
    holds : Holding -> Bool
    holds HoldsReferences = True
    holds HoldsNoReference = False
    once : ByType -> Bool
    once UsedOnceByType = True
    once UsedAsGraded = False
    counted : Counting -> Bool
    counted Counted = True
    counted Uncounted = False
    cell : CellWord -> Bool
    cell AlwaysCell = True
    cell MayBeOtherWord = False

export
factsTraits : TypeFacts -> List String
factsTraits NoValueFacts = []
factsTraits (Answers _) = [interfaceRecord valueFactsInterface]

export
factsFields : TypeFacts -> Lines
factsFields NoValueFacts = []
factsFields (Answers f) = factsDefinition f

export
typeOds : TypeDef p -> Lines
typeOds t =
  ["def " ++ typeRecord t ++ " : Idr_Type<" ++ quoted (camelMnemonic t.mnemonic) ++ ", "
     ++ quoted (mnemonicText t.mnemonic) ++ ", [" ++ joinWith ", " (interfaceTraits OverTypes t.interfaces ++ factsTraits t.facts) ++ "]> {"]
  ++ indent 2 (docFields t.doc
               ++ ["let parameters = " ++ dag "ins" (map parameterOds (toList t.params)) ++ ";"]
               ++ syntaxFields t.params t.syntax
               ++ verifierFields t.verifier
               ++ storageFields t.storage
               ++ membersField t.members
               ++ factsFields t.facts)
  ++ ["}", ""]

export
attributeOds : AttrDef p -> Lines
attributeOds x =
  ["def " ++ attrRecord x ++ " : Idr_Attr<" ++ quoted (camelMnemonic x.mnemonic) ++ ", "
     ++ quoted (mnemonicText x.mnemonic) ++ ", [" ++ joinWith ", " (interfaceTraits OverAttributes x.interfaces) ++ "]> {"]
  ++ indent 2 (docFields x.doc
               ++ ["let parameters = " ++ dag "ins" (map (typedParameterOds x.typed) (indexed x.params)) ++ ";"]
               ++ syntaxFields x.params x.syntax
               ++ verifierFields x.verifier
               ++ storageFields x.storage
               ++ membersField x.members)
  ++ ["}", ""]

export
anyTypeOds : AnyTypeDef -> Lines
anyTypeOds (SomeType t) = typeOds t

export
anyAttrOds : AnyAttrDef -> Lines
anyAttrOds (SomeAttr x) = attributeOds x

------------------------------------------------------------------------------
-- Interfaces, traits, resources
------------------------------------------------------------------------------

export
methodOds : InterfaceSubject -> Method -> String
methodOds subject m =
  let kind = case m.binding of
               PerObject => "InterfaceMethod"
               PerClass => "StaticInterfaceMethod"
      self = case subject of
               OverOps => "$_op"
               OverTypes => "$_type"
               OverAttributes => "$_attr"
      args = map (\p => quoted (codeText p.type) ++ ":$" ++ identText p.name) m.params
      callArgs = map (\p => identText p.name) m.params
      given = case m.binding of
                PerObject => self :: callArgs
                PerClass => callArgs
      calls : Ident -> String
      calls fn = ", [{}], [{ return ::idr::" ++ identText fn ++ "(" ++ joinWith ", " given ++ "); }]"
      fallback = case m.fallback of
                   EveryImplementer => ""
                   Delegates fn => calls fn
                   DelegatesByClass fn => calls fn
  in kind ++ "<" ++ quoted (lineText m.doc) ++ ", " ++ quoted (codeText m.result) ++ ", "
       ++ quoted (identText m.name) ++ ", " ++ dag "ins" args ++ fallback ++ ">"

export
interfaceOds : InterfaceDef -> Lines
interfaceOds d =
  let kind = case d.subject of
               OverOps => "OpInterface"
               OverTypes => "TypeInterface"
               OverAttributes => "AttrInterface"
      bases = case d.bases of
                [] => []
                bs => ["let baseInterfaces = [" ++ joinWith ", " (map interfaceRecord bs) ++ "];"]
      verifier = case d.verifier of
                   Unverified => []
                   Verifies fn order =>
                     ["let verify = [{ return ::idr::" ++ identText fn ++ "($_op); }];"]
                     ++ (case order of
                           BeforeRegions => []
                           AfterRegions => ["let verifyWithRegions = 1;"])
      methods = map (methodOds d.subject) d.methods
  in ["def " ++ interfaceRecord d ++ " : " ++ kind ++ "<" ++ quoted (identText d.name) ++ "> {"]
     ++ indent 2 (["let cppNamespace = \"::idr\";"]
                  ++ descriptionField d.doc
                  ++ bases
                  ++ ["let methods = ["]
                  ++ indent 2 (zipWith (++) methods (replicate (pred (length methods)) "," ++ [""]))
                  ++ ["];"]
                  ++ verifier)
     ++ ["}", ""]

export
traitDefOds : TraitDef -> Lines
traitDefOds d =
  slashComment [lineText d.doc.summary]
  ++ ["def " ++ traitRecord d ++ " : NativeOpTrait<" ++ quoted (identText d.name) ++ "> { let cppNamespace = \"::idr\"; }"]

export
resourceOdsDef : ResourceDef -> Lines
resourceOdsDef r = ["def " ++ resourceRecord r ++ " : Resource<" ++ quoted ("::idr::effects::" ++ identText r.name) ++ ">;"]

------------------------------------------------------------------------------
-- The dialect
------------------------------------------------------------------------------

export
dialectOds : DialectDef -> Lines
dialectOds d =
  [ "def " ++ dialectRecord Idr ++ " : Dialect {"
  , "  let name = \"idr\";"
  , "  let cppNamespace = \"::idr\";"
  , "  let summary = " ++ quoted (lineText d.summary) ++ ";" ]
  ++ indent 2 (descriptionField (MkDoc d.summary d.description))
  ++ [ "  let useDefaultTypePrinterParser = 1;"
     , "  let useDefaultAttributePrinterParser = 1;"
     , "  let hasConstantMaterializer = 1;"
     , "  let hasOperationAttrVerify = 1;"
     , "  let hasRegionArgAttrVerify = 1;"
     , "  let dependentDialects = [" ++ joinWith ", " (map (quoted . loadsClass) d.loads) ++ "];" ]
  ++ indent 2 (membersField d.members)
  ++ ["}", ""]

||| The base classes every op, type and attribute of ours is printed
||| against, and the parameter of a hand C++ value, read and written by the
||| custom directive the specification names.
export
baseClasses : Lines
baseClasses =
  [ "class Idr_Op<string mnemonic, list<Trait> traits = []> : Op<" ++ dialectRecord Idr ++ ", mnemonic, traits>;"
  , ""
  , "class Idr_Type<string name, string typeMnemonic, list<Trait> traits = []>"
  , "    : TypeDef<" ++ dialectRecord Idr ++ ", name, traits> {"
  , "  let mnemonic = typeMnemonic;"
  , "}"
  , ""
  , "class Idr_Attr<string name, string attrMnemonic, list<Trait> traits = []>"
  , "    : AttrDef<" ++ dialectRecord Idr ++ ", name, traits> {"
  , "  let mnemonic = attrMnemonic;"
  , "}"
  , ""
  , "// The traits the generator gives ops from their facts: a pure runtime op"
  , "// folds by calling its function, a partial op checks its guards, and a"
  , "// result's uses follow the grade's rule over the given operands."
  , "def Idr_RuntimeFolds : NativeOpTrait<\"RuntimeFolds\"> { let cppNamespace = \"::idr\"; }"
  , "def Idr_GuardedOp : NativeOpTrait<\"GuardedOp\"> { let cppNamespace = \"::idr\"; }"
  , "class Idr_InlineArith<string fn> : ParamNativeOpTrait<\"InlineArith\", fn> {"
  , "  let cppNamespace = \"::idr::numeric\";"
  , "}"
  , "class Idr_ResultUsesMax<string positions> : ParamNativeOpTrait<\"ResultUsesMax\", positions> {"
  , "  let cppNamespace = \"::idr\";"
  , "}"
  , ""
  , "class Idr_HandParameter<string cppType, string directive>"
  , "    : AttrOrTypeParameter<cppType, \"\"> {"
  , "  let parser = \"::idr::parse\" # directive # \"($_parser)\";"
  , "  let printer = \"::idr::print\" # directive # \"($_printer, $_self)\";"
  , "}"
  , ""
  , "// An array of a wire's values: held as a view the storage copies, parsed"
  , "// into the vector that owns them."
  , "class Idr_HandArrayParameter<string element, string directive>"
  , "    : ArrayRefParameter<element, \"\"> {"
  , "  let parser = \"::idr::parse\" # directive # \"($_parser)\";"
  , "  let printer = \"::idr::print\" # directive # \"($_printer, $_self)\";"
  , "}"
  , ""
  , "// A property of a hand class: held as itself, its attribute form, its hash"
  , "// and its bytecode the hooks its directive names, which a hand unit defines."
  , "class Idr_HandProperty<string cppType, string directive, string default, string desc>"
  , "    : Property<cppType, desc> {"
  , "  let convertToAttribute = \"return ::idr::convert\" # directive # \"ToAttribute($_ctxt, $_storage);\";"
  , "  let convertFromAttribute = \"return ::idr::convert\" # directive # \"FromAttribute($_storage, $_attr, $_diag);\";"
  , "  let hashProperty = \"::idr::hash\" # directive # \"($_storage)\";"
  , "  let writeToMlirBytecode = \"::idr::write\" # directive # \"($_writer, $_storage);\";"
  , "  let readFromMlirBytecode = \"if (::mlir::failed(::idr::read\" # directive # \"($_reader, $_storage))) return ::mlir::failure();\";"
  , "  let defaultValue = default;"
  , "}"
  , "" ]

------------------------------------------------------------------------------
-- Passes
------------------------------------------------------------------------------

export
stageName : Stage -> String
stageName s = identText (stageClosed.describe s).name

export
baseClassOf : Pass -> String
baseClassOf p = case requires p.stages of
  Nothing => "::mlir::OperationPass<" ++ anchorClass p.anchor ++ ">"
  Just s => "::idr::StagedPass<DerivedT, " ++ anchorClass p.anchor ++ ", ::idr::Stage::" ++ stageName s
              ++ ", ::idr::Stage::" ++ stageName (leaves p.stages s) ++ ">"

export
statisticOds : Statistic -> String
statisticOds st =
  "Statistic<" ++ quoted (identText st.name) ++ ", " ++ quoted (lineText st.argument) ++ ", " ++ quoted (lineText st.doc) ++ ">"

export
passOds : Pass -> Lines
passOds p =
  let stats = case p.statistics of
                [] => []
                sts => ["let statistics = ["] ++ indent 2 (map (\st => statisticOds st ++ ",") sts) ++ ["];"]
      opts = case p.options of
               NoOptions => []
               Holds => ["let options = [", "  ListOption<\"holds\", \"holds\", \"std::string\", \"The properties that must hold\">,", "];"]
      loads = case p.loads of
                [] => []
                ls => ["let dependentDialects = [" ++ joinWith ", " (map (quoted . loadsClass) ls) ++ "];"]
      made = case p.construction of
               Registered => []
               MadeBy fn args => ["let constructor = " ++ quoted (cppText fn ++ "(" ++ joinWith ", " (map identText args) ++ ")") ++ ";"]
  in ["def " ++ passRecord p ++ " : Pass<" ++ quoted (passArgument p) ++ ", " ++ quoted (anchorClass p.anchor) ++ "> {"]
     ++ indent 2 (docFields p.doc ++ ["let baseClass = " ++ quoted (baseClassOf p) ++ ";"] ++ stats ++ opts ++ loads ++ made)
     ++ ["}", ""]
