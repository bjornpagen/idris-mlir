-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Every type and attribute of the dialect native in bytecode, its layout
||| derived from its parameters: one member per parameter, in order, by its
||| kind. Printed once to upstream's bytecode DSL, from which mlir-tblgen
||| writes the C++ reader and writer, and once to the frontend's encoders, so
||| no layout is restated and no `idr` text crosses the handoff. A value a
||| wire lays out is read and written by the codecs printed from its wire
||| (`Spec.Generator.Wire`), which its record names.
module IdrisMLIR.Spec.Generator.Bytecode

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Generator.Render
import IdrisMLIR.Spec.Generator.Ods
import IdrisMLIR.Spec.Generator.Wire

import Data.List
import Data.Vect

%default total

||| A parameter's member in upstream's bytecode DSL.
export
memberOf : ParamKind -> String
memberOf TypeValue = "Type"
memberOf AttrValue = "Attribute"
memberOf (EnumValue e) = "Idr_Enum<" ++ quoted (identText e.enum.name) ++ ">"
memberOf (OptionalCase _ c) = "Idr_OptionalCase<" ++ quoted (codeText c) ++ ">"
memberOf StringValue = "Idr_String"
memberOf IntegerValue = "Idr_APInt"
memberOf CountValue = "VarInt"
memberOf (ListOf k) = "Array<" ++ memberOf k ++ ">"
memberOf (WiredValue w d) = "Idr_Wired<" ++ quoted (wiredRead w) ++ ", " ++ quoted (identText d.name) ++ ">"

export
builderOf : Bytecode -> List String
builderOf Derived = []
builderOf (CheckedBy fn) = ["  let cBuilder = \"::idr::" ++ identText fn ++ "(reader, context, $_args)\";"]

export
memberList : Vect p Parameter -> String
memberList ps = joinWith ", " (map (\x => memberOf x.kind ++ ":$" ++ identText x.name) (toList ps))

export
typeBytecode : AnyTypeDef -> (String, Lines)
typeBytecode (SomeType t) =
  let name = typeClass t
  in (name, ["def " ++ name ++ " : DialectType<(type " ++ memberList t.params ++ ")> {"] ++ builderOf t.bytecode ++ ["}"])

export
attrBytecode : AnyAttrDef -> (String, Lines)
attrBytecode (SomeAttr a) =
  let name = attrClass a
  in (name, ["def " ++ name ++ " : DialectAttribute<(attr " ++ memberList a.params ++ ")> {"] ++ builderOf a.bytecode ++ ["}"])

||| The dialect's bytecode records, every type and attribute, in declaration
||| order: a type's code is its position among the types.
export
bytecodeOds : List AnyTypeDef -> List AnyAttrDef -> Lines
bytecodeOds ts as =
  let types = map typeBytecode ts
      attrs = map attrBytecode as
  in banner slashComment
     ++ [ "#ifndef IDR_GENERATED_BYTECODE", "#define IDR_GENERATED_BYTECODE", ""
        , "include \"mlir/IR/BytecodeBase.td\"", ""
        , "// An enum of the dialect, written as its case's number; a number that is"
        , "// no case is refused by the reader."
        , "class Idr_Enum<string name> :"
        , "  WithParser <\"succeeded(::idr::readEnum($_reader, $_var, ::idr::symbolize\" # name # \"))\","
        , "  WithBuilder<\"$_args\","
        , "  WithPrinter<\"$_writer.writeVarInt(static_cast<uint64_t>($_getter))\","
        , "  WithType   <\"::idr::\" # name>>>>;"
        , "// A case of a closed set held in a class over its cases, or none: zero"
        , "// for none, else one more than the case's position."
        , "class Idr_OptionalCase<string cppClass> :"
        , "  WithParser <\"succeeded(::idr::readOptionalCase($_reader, $_var))\","
        , "  WithBuilder<\"$_args\","
        , "  WithPrinter<\"::idr::writeOptionalCase($_writer, $_getter)\","
        , "  WithType   <\"::std::optional<\" # cppClass # \">\">>>>;"
        , "def Idr_String : WithParser<\"succeeded($_reader.readString($_var))\","
        , "  WithBuilder<\"$_args\", WithPrinter<\"$_writer.writeOwnedString($_getter)\","
        , "  WithType<\"::llvm::StringRef\">>>>;"
        , "// An integer of any size: its width, then upstream's integer of that"
        , "// width; a storage keyed at the fewest bits gives it at those."
        , "def Idr_APInt : WithParser<\"succeeded(::idr::readInteger($_reader, $_var))\","
        , "  WithBuilder<\"$_args\", WithPrinter<\"::idr::writeInteger($_writer, $_getter)\","
        , "  WithType<\"::llvm::APInt\">>>>;"
        , "// A value its wire lays out, read and written by the codecs printed from"
        , "// the wire beside these readers (Generated/Wire.cpp.inc), named for its"
        , "// directive: an array's values are read with the arena that keeps what"
        , "// they view, which outlives the builder they are given to."
        , "class Idr_Wired<string cppType, string directive> :"
        , "  WithParser <\"succeeded(read\" # directive # \"($_reader, $_var))\","
        , "  WithBuilder<\"$_args\","
        , "  WithPrinter<\"write\" # directive # \"($_writer, $_getter)\","
        , "  WithType   <cppType>>>>;"
        , "" ]
     ++ concatMap snd types
     ++ ["", "def IdrDialectTypes : DialectTypes<\"Idr\"> {", "  let elems = [" ++ joinWith ", " (map fst types) ++ "];", "}"]
     ++ concatMap snd attrs
     ++ ["", "def IdrDialectAttributes : DialectAttributes<\"Idr\"> {", "  let elems = [" ++ joinWith ", " (map fst attrs) ++ "];", "}"]
     ++ ["", "#endif // IDR_GENERATED_BYTECODE"]
