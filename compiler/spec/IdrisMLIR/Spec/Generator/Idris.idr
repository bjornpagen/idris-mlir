-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the frontend cannot import from the specification and must have
||| printed: a builder per op it writes, each a plain function typed by its
||| op's groups (a builder generic over the specification's op value would
||| take a type computed from a run-time value of varying representation,
||| which the subset refuses); an encoder per type and attribute, its
||| layout derived from the parameters as the C++ reader's is; and, for a
||| value a wire lays out, its type and its parts, from the wire the C++
||| codec is printed from. Every binder printed is primed, so no keyword or
||| helper name can collide with one.
module IdrisMLIR.Spec.Generator.Idris

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Generator.Render
import IdrisMLIR.Spec.Generator.Ods
import IdrisMLIR.Spec.Generator.Wire
import IdrisMLIR.Spec.Ops.Checks
import IdrisMLIR.Spec.Runtime.Endings

import Data.Fin
import Data.List
import Data.List1
import Data.Vect

%default total

||| A word in lower camel case: `file_time` is `fileTime`.
export
lowerCamel : String -> String
lowerCamel s = case unpack s of
  [] => ""
  (c :: cs) => pack ((if upper c then chr (ord c + 32) else c) :: cs)

||| A binder, primed.
export
primed : Ident -> String
primed i = identText i ++ "'"

------------------------------------------------------------------------------
-- Builders
------------------------------------------------------------------------------

export
operandType : Arity -> String
operandType Single = "Value"
operandType Optional = "Maybe Value"
operandType Variadic = "List Value"
operandType OneOrMore = "List1 Value"

||| A group's operands as a list, over its binder: a group of one or more
||| as its Foldable's list, as an optional group's is, so a guard's check
||| that binds it again to the list of what the checks give reads the same.
export
operandList : Operand -> String
operandList x = case x.arity of
  Single => "[" ++ primed x.name ++ "]"
  Optional => "toList " ++ primed x.name
  Variadic => primed x.name
  OneOrMore => "toList " ++ primed x.name

export
resultType : Arity -> String
resultType Single = "MlirType"
resultType Optional = "Maybe MlirType"
resultType Variadic = "List MlirType"
resultType OneOrMore = "List1 MlirType"

export
resultList : Result -> String
resultList x = case x.arity of
  Single => "[" ++ primed x.name ++ "]"
  Optional => "toList " ++ primed x.name
  Variadic => primed x.name
  OneOrMore => "toList " ++ primed x.name

export
regionType : RegionArity -> String
regionType OneRegion = "Region"
regionType AnyRegions = "List Region"

export
regionList : Region -> String
regionList x = case x.arity of
  OneRegion => "[" ++ primed x.name ++ "]"
  AnyRegions => primed x.name

||| Whether an attribute may be left out: an attribute that may be absent
||| or has a default, or a property with a default, which the writer then
||| leaves at it. A builder takes it as a named argument, nothing when not
||| given.
export
optionalAttr : Attr -> Bool
optionalAttr x = case x.kind of
  AnAttribute _ MayBeAbsent => True
  AnAttribute _ (DefaultValued _) => True
  AnAttribute _ Required => False
  AProperty (EnumProperty _) => False
  AProperty (DefaultedEnumProperty _ _) => True
  AProperty (CountProperty _) => True
  AProperty (HandProperty _ _ _) => True

||| A module's name, its segments joined by dots.
export
moduleName : List1 Ident -> String
moduleName m = joinWith "." (map identText (forget m))

||| A closed set's Idris type, by its full name, so no import can make it
||| ambiguous.
export
enumType : ImportedEnum -> String
enumType e = moduleName e.source.typeHome ++ "." ++ identText e.source.typeName

||| A closed set, by its full name, so no import can make it ambiguous.
export
enumSet : ImportedEnum -> String
enumSet e = moduleName e.source.setHome ++ "." ++ identText e.source.setName

||| A value's position among its closed set's cases, the wire form, as an
||| expression over its binder: the closed set's own order computes it.
export
enumPosition : ImportedEnum -> String -> String
enumPosition e v = "position " ++ enumSet e ++ " " ++ v

||| The case at a position of a closed set, as a printed module writes a
||| value the specification holds: by the position, which the module's type
||| check holds to be one of the set's.
export
caseValue : ImportedEnum -> Nat -> String
caseValue e k = "(caseAt " ++ enumSet e ++ " " ++ decimal k ++ ")"

