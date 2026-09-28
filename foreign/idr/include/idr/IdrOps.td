// The idr dialect: the contract between the Idris compiler and the C++ side
// (docs/cutover.md, section 10, which becomes docs/architecture/08). Rule
// identifiers refer to those documents. Every fact about an op is declared
// here once; the C++ in lib/Dialect and every pass derive from it.

#ifndef IDR_OPS
#define IDR_OPS

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/IR/BuiltinAttributes.td"
include "mlir/Interfaces/CallInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/InferIntRangeInterface.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Idr_Dialect : Dialect {
  let name = "idr";
  let cppNamespace = "::idr";
  let summary = "Monomorphic Idris programs: data, closures, matches, strings and bigs";
  let useDefaultTypePrinterParser = 1;
  let useDefaultAttributePrinterParser = 1;
  let hasConstantMaterializer = 1;
  // OPT-CALL-1 (A20): the pattern that removes unused calls of func.call.
  let hasCanonicalizer = 1;
  // The module's and the functions' rules (IDR-WORLD-1, IDR-DATA-4, IDR-FN-1).
  let hasOperationAttrVerify = 1;
  let hasRegionArgAttrVerify = 1;
  // Constants of scalars, calls from closures, and regions ending in
  // ub.unreachable.
  let dependentDialects = ["::mlir::arith::ArithDialect", "::mlir::func::FuncDialect",
                           "::mlir::ub::UBDialect"];
}

//===----------------------------------------------------------------------===//
// Types (IDR-TY-*)
//===----------------------------------------------------------------------===//

class Idr_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Idr_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

// IDR-TY-1
def Idr_DataType : Idr_Type<"Data", "data"> {
  let summary = "a value of the unboxed sum declared by idr.data";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$name);
  let assemblyFormat = "`<` $name `>`";
}

// IDR-TY-6: a value of a boxed (recursive) type, declared `idr.data @T box`.
def Idr_BoxType : Idr_Type<"Box", "box"> {
  let summary = "a value of the boxed type declared by idr.data ... box";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$name);
  let assemblyFormat = "`<` $name `>`";
}

// IDR-TY-7: `!idr.fn<(A...) -> (R...)>`; Lazy and Inf are `!idr.fn<() -> (a)>`.
def Idr_FnType : Idr_Type<"Fn", "fn"> {
  let summary = "a closure";
  let parameters = (ins ArrayRefParameter<"::mlir::Type">:$inputs,
                        ArrayRefParameter<"::mlir::Type">:$results);
  let hasCustomAssemblyFormat = 1;
  let extraClassDeclaration = [{
    ::mlir::FunctionType getFunctionType() const;
  }];
}

// IDR-TY-2
def Idr_ErasedType : Idr_Type<"Erased", "erased"> {
  let summary = "a quantity-0 value with no runtime representation";
}

// IDR-TY-4 (revised at the cutover): any string, not only a literal.
def Idr_StrType : Idr_Type<"Str", "str"> {
  let summary = "a string (UTF-8)";
}

// IDR-TY-8
def Idr_BigType : Idr_Type<"Big", "big"> {
  let summary = "an Integer, or a Nat-like value (non-negative)";
}

// IDR-TY-5
def Idr_WorldType : Idr_Type<"World", "world"> {
  let summary = "the IO world token";
}

def Idr_SumType : AnyTypeOf<[Idr_DataType, Idr_BoxType]>;
def Idr_Int : AnyTypeOf<[I8, I16, I32, I64]>;

//===----------------------------------------------------------------------===//
// Constant attributes (IDR-CONST-1)
//===----------------------------------------------------------------------===//

// A value, written untyped: its type is that of the idr.constant holding it,
// or of the field or capture it fills. The self type exists only because
// MLIR's parser reads the `: T` after an attribute into the attribute; the
// verifiers accept only NoneType there.
class Idr_Attr<string name, string attrMnemonic, dag params = (ins)>
    : AttrDef<Idr_Dialect, name, [TypedAttrInterface]> {
  let mnemonic = attrMnemonic;
  let parameters = !con(params, (ins AttributeSelfTypeParameter<"">:$type));
}

