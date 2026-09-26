// The idr dialect: the contract between the Idris compiler and the C++ side
// (docs/architecture/08-idr-dialect.md). Rule identifiers refer to that spec.

#ifndef IDR_OPS
#define IDR_OPS

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/IR/BuiltinAttributes.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Interfaces/InferTypeOpInterface.td"

def Idr_Dialect : Dialect {
  let name = "idr";
  let cppNamespace = "::idr";
  let summary = "Monomorphic, first-order Idris programs (heap-free profile)";
  let useDefaultTypePrinterParser = 1;
  let hasConstantMaterializer = 1;
}

class Idr_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Idr_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

// IDR-TY-1
def Idr_DataType : Idr_Type<"Data", "data"> {
  let summary = "a value of a monomorphic data type declared by idr.data";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$name);
  let assemblyFormat = "`<` $name `>`";
}

// IDR-TY-2
def Idr_ErasedType : Idr_Type<"Erased", "erased"> {
  let summary = "a quantity-0 value with no runtime representation";
}

// IDR-TY-4
def Idr_StrType : Idr_Type<"Str", "str"> {
  let summary = "a static string in read-only data";
}

// IDR-TY-5
def Idr_WorldType : Idr_Type<"World", "world"> {
  let summary = "the IO world token";
}

def Idr_CrashResource : Resource<"::idr::CrashResource">;
def Idr_IOResource : Resource<"::idr::IOResource">;

class Idr_Op<string mnemonic, list<Trait> traits = []>
    : Op<Idr_Dialect, mnemonic, traits>;

//===----------------------------------------------------------------------===//
// Data declarations (IDR-DATA-*)
//===----------------------------------------------------------------------===//

def Idr_DataOp : Idr_Op<"data", [Symbol, SymbolTable, IsolatedFromAbove,
    NoRegionArguments, SingleBlock, NoTerminator, HasParent<"::mlir::ModuleOp">]> {
  let summary = "declares a monomorphic, non-recursive data type";
  let arguments = (ins SymbolNameAttr:$sym_name);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name attr-dict-with-keyword $body";
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::llvm::SmallVector<class CtorOp> getCtors();
  }];
}

def Idr_CtorOp : Idr_Op<"ctor", [Symbol, HasParent<"DataOp">]> {
  let summary = "declares one constructor of an idr.data type";
  let arguments = (ins SymbolNameAttr:$sym_name, I64Attr:$tag,
                       TypeArrayAttr:$field_types, StrArrayAttr:$quantities);
  let assemblyFormat = [{
    $sym_name `tag` $tag `fields` $field_types `quantities` $quantities attr-dict
  }];
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Values
//===----------------------------------------------------------------------===//

def Idr_ErasedOp : Idr_Op<"erased", [Pure, ConstantLike]> {
  let summary = "the erased value";
  let results = (outs Idr_ErasedType:$result);
  let assemblyFormat = "attr-dict `:` type($result)";
  let hasFolder = 1;
}

def Idr_ConOp : Idr_Op<"con", [Pure,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "builds a constructor value (IDR-CON-1)";
  let arguments = (ins SymbolRefAttr:$ctor, Variadic<AnyType>:$fields);
  let results = (outs Idr_DataType:$result);
  let assemblyFormat = [{
    $ctor `(` $fields `)` attr-dict `:` functional-type($fields, $result)
  }];
}

def Idr_TagOp : Idr_Op<"tag", [Pure]> {
  let summary = "the constructor tag of a data value (IDR-TAG-1)";
  let arguments = (ins Idr_DataType:$value);
  let results = (outs Index:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasFolder = 1;
}

def Idr_FieldOp : Idr_Op<"field", [Pure,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "reads a field of a constructor value (IDR-FIELD-1)";
  let arguments = (ins Idr_DataType:$value, FlatSymbolRefAttr:$ctor,
                       I64Attr:$index);
  let results = (outs AnyType:$result);
  let assemblyFormat = [{
    $value `[` $ctor `,` $index `]` attr-dict `:` type($value) `->` type($result)
  }];
  let hasFolder = 1;
}

class Idr_DivisionOp<string mnemonic> : Idr_Op<mnemonic, [
    SameOperandsAndResultType,
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>]> {
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$lhs,
                       AnySignlessInteger:$rhs);
  let results = (outs AnySignlessInteger:$result);
  let assemblyFormat = [{
    (`signed` $is_signed^)? $lhs `,` $rhs attr-dict `:` type($result)
  }];
  let hasFolder = 1;
}

// IDR-DIV-*, IDR-EFF-1
def Idr_DivOp : Idr_DivisionOp<"div"> {
  let summary = "Idris div: Euclidean when signed, crashes on zero";
}
def Idr_ModOp : Idr_DivisionOp<"mod"> {
  let summary = "Idris mod: Euclidean when signed, crashes on zero";
}

// IDR-CHAR-1
def Idr_ToCharOp : Idr_Op<"to_char", [Pure]> {
  let summary = "an integer as a Char: itself if a scalar value, else 0";
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "(`signed` $is_signed^)? $value attr-dict `:` type($value)";
  let hasFolder = 1;
}

// IDR-STR-1
def Idr_StrLitOp : Idr_Op<"str.lit", [Pure, ConstantLike]> {
  let summary = "a static string literal (UTF-8 bytes)";
  let arguments = (ins StrAttr:$value);
  let results = (outs Idr_StrType:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
  let hasFolder = 1;
}

//===----------------------------------------------------------------------===//
// IO (IDR-IO-1, IDR-EFF-2)
//===----------------------------------------------------------------------===//

class Idr_IOOp<string mnemonic, list<Trait> traits = []> : Idr_Op<mnemonic,
    !listconcat(traits, [MemoryEffects<[MemRead<Idr_IOResource>,
                                        MemWrite<Idr_IOResource>]>])>;

def Idr_PutStrOp : Idr_IOOp<"io.put_str"> {
  let arguments = (ins Idr_StrType:$str, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$str `,` $world attr-dict";
}

def Idr_PutCharOp : Idr_IOOp<"io.put_char"> {
  let arguments = (ins I32:$ch, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$ch `,` $world attr-dict";
}

def Idr_PutIntOp : Idr_IOOp<"io.put_int"> {
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$value,
                       Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    (`signed` $is_signed^)? $value `,` $world attr-dict `:` type($value)
  }];
}

def Idr_GetCharOp : Idr_IOOp<"io.get_char"> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I32:$ch, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

def Idr_ExitOp : Idr_IOOp<"io.exit"> {
  let arguments = (ins I64:$code, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$code `,` $world attr-dict";
}

#endif // IDR_OPS
