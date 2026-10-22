-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the frontend cannot import from the specification and must have
||| printed: a builder per op it writes, each a plain function typed by its
||| op's groups (a builder generic over the specification's op value would
||| take a type computed from a run-time value of varying representation,
||| which the subset refuses), and an encoder per type and attribute, its
||| layout derived from the parameters as the C++ reader's is. Every binder
||| printed is primed, so no keyword or helper name can collide with one.
module IdrisMLIR.Spec.Generator.Idris

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Generator.Render
import IdrisMLIR.Spec.Generator.Ods

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

export
operandList : Operand -> String
operandList x = case x.arity of
  Single => "[" ++ primed x.name ++ "]"
  Optional => "toList " ++ primed x.name
  Variadic => primed x.name

export
resultType : Arity -> String
resultType Single = "MlirType"
resultType Optional = "Maybe MlirType"
resultType Variadic = "List MlirType"

export
resultList : Result -> String
resultList x = case x.arity of
  Single => "[" ++ primed x.name ++ "]"
  Optional => "toList " ++ primed x.name
  Variadic => primed x.name

export
regionType : RegionArity -> String
regionType OneRegion = "Region"
regionType AnyRegions = "List Region"

export
regionList : Region -> String
regionList x = case x.arity of
  OneRegion => "[" ++ primed x.name ++ "]"
  AnyRegions => primed x.name

export
attrPair : Attr -> String
attrPair x = case x.kind of
  AnAttribute _ MayBeAbsent => "attrIf " ++ quoted (identText x.name) ++ " id " ++ primed x.name
  AnAttribute _ (DefaultValued _) => "attrIf " ++ quoted (identText x.name) ++ " id " ++ primed x.name
  _ => "[(" ++ quoted (identText x.name) ++ ", " ++ primed x.name ++ ")]"

||| Whether an attribute may be left out: a builder takes it as a named
||| argument, nothing when not given.
export
optionalAttr : Attr -> Bool
optionalAttr x = case x.kind of
  AnAttribute _ MayBeAbsent => True
  AnAttribute _ (DefaultValued _) => True
  _ => False

export
attrType : Attr -> String
attrType x = case x.kind of
  AnAttribute _ MayBeAbsent => "Maybe MlirAttr"
  AnAttribute _ (DefaultValued _) => "Maybe MlirAttr"
  _ => "MlirAttr"

export
concatList : List String -> String
concatList [] = "[]"
concatList [x] = x
concatList xs = joinWith " ++ " xs

||| The position of a case among its enum's cases: its number.
export
caseNumber : CaseRef -> Nat
caseNumber c = go 0 (forget c.enum.cases)
  where
    go : Nat -> List Case -> Nat
    go n [] = n
    go n (x :: xs) = if x.name == c.name then n else go (S n) xs

export
guardRow : Guard i -> String
guardRow g =
  "MkGuard " ++ quoted ("idr." ++ mnemonicText g.check) ++ " [" ++ joinWith ", " (map (decimal . finToNat) (forget g.given))
    ++ "] " ++ decimal (caseNumber g.cause)

||| An op's builder: one argument per required attribute, operand group,
||| region group and result group, in that order, each attribute that may
||| be left out a named argument, nothing unless given; and the op it
||| makes. A partial op's builder gives its guards with it, so it is never
||| placed without them.
export
builder : Op i o a r -> Lines
builder op =
  let name = lowerCamel (camelMnemonic op.mnemonic) ++ "Op"
      attrs = toList op.attrs
      ins = toList op.ins
      regions = toList op.regions
      outs = toList op.outs
      required = filter (not . optionalAttr) attrs
      optional = filter optionalAttr attrs
      binders = map (\x => "{" ++ primed x.name ++ "}") optional
                ++ map (\x => primed x.name) required ++ map (\x => primed x.name) ins
                ++ map (\x => primed x.name) regions ++ map (\x => primed x.name) outs
      implicits = map (\x => "{default Nothing " ++ primed x.name ++ " : Maybe MlirAttr}") optional
      types = implicits ++ map attrType required ++ map (\x => operandType x.arity) ins
              ++ map (\x => regionType x.arity) regions ++ map (\x => resultType x.arity) outs
      made = "MkOp " ++ quoted (opName op) ++ " (" ++ concatList (map operandList ins) ++ ") ("
             ++ concatList (map attrPair attrs) ++ ") (" ++ concatList (map regionList regions) ++ ") [] ("
             ++ concatList (map resultList outs) ++ ")"
      (resultTy, body) = case op.guards of
                           [] => ("Op", made)
                           gs => ("Guarded", "MkGuarded (" ++ made ++ ") [" ++ joinWith ", " (map guardRow gs) ++ "]")
  in barComment ["`" ++ opName op ++ "`: " ++ lineText op.doc.summary]
     ++ ["export", name ++ " : " ++ joinWith " -> " (types ++ [resultTy])]
     ++ [name ++ spaced binders ++ " =", "  " ++ body, ""]