||| What a module that writes a case by `caseAt` imports: the module that
||| declares it, and those of the names its type check reduces, since Idris
||| loads a module's definitions only where it is imported or re-exported:
||| `Fin`, whose literal the position is, and `forget`, by which the check
||| counts the set's cases to hold the position one of them. Both printers
||| of builders read it, this one directly and idris-mlir-tblgen from the
||| guard's admitted record, so neither restates what `caseAt` needs.
export
caseImports : List String
caseImports = ["IdrisMLIR.Spec.Core.Enums", "Data.Fin", "Data.List1"]

||| What a builder takes for an attribute: the attribute, as made; or, for
||| an enum property, its case, typed, which the builder encodes as the
||| property's storage holds it, so no caller spells a width or a number.
data AttrValue = AsAttribute | AsCase ImportedEnum

attrValueOf : Attr -> AttrValue
attrValueOf x = case x.kind of
  AProperty (EnumProperty e) => AsCase e
  AProperty (DefaultedEnumProperty e _) => AsCase e
  _ => AsAttribute

||| The attribute a value of `v` makes, as an expression over its binder: an
||| enum's case as the module's `enumAttr` encodes one.
madeFrom : AttrValue -> String -> String
madeFrom AsAttribute v = v
madeFrom (AsCase e) v = "enumAttr " ++ enumSet e ++ " " ++ v

||| The same, as a function.
maker : AttrValue -> String
maker AsAttribute = "id"
maker (AsCase e) = "(enumAttr " ++ enumSet e ++ ")"

valueType : AttrValue -> String
valueType AsAttribute = "MlirAttr"
valueType (AsCase e) = enumType e

export
attrPair : Attr -> String
attrPair x =
  if optionalAttr x
    then "attrIf " ++ quoted (identText x.name) ++ " " ++ maker (attrValueOf x) ++ " " ++ primed x.name
    else "[(" ++ quoted (identText x.name) ++ ", " ++ madeFrom (attrValueOf x) (primed x.name) ++ ")]"

export
attrType : Attr -> String
attrType x = if optionalAttr x then "Maybe " ++ valueType (attrValueOf x) else valueType (attrValueOf x)

export
concatList : List String -> String
concatList [] = "[]"
concatList [x] = x
concatList xs = joinWith " ++ " xs

||| How many operands a group holds, as an expression over its binder.
export
groupLength : Operand -> String
groupLength x = case x.arity of
  Single => "1"
  Optional => "length (toList " ++ primed x.name ++ ")"
  Variadic => "length " ++ primed x.name
  OneOrMore => "length (toList " ++ primed x.name ++ ")"

||| How many results a group holds, as an expression over its binder.
export
resultLength : Result -> String
resultLength x = case x.arity of
  Single => "1"
  Optional => "length (toList " ++ primed x.name ++ ")"
  Variadic => "length " ++ primed x.name
  OneOrMore => "length (toList " ++ primed x.name ++ ")"

||| The segment sizes an op's groups call for, as attribute pairs: each
||| group's size, where more than one group may hold any number.
export
segmentPairs : Op i o a r -> List String
segmentPairs op =
  stated (segmentsOf (map (.arity) (toList op.ins))) "operandSegmentSizes" (map groupLength (toList op.ins))
  ++ stated (segmentsOf (map (.arity) (toList op.outs))) "resultSegmentSizes" (map resultLength (toList op.outs))
  where
    stated : Segments -> String -> List String -> List String
    stated FixedByCount _ _ = []
    stated SizesStated key lengths = ["[(" ++ quoted key ++ ", DenseI32ArrayAttr [" ++ joinWith ", " lengths ++ "])]"]

||| An op's name as the frontend holds it: the dialect it is defined in,
||| by the specification's value, and its name there.
export
opNameOf : Op i o a r -> String
opNameOf op =
  "(MkOpName Dialect." ++ identText (dialectName (homeDialect op.home)) ++ " " ++ quoted (mnemonicText op.mnemonic) ++ ")"

||| An expression as an argument: in parentheses where it is more than one
||| word.
argument : String -> String
argument e = if any (== ' ') (unpack e) then "(" ++ e ++ ")" else e

||| The indentation of a body's line `depth` guards in.
padding : Nat -> String
padding depth = pack (replicate (2 + 2 * depth) ' ')

