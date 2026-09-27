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
// What an op declares once, for every pass to derive from (Idr.h)
//===----------------------------------------------------------------------===//

// IDR-MOD-1: the first contract version that admits the op; idr-check-input
// rejects it below that version. Ops without it are admitted from version 0.
class Idr_Since<int version>
    : ParamNativeOpTrait<"Since", !cast<string>(version)> {
  let cppNamespace = "::idr";
}

// LOW-IO-2: the op lowers to a call of this runtime helper.
def Idr_RuntimeCallOpInterface : OpInterface<"RuntimeCallOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op whose lowering calls a runtime helper.";
  let methods = [
    InterfaceMethod<"The runtime helper the lowering calls.",
                    "::llvm::StringRef", "getHelper">,
  ];
}

class Idr_CallsHelper<string helper>
    : ParamNativeOpTrait<"CallsHelper", "\"" # helper # "\""> {
  let cppNamespace = "::idr";
}

class Idr_Helper<string helper>
    : TraitList<[Idr_CallsHelper<helper>, Idr_RuntimeCallOpInterface]>;

// IDR-EFF-1: an op that may end the program. Its cause is the text of the
// crash message (LOW-CRASH-1); its effects and speculatability follow.
def Idr_MayCrashOpInterface : OpInterface<"MayCrashOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op that may end the program with a crash.";
  let methods = [
    InterfaceMethod<"What the crash reports, or nothing when the op cannot crash.",
                    "std::optional<::llvm::StringRef>", "getCrashCause">,
  ];
}

def Idr_MayCrashTrait : NativeOpTrait<"MayCrash"> {
  let cppNamespace = "::idr";
}

defvar Idr_MayCrash = [Idr_MayCrashTrait,
                       DeclareOpInterfaceMethods<Idr_MayCrashOpInterface>,
                       MemoryEffectsOpInterface, ConditionallySpeculatable];

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
  let results = (outs I64:$result);
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

class Idr_DivisionOp<string mnemonic, bit isQuotient>
    : Idr_Op<mnemonic, !listconcat([SameOperandsAndResultType], Idr_MayCrash)> {
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$lhs,
                       AnySignlessInteger:$rhs);
  let results = (outs AnySignlessInteger:$result);
  let assemblyFormat = [{
    (`signed` $is_signed^)? $lhs `,` $rhs attr-dict `:` type($result)
  }];
  let hasFolder = 1;
  let extraClassDeclaration = "static constexpr bool quotient = "
                              # !if(isQuotient, "true", "false") # ";";
  let extraClassDefinition = [{
    ::mlir::OpFoldResult $cppClass::fold(FoldAdaptor adaptor) {
      return foldDivision(*this, adaptor);
    }
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() {
      return divisionCrashCause(getRhs());
    }
  }];
}

// IDR-DIV-*, IDR-EFF-1
def Idr_DivOp : Idr_DivisionOp<"div", 1> {
  let summary = "Idris div: Euclidean when signed, crashes on zero";
}
def Idr_ModOp : Idr_DivisionOp<"mod", 0> {
  let summary = "Idris mod: Euclidean when signed, crashes on zero";
}

// IDR-CHAR-1
def Idr_ToCharOp : Idr_Op<"to_char", [Pure, Idr_Since<1>]> {
  let summary = "an integer as a Char: itself if a scalar value, else 0";
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "(`signed` $is_signed^)? $value attr-dict `:` type($value)";
  let hasFolder = 1;
}

// IDR-DBL-3 (v3): the first character of prim__cast_DoubleString (ELIM-G-15).
def Idr_DoubleHeadOp : Idr_Op<"double_head", [Pure, Idr_Since<3>,
    Idr_Helper<"__idr_double_head">]> {
  let summary = "the first character of a Double as the reference prints it";
  let arguments = (ins F64:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "$value attr-dict";
}

// IDR-CRASH-1 (v3): a case the definition does not cover (SEM-CRASH-2).
// Its results, of any types, stand for the values its block returns; they
// are never produced.
def Idr_CrashOp : Idr_Op<"crash", !listconcat([Idr_Since<3>], Idr_MayCrash)> {
  let summary = "ends the program with a message naming the cause";
  let arguments = (ins StrAttr:$message);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = "$message attr-dict (`:` type($results)^)?";
}

// IDR-STR-1
def Idr_StrLitOp : Idr_Op<"str.lit", [Pure, ConstantLike, Idr_Since<1>]> {
  let summary = "a static string literal (UTF-8 bytes)";
  let arguments = (ins StrAttr:$value);
  let results = (outs Idr_StrType:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
  let hasFolder = 1;
}

// IDR-DBL-1: truncates toward zero and wraps to the result width; crashes on
// NaN and the infinities (IDR-EFF-1).
def Idr_ToIntOp : Idr_Op<"to_int", !listconcat([Idr_Since<2>,
    Idr_Helper<"__idr_f64_to_i64">], Idr_MayCrash)> {
  let summary = "a Double as an integer, truncated and wrapped";
  let arguments = (ins F64:$value);
  let results = (outs AnySignlessInteger:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
  let hasFolder = 1;
}

//===----------------------------------------------------------------------===//
// IO (IDR-IO-1, IDR-EFF-2)
//===----------------------------------------------------------------------===//

// Each IO op lowers to exactly a call of its helper (LOW-IO-2).
class Idr_IOOp<string mnemonic, int since, list<Trait> traits> : Idr_Op<mnemonic,
    !listconcat(traits, [Idr_Since<since>,
                         MemoryEffects<[MemRead<Idr_IOResource>,
                                        MemWrite<Idr_IOResource>]>])>;

def Idr_PutStrOp : Idr_IOOp<"io.put_str", 1, [Idr_Helper<"__idr_put_bytes">]> {
  let arguments = (ins Idr_StrType:$str, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$str `,` $world attr-dict";
}

def Idr_PutCharOp : Idr_IOOp<"io.put_char", 1, [Idr_Helper<"__idr_put_char">]> {
  let arguments = (ins I32:$ch, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$ch `,` $world attr-dict";
}

// The helper depends on the signedness.
def Idr_PutIntOp : Idr_IOOp<"io.put_int", 1,
    [DeclareOpInterfaceMethods<Idr_RuntimeCallOpInterface>]> {
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$value,
                       Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    (`signed` $is_signed^)? $value `,` $world attr-dict `:` type($value)
  }];
  let extraClassDefinition = [{
    ::llvm::StringRef $cppClass::getHelper() {
      return getIsSigned() ? "__idr_put_int_s" : "__idr_put_int_u";
    }
  }];
}

// IDR-DBL-2
def Idr_PutDoubleOp : Idr_IOOp<"io.put_double", 2, [Idr_Helper<"__idr_put_double">]> {
  let arguments = (ins F64:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$value `,` $world attr-dict";
}

def Idr_GetCharOp : Idr_IOOp<"io.get_char", 1, [Idr_Helper<"__idr_get_char">]> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I32:$ch, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

// IDR-IO-2 (v3): the Prelude's getChar, one byte (SEM-IO-7).
def Idr_GetByteOp : Idr_IOOp<"io.get_byte", 3, [Idr_Helper<"__idr_get_byte">]> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I32:$ch, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

def Idr_ExitOp : Idr_IOOp<"io.exit", 1, [Idr_Helper<"__idr_exit">]> {
  let arguments = (ins I64:$code, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$code `,` $world attr-dict";
}

#endif // IDR_OPS