def Idr_ConAttr : Idr_Attr<"Con", "con",
    (ins "::mlir::SymbolRefAttr":$ctor, "::mlir::ArrayAttr":$fields)> {
  let summary = "a constructor of a sum or box, its fields as attributes";
  let assemblyFormat = "`<` $ctor `,` $fields `>`";
  let builders = [
    AttrBuilder<(ins "::mlir::SymbolRefAttr":$ctor, "::mlir::ArrayAttr":$fields), [{
      return $_get($_ctxt, ctor, fields, ::mlir::NoneType::get($_ctxt));
    }]>
  ];
  let genVerifyDecl = 1;
}

def Idr_ClosureAttr : Idr_Attr<"Closure", "closure",
    (ins "::mlir::FlatSymbolRefAttr":$callee, "::mlir::ArrayAttr":$captures)> {
  let summary = "a closure of a function with its captures as attributes";
  let assemblyFormat = "`<` $callee `,` $captures `>`";
  let builders = [
    AttrBuilder<(ins "::mlir::FlatSymbolRefAttr":$callee, "::mlir::ArrayAttr":$captures), [{
      return $_get($_ctxt, callee, captures, ::mlir::NoneType::get($_ctxt));
    }]>
  ];
}

def Idr_BigAttr : Idr_Attr<"Big", "big",
    (ins StringRefParameter<"the decimal digits">:$value)> {
  let summary = "an integer of any size, in canonical decimal";
  let assemblyFormat = "`<` $value `>`";
  let builders = [
    AttrBuilder<(ins "::llvm::StringRef":$value), [{
      return $_get($_ctxt, value, ::mlir::NoneType::get($_ctxt));
    }]>
  ];
  let genVerifyDecl = 1;
}

def Idr_ErasedAttr : Idr_Attr<"Erased", "erased"> {
  let summary = "the erased value";
  let assemblyFormat = "";
  let builders = [
    AttrBuilder<(ins), [{ return $_get($_ctxt, ::mlir::NoneType::get($_ctxt)); }]>
  ];
}

def Idr_CmpPredicate : I64EnumAttr<"CmpPredicate",
    "a comparison of strings or bigs", [
      I64EnumAttrCase<"eq", 0>, I64EnumAttrCase<"lt", 1>,
      I64EnumAttrCase<"lte", 2>, I64EnumAttrCase<"gt", 3>,
      I64EnumAttrCase<"gte", 4>]> {
  let cppNamespace = "::idr";
}

//===----------------------------------------------------------------------===//
// What an op declares once, for every pass to derive from (Idr.h)
//===----------------------------------------------------------------------===//

def Idr_CrashResource : Resource<"::idr::CrashResource">;
def Idr_IOResource : Resource<"::idr::IOResource">;
def Idr_DivergenceResource : Resource<"::idr::DivergenceResource">;

class Idr_Op<string mnemonic, list<Trait> traits = []>
    : Op<Idr_Dialect, mnemonic, traits>;

// The op lowers to a call of the runtime's C function named after it:
// `idr.str.append` calls `idris_rt_str_append` (LOW-RT-1).
def Idr_RuntimeCallOpInterface : OpInterface<"RuntimeCallOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op whose lowering calls a runtime function.";
  let methods = [
    InterfaceMethod<"The runtime function the lowering calls.",
                    "::llvm::StringRef", "getHelper">,
  ];
}

def Idr_CallsRuntimeTrait : NativeOpTrait<"CallsRuntime"> {
  let cppNamespace = "::idr";
}

def Idr_CallsRuntime : TraitList<[Idr_CallsRuntimeTrait, Idr_RuntimeCallOpInterface]>;

// IDR-EFF-1, A21: an op that may end the program. Its cause is the text of
// the crash message (LOW-CRASH-1); its effects and speculatability follow.
def Idr_MayCrashOpInterface : OpInterface<"MayCrashOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op that may end the program with a crash.";
  let methods = [
    InterfaceMethod<"What the crash reports, or nothing when the op cannot crash.",
                    "std::optional<::llvm::StringRef>", "getCrashCause">,
  ];
}