||| A partial op's body, `depth` guards in: each guard written as the check
||| of the operand group it is given first, against the groups it is given
||| after, its continuation binding that group's binder again to what the
||| check gives, so every later guard and the op itself take the checked
||| value; then the op `made`. A group of one operand is checked by
||| `Checking`; one that holds any number, or none, by `checkingEach`,
||| operand by operand against the same others, its binder then the list of
||| what the checks give, which the op's operand list and a later guard
||| read as a group's operands either way.
guardedLines : Nat -> Vect i Operand -> List (Guard (Fin i)) -> String -> Lines
guardedLines depth ins [] made = [padding depth ++ "Unguarded (" ++ made ++ ")" ++ pack (replicate depth ')')]
guardedLines depth ins (g :: gs) made =
  let checked = index (Vect.head g.given) ins
      others = argument (concatList (map (\k => operandList (index k ins)) (toList (Vect.tail g.given))))
      check = opNameOf (guardOpOf g.check)
      cause = caseValue causeEnum (position causeClosed g.cause)
      binder = primed checked.name
      opening = case checked.arity of
                  Single => "Checking " ++ check ++ " " ++ cause ++ " " ++ binder
                  Optional => "checkingEach " ++ check ++ " " ++ cause ++ " (toList " ++ binder ++ ")"
                  Variadic => "checkingEach " ++ check ++ " " ++ cause ++ " " ++ binder
                  OneOrMore => "checkingEach " ++ check ++ " " ++ cause ++ " (toList " ++ binder ++ ")"
  in (padding depth ++ opening ++ " " ++ others ++ " (\\" ++ binder ++ " =>")
     :: guardedLines (S depth) ins gs made

||| The Idris type a fixed result's type is.
builtIdris : Buildable -> String
builtIdris BuiltI1 = "IntegerType 1"
builtIdris BuiltI8 = "IntegerType 8"
builtIdris BuiltI16 = "IntegerType 16"
builtIdris BuiltI32 = "IntegerType 32"
builtIdris BuiltI64 = "IntegerType 64"
builtIdris BuiltIndex = "IndexType"
builtIdris BuiltF64 = "F64Type"
builtIdris BuiltNone = "NoneType"

||| A result's type as its rule computes it from the operands' binders: an
||| operand's type, its element type or itself (as upstream's
||| `getElementTypeOrSelf` gives it), or the fixed type.
typeByRule : Vect i Operand -> TypeRule i -> String
typeByRule ins (OperandType g) = primed (index g ins).name ++ ".type"
typeByRule ins (ElementTypeOf g) = "elementTypeOrSelf " ++ primed (index g ins).name ++ ".type"
typeByRule _ (FixedType b) = builtIdris b

||| The result groups an op's builder is given, and its results' types: each
||| group's binder where they are stated; none, where every type is fixed by
||| its rule, which computes it.
resultsOf : Op i o a r -> (List Result, String)
resultsOf op = case op.typing of
  StatedTypes => (toList op.outs, concatList (map resultList (toList op.outs)))
  InferredTypes rules => ([], concatList (map (\rule => "[" ++ typeByRule op.ins rule ++ "]") (toList rules)))

||| An op's builder: one argument per required attribute, operand group,
||| region group and result group whose types are stated, in that order,
||| each attribute that may be left out a named argument, nothing unless
||| given; and the op it makes. A partial op's builder gives its guards with
||| it, each before the op as a guard to write and what follows given its
||| result, so it is never placed without them.
export
builder : Op i o a r -> Lines
builder op =
  let name = lowerCamel (camelMnemonic op.mnemonic) ++ "Op"
      attrs = toList op.attrs
      ins = toList op.ins
      regions = toList op.regions
      (outs, resultTypes) = resultsOf op
      required = filter (not . optionalAttr) attrs
      optional = filter optionalAttr attrs
      binders = map (\x => "{" ++ primed x.name ++ "}") optional
                ++ map (\x => primed x.name) required ++ map (\x => primed x.name) ins
                ++ map (\x => primed x.name) regions ++ map (\x => primed x.name) outs
      implicits = map (\x => "{default Nothing " ++ primed x.name ++ " : " ++ attrType x ++ "}") optional
      types = implicits ++ map attrType required ++ map (\x => operandType x.arity) ins
              ++ map (\x => regionType x.arity) regions ++ map (\x => resultType x.arity) outs
      made = "MkOp " ++ opNameOf op ++ " (" ++ concatList (map operandList ins) ++ ") ("
             ++ concatList (map attrPair attrs ++ segmentPairs op) ++ ") (" ++ concatList (map regionList regions) ++ ") [] ("
             ++ resultTypes ++ ")"
      (resultTy, body) = the (String, Lines) $ case op.guards of
                           [] => ("Op", ["  " ++ made])
                           gs => ("Guarded", guardedLines 0 op.ins gs made)
  in barComment ["`" ++ opName op ++ "`: " ++ lineText op.doc.summary]
     ++ ["export", name ++ " : " ++ joinWith " -> " (types ++ [resultTy])]
     ++ [name ++ spaced binders ++ " ="] ++ body ++ [""]