||| Whether the frontend writes the op: its stages include the frontend's.
export
written : AnyOp -> Bool
written (SomeOp op) = legalAt op.stages Higher

||| The builders of every op the frontend writes, as one module.
export
buildersModule : List AnyOp -> Lines
buildersModule ops =
  banner (map (\l => "-- " ++ l))
  ++ barComment ["The idr dialect's ops the frontend writes, one builder each, printed"
                , "from the dialect's specification."]
  ++ [ "module IdrisMLIR.Dialect.Idr", ""
     , "import IdrisMLIR.MLIR", ""
     , "import Data.Fin", "import Data.List", ""
     , "%default total", "" ]
  ++ barComment ["A guard a partial op takes, built before it: the guard op's name, the"
                , "positions of the op's operands it is given (the one it guards first),"
                , "and the number of the cause its crash names."]
  ++ [ "public export", "record Guard where", "  constructor MkGuard", "  check : String", "  given : List Nat", "  cause : Nat", "" ]
  ++ barComment ["An op and the guards placed before it."]
  ++ [ "public export", "record Guarded where", "  constructor MkGuarded", "  op : Op", "  guards : List Guard", "" ]
  ++ concatMap (\(SomeOp op) => builder op) (filter written ops)

------------------------------------------------------------------------------
-- Encoders
------------------------------------------------------------------------------

export
paramIdrisType : ParamKind -> String
paramIdrisType TypeValue = "TypeRef"
paramIdrisType AttrValue = "AttrRef"
paramIdrisType (EnumValue _) = "Nat"
paramIdrisType StringValue = "String"
paramIdrisType IntegerValue = "Integer"
paramIdrisType CountValue = "Nat"
paramIdrisType (ListOf k) = "List (" ++ paramIdrisType k ++ ")"
paramIdrisType (HandValue _ _) = "List Part"

||| The parts of a value of a parameter's kind, as an expression over its
||| binder.
export
partsOf : ParamKind -> String -> String
partsOf TypeValue v = "[TypeAt " ++ v ++ "]"
partsOf AttrValue v = "[AttrAt " ++ v ++ "]"
partsOf (EnumValue _) v = "[VarInt " ++ v ++ "]"
partsOf StringValue v = "[Str " ++ v ++ "]"
partsOf IntegerValue v = "[SignedVarInt " ++ v ++ "]"
partsOf CountValue v = "[VarInt " ++ v ++ "]"
partsOf (ListOf k) v = "(VarInt (length " ++ v ++ ") :: concatMap (\\x' => " ++ partsOf k "x'" ++ ") " ++ v ++ ")"
partsOf (HandValue _ _) v = v

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
fieldType (EnumValue _) = "Nat"
fieldType StringValue = "String"
fieldType IntegerValue = "Integer"
fieldType CountValue = "Nat"
fieldType (ListOf k) = "List (" ++ fieldType k ++ ")"
fieldType (HandValue _ _) = "List Part"

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

||| The value sums and encoders of every type and attribute of the dialect.
export
encodersModule : List AnyTypeDef -> List AnyAttrDef -> Lines
encodersModule ts as =
  let types = map (\(SomeType t) => (typeClass t, toList t.params)) ts
      attrs = map (\(SomeAttr x) => (attrClass x, toList x.params)) as
  in banner (map (\l => "-- " ++ l))
     ++ barComment ["The idr dialect's types and attributes as the frontend writes them:"
                   , "their value sums, and each one's bytecode entry, its layout derived"
                   , "from its parameters as the C++ reader's is; printed from the dialect's"
                   , "specification."]
     ++ [ "module IdrisMLIR.Encoding.Idr", "", "import IdrisMLIR.MLIR.Parts", "", "%default total", "" ]
     ++ valueSum "IdrType" "types" types
     ++ valueSum "IdrAttr" "attributes" attrs
     ++ concatMap (\(n, (cls, ps)) => encoder "types" n cls ps) (numberedFrom 0 types)
     ++ concatMap (\(n, (cls, ps)) => encoder "attributes" n cls ps) (numberedFrom 0 attrs)
     ++ encodeSum "IdrType" types
     ++ encodeSum "IdrAttr" attrs