// `allocates`: the op also allocates its result (MemAlloc).
class Idr_MayCrashTrait<bit allocates>
    : ParamNativeOpTrait<"MayCrash", !if(allocates, "true", "false")> {
  let cppNamespace = "::idr";
}

class Idr_MayCrash<bit allocates = 0> : TraitList<[Idr_MayCrashTrait<allocates>,
    DeclareOpInterfaceMethods<Idr_MayCrashOpInterface>,
    MemoryEffectsOpInterface, ConditionallySpeculatable]>;

// IDR-EFF-2: the idr.io ops, which idr-effects looks for (IDR-FACT-1).
def Idr_PerformsIO : NativeOpTrait<"PerformsIO"> {
  let cppNamespace = "::idr";
}

//===----------------------------------------------------------------------===//
// Data declarations (IDR-DATA-*)
//===----------------------------------------------------------------------===//

def Idr_DataOp : Idr_Op<"data", [Symbol, SymbolTable, IsolatedFromAbove,
    NoRegionArguments, SingleBlock, NoTerminator, HasParent<"::mlir::ModuleOp">]> {
  let summary = "declares a monomorphic data type, unboxed or boxed";
  let arguments = (ins SymbolNameAttr:$sym_name, UnitAttr:$box);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name (`box` $box^)? attr-dict-with-keyword $body";
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::llvm::SmallVector<class CtorOp> getCtors();
    // The type of a value of this declaration: !idr.box or !idr.data.
    ::mlir::Type getValueType();
  }];
}

def Idr_CtorOp : Idr_Op<"ctor", [Symbol, HasParent<"DataOp">]> {
  let summary = "declares one constructor of an idr.data type";
  let arguments = (ins SymbolNameAttr:$sym_name, I64Attr:$tag,
                       TypeArrayAttr:$field_types, StrArrayAttr:$quantities);
  let assemblyFormat = [{
    $sym_name `tag` $tag custom<FieldTypes>($field_types) attr-dict
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::Type getFieldType(unsigned index);
  }];
}

//===----------------------------------------------------------------------===//
// Values (IDR-CONST-2, IDR-CON-1, IDR-FIELD-1, IDR-TAG-1)
//===----------------------------------------------------------------------===//

def Idr_ConstantOp : Idr_Op<"constant", [ConstantLike, Pure,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "a constant: a constructor, closure, string, big or the erased value";
  let arguments = (ins AnyAttr:$value);
  let results = (outs AnyType:$result);
  let hasCustomAssemblyFormat = 1;
  let hasFolder = 1;
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    // Whether idr.constant holds `value` as a `type`, as materializeConstant
    // asks. Scalars are arith.constant's.
    static bool isBuildableWith(::mlir::Attribute value, ::mlir::Type type);
  }];
}

// A box's idr.con allocates its result; any other is Pure.
def Idr_ConOp : Idr_Op<"con", [
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "builds a constructor value";
  let arguments = (ins SymbolRefAttr:$ctor, Variadic<AnyType>:$fields);
  let results = (outs Idr_SumType:$result);
  let assemblyFormat = [{
    $ctor `(` $fields `)` attr-dict `:` functional-type($fields, $result)
  }];
  let hasFolder = 1;
}

// Reading a field of another constructor gives an unspecified value but never
// traps, so the op is speculatable (IDR-FIELD-1).
def Idr_FieldOp : Idr_Op<"field", [Pure,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "reads a field of a constructor value";
  let arguments = (ins Idr_SumType:$value, FlatSymbolRefAttr:$ctor,
                       I64Attr:$index);
  let results = (outs AnyType:$result);
  let assemblyFormat = [{
    $value `[` $ctor `,` $index `]` attr-dict `:` type($value) `->` type($result)
  }];
  let hasFolder = 1;
}