||| Whether the frontend may write a form legal at `stages`: they include
||| the frontend's. What it may write of an op, a type, an attribute and a
||| variant's alternative is printed for it, and nothing else.
export
writes : Legal -> Bool
writes stages = legalAt stages Higher

||| Whether the frontend writes the op.
export
written : AnyOp -> Bool
written (SomeOp op) = writes op.stages

||| Whether the frontend writes the type, or the attribute.
typeWritten : AnyTypeDef -> Bool
typeWritten (SomeType t) = writes t.stages

attrWritten : AnyAttrDef -> Bool
attrWritten (SomeAttr x) = writes x.stages

||| The modules an op's enum properties' closed sets live in, and its
||| guards' causes', as its builder names their types and values.
propertyHomes : AnyOp -> List String
propertyHomes (SomeOp op) =
  concatMap homes (toList op.attrs)
  ++ (case op.guards of
        [] => []
        _ => homesOf causeEnum)
  where
    homesOf : ImportedEnum -> List String
    homesOf e = [moduleName e.source.typeHome, moduleName e.source.setHome]
    homes : Attr -> List String
    homes x = case attrValueOf x of
      AsCase e => homesOf e
      AsAttribute => []

||| The builders of every op the frontend writes, as one module. A partial
||| op's builder gives `Guarded`, which the frontend declares with its ops,
||| and writes its guards' causes by `caseAt`, so the module imports what
||| that names; `enumAttr` names the closed set and its positions.
export
buildersModule : List AnyOp -> Lines
buildersModule ops =
  let writtenOps = filter written ops
      homes = [ "IdrisMLIR.MLIR", "IdrisMLIR.Spec.Core.Dialect", "IdrisMLIR.Spec.Core.Enums" ]
              ++ concatMap propertyHomes writtenOps ++ caseImports
  in banner (map (\l => "-- " ++ l))
     ++ barComment ["The idr dialect's ops the frontend writes, one builder each, printed"
                   , "from the dialect's specification."]
     ++ [ "module IdrisMLIR.Dialect.Idr", "" ]
     ++ map ("import " ++) (once [] homes)
     ++ [ ""
        , "import Data.List", ""
        , "%default total", "" ]
     ++ barComment [ "A case of a closed set as an enum property holds it, and as a guard's"
                   , "check names its cause: its position, at the width every enum of the"
                   , "dialect is stored at. Every builder encodes a case by it, and so does"
                   , "the writer of a guard's check." ]
     ++ [ "export", "enumAttr : Closed a -> a -> MlirAttr"
        , "enumAttr set x = IntegerAttr (natToInteger (position set x)) (OfWidth " ++ decimal enumBits ++ ")", "" ]
     ++ concatMap (\(SomeOp op) => builder op) writtenOps
  where
    once : List String -> List String -> List String
    once _ [] = []
    once seen (m :: ms) = if elem m seen then once seen ms else m :: once (m :: seen) ms

------------------------------------------------------------------------------
-- Wires
------------------------------------------------------------------------------

||| A leaf's Idris type, over what the types `ty` and attributes `at` it
||| holds are.
export
leafIdris : Leaf -> (ty, at : String) -> String
leafIdris LeafCount _ _ = "Nat"
leafIdris LeafWord32 _ _ = "Nat"
leafIdris (LeafCase e) _ _ = enumType e
leafIdris LeafLabel _ _ = "String"
leafIdris (LeafType _) ty _ = ty
leafIdris (LeafAttr _) _ at = at
leafIdris (LeafMaybeAttr _) _ at = "Maybe " ++ at

||| A wire's Idris type: a composite's is the type printed for it.
export
wireIdris : Wire -> (ty, at : String) -> String
wireIdris (WireLeaf l) ty at = leafIdris l ty at
wireIdris (WireArray w) ty at = "List (" ++ wireIdris w ty at ++ ")"
wireIdris (WireOf c) ty at = identText (compositeName c) ++ " " ++ ty ++ " " ++ at

export
wiredIdris : Wired -> (ty, at : String) -> String
wiredIdris (WiredArray w) ty at = "List (" ++ wireIdris w ty at ++ ")"
wiredIdris (WiredOne l) ty at = leafIdris l ty at
wiredIdris (WiredOf c) ty at = wireIdris (WireOf c) ty at

||| A leaf's parts, as an expression over its binder: as the C++ reader
||| reads it.
export
leafParts : Leaf -> String -> String
leafParts LeafCount v = "[VarInt " ++ v ++ "]"
leafParts LeafWord32 v = "[VarInt " ++ v ++ "]"
leafParts (LeafCase e) v = "[VarInt (" ++ enumPosition e v ++ ")]"
leafParts LeafLabel v = "[Str " ++ v ++ "]"
leafParts (LeafType _) v = "[TypeAt " ++ v ++ "]"
leafParts (LeafAttr _) v = "[AttrAt " ++ v ++ "]"
leafParts (LeafMaybeAttr _) v = "[OptionalAttrAt " ++ v ++ "]"

||| A wire's parts: an array's count, then each element's.
export
wireParts : Wire -> String -> String
wireParts (WireLeaf l) v = leafParts l v
wireParts (WireArray w) v = "(VarInt (length " ++ v ++ ") :: concatMap (\\x' => " ++ wireParts w "x'" ++ ") " ++ v ++ ")"
wireParts (WireOf c) v = "parts" ++ identText (compositeName c) ++ " " ++ v

export
wiredParts : Wired -> String -> String
wiredParts (WiredArray w) v = wireParts (WireArray w) v
wiredParts (WiredOne l) v = leafParts l v
wiredParts (WiredOf c) v = wireParts (WireOf c) v

||| A constructor's pattern over its binders, primed: its name alone, or in
||| parentheses with them.
patternOf : String -> List String -> String
patternOf con [] = con
patternOf con bs = "(" ++ con ++ spaced (map (++ "'") bs) ++ ")"

||| Parts joined, none an empty list.
partsJoined : List String -> String
partsJoined [] = "[]"
partsJoined ps = joinWith " ++ " ps

||| One case of a composite as the frontend holds it: its constructor, the
||| fields it holds (each binder and wire), the case's position in the
||| closed set where the composite has one, and what it is.
record Shape where
  constructor MkShape
  con : String
  holds : List (String, Wire)
  place : Maybe Nat
  about : Line

||| A field as a shape holds it: its member's name, which its binder takes
||| primed, and its wire.
fieldOf : WireField -> (String, Wire)
fieldOf f = (identText (fieldName f), fieldWire f)

||| The cases of a composite's body as the frontend holds them: a struct
||| one constructor, `Mk<Name>`; a flat struct one constructor per case,
||| `<Name><Case>`; a variant one per case the frontend writes, at its
||| position among all, holding its alternative, by the alternative's name
||| in lower camel case.
shapesOf : String -> Doc -> CompositeBody -> List Shape
shapesOf name doc (Fields fs) = [MkShape ("Mk" ++ name) (map fieldOf fs) Nothing doc.summary]
shapesOf name _ (Flat e _ cases) =
  map (\(n, (c, fs)) => MkShape (name ++ identText c.name) (map fieldOf fs) (Just n) c.doc)
      (numbered (zip (forget e.cases) cases))
shapesOf name _ (Variant e alternatives) =
  map (\(n, (c, alternative)) =>
        MkShape (name ++ identText c.name)
                [(lowerCamel (identText (compositeName alternative)), WireOf alternative)] (Just n) c.doc)
      (mapMaybe writtenCase (numbered (zip (forget e.cases) alternatives)))
  where
    writtenCase : (Nat, (Case, Alternative)) -> Maybe (Nat, (Case, Composite))
    writtenCase (n, (c, MkAlternative stages alternative)) =
      if writes stages then Just (n, (c, alternative)) else Nothing

||| A composite as the frontend holds it: a type over the types `ty` and
||| attributes `at` it holds, one constructor per case.
compositeData : Composite -> Lines
compositeData (MkComposite n _ body doc) =
  let name = identText n
  in barComment [lineText doc.summary]
     ++ ["public export", "data " ++ name ++ " : (ty : Type) -> (at : Type) -> Type where"]
     ++ concatMap (shapeLine name) (shapesOf name doc body)
     ++ [""]
  where
    shapeLine : String -> Shape -> Lines
    shapeLine name sh =
      map ("  " ++) (barComment [lineText sh.about])
      ++ ["  " ++ sh.con ++ " : "
          ++ joinWith " -> " (map (\(b, w) => "(" ++ b ++ "' : " ++ wireIdris w "ty" "at" ++ ")") sh.holds
                             ++ [name ++ " ty at"])]