// IDR-RANGE-1: the tag is in [0, n-1] for n constructors.
def Idr_TagOp : Idr_Op<"tag", [Pure,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the constructor tag of a value";
  let arguments = (ins Idr_SumType:$value);
  let results = (outs I64:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasFolder = 1;
}

//===----------------------------------------------------------------------===//
// Matches (IDR-MATCH-5, IDR-MATCH-6)
//===----------------------------------------------------------------------===//

// Region i < cases.size() is the case cases[i]; one more region is the default.
class Idr_MatchOpBase<string mnemonic, list<Trait> traits = []>
    : Idr_Op<mnemonic, !listconcat(traits, [RecursiveMemoryEffects,
        RecursivelySpeculatable,
        DeclareOpInterfaceMethods<RegionBranchOpInterface,
            ["getEntrySuccessorRegions", "getRegionInvocationBounds",
             "getSuccessorInputs"]>])> {
  let results = (outs Variadic<AnyType>:$results);
  let regions = (region VariadicRegion<SizedRegion<1>>:$regions);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasCanonicalizer = 1;
  let extraClassDeclaration = [{
    // The region of case `index`, and the default region, if any.
    ::mlir::Region &getCaseRegion(unsigned index) { return getRegions()[index]; }
    ::mlir::Region *getDefaultRegion() {
      return getRegions().size() > getCases().size() ? &getRegions().back() : nullptr;
    }
    // The region that runs when the scrutinee is the constant `value` (or,
    // for idr.match, when it is built by an idr.con), or null if unknown.
    ::mlir::Region *getTakenRegion(::mlir::Attribute value);
  }];
}

def Idr_MatchOp : Idr_MatchOpBase<"match", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "branches on the constructor of a sum or box";
  let arguments = (ins Idr_SumType:$scrutinee, ArrayAttr:$cases);
}

def Idr_MatchLitOp : Idr_MatchOpBase<"match_lit"> {
  let summary = "branches on the value of an integer, string or big";
  let arguments = (ins AnyTypeOf<[AnySignlessInteger, Idr_StrType, Idr_BigType]>:$scrutinee,
                       ArrayAttr:$cases);
}

def Idr_YieldOp : Idr_Op<"yield", [Pure, ReturnLike, Terminator,
    ParentOneOf<["MatchOp", "MatchLitOp"]>]> {
  let summary = "ends a region of a match with its results";
  let arguments = (ins Variadic<AnyType>:$results);
  let assemblyFormat = "attr-dict ($results^ `:` type($results))?";
}

//===----------------------------------------------------------------------===//
// Closures (IDR-CLOS-1)
//===----------------------------------------------------------------------===//