||| A composite's parts, its types and attributes by their entries: the
||| case's position where it has one, then each field's, as the C++ reader
||| reads them.
compositeParts : Composite -> Lines
compositeParts (MkComposite n _ body doc) =
  let name = identText n
  in barComment ["The parts of a `" ++ name ++ "`, its types and attributes by their entries."]
     ++ ["export", "parts" ++ name ++ " : " ++ name ++ " TypeRef AttrRef -> List Part"]
     ++ map (clause name) (shapesOf name doc body)
     ++ [""]
  where
    clause : String -> Shape -> String
    clause name sh =
      "parts" ++ name ++ " " ++ patternOf sh.con (map fst sh.holds) ++ " = "
      ++ partsJoined (maybe [] (\k => ["[VarInt " ++ decimal k ++ "]"]) sh.place
                      ++ map (\(b, w) => wireParts w (b ++ "'")) sh.holds)

mutual
  ||| The modules the closed sets of a wire's leaves live in, as the
  ||| frontend's types of them name them and their positions are computed.
  wireHomes : Wire -> List String
  wireHomes (WireLeaf l) = leafHomes l
  wireHomes (WireArray w) = wireHomes w
  wireHomes (WireOf _) = []

  leafHomes : Leaf -> List String
  leafHomes (LeafCase e) = [moduleName e.source.typeHome, moduleName e.source.setHome]
  leafHomes _ = []

||| The modules a composite's own fields name, each once.
compositeHomes : List Composite -> List String
compositeHomes cs = nub (concatMap homes cs)
  where
    fieldsHomes : List (String, Wire) -> List String
    fieldsHomes = concatMap (\(_, w) => wireHomes w)
    homes : Composite -> List String
    homes (MkComposite n _ b d) = concatMap (\sh => fieldsHomes sh.holds) (shapesOf (identText n) d b)

||| The frontend's side of every composite the parameters of the types and
||| attributes it writes reach through the alternatives it writes: its type
||| and its parts, each composite after every one it holds.
export
wireModule : List AnyTypeDef -> List AnyAttrDef -> Lines
wireModule ts as =
  let cs = compositesOf writes (filter typeWritten ts) (filter attrWritten as)
  in banner (map (\l => "-- " ++ l))
     ++ barComment [ "The values the idr dialect's types and attributes the frontend writes"
                   , "hold that a wire of the specification lays out: each one's type, over"
                   , "what the types `ty` and attributes `at` it holds are, one constructor"
                   , "per case the frontend writes, and its parts, as the dialect's C++"
                   , "reader reads them. Printed from the dialect's specification." ]
     ++ [ "module IdrisMLIR.Encoding.Wire", "", "import IdrisMLIR.MLIR.Parts", "import IdrisMLIR.Spec.Core.Enums" ]
     ++ map ("import " ++) (compositeHomes cs)
     ++ [ "", "%default total", "" ]
     ++ concatMap (\c => compositeData c ++ compositeParts c) cs

export
paramIdrisType : ParamKind -> String
paramIdrisType TypeValue = "TypeRef"
paramIdrisType AttrValue = "AttrRef"
paramIdrisType (EnumValue e) = enumType e
paramIdrisType (OptionalCase e _) = "Maybe " ++ enumType e
paramIdrisType StringValue = "String"
paramIdrisType IntegerValue = "Integer"
paramIdrisType CountValue = "Nat"
paramIdrisType (ListOf k) = "List (" ++ paramIdrisType k ++ ")"
paramIdrisType (WiredValue w _) = wiredIdris w "TypeRef" "AttrRef"

||| The parts of a value of a parameter's kind, as an expression over its
||| binder.
export
partsOf : ParamKind -> String -> String
partsOf TypeValue v = "[TypeAt " ++ v ++ "]"
partsOf AttrValue v = "[AttrAt " ++ v ++ "]"
partsOf (EnumValue e) v = "[VarInt (" ++ enumPosition e v ++ ")]"
partsOf (OptionalCase e _) v = "[VarInt (maybe 0 (\\x' => S (" ++ enumPosition e "x'" ++ ")) " ++ v ++ ")]"
partsOf StringValue v = "[Str " ++ v ++ "]"
partsOf IntegerValue v = "[IntegerAt " ++ v ++ "]"
partsOf CountValue v = "[VarInt " ++ v ++ "]"
partsOf (ListOf k) v = "(VarInt (length " ++ v ++ ") :: concatMap (\\x' => " ++ partsOf k "x'" ++ ") " ++ v ++ ")"
partsOf (WiredValue w _) v = wiredParts w v

export
encoder : String -> Nat -> String -> List Parameter -> Lines
encoder kind code cls params =
  let stem = lowerCamel cls
      binders = map (\x => primed x.name) params
      types = map (\x => paramIdrisType x.kind) params
      parts = ("[VarInt " ++ stem ++ "Code]") :: map (\x => partsOf x.kind (primed x.name)) params
  in barComment ["The code of `" ++ cls ++ "`, its place among the dialect's " ++ kind ++ "."]
     ++ ["export", stem ++ "Code : Nat", stem ++ "Code = " ++ decimal code, ""]
     ++ barComment ["The parts of `" ++ cls ++ "`: its code, then each parameter."]
     ++ ["export", "encode" ++ cls ++ " : " ++ joinWith " -> " (types ++ ["List Part"])]
     ++ ["encode" ++ cls ++ spaced binders ++ " = " ++ joinWith " ++ " parts, ""]

export
numberedFrom : Nat -> List a -> List (Nat, a)
numberedFrom _ [] = []
numberedFrom n (x :: xs) = (n, x) :: numberedFrom (S n) xs

||| A parameter's field in a value sum, the types it holds `ty` and the
||| attributes `at`, which the writer turns into entries.
fieldType : ParamKind -> String
fieldType TypeValue = "ty"
fieldType AttrValue = "at"
fieldType (EnumValue e) = enumType e
fieldType (OptionalCase e _) = "Maybe " ++ enumType e
fieldType StringValue = "String"
fieldType IntegerValue = "Integer"
fieldType CountValue = "Nat"
fieldType (ListOf k) = "List (" ++ fieldType k ++ ")"
fieldType (WiredValue w _) = wiredIdris w "ty" "at"

||| One constructor of a value sum, named for its C++ class.
constructorOf : String -> String -> List Parameter -> String
constructorOf sum cls params =
  "  " ++ cls ++ " : " ++ joinWith " -> " (map (\x => "(" ++ primed x.name ++ " : " ++ fieldType x.kind ++ ")") params ++ [sum ++ " ty at"])

||| A value sum: the dialect's types or attributes, one constructor each,
||| over the types and attributes they hold.
valueSum : String -> String -> List (String, List Parameter) -> Lines
valueSum sum noun defs =
  barComment ["The dialect's " ++ noun ++ ", one constructor each, named for its C++ class;"
             , "`ty` and `at` are what the types and attributes they hold are."]
  ++ ["public export", "data " ++ sum ++ " : (ty : Type) -> (at : Type) -> Type where"]
  ++ map (\(cls, ps) => constructorOf sum cls ps) defs
  ++ [""]

||| The encoder of a value of a sum: each constructor's own encoder, its
||| types and attributes their entries.
encodeSum : String -> List (String, List Parameter) -> Lines
encodeSum sum defs =
  barComment ["The parts of a value of `" ++ sum ++ "`, its types and attributes by their entries."]
  ++ ["export", "encode" ++ sum ++ " : " ++ sum ++ " TypeRef AttrRef -> List Part"]
  ++ map clause defs
  ++ [""]
  where
    clause : (String, List Parameter) -> String
    clause (cls, ps) =
      "encode" ++ sum ++ " (" ++ cls ++ spaced (map (\x => primed x.name) ps) ++ ") = encode" ++ cls ++ spaced (map (\x => primed x.name) ps)

||| The mnemonics of a value sum's constructors, as a list in declaration
||| order and by value: the frontend's syntax samples check every one is
||| sampled, as they check the upstream dialects' sums.
mnemonicsOf : (sum, stem, noun : String) -> List (String, String, List Parameter) -> Lines
mnemonicsOf sum stem noun defs =
  barComment ["The mnemonics of the dialect's " ++ noun ++ ", in declaration order."]
  ++ [ "export", stem ++ "Mnemonics : List String"
     , stem ++ "Mnemonics = [" ++ joinWith ", " (map (\(_, m, _) => quoted m) defs) ++ "]", "" ]
  ++ barComment ["The mnemonic of each of the dialect's " ++ noun ++ "."]
  ++ ["export", stem ++ "Mnemonic : " ++ sum ++ " ty at -> String"]
  ++ map clause defs
  ++ [""]
  where
    pattern : String -> List Parameter -> String
    pattern cls [] = cls
    pattern cls ps = "(" ++ cls ++ spaced (map (const "_") ps) ++ ")"
    clause : (String, String, List Parameter) -> String
    clause (cls, m, ps) = stem ++ "Mnemonic " ++ pattern cls ps ++ " = " ++ quoted m