def Idr_ClosureOp : Idr_Op<"closure", [Pure,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "a closure of a function: its leading parameters are the captures";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$captures);
  let results = (outs Idr_FnType:$result);
  let assemblyFormat = [{
    $callee `(` $captures `)` attr-dict `:` functional-type($captures, $result)
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
}

// The callee is a value, so the effects are unknown.
def Idr_ApplyOp : Idr_Op<"apply", [CallOpInterface,
    TypesMatchWith<"callee input types match argument types", "callee", "args",
                   "::llvm::cast<FnType>($_self).getInputs()">,
    TypesMatchWith<"callee result types match result types", "callee", "results",
                   "::llvm::cast<FnType>($_self).getResults()">]> {
  let summary = "applies a closure to arguments";
  let arguments = (ins Idr_FnType:$callee, Variadic<AnyType>:$args,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = "$callee `(` $args `)` attr-dict `:` qualified(type($callee))";
  let hasCanonicalizeMethod = 1;
  let extraClassDeclaration = [{
    ::mlir::CallInterfaceCallable getCallableForCallee() { return getCallee(); }
    void setCalleeFromCallable(::mlir::CallInterfaceCallable callee) {
      setOperand(0, ::llvm::cast<::mlir::Value>(callee));
    }
    ::mlir::Operation::operand_range getArgOperands() { return getArgs(); }
    ::mlir::MutableOperandRange getArgOperandsMutable() { return getArgsMutable(); }
  }];
}

//===----------------------------------------------------------------------===//
// Crashes and loops
//===----------------------------------------------------------------------===//

// IDR-CRASH-1 (revised): a case the definition does not cover (SEM-CRASH-2),
// followed by ub.unreachable.
def Idr_CrashOp : Idr_Op<"crash", [Idr_MayCrash<>]> {
  let summary = "ends the program with a message naming the cause";
  let arguments = (ins StrAttr:$message);
  let assemblyFormat = "$message attr-dict";
}

// LOW-TAIL-4 (A14): created by idr-tail-loops in loops of functions that are
// not total, never written by Emit. MLIR deletes a region op without effects
// even if it never finishes; this op's effect keeps such a loop (SEM-EVAL-5),
// and orders it with output as a crash is (A21).
def Idr_MayLoopOp : Idr_Op<"may_loop", [MemoryEffects<[
    MemWrite<Idr_DivergenceResource>, MemWrite<Idr_IOResource>]>]> {
  let summary = "marks one iteration of a loop that may not terminate";
  let assemblyFormat = "attr-dict";
}

//===----------------------------------------------------------------------===//
// Scalars
//===----------------------------------------------------------------------===//

class Idr_DivisionOp<string mnemonic, bit isQuotient>
    : Idr_Op<mnemonic, [SameOperandsAndResultType, Idr_MayCrash<>]> {
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$lhs,
                       AnySignlessInteger:$rhs);
  let results = (outs AnySignlessInteger:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $lhs `,` $rhs attr-dict `:` type($result)
  }];
  let hasFolder = 1;
  let extraClassDeclaration = "static constexpr bool quotient = "
                              # !if(isQuotient, "true", "false") # ";";
  let extraClassDefinition = [{
    ::mlir::OpFoldResult $cppClass::fold(FoldAdaptor adaptor) {
      return foldDivision(*this, adaptor);
    }
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() {
      if (knownNonZero(getRhs()))
        return std::nullopt;
      return ::llvm::StringRef("division by zero");
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
def Idr_ToCharOp : Idr_Op<"to_char", [Pure,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "an integer as a Char: itself if a scalar value, else 0";
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$value);
  let results = (outs I32:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
  }];
  let hasFolder = 1;
}

// IDR-DBL-1: truncates toward zero and wraps to the result width; crashes on
// NaN and the infinities (IDR-EFF-1).
def Idr_ToIntOp : Idr_Op<"to_int", [Idr_CallsRuntime, Idr_MayCrash<>]> {
  let summary = "a Double as an integer, truncated and wrapped";
  let arguments = (ins F64:$value);
  let results = (outs AnySignlessInteger:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
  let hasFolder = 1;
}

// IDR-DBL-3: the first character of prim__cast_DoubleString (ELIM-G-15).
def Idr_DoubleHeadOp : Idr_Op<"double_head", [Pure, Idr_CallsRuntime,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the first character of a Double as the reference prints it";
  let arguments = (ins F64:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "$value attr-dict";
}

// The first character of the decimal text of an integer (ELIM-G-15, A4).
def Idr_IntHeadOp : Idr_Op<"int_head", [Pure, Idr_CallsRuntime,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the first character of an integer's decimal text";
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value);
  let results = (outs I32:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
  }];
}

//===----------------------------------------------------------------------===//
// Strings (IDR-STR-2)
//===----------------------------------------------------------------------===//

// A string builder allocates its result (MemAlloc).
class Idr_StrBuilderOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<"str." # mnemonic, !listconcat(traits, [Idr_CallsRuntime])> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let results = (outs Res<Idr_StrType, "", [MemAlloc]>:$result);
}

def Idr_StrAppendOp : Idr_StrBuilderOp<"append"> {
  let summary = "the concatenation of two strings";
  let arguments = (ins Idr_StrType:$lhs, Idr_StrType:$rhs);
  let assemblyFormat = "$lhs `,` $rhs attr-dict";
}

def Idr_StrConsOp : Idr_StrBuilderOp<"cons"> {
  let summary = "a character before a string";
  let arguments = (ins I32:$head, Idr_StrType:$tail);
  let assemblyFormat = "$head `,` $tail attr-dict";
}

def Idr_StrFromCharOp : Idr_StrBuilderOp<"from_char"> {
  let summary = "the string of one character";
  let arguments = (ins I32:$value);
  let assemblyFormat = "$value attr-dict";
}

// `signed` or `unsigned` for an integer, nothing for a Double.
def Idr_StrShowOp : Idr_StrBuilderOp<"show"> {
  let summary = "the text of a number, as prim__cast_TString writes it";
  let arguments = (ins UnitAttr:$is_signed, AnyTypeOf<[Idr_Int, F64]>:$value);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
  }];
  let hasVerifier = 1;
}

def Idr_StrSubstrOp : Idr_StrBuilderOp<"substr"> {
  let summary = "the characters of a string from a start, at most a length";
  let arguments = (ins Idr_StrType:$str, I64:$start, I64:$length);
  let assemblyFormat = "$str `,` $start `,` $length attr-dict";
}

def Idr_StrReverseOp : Idr_StrBuilderOp<"reverse"> {
  let summary = "the characters of a string in reverse order";
  let arguments = (ins Idr_StrType:$str);
  let assemblyFormat = "$str attr-dict";
}

def Idr_StrTailOp : Idr_Op<"str.tail", [Idr_CallsRuntime, Idr_MayCrash<1>]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a string without its first character; crashes on \"\"";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs Idr_StrType:$result);
  let assemblyFormat = "$str attr-dict";
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() {
      if (knownNonEmpty(getStr()))
        return std::nullopt;
      return ::llvm::StringRef("tail of an empty string");
    }
  }];
}

// IDR-RANGE-1
def Idr_StrLengthOp : Idr_Op<"str.length", [Pure, Idr_CallsRuntime,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the number of characters of a string";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs I64:$result);
  let assemblyFormat = "$str attr-dict";
}

def Idr_StrIndexOp : Idr_Op<"str.index", [Idr_CallsRuntime, Idr_MayCrash<>]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the character at an index; crashes out of range";
  let arguments = (ins Idr_StrType:$str, I64:$index);
  let results = (outs I32:$result);
  let assemblyFormat = "$str `,` $index attr-dict";
}

def Idr_StrHeadOp : Idr_Op<"str.head", [Idr_CallsRuntime, Idr_MayCrash<>]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the first character of a string; crashes on \"\"";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs I32:$result);
  let assemblyFormat = "$str attr-dict";
  let hasCanonicalizer = 1;
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() {
      if (knownNonEmpty(getStr()))
        return std::nullopt;
      return ::llvm::StringRef("head of an empty string");
    }
  }];
}

def Idr_StrCmpOp : Idr_Op<"str.cmp", [Pure, Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "compares two strings";
  let arguments = (ins Idr_CmpPredicate:$predicate, Idr_StrType:$lhs,
                       Idr_StrType:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate $lhs `,` $rhs attr-dict";
}

def Idr_StrToIntOp : Idr_Op<"str.to_int", [Pure, Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a string as an integer, as prim__cast_StringT reads it";
  let arguments = (ins UnitAttr:$is_signed, Idr_StrType:$str);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $str attr-dict `:` type($result)
  }];
}

def Idr_StrToDoubleOp : Idr_Op<"str.to_double", [Pure, Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a string as a Double, as prim__cast_StringDouble reads it";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs F64:$result);
  let assemblyFormat = "$str attr-dict";
}

//===----------------------------------------------------------------------===//
// Bigs (IDR-BIG-1)
//===----------------------------------------------------------------------===//

// An op that makes a big allocates its result (MemAlloc).
class Idr_BigBinaryOp<string mnemonic, string what>
    : Idr_Op<"big." # mnemonic, [Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = what # " of two bigs";
  let arguments = (ins Idr_BigType:$lhs, Idr_BigType:$rhs);
  let results = (outs Res<Idr_BigType, "", [MemAlloc]>:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict";
}

def Idr_BigAddOp : Idr_BigBinaryOp<"add", "the sum">;
def Idr_BigSubOp : Idr_BigBinaryOp<"sub", "the difference">;
def Idr_BigMulOp : Idr_BigBinaryOp<"mul", "the product">;
def Idr_BigAndOp : Idr_BigBinaryOp<"and", "the bitwise and">;
def Idr_BigOrOp : Idr_BigBinaryOp<"or", "the bitwise or">;
def Idr_BigXorOp : Idr_BigBinaryOp<"xor", "the bitwise xor">;