||| The modules the closed sets of the parameters live in, each once: what
||| the encoders import to name their types and compute their positions.
export
enumModules : List Parameter -> List String
enumModules ps = go [] (concatMap (\x => homes x.kind) ps)
  where
    homes : ParamKind -> List String
    homes (EnumValue e) = [moduleName e.source.typeHome, moduleName e.source.setHome]
    homes (OptionalCase e _) = [moduleName e.source.typeHome, moduleName e.source.setHome]
    homes (ListOf k) = homes k
    homes (WiredValue (WiredOne l) _) = leafHomes l
    homes (WiredValue (WiredArray w) _) = wireHomes w
    homes (WiredValue (WiredOf c) _) = wireHomes (WireOf c)
    homes _ = []
    go : List String -> List String -> List String
    go _ [] = []
    go seen (m :: ms) = if elem m seen then go seen ms else m :: go (m :: seen) ms

||| A type or an attribute as its encoder is printed: its C++ class, its
||| mnemonic, its parameters and the stages it may stand at.
record Form where
  constructor MkForm
  cls : String
  mnemonic : String
  params : List Parameter
  stages : Legal

typeForm : AnyTypeDef -> Form
typeForm (SomeType t) = MkForm (typeClass t) (mnemonicText t.mnemonic) (toList t.params) t.stages

attrForm : AnyAttrDef -> Form
attrForm (SomeAttr x) = MkForm (attrClass x) (mnemonicText x.mnemonic) (toList x.params) x.stages

||| The forms the frontend writes, each with its code, its place among all
||| of them, as the C++ reader numbers them.
writtenForms : List Form -> List (Nat, Form)
writtenForms fs = filter (\(_, f) => writes f.stages) (numberedFrom 0 fs)

||| Forms as a value sum takes them: each one's class and parameters.
sumOf : List (Nat, Form) -> List (String, List Parameter)
sumOf = map (\(_, f) => (f.cls, f.params))

||| Forms as their mnemonics are printed: each one's class, mnemonic and
||| parameters.
namedForms : List (Nat, Form) -> List (String, String, List Parameter)
namedForms = map (\(_, f) => (f.cls, f.mnemonic, f.params))

||| The value sums and encoders of the types and attributes the frontend
||| writes.
export
encodersModule : List AnyTypeDef -> List AnyAttrDef -> Lines
encodersModule ts as =
  let types = writtenForms (map typeForm ts)
      attrs = writtenForms (map attrForm as)
      modules = enumModules (concatMap (\(_, f) => f.params) (types ++ attrs))
  in banner (map (\l => "-- " ++ l))
     ++ barComment ["The idr dialect's types and attributes the frontend writes: their"
                   , "value sums, a closed set's value typed, their mnemonics, and each"
                   , "one's bytecode entry, its code its place among all of the dialect's"
                   , "and its layout derived from its parameters as the C++ reader's is, a"
                   , "closed set's value written as its position; printed from the"
                   , "dialect's specification."]
     ++ [ "module IdrisMLIR.Encoding.Idr", "", "import IdrisMLIR.MLIR.Parts"
        , "import IdrisMLIR.Encoding.Wire"
        , "import IdrisMLIR.Spec.Core.Enums" ]
     ++ map ("import " ++) modules
     ++ [ "", "%default total", "" ]
     ++ valueSum "IdrType" "types" (sumOf types)
     ++ valueSum "IdrAttr" "attributes" (sumOf attrs)
     ++ mnemonicsOf "IdrType" "idrType" "types" (namedForms types)
     ++ mnemonicsOf "IdrAttr" "idrAttr" "attributes" (namedForms attrs)
     ++ concatMap (\(n, f) => encoder "types" n f.cls f.params) types
     ++ concatMap (\(n, f) => encoder "attributes" n f.cls f.params) attrs
     ++ encodeSum "IdrType" (sumOf types)
     ++ encodeSum "IdrAttr" (sumOf attrs)