class Idr_BigDivisionOp<string mnemonic, string what>
    : Idr_Op<"big." # mnemonic, [Idr_CallsRuntime, Idr_MayCrash<1>]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = what # " of two bigs, as Integer's div and mod; crashes on zero";
  let arguments = (ins Idr_BigType:$lhs, Idr_BigType:$rhs);
  let results = (outs Idr_BigType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict";
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() {
      if (knownNonZero(getRhs()))
        return std::nullopt;
      return ::llvm::StringRef("division by zero");
    }
  }];
}

def Idr_BigDivOp : Idr_BigDivisionOp<"div", "the quotient">;
def Idr_BigModOp : Idr_BigDivisionOp<"mod", "the remainder">;

def Idr_BigNegOp : Idr_Op<"big.neg", [Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the negation of a big";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Res<Idr_BigType, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict";
}

def Idr_BigCmpOp : Idr_Op<"big.cmp", [Pure, Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "compares two bigs";
  let arguments = (ins Idr_CmpPredicate:$predicate, Idr_BigType:$lhs,
                       Idr_BigType:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate $lhs `,` $rhs attr-dict";
}

def Idr_BigFromIntOp : Idr_Op<"big.from_int", [Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "an integer as a big";
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value);
  let results = (outs Res<Idr_BigType, "", [MemAlloc]>:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
  }];
}

def Idr_BigToIntOp : Idr_Op<"big.to_int", [Pure, Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a big as an integer, wrapped to its width";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
}

def Idr_BigFromDoubleOp : Idr_Op<"big.from_double",
    [Idr_CallsRuntime, Idr_MayCrash<1>]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a Double truncated to a big; crashes on NaN and the infinities";
  let arguments = (ins F64:$value);
  let results = (outs Idr_BigType:$result);
  let assemblyFormat = "$value attr-dict";
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() {
      if (knownFinite(getValue()))
        return std::nullopt;
      return ::llvm::StringRef("cast of a non-finite Double");
    }
  }];
}

def Idr_BigToDoubleOp : Idr_Op<"big.to_double", [Pure, Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a big as the nearest Double";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs F64:$result);
  let assemblyFormat = "$value attr-dict";
}

def Idr_BigShowOp : Idr_Op<"big.show", [Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the decimal text of a big";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Res<Idr_StrType, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict";
}

def Idr_BigFromStrOp : Idr_Op<"big.from_str", [Idr_CallsRuntime]> {
  // LOW-RT-1: folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a string as a big, as prim__cast_StringInteger reads it";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs Res<Idr_BigType, "", [MemAlloc]>:$result);
  let assemblyFormat = "$str attr-dict";
}

//===----------------------------------------------------------------------===//
// IO (IDR-IO-*, IDR-EFF-2)
//===----------------------------------------------------------------------===//

// Each IO op consumes one world and produces the next.
class Idr_IOOp<string mnemonic, list<Trait> traits = []> : Idr_Op<"io." # mnemonic,
    !listconcat(traits, [Idr_PerformsIO, Idr_CallsRuntime,
                         MemoryEffects<[MemRead<Idr_IOResource>,
                                        MemWrite<Idr_IOResource>]>])>;

def Idr_PutStrOp : Idr_IOOp<"put_str"> {
  let arguments = (ins Idr_StrType:$str, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$str `,` $world attr-dict";
  let hasCanonicalizer = 1;
}

def Idr_PutCharOp : Idr_IOOp<"put_char"> {
  let arguments = (ins I32:$ch, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$ch `,` $world attr-dict";
}

def Idr_PutIntOp : Idr_IOOp<"put_int"> {
  let arguments = (ins UnitAttr:$is_signed, AnySignlessInteger:$value,
                       Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value `,` $world attr-dict `:` type($value)
  }];
}

// IDR-DBL-2
def Idr_PutDoubleOp : Idr_IOOp<"put_double"> {
  let arguments = (ins F64:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$value `,` $world attr-dict";
}

def Idr_GetCharOp : Idr_IOOp<"get_char"> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I32:$ch, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

// IDR-IO-2: one byte of input, or 255 at its end (SEM-IO-7).
def Idr_GetByteOp : Idr_IOOp<"get_byte"> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I32:$ch, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

def Idr_ExitOp : Idr_IOOp<"exit"> {
  let arguments = (ins I64:$code, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$code `,` $world attr-dict";
}

#endif // IDR_OPS
