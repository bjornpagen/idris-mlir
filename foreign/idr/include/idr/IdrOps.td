// The idr dialect: the contract between the Idris compiler and the C++ side.
// Every fact about an op is declared here once; the C++ in lib/Dialect and
// every pass derive from it.

#ifndef IDR_OPS
#define IDR_OPS

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/IR/BuiltinAttributes.td"
include "mlir/IR/BuiltinTypeInterfaces.td"
include "mlir/Interfaces/CallInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/InferIntRangeInterface.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Idr_Dialect : Dialect {
  let name = "idr";
  let cppNamespace = "::idr";
  let summary = "Monomorphic Idris programs: data, closures, matches, strings and bigs";
  // The dialect reads and writes its types: the common grades have
  // spellings, one table of them over the generated syntax (Initialize.cc).
  let useDefaultTypePrinterParser = 0;
  let extraClassDeclaration = [{
    ::mlir::Type parseType(::mlir::DialectAsmParser &parser) const override;
    void printType(::mlir::Type type, ::mlir::DialectAsmPrinter &printer) const override;
  }];
  let useDefaultAttributePrinterParser = 1;
  let hasConstantMaterializer = 1;
  // Upstream's patterns on other dialects' ops over this dialect's values:
  // the dimension of an array (lib/Dialect/Dialect.cc).
  let hasCanonicalizer = 1;
  // The module's and the functions' rules.
  let hasOperationAttrVerify = 1;
  let hasRegionArgAttrVerify = 1;
  // Every discardable attribute of the dialect, which its verifier knows
  // by these names and rejects any other `idr.*` (lib/Dialect/Dialect.cc
  // says where each may sit). A fact Idris proved is never one of these:
  // it is a type.
  let discardableAttrs = (ins
    // The module is a whole program (verifyProgram).
    "::mlir::UnitAttr":$program,
    // A function's facts: every loop of its body proved terminating, broken
    // last, its effects.
    "::mlir::UnitAttr":$total,
    "::mlir::UnitAttr":$break_last,
    "::idr::EffectAttr":$effects,
    // idr-stack's box whose cell never leaves its frame.
    "::mlir::UnitAttr":$stack,
    // idr-specialize's clone: its name and its key.
    "::idr::CloneAttr":$clone,
    // A clone's hole.
    "::mlir::IntegerAttr":$hole
  );
  // Constants of scalars, calls from closures, and regions ending in
  // ub.unreachable; and the layouts of cells, whose sizes the owned stage
  // checks, which are LLVM's.
  let dependentDialects = ["::mlir::arith::ArithDialect", "::mlir::func::FuncDialect",
                           "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect"];
}

//===----------------------------------------------------------------------===//
// Grades
//===----------------------------------------------------------------------===//

// A grade's halves (idr::Grade), enums so that their spellings are said
// once: read by the generated parser, written by the generated printers in
// C++ and in Idris. The quantity is spelled in words: an enum parameter is
// read as a keyword, which `0` and `1` are not.
def Idr_Quantity : I32EnumAttr<"Quantity", "the number of uses Idris proved of a value", [
    I32EnumAttrCase<"Zero", 0, "zero">, I32EnumAttrCase<"One", 1, "one">,
    I32EnumAttrCase<"Many", 2, "many">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

def Idr_Permission : I32EnumAttr<"Permission", "what a value owns", [
    I32EnumAttrCase<"Plain", 0, "plain">, I32EnumAttrCase<"Borrow", 1, "borrow">,
    I32EnumAttrCase<"Own", 2, "own">, I32EnumAttrCase<"Excl", 3, "excl">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

//===----------------------------------------------------------------------===//
// Types
//===----------------------------------------------------------------------===//

class Idr_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Idr_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

// Every runtime value type is an element type of memref, so an array of
// values (idr.array.new) is a builtin memref: what the memref and
// bufferization passes work on, with no array type of our own.
def Idr_DataType : Idr_Type<"Data", "data", [MemRefElementTypeInterface]> {
  let summary = "a value of the unboxed sum declared by idr.data";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$name);
  let assemblyFormat = "`<` $name `>`";
}

// A value of a boxed (recursive) type, declared `idr.data @T box`.
def Idr_BoxType : Idr_Type<"Box", "box", [MemRefElementTypeInterface]> {
  let summary = "a value of the boxed type declared by idr.data ... box";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$name);
  let assemblyFormat = "`<` $name `>`";
}

// `!idr.fn<(A...) -> R>`: the closure's signature is a function type, held
// as one and written as MLIR writes one (a single result without
// parentheses, which the parser reads either way). A suspension is
// `!idr.lazy<T>`, not a function: defunctionalization would turn a
// function into a sum and the cell would no longer be the one that was
// forced.
def Idr_FnType : Idr_Type<"Fn", "fn", [MemRefElementTypeInterface]> {
  let summary = "a closure";
  let parameters = (ins "::mlir::FunctionType":$function_type);
  let assemblyFormat = "`<` $function_type `>`";
  let builders = [
    TypeBuilder<(ins "::llvm::ArrayRef<::mlir::Type>":$inputs,
                     "::llvm::ArrayRef<::mlir::Type>":$results), [{
      return $_get($_ctxt, ::mlir::FunctionType::get($_ctxt, inputs, results));
    }]>
  ];
  let extraClassDeclaration = [{
    ::llvm::ArrayRef<::mlir::Type> getInputs() const { return getFunctionType().getInputs(); }
    ::llvm::ArrayRef<::mlir::Type> getResults() const { return getFunctionType().getResults(); }
  }];
}

// One cell, shared by every reference to it. idr-defunctionalize makes each
// lazy type a memo sum (an idr.data with `memo`, always a box): the
// constructor the cell holds is its state, one per label until it is
// forced, `running` while its force runs, and `forced` with the value after.
// A flag beside the payload could disagree with the state; the constructor
// cannot.
def Idr_LazyType : Idr_Type<"Lazy", "lazy", [MemRefElementTypeInterface]> {
  let summary = "a suspension of one value, forced once into this cell";
  let parameters = (ins "::mlir::Type":$value);
  let assemblyFormat = "`<` $value `>`";
  let builders = [
    TypeBuilderWithInferredContext<(ins "::mlir::Type":$value), [{
      return $_get(value.getContext(), value);
    }]>
  ];
}

def Idr_StrType : Idr_Type<"Str", "str", [MemRefElementTypeInterface]> {
  let summary = "a string (UTF-8)";
}

def Idr_BigType : Idr_Type<"Big", "big", [MemRefElementTypeInterface]> {
  let summary = "an Integer";
}

// Nat, and every type Idris shapes like it (a nullary constructor and a
// unary successor, Fin among them): a big at runtime, never negative. Every
// op that produces one keeps it non-negative (a sum, a product, a
// predecessor of a value that is not zero), and the only way in from an
// Integer, idr.nat.from_big, clamps, so the type itself proves the range.
// Integer range analysis is to seed [0, +inf) from this type in its entry
// state (setToEntryState), for block arguments and results it cannot see
// computed.
def Idr_NatType : Idr_Type<"Nat", "nat", [MemRefElementTypeInterface]> {
  let summary = "a natural number: a non-negative big";
}

// The values a big op computes on: an Integer, or a natural where the
// operation keeps naturals natural.
def Idr_BigOrNat : AnyTypeOf<[Idr_BigType, Idr_NatType]>;

// The carrier of the world: the IO world token, which only ever appears
// at grade (one, plain), the type spelled !idr.world. The carrier itself
// is !idr.world_carrier.
def Idr_WorldCarrier : Idr_Type<"World", "world_carrier"> {
  let summary = "the IO world token";
}

// A grade lives in the type, where no pass can drop it. It is a pair
// (u, p) (idr::Grade): u is the quantity Idris proved, zero, one or many,
// and p is what the value owns, plain (nothing to say), borrow, own or
// excl. A plain type T is (many, plain) and is never written as !idr.q.
// The type is `!idr.q<quantity, permission, value>`, and the common grades
// have spellings, which the dialect reads and writes from one table
// (Initialize.cc): !idr.erased is (zero, plain) of no carrier, `none` (the
// value has no runtime representation), !idr.lin<T> is (one, plain) of T,
// !idr.own<T> and !idr.excl<T> are (many, own) and (many, excl) of T, and
// !idr.world is (one, plain) of the world. A value of quantity one is used
// at most once on every path; its one use is idr.lin.use, or a position
// that is linear itself (a parameter, a field, a capture or a result of
// the same type).
def Idr_QType : Idr_Type<"Q", "q"> {
  let summary = "a value at a grade: its quantity and what it owns";
  let parameters = (ins EnumParameter<Idr_Quantity>:$quantity,
                        EnumParameter<Idr_Permission>:$permission, "::mlir::Type":$value);
  let assemblyFormat = "`<` $quantity `,` $permission `,` $value `>`";
  let genVerifyDecl = 1;
  let builders = [
    TypeBuilder<(ins "::idr::Grade":$grade, "::mlir::Type":$value), [{
      return $_get($_ctxt, grade.quantity, grade.permission, value);
    }]>
  ];
  let extraClassDeclaration = [{
    ::idr::Grade getGrade() const { return {getQuantity(), getPermission()}; }
  }];
}

// The positions that take a grade: the world, and a linear value other
// than the world (one that entered its grade, and is used out of it).
def Idr_WorldType : Type<CPred<"::idr::isWorld($_self)">, "the world", "::idr::QType"> {
  let builderCall = "::idr::world($_builder.getContext())";
}
def Idr_LinType : Type<CPred<"::idr::isLinear($_self)">,
                       "a value of quantity 1 other than the world", "::idr::QType">;

def Idr_SumType : AnyTypeOf<[Idr_DataType, Idr_BoxType]>;
def Idr_Int : AnyTypeOf<[I8, I16, I32, I64]>;

// A value of a type at any grade: what an op that makes one produces,
// plain before idr-rc and owned after it.
class Idr_AtAnyGrade<string cppType, string name>
    : Type<CPred<"::llvm::isa<" # cppType # ">(::idr::unrestricted($_self))">, name, "::mlir::Type">;
def Idr_StrValue : Idr_AtAnyGrade<"::idr::StrType", "a string at any grade">;
def Idr_BigValue : Idr_AtAnyGrade<"::idr::BigType", "an Integer at any grade">;
def Idr_NatValue : Idr_AtAnyGrade<"::idr::NatType", "a natural at any grade">;
def Idr_BigOrNatValue : Idr_AtAnyGrade<"::idr::BigType, ::idr::NatType", "an Integer or a natural at any grade">;
def Idr_BoxValue : Idr_AtAnyGrade<"::idr::BoxType", "a box at any grade">;
// The cell, plain before idr-rc and owned after it. The value inside stays
// the carrier: ownership is the grade of this reference, not a second type.
def Idr_LazyValue : Idr_AtAnyGrade<"::idr::LazyType", "a suspension at any grade">;
def Idr_SumValue : Idr_AtAnyGrade<"::idr::DataType, ::idr::BoxType", "a constructor value at any grade">;
// A constructor value at any quantity that holds no reference of its own:
// what a match takes apart, whose regions bind its fields at its grade.
def Idr_SumView : Type<And<[Idr_SumValue.predicate, CPred<"!::idr::isOwned($_self)">]>,
                       "a constructor value at any quantity, not owned", "::mlir::Type">;

// The result is the operand's value, at whatever grade the result has.
def Idr_ResultCarriesOperand : NativeOpTrait<"ResultCarriesOperand"> {
  let cppNamespace = "::idr";
}

//===----------------------------------------------------------------------===//
// Constant attributes
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

// A constructor with its fields, plain, or a run: n >= 2 cells of one
// constructor linked through one field, the spine, and ending in a tail,
// held flat, so that a list constant is one level deep to the printer, the
// parser, bytecode and every walk, however long it is. A walker that follows
// the spine steps through getRunCells and then getTail, never through
// getFields, which builds the rest of the run at each step. One value has one
// attribute: `get` makes a run exactly where repeated cells form one, and the
// verifier rejects any other run. What is stored is the cells: a plain con is
// one cell holding all its fields, with a null tail and spine 0; a run is its
// cells, each holding its fields without the spine field, then its tail and
// the spine's index. The generated walk and replace see each cell as an
// ArrayAttr and the tail as itself, so a run is one level deep to them. A
// replace rebuilds from the replaced parameters (Base::get) without
// canonicalizing, so it can make a run that is not canonical, which the
// verifier rejects.
//
// It is written as it is stored: a plain constructor as its one cell,
// `<@T::@C, [fields]>`, and a run as its cells, its tail and the field it
// runs along, `<@T::@C, [a], [b] tail t along 1>`, `along 0` left out. Each
// optional group starts with its keyword, so the parser tries the keyword
// and not the attribute after it, and the cells, a list without brackets,
// end at it. The generated parser builds through the getChecked below,
// which gives the attribute `get` gives for the same value, however it was
// written.
def Idr_ConAttr : Idr_Attr<"Con", "con",
    (ins "::mlir::SymbolRefAttr":$ctor, ArrayRefParameter<"::mlir::ArrayAttr">:$cells,
         OptionalParameter<"::mlir::Attribute">:$tail,
         DefaultValuedParameter<"unsigned", "0">:$spine)> {
  let summary = "a constructor of a sum or box, its fields as attributes, a list's cells flat";
  let assemblyFormat = "`<` $ctor `,` $cells (`tail` $tail^)? (`along` $spine^)? `>`";
  let genVerifyDecl = 1;
  let skipDefaultBuilders = 1;
  let builders = [
    // A run when one field is a run of `ctor` along that field, or the
    // second cell of one; otherwise the plain con.
    AttrBuilder<(ins "::mlir::SymbolRefAttr":$ctor, "::mlir::ArrayAttr":$fields)>
  ];
  let extraClassDeclaration = [{
    // What repeated `get` gives for the cells `cells` (each one's fields
    // without the spine field) linked through field `spine` and ending in
    // `tail`, built in O(n).
    static ConAttr getRun(::mlir::MLIRContext *context, ::mlir::SymbolRefAttr ctor,
                          unsigned spine, ::llvm::ArrayRef<::mlir::ArrayAttr> cells,
                          ::mlir::Attribute tail);
    // A run has a tail; a plain con has none.
    bool isRun() const { return static_cast<bool>(getTail()); }
    // The number of cells: 1 for a plain con.
    unsigned getRunLength() const { return static_cast<unsigned>(getCells().size()); }
    // A run's cells' fields without the spine field; empty for a plain con,
    // whose one cell is its fields (getFields).
    ::llvm::ArrayRef<::mlir::ArrayAttr> getRunCells() const {
      return isRun() ? getCells() : ::llvm::ArrayRef<::mlir::ArrayAttr>();
    }
    // Field `index` of the first cell: O(1) off the spine, and on it the run
    // from the second cell.
    ::mlir::Attribute getField(unsigned index) const;
    // The first cell's fields, for both forms: O(n) on a run, which builds
    // the rest of the run.
    ::mlir::ArrayAttr getFields() const;
    // The attribute of a constructor written as its stored parameters, as
    // the generated parser reads them: what `get` gives for the value they
    // say, a run where its cells form one, or null after an error.
    static ConAttr getChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
                              ::mlir::MLIRContext *context, ::mlir::SymbolRefAttr ctor,
                              ::llvm::ArrayRef<::mlir::ArrayAttr> cells, ::mlir::Attribute tail,
                              unsigned spine, ::mlir::Type type);
  private:
    // The attribute of stored parameters that get, getRun and the parser
    // have made canonical. ODS completes the storage only in the unit that
    // registers it, so these reach Base::get and Base::getChecked there.
    static ConAttr getStored(::mlir::MLIRContext *context, ::mlir::SymbolRefAttr ctor,
                             ::llvm::ArrayRef<::mlir::ArrayAttr> cells, ::mlir::Attribute tail,
                             unsigned spine, ::mlir::Type type);
    static ConAttr getStoredChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
                                    ::mlir::MLIRContext *context, ::mlir::SymbolRefAttr ctor,
                                    ::llvm::ArrayRef<::mlir::ArrayAttr> cells,
                                    ::mlir::Attribute tail, unsigned spine, ::mlir::Type type);
  public:
  }];
  let extraClassDefinition = [{
    $cppClass $cppClass::getStored(::mlir::MLIRContext *context, ::mlir::SymbolRefAttr ctor,
                                   ::llvm::ArrayRef<::mlir::ArrayAttr> cells,
                                   ::mlir::Attribute tail, unsigned spine, ::mlir::Type type) {
      return Base::get(context, ctor, cells, tail, spine, type);
    }
    $cppClass $cppClass::getStoredChecked(
        ::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
        ::mlir::MLIRContext *context, ::mlir::SymbolRefAttr ctor,
        ::llvm::ArrayRef<::mlir::ArrayAttr> cells, ::mlir::Attribute tail, unsigned spine,
        ::mlir::Type type) {
      return Base::getChecked(emitError, context, ctor, cells, tail, spine, type);
    }
  }];
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
// Facts about functions (lib/Facts)
//===----------------------------------------------------------------------===//

// What a call of a function may do besides computing its results, as
// idr-effects finds it: `io`, perform IO, which takes a world, so only a
// function that takes one can, or anything at all, as a function without
// a body may; `crash`, end the program with a crash; `diverge`, never
// return, which a function may where its own body loops without Idris's
// proof (no `idr.total`) or where it reaches one that may. The attribute
// is `idr.effects` on every function. Simplification only removes what a
// function reaches, so a stale value says too much, never too little; a
// function without it may do anything.
def Idr_Effect : I32BitEnumAttr<"Effect", "what a call of a function may do", [
      I32BitEnumAttrCaseNone<"none">,
      I32BitEnumAttrCaseBit<"io", 0>,
      I32BitEnumAttrCaseBit<"crash", 1>,
      I32BitEnumAttrCaseBit<"diverge", 2>]> {
  let cppNamespace = "::idr";
  let separator = ", ";
  let genSpecializedAttr = 0;
}

def Idr_EffectAttr : EnumAttr<Idr_Dialect, Idr_Effect, "effects">;

//===----------------------------------------------------------------------===//
// What an op declares once, for every pass to derive from (Idr.h)
//===----------------------------------------------------------------------===//

def Idr_CrashResource : Resource<"::idr::CrashResource">;
def Idr_IOResource : Resource<"::idr::IOResource">;
def Idr_DivergenceResource : Resource<"::idr::DivergenceResource">;
def Idr_LinResource : Resource<"::idr::LinResource">;
def Idr_ReferenceResource : Resource<"::idr::ReferenceResource">;

// Every discardable attribute of an idr op is one the dialect defines, or
// one our own tools read.
def Idr_KnownAttributes : NativeOpTrait<"KnownAttributes"> {
  let cppNamespace = "::idr";
}

// An op's verify() runs before the ops of its regions are verified, when one
// of them may still hold a null operand or lack an attribute: a tool that
// drops uses, as idris-mlir-reduce does, leaves such ops behind. So a check
// that reads an op of a region is in verifyRegions (hasRegionVerifier),
// which runs after them, and verify() reads only the op and the arguments
// of its regions' blocks.
class Idr_Op<string mnemonic, list<Trait> traits = []>
    : Op<Idr_Dialect, mnemonic, !listconcat(traits, [Idr_KnownAttributes])>;

// The op lowers to a call of the runtime's C function named after it:
// `idr.str.append` calls `idris_rt_str_append`. Lowering gives every op
// with this trait that pattern.
def Idr_CallsRuntime : NativeOpTrait<"CallsRuntime"> {
  let cppNamespace = "::idr";
}

// An op that may end the program. Its cause is the text of the crash
// message; its effects and speculatability follow.
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

// The idr.io ops, which idr-effects looks for.
def Idr_PerformsIO : NativeOpTrait<"PerformsIO"> {
  let cppNamespace = "::idr";
}

// Where an op takes over the reference an operand holds, said once, here,
// beside the op: idr-rc places counts by it (idr::consumes), and after idr-rc
// an op whose only effect is what it takes over reports a Free of what it
// takes owned (idr::consumedEffects), so that no pass drops it as dead.
def Idr_ConsumingOpInterface : OpInterface<"ConsumingOpInterface"> {
  let cppNamespace = "::idr";
  let description = "An op that takes over the reference an operand holds.";
  let methods = [
    InterfaceMethod<"Whether the operand at `number` is taken over.",
                    "bool", "consumesOperand", (ins "unsigned":$number), "",
                    [{ return $_op.consumedByTrait(number); }]>,
  ];
}

// `groups`: the ODS operand groups the op takes over, as "0" or "0, 2".
// The trait is ::idr::ConsumesOperands<groups>::Impl: a ParamNativeOpTrait
// names ::mlir::OpTrait:: unless its class sets the namespace, as
// Idr_MayCrashTrait does.
class Idr_ConsumesOperandsTrait<string groups>
    : ParamNativeOpTrait<"ConsumesOperands", groups> {
  let cppNamespace = "::idr";
}
class Idr_Consumes<string groups>
    : TraitList<[Idr_ConsumesOperandsTrait<groups>, Idr_ConsumingOpInterface]>;

// An op whose only effect is what it takes over, reported by the trait.
class Idr_ConsumesOnly<string groups>
    : TraitList<[Idr_Consumes<groups>, MemoryEffectsOpInterface, AlwaysSpeculatable]>;

// An op Idris names as a primitive: idris-mlir-tblgen generates its
// constructor of `IdrPrim` (or `IdrRegionPrim`) for the Idris side.
def Idr_Primitive : NativeOpTrait<"Primitive"> { let cppNamespace = "::idr"; }

//===----------------------------------------------------------------------===//
// Data declarations
//===----------------------------------------------------------------------===//

// A declaration that is public, always: an idr.data, which the types of
// values name, and no type of a value counts as a use of a symbol; and its
// constructors, whose positions are their tags. No pass may take one for
// unused, so none may make one private.
def Idr_PublicSymbol : NativeOpTrait<"PublicSymbol"> {
  let cppNamespace = "::idr";
}

def Idr_DataOp : Idr_Op<"data", [SymbolName, Idr_PublicSymbol, Symbol, SymbolTable,
    IsolatedFromAbove, NoRegionArguments, SingleBlock, NoTerminator,
    HasParent<"::mlir::ModuleOp">]> {
  let summary = "declares a monomorphic data type, unboxed or boxed";
  // `closures`: a sum idr-defunctionalize made of closures, one constructor
  // per label, named after the label's function, whose fields are its
  // captures: a value of it is a closure.
  // `memo`: a sum idr-defunctionalize made of a lazy type, always a box, so
  // that two references see one memo: one constructor per label, as a
  // closure sum has, then `running` and `forced` with the value. A force
  // writes its cell from one state into the next. `labels` names the label
  // functions, here where the module resolves them, so that every
  // interprocedural analysis before idr-lower sees each one taken by address
  // and keeps its body.
  let arguments = (ins SymbolNameAttr:$sym_name, UnitAttr:$box, UnitAttr:$closures,
                       UnitAttr:$memo, OptionalAttr<FlatSymbolRefArrayAttr>:$labels);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = [{
    $sym_name (`box` $box^)? (`closures` $closures^)? (`memo` $memo^)?
    (`labels` $labels^)? attr-dict-with-keyword $body
  }];
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    ::llvm::SmallVector<class CtorOp> getCtors();
    // The type of a value of this declaration: !idr.box or !idr.data.
    ::mlir::Type getValueType();
  }];
}

// A field's quantity is its type: !idr.erased, !idr.lin<T> or T. A
// constructor's tag is its position in its declaration, so no attribute
// restates it. `by_name`: a label of a memo sum whose function reaches an
// observable effect, so that the effect happens where the value is demanded:
// its cell is never written, and every force runs the function.
def Idr_CtorOp : Idr_Op<"ctor", [SymbolName, Idr_PublicSymbol, Symbol, HasParent<"DataOp">]> {
  let summary = "declares one constructor of an idr.data type";
  let arguments = (ins SymbolNameAttr:$sym_name, TypeArrayAttr:$field_types,
                       UnitAttr:$by_name);
  let assemblyFormat = [{
    $sym_name custom<FieldTypes>($field_types) (`by_name` $by_name^)? attr-dict
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::Type getFieldType(unsigned index);
    // The tag: the position among the constructors of the declaration.
    unsigned getTag();
  }];
}

//===----------------------------------------------------------------------===//
// Values
//===----------------------------------------------------------------------===//

// A constant big or natural has its value's range (lib/Dialect/BigRanges.cc);
// any other constant is not an integer, and has none.
def Idr_ConstantOp : Idr_Op<"constant", [ConstantLike, Pure,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
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

// A box's idr.con allocates its result; any other is Pure, until idr-rc
// makes its fields owned, which it takes over.
def Idr_ConOp : Idr_Op<"con", [
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    Idr_Consumes<"0">]> {
  let summary = "builds a constructor value";
  let arguments = (ins SymbolRefAttr:$ctor, Variadic<AnyType>:$fields);
  let results = (outs Idr_SumValue:$result);
  let assemblyFormat = [{
    $ctor `(` $fields `)` attr-dict `:` functional-type($fields, $result)
  }];
  let hasFolder = 1;
}

// A sum's field is one of its slots, there whatever constructor built the
// value, so reading another constructor's gives an unspecified value: the
// read may run anywhere (it is speculatable). A box's field is a load from
// its cell, which is as large as its own constructor (an atom is its header
// alone), so reading a larger constructor's field from it would load past
// its end: the read stays where its constructor is known, under its match
// or after the test of its tag, and moves nowhere it would run without them
// (it is not speculatable). Neither read has a memory effect though a box's
// loads from the cell, because a cell never changes while a reference to it
// is live: it is written when it is built (a field built pending once more,
// through its destination, before anything reads it), and reused only
// through the token of a box idr.take consumed. In the owned stage, where
// references end, the verifier refuses a read through a view once the
// reference the view borrows is gone, so a pass that moves a read past its
// cell's drop fails there instead of reading a freed cell.
def Idr_FieldOp : Idr_Op<"field", [NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "reads a field of a constructor value";
  let arguments = (ins Idr_SumType:$value, FlatSymbolRefAttr:$ctor,
                       I64Attr:$index);
  let results = (outs AnyType:$result);
  let assemblyFormat = [{
    $value `[` $ctor `,` $index `]` attr-dict `:` type($value) `->` type($result)
  }];
  let hasFolder = 1;
  let hasCanonicalizeMethod = 1;
}

// The tag is in [0, n-1] for n constructors. It is Pure though it may load
// the cell's header, for idr.field's reason: a cell never changes while a
// reference to it is live, and the owned stage refuses a read once the
// reference is gone.
def Idr_TagOp : Idr_Op<"tag", [Pure,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the constructor tag of a value";
  let arguments = (ins Idr_SumType:$value);
  let results = (outs I64:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasFolder = 1;
}

//===----------------------------------------------------------------------===//
// Destinations (lib/Tail/Trmc.cppm)
//===----------------------------------------------------------------------===//

// A recursion that returns a constructor around its own result, `Cons x
// (copy xs)`, builds the constructor first, without that field, and gives
// the field to the recursive call as a destination to write once it has
// the value: a cell's field is then written top down and the recursion is
// a tail call, so idr-tail-loops makes it a loop.

def Idr_DestType : Idr_Type<"Dest", "dest"> {
  let summary = "a field of a cell built without it, to be written exactly once";
  let parameters = (ins "::mlir::Type":$value);
  let assemblyFormat = "`<` $value `>`";
  let genVerifyDecl = 1;
}

def Idr_PendingOp : Idr_Op<"dest.pending", [Pure]> {
  let summary = "the operand of a constructor for a field it is built without";
  let description = [{
    No value: the field is written later, through the destination
    `idr.dest.of` names. A constructor with a pending field is never
    static, and nothing reads the field before it is written.
  }];
  let results = (outs AnyType:$result);
  let assemblyFormat = "attr-dict `:` type($result)";
}

def Idr_DestOfOp : Idr_Op<"dest.of", [Pure,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "the destination that is a pending field of a cell just built";
  let arguments = (ins Idr_BoxType:$value, FlatSymbolRefAttr:$ctor, I64Attr:$index);
  let results = (outs Idr_DestType:$result);
  let assemblyFormat = [{
    $value `[` $ctor `,` $index `]` attr-dict `:` type($value) `->` type($result)
  }];
  let hasVerifier = 1;
}

// The value is what the destination holds, owned or exclusive.
def Idr_DestWriteOp : Idr_Op<"dest.write", [
    PredOpTrait<"the value is what the destination holds, owned",
      And<[CPred<"::idr::isOwned($value.getType())">,
           CPred<"::idr::view($value.getType()) == ::llvm::cast<::idr::DestType>($dest.getType()).getValue()">]>>,
    Idr_Consumes<"1">]> {
  let summary = "writes the value of a pending field, consuming its reference";
  let arguments = (ins Arg<Idr_DestType, "", [MemWrite]>:$dest, AnyType:$value);
  let assemblyFormat = "$dest `,` $value attr-dict `:` type($dest) `,` type($value)";
}

//===----------------------------------------------------------------------===//
// Matches
//===----------------------------------------------------------------------===//

// Region i < cases.size() is the case cases[i]; one more region is the default.
class Idr_MatchOpBase<string mnemonic, list<Trait> traits = []>
    : Idr_Op<mnemonic, !listconcat(traits, [RecursiveMemoryEffects,
        RecursivelySpeculatable, SingleBlock,
        DeclareOpInterfaceMethods<RegionBranchOpInterface,
            ["getEntrySuccessorRegions", "getRegionInvocationBounds",
             "getSuccessorInputs"]>])> {
  let results = (outs Variadic<AnyType>:$results);
  let regions = (region VariadicRegion<SizedRegion<1>>:$regions);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
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
  let summary = "branches on the constructor of a sum or box, taking it apart at its grade";
  let description = [{
    The scrutinee is taken at its grade: a linear one is used by the match,
    and each case binds the constructor's fields at the product of the
    scrutinee's quantity and the field's, as Idris binds pattern variables.
    The default region binds nothing, or takes a scrutinee no case took
    apart back at its type.
  }];
  let arguments = (ins Idr_SumView:$scrutinee, ArrayAttr:$cases);
}

// A condition (i1) too: idr-rc makes a select of counted values a match
// on its condition, so that each branch consumes what it yields.
def Idr_MatchLitOp : Idr_MatchOpBase<"match_lit"> {
  let summary = "branches on the value of a condition, integer, string, big or natural";
  let arguments = (ins AnyTypeOf<[I1, Idr_Int, Idr_StrType, Idr_BigType,
                                  Idr_NatType]>:$scrutinee,
                       ArrayAttr:$cases);
}

// A match and an array loop branch into their regions, and the yield goes on
// to what its parent says. A lambda or a delay does not: its body runs when
// the closure is applied or the suspension forced, so the yield that ends it
// has no region successor (lib/Dialect/Ops/Regions.cc), where the interface's
// default would ask the parent as a region branch, which it is not.
def Idr_YieldOp : Idr_Op<"yield", [Idr_ConsumesOnly<"0">, ReturnLike, Terminator,
    ParentOneOf<["MatchOp", "MatchLitOp", "ArrayGenerateOp", "ArrayFoldOp",
                 "LambdaOp", "DelayOp"]>,
    DeclareOpInterfaceMethods<RegionBranchTerminatorOpInterface,
        ["getMutableSuccessorOperands", "getSuccessorRegions"]>]> {
  let summary = "ends a region of a match, a lambda or a delay, or the body of an array loop, with its results";
  let arguments = (ins Variadic<AnyType>:$results);
  let assemblyFormat = "attr-dict ($results^ `:` type($results))?";
}

//===----------------------------------------------------------------------===//
// Closures
//===----------------------------------------------------------------------===//

// A closure takes its captures over.
def Idr_ClosureOp : Idr_Op<"closure", [Idr_ConsumesOnly<"0">,
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

// Builds the cell, which takes the captures over. Does not run the
// function: a force does, the first one, or every one for a label that is
// `by_name`. Folding to #idr.closure keeps one constant for every use, the
// same attribute a closure uses, at this type.
def Idr_SuspendOp : Idr_Op<"suspend", [Idr_ConsumesOnly<"0">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "a suspension of a function: every parameter is a capture";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$captures);
  let results = (outs Idr_LazyValue:$result);
  let assemblyFormat = [{
    $callee `(` $captures `)` attr-dict `:` functional-type($captures, $result)
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
}

// What Emit writes for a lambda and for a delay: the body is the region, and
// the captures are the values it uses from above. Building either runs
// nothing, so the body's effects are not the op's, as they are not an
// idr.closure's or an idr.suspend's. The lambda's block takes the parameters
// of its !idr.fn type, the delay's none, and each ends in idr.yield of the
// result, or in ub.unreachable. idr-isolate, the first step, makes each an
// idr.closure or idr.suspend of a function of its own, the captures its
// leading parameters.
def Idr_LambdaOp : Idr_Op<"lambda", [SingleBlock, Pure,
    AutomaticAllocationScope]> {
  let summary = "a closure whose body is its region; its captures are the values it uses from above";
  let results = (outs Idr_FnType:$result);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "attr-dict `:` qualified(type($result)) $body";
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
}

def Idr_DelayOp : Idr_Op<"delay", [SingleBlock, Pure]> {
  let summary = "a suspension whose body is its region; its captures are the values it uses from above";
  let results = (outs Idr_LazyValue:$result);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "attr-dict `:` type($result) $body";
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
}

// Reads the cell: a suspension, or, after idr-defunctionalize, the box of a
// memo sum. Not a call of a shared suspension: that would run the body at
// every use. A suspension with this one use is the call, at this point. Its
// effects are the cell's: none for a view of a cell that memoizes, so an
// unused force is erased; the cell freed when the force takes it over; the
// IO resource when a label of its sum is `by_name`. Not speculatable, so one
// is not hoisted into a path that did not force. Whether it takes its cell
// over is where it is, its operand's last use, as for a match's scrutinee,
// not a fact of the op, so it does not declare consumption.
def Idr_ForceOp : Idr_Op<"force", [
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>]> {
  let summary = "the value of a suspension, computed on the first force and shared";
  let arguments = (ins AnyTypeOf<[Idr_LazyValue, Idr_BoxValue]>:$suspension);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$suspension attr-dict `:` type($suspension) `->` type($result)";
  let hasVerifier = 1;
  let hasCanonicalizer = 1;
}

// The callee is a value, so the effects are unknown. The arguments are
// taken over, as a call's are.
def Idr_ApplyOp : Idr_Op<"apply", [CallOpInterface,
    TypesMatchWith<"callee input types match argument types", "callee", "args",
                   "::llvm::cast<FnType>($_self).getInputs()",
                   "::idr::sameCarriers">,
    TypesMatchWith<"callee result types match result types", "callee", "results",
                   "::llvm::cast<FnType>($_self).getResults()",
                   "::idr::sameCarriers">,
    Idr_Consumes<"1">]> {
  let summary = "applies a closure to arguments";
  let arguments = (ins Idr_FnType:$callee, Variadic<AnyType>:$args,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs);
  let results = (outs Variadic<AnyType>:$results);
  // The parameter and result attributes are written as func.call_indirect
  // writes its own.
  let assemblyFormat = [{
    $callee `(` $args `)`
    oilist<`,`>(
        `arg_attrs` `=` $arg_attrs
      | `res_attrs` `=` $res_attrs
    )
    attr-dict `:` qualified(type($callee))
  }];
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

// A case the definition does not cover, followed by ub.unreachable.
def Idr_CrashOp : Idr_Op<"crash", [Idr_MayCrash<>]> {
  let summary = "ends the program with a message naming the cause";
  let arguments = (ins StrAttr:$message);
  let assemblyFormat = "$message attr-dict";
}

// A trusted library's crash of a string it computed. The message is the
// string's text. The op does not return; Emit follows it with unreachable.
def Idr_CrashStrOp : Idr_Op<"crash_str", [Idr_CallsRuntime, Idr_MayCrash<>, Idr_Primitive]> {
  let summary = "ends the program with a string's text";
  let arguments = (ins Idr_StrType:$message);
  let assemblyFormat = "$message attr-dict";
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() {
      return ::llvm::StringRef("idris_crash");
    }
  }];
}

// Created by idr-tail-loops in loops of functions that are not total; never
// written by Emit. MLIR deletes a region op without effects even if it never
// finishes; this op's effect keeps such a loop, and orders it with output as
// a crash is. It lowers to llvm.sideeffect, before which idr-meter counts the
// tick that lets idr-eval stop a call that does not end.
def Idr_MayLoopOp : Idr_Op<"may_loop", [MemoryEffects<[
    MemWrite<Idr_DivergenceResource>, MemWrite<Idr_IOResource>]>]> {
  let summary = "marks one iteration of a loop that may not terminate";
  let assemblyFormat = "attr-dict";
}

//===----------------------------------------------------------------------===//
// Guards
//===----------------------------------------------------------------------===//

// What a pass asks of any guard, so that none lists the guards: the
// condition it checks, and the operand it guards.
def Idr_GuardOpInterface : OpInterface<"GuardOpInterface"> {
  let cppNamespace = "::idr";
  let description = "A guard: crashes unless its condition holds, else gives its operand.";
  let methods = [
    InterfaceMethod<"The condition the guard checks.", "::idr::CheckKind", "getKind">,
    InterfaceMethod<"The operand whose value the guard's result passes on.",
                    "::mlir::Value", "getGuarded">,
  ];
}

// A partial primitive is a guard and a total op. The guard crashes with its
// cause, the text of the crash message, when its condition fails, and
// otherwise gives its operand, which the total op takes in the operand's
// place: the op stays below its check by data dependence, and a pass that
// builds the op on an operand nothing proved builds the guard too. A proof
// is the absence of the guard. A guard folds to its operand where the
// operand shows its condition holds (lib/Dialect/Ops/Check.cc), and
// idr-in-bounds erases those it proves where they run. The result of a guard
// with an integer range is the operand's range clamped by the condition.
// `kind` is the guard's ::idr::CheckKind. The operand a guard guards is its
// first, which its folder and its lowering give as its result.
class Idr_CheckOp<string mnemonic, string kind, list<Trait> traits = []>
    : Idr_Op<"check." # mnemonic, !listconcat(traits, [Idr_MayCrash<>,
        DeclareOpInterfaceMethods<Idr_GuardOpInterface>])> {
  // nonzero and nonempty also take their operand's reference over and give
  // it to their result (Idr_Consumes), whose trait offers getEffects too: a
  // guard's effects are its crash's alone.
  let extraClassDeclaration = [{
    using ::idr::MayCrash<false>::Impl<ConcreteOpType>::getEffects;
  }];
  let extraClassDefinition = [{
    std::optional<::llvm::StringRef> $cppClass::getCrashCause() { return getCause(); }
    ::idr::CheckKind $cppClass::getKind() { return ::idr::CheckKind::}] # kind # [{; }
    ::mlir::Value $cppClass::getGuarded() { return getOperation()->getOperand(0); }
  }];
  let hasFolder = 1;
}

def Idr_CheckNonzeroOp : Idr_CheckOp<"nonzero", "Nonzero", [SameOperandsAndResultType,
    Idr_Consumes<"0">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the value, which must not be zero, else the program crashes";
  let arguments = (ins AnyTypeOf<[Idr_Int, Idr_BigValue]>:$value, StrAttr:$cause);
  let results = (outs AnyTypeOf<[Idr_Int, Idr_BigValue]>:$checked);
  let assemblyFormat = "$value `,` $cause attr-dict `:` type($value)";
}

def Idr_CheckInBoundsOp : Idr_CheckOp<"in_bounds", "InBounds", [
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the index, which must be at least 0 and below the length, else the program crashes";
  let arguments = (ins I64:$index, I64:$length, StrAttr:$cause);
  let results = (outs I64:$checked);
  let assemblyFormat = "$index `,` $length `,` $cause attr-dict";
}

def Idr_CheckNonemptyOp : Idr_CheckOp<"nonempty", "Nonempty", [SameOperandsAndResultType,
    Idr_Consumes<"0">]> {
  let summary = "the string, which must have at least one byte, else the program crashes";
  let arguments = (ins Idr_StrValue:$str, StrAttr:$cause);
  let results = (outs Idr_StrValue:$checked);
  let assemblyFormat = "$str `,` $cause attr-dict `:` type($str)";
}

def Idr_CheckByteOp : Idr_CheckOp<"byte", "Byte", [
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the value, which must be from 0 to 255, else the program crashes";
  let arguments = (ins I64:$value, StrAttr:$cause);
  let results = (outs I64:$checked);
  let assemblyFormat = "$value `,` $cause attr-dict";
}

def Idr_CheckFiniteOp : Idr_CheckOp<"finite", "Finite"> {
  let summary = "the value, which must be neither NaN nor infinite, else the program crashes";
  let arguments = (ins F64:$value, StrAttr:$cause);
  let results = (outs F64:$checked);
  let assemblyFormat = "$value `,` $cause attr-dict";
}

// The bytes [offset, offset + count) of something of `size` bytes: both at
// least 0, and the end, computed without overflow, at most the size.
def Idr_CheckRangeOp : Idr_CheckOp<"range", "Range", [
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the offset, whose range of `count` bytes must lie in `size`, else the program crashes";
  let arguments = (ins I64:$offset, I64:$count, I64:$size, StrAttr:$cause);
  let results = (outs I64:$checked);
  let assemblyFormat = "$offset `,` $count `,` $size `,` $cause attr-dict";
}

//===----------------------------------------------------------------------===//
// Scalars
//===----------------------------------------------------------------------===//

// The divisor is not zero: idr.check.nonzero guards it.
class Idr_DivisionOp<string mnemonic, bit isQuotient>
    : Idr_Op<mnemonic, [SameOperandsAndResultType, NoMemoryEffect,
                        DeclareOpInterfaceMethods<ConditionallySpeculatable>]> {
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$lhs, Idr_Int:$rhs);
  let results = (outs Idr_Int:$result);
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
  }];
}

def Idr_DivOp : Idr_DivisionOp<"div", 1> {
  let summary = "Idris div: Euclidean when signed, of a divisor that is not zero";
}
def Idr_ModOp : Idr_DivisionOp<"mod", 0> {
  let summary = "Idris mod: Euclidean when signed, of a divisor that is not zero";
}

// Idris's shifts of a fixed-width integer: the value shifted
// arithmetically by the amount, then wrapped to the type's width. So a
// left shift by the width or more is 0, a right shift by it or more is the
// sign (0 or -1; 0 when unsigned), and a negative amount shifts the other
// way. Defined for every amount, unlike arith's shifts, which are poison
// from the width up.
class Idr_ShiftOp<string mnemonic, bit isLeft>
    : Idr_Op<mnemonic, [Pure, SameOperandsAndResultType]> {
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$lhs, Idr_Int:$rhs);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $lhs `,` $rhs attr-dict `:` type($result)
  }];
  let hasFolder = 1;
  let extraClassDeclaration = "static constexpr bool left = "
                              # !if(isLeft, "true", "false") # ";";
  let extraClassDefinition = [{
    ::mlir::OpFoldResult $cppClass::fold(FoldAdaptor adaptor) {
      return foldShift(*this, adaptor);
    }
  }];
}

def Idr_ShlOp : Idr_ShiftOp<"shl", 1> {
  let summary = "Idris shiftL: defined for every amount, wrapped to the width";
}
def Idr_ShrOp : Idr_ShiftOp<"shr", 0> {
  let summary = "Idris shiftR: arithmetic, defined for every amount";
}

def Idr_ToCharOp : Idr_Op<"to_char", [Pure,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "an integer as a Char: itself if a scalar value, else 0";
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value);
  let results = (outs I32:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
  }];
  let hasFolder = 1;
}

// An Int written as a byte of a buffer, which is 0 to 255: idr.check.byte
// guards it, as Chez's bytevector-u8-set! refuses any other.
def Idr_ToByteOp : Idr_Op<"to_byte", [NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "an Int from 0 to 255 as a byte";
  let arguments = (ins I64:$value);
  let results = (outs I8:$result);
  let assemblyFormat = "$value attr-dict";
  let hasFolder = 1;
}

// Truncates toward zero and wraps to the result width. The Double is
// finite: idr.check.finite guards it.
def Idr_ToIntOp : Idr_Op<"to_int", [Idr_CallsRuntime, NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>, Idr_Primitive]> {
  let summary = "a finite Double as an integer, truncated and wrapped";
  let arguments = (ins F64:$value);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
  let hasFolder = 1;
}

// The first character of prim__cast_DoubleString.
def Idr_DoubleHeadOp : Idr_Op<"double_head", [Pure, Idr_CallsRuntime, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the first character of a Double's text";
  let arguments = (ins F64:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "$value attr-dict";
}

// The first character of the decimal text of an integer.
def Idr_IntHeadOp : Idr_Op<"int_head", [Pure, Idr_CallsRuntime,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the first character of an integer's decimal text";
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value);
  let results = (outs I32:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
  }];
}

//===----------------------------------------------------------------------===//
// Strings
//===----------------------------------------------------------------------===//

// A string builder allocates its result (MemAlloc).
class Idr_StrBuilderOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<"str." # mnemonic, !listconcat(traits, [Idr_CallsRuntime])> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$result);
}

def Idr_StrAppendOp : Idr_StrBuilderOp<"append", [Idr_Primitive]> {
  let summary = "the concatenation of two strings";
  let arguments = (ins Idr_StrType:$lhs, Idr_StrType:$rhs);
  let assemblyFormat = "$lhs `,` $rhs attr-dict custom<StrResult>(type($result))";
}

def Idr_StrConsOp : Idr_StrBuilderOp<"cons", [Idr_Primitive]> {
  let summary = "a character before a string";
  let arguments = (ins I32:$head, Idr_StrType:$tail);
  let assemblyFormat = "$head `,` $tail attr-dict custom<StrResult>(type($result))";
}

def Idr_StrFromCharOp : Idr_StrBuilderOp<"from_char", [Idr_Primitive]> {
  let summary = "the string of one character";
  let arguments = (ins I32:$value);
  let assemblyFormat = "$value attr-dict custom<StrResult>(type($result))";
}

// A string built once from a list the Prelude would build a piece at a
// time: pack over a List Char, concat over a List String. The list is a
// box of a nil without fields and a cons of the element and the rest; the
// op walks it twice, once for the size of the result and once to write it.
def Idr_StrPackOp : Idr_StrBuilderOp<"pack", [Idr_Primitive]> {
  let summary = "the string of a list of characters, built once";
  let arguments = (ins Idr_SumValue:$list);
  let assemblyFormat = "$list attr-dict `:` type($list) `->` type($result)";
  let hasVerifier = 1;
}

def Idr_StrConcatOp : Idr_StrBuilderOp<"concat", [Idr_Primitive]> {
  let summary = "the concatenation of a list of strings, built once";
  let arguments = (ins Idr_SumValue:$list);
  let assemblyFormat = "$list attr-dict `:` type($list) `->` type($result)";
  let hasVerifier = 1;
}

// Output of a list pack or concat walks: its characters or its strings,
// written in order, each as put_char or put_str writes it, which is what
// writing the list's pack or concat writes. Output of a pack or a concat
// whose string has no other use becomes this op, and the string is never
// built. Where the op meets the list's constructor it takes one step of
// the walk: the nil writes nothing, and a cell writes its element before
// the rest, so a cell built only to be written is not built. It is IO, as
// the idr.io ops are, but calls no runtime function named after it: its
// lowering walks the list (Lower/Strings.cc).
def Idr_PutListOp : Idr_Op<"io.put_list", [Idr_PerformsIO, Idr_Primitive,
    MemoryEffects<[MemRead<Idr_IOResource>, MemWrite<Idr_IOResource>]>]> {
  let summary = "writes the characters or the strings of a list, in order";
  let arguments = (ins Idr_SumValue:$list, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$list `,` $world attr-dict `:` type($list)";
  let hasVerifier = 1;
  let hasCanonicalizer = 1;
  let extraClassDeclaration = [{
    // What the list holds: i32, a character, or !idr.str; null when it is
    // not a list of either, which the verifier refuses.
    ::mlir::Type getElementType();
  }];
}

// `signed` or `unsigned` for an integer, nothing for a Double.
def Idr_StrShowOp : Idr_StrBuilderOp<"show"> {
  let summary = "the text of a number, as prim__cast_TString writes it";
  let arguments = (ins UnitAttr:$is_signed, AnyTypeOf<[Idr_Int, F64]>:$value);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value) custom<StrResult>(type($result))
  }];
  let hasVerifier = 1;
}

def Idr_StrSubstrOp : Idr_StrBuilderOp<"substr", [Idr_Primitive]> {
  let summary = "the characters of a string from a start, at most a length";
  let arguments = (ins Idr_StrType:$str, I64:$start, I64:$length);
  let assemblyFormat = "$str `,` $start `,` $length attr-dict custom<StrResult>(type($result))";
}

def Idr_StrReverseOp : Idr_StrBuilderOp<"reverse", [Idr_Primitive]> {
  let summary = "the characters of a string in reverse order";
  let arguments = (ins Idr_StrType:$str);
  let assemblyFormat = "$str attr-dict custom<StrResult>(type($result))";
}

// The string is not empty: idr.check.nonempty guards it. A new string,
// allocated like a builder's.
def Idr_StrTailOp : Idr_Op<"str.tail", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a string without its first character, of a string that is not empty";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$str attr-dict custom<StrResult>(type($result))";
}

def Idr_StrLengthOp : Idr_Op<"str.length", [Pure, Idr_CallsRuntime, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the number of characters of a string";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs I64:$result);
  let assemblyFormat = "$str attr-dict";
}

// The number of bytes of a string, the length of its UTF-8, interior zeros
// included. Folded by calling the runtime, as str.length is.
def Idr_StrBytesLengthOp : Idr_Op<"str.bytes_length", [Pure, Idr_CallsRuntime, Idr_Primitive]> {
  let hasFolder = 1;
  let summary = "the number of bytes of a string";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs I64:$result);
  let assemblyFormat = "$str attr-dict";
}

// A string by byte offset, as the linear string iterator walks it. Every
// offset has a meaning, so these ops need no guard: it is clamped to the
// string's bytes, and an offset inside a character's encoding stands for
// the start of that character. Folded by calling the runtime.
def Idr_StrScalarAtOp : Idr_Op<"str.scalar_at", [Pure, Idr_CallsRuntime, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "the character that starts at a byte offset, 0 at the end";
  let arguments = (ins Idr_StrType:$str, I64:$offset);
  let results = (outs I32:$result);
  let assemblyFormat = "$str `,` $offset attr-dict";
}

def Idr_StrScalarEndOp : Idr_Op<"str.scalar_end", [Pure, Idr_CallsRuntime, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "the byte offset after the character at a byte offset";
  let arguments = (ins Idr_StrType:$str, I64:$offset);
  let results = (outs I64:$result);
  let assemblyFormat = "$str `,` $offset attr-dict";
}

def Idr_StrDropBytesOp : Idr_StrBuilderOp<"drop_bytes", [Idr_Primitive]> {
  let summary = "the characters of a string from a byte offset on";
  let arguments = (ins Idr_StrType:$str, I64:$offset);
  let assemblyFormat = "$str `,` $offset attr-dict custom<StrResult>(type($result))";
}

// The index is at least 0 and below the string's length: idr.check.in_bounds
// guards it.
def Idr_StrIndexOp : Idr_Op<"str.index", [Idr_CallsRuntime, NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the character at an index within the string";
  let arguments = (ins Idr_StrType:$str, I64:$index);
  let results = (outs I32:$result);
  let assemblyFormat = "$str `,` $index attr-dict";
}

// The string is not empty: idr.check.nonempty guards it.
def Idr_StrHeadOp : Idr_Op<"str.head", [Idr_CallsRuntime, NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the first character of a string that is not empty";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs I32:$result);
  let assemblyFormat = "$str attr-dict";
  let hasCanonicalizer = 1;
}

def Idr_StrCmpOp : Idr_Op<"str.cmp", [Pure, Idr_CallsRuntime]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "compares two strings";
  let arguments = (ins Idr_CmpPredicate:$predicate, Idr_StrType:$lhs,
                       Idr_StrType:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate $lhs `,` $rhs attr-dict";
}

def Idr_StrToIntOp : Idr_Op<"str.to_int", [Pure, Idr_CallsRuntime]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a string as an integer, as prim__cast_StringT reads it";
  let arguments = (ins UnitAttr:$is_signed, Idr_StrType:$str);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $str attr-dict `:` type($result)
  }];
}

def Idr_StrToDoubleOp : Idr_Op<"str.to_double", [Pure, Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a string as a Double, as prim__cast_StringDouble reads it";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs F64:$result);
  let assemblyFormat = "$str attr-dict";
}

//===----------------------------------------------------------------------===//
// Bigs
//===----------------------------------------------------------------------===//

// An op that makes a big allocates its result (MemAlloc).
class Idr_BigBinaryOp<string mnemonic, string what, list<Trait> traits = []>
    : Idr_Op<"big." # mnemonic, !listconcat([Idr_CallsRuntime, Idr_Primitive], traits)> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = what # " of two bigs";
  let arguments = (ins Idr_BigType:$lhs, Idr_BigType:$rhs);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict custom<BigResult>(type($result))";
}

// The sum and the product of two naturals are natural, so these take
// Integers or naturals, and give what they take: Nat's plus and mult are
// these ops. The type is written only for naturals: `: !idr.nat`.
class Idr_BigNaturalOp<string mnemonic, string what>
    : Idr_Op<"big." # mnemonic, [Idr_CallsRuntime, Idr_Primitive, AllTypesMatch<["lhs", "rhs"]>,
                                 Idr_ResultCarriesOperand,
                                 DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = what # " of two bigs or two naturals";
  let arguments = (ins Idr_BigOrNat:$lhs, Idr_BigOrNat:$rhs);
  let results = (outs Res<Idr_BigOrNatValue, "", [MemAlloc]>:$result);
  // The operands' type, written for naturals; the result's when it is
  // the operands' at another grade: `-> !idr.own<!idr.nat>`.
  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict custom<Natural>(type($lhs))
    custom<NaturalResult>(type($result), ref(type($lhs)))
  }];
}

def Idr_BigAddOp : Idr_BigNaturalOp<"add", "the sum">;
def Idr_BigSubOp : Idr_BigBinaryOp<"sub", "the difference", [DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]>;
def Idr_BigMulOp : Idr_BigNaturalOp<"mul", "the product">;
def Idr_BigAndOp : Idr_BigBinaryOp<"and", "the bitwise and">;
def Idr_BigOrOp : Idr_BigBinaryOp<"or", "the bitwise or">;
def Idr_BigXorOp : Idr_BigBinaryOp<"xor", "the bitwise xor">;

// Integer's shifts: the value's infinite two's complement moved by the
// amount, left or right, the other way when the amount is negative. A left
// shift is value * 2^amount and a right shift the floor of value / 2^amount,
// so every amount has a value, and a shift toward zero or of 0 has one for
// any amount; one too large to hold is exhausted memory, unmodelled as it is
// for idr.big.mul, so the ops get no Idr_MayCrash. The amount is an Integer,
// as Idris types the primitive; base's Bits Integer passes a Nat's. A left
// shift's result may be far larger than its operands, so its folder folds
// only a constant within idr::constantBytes.
class Idr_BigShiftOp<string mnemonic, bit isLeft>
    : Idr_Op<"big." # mnemonic, [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let arguments = (ins Idr_BigType:$value, Idr_BigType:$amount);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value `,` $amount attr-dict custom<BigResult>(type($result))";
  let extraClassDeclaration = "static constexpr bool left = "
                              # !if(isLeft, "true", "false") # ";";
}

def Idr_BigShlOp : Idr_BigShiftOp<"shl", 1> {
  let summary = "a big shifted left, Integer's shiftL";
}
def Idr_BigShrOp : Idr_BigShiftOp<"shr", 0> {
  let summary = "a big shifted right, Integer's shiftR, filling with its sign";
}

// The divisor is not zero: idr.check.nonzero guards it.
class Idr_BigDivisionOp<string mnemonic, string what>
    : Idr_Op<"big." # mnemonic, [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = what # " of two bigs, as Integer's div and mod, by a divisor that is not zero";
  let arguments = (ins Idr_BigType:$lhs, Idr_BigType:$rhs);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict custom<BigResult>(type($result))";
}

def Idr_BigDivOp : Idr_BigDivisionOp<"div", "the quotient">;
def Idr_BigModOp : Idr_BigDivisionOp<"mod", "the remainder">;

def Idr_BigNegOp : Idr_Op<"big.neg", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the negation of a big";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<BigResult>(type($result))";
}

// The frontend writes it where a match on a natural found it is not zero,
// so the value visibly shrinks: the passes see structural descent, not
// arithmetic. That the operand is not zero is also why the result is
// natural. A small operand's predecessor is computed inline; a GMP one's
// is a new big, so the op allocates its result like the other big ops.
def Idr_BigPredOp : Idr_Op<"big.pred", [Idr_CallsRuntime,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the predecessor of a natural that is not zero";
  let arguments = (ins Idr_NatType:$value);
  let results = (outs Res<Idr_NatValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<NatResult>(type($result))";
}

// Two naturals compare as the Integers they are: Nat's equalNat and
// compareNat are this op. The type is written only for naturals.
def Idr_BigCmpOp : Idr_Op<"big.cmp", [Pure, Idr_CallsRuntime,
    AllTypesMatch<["lhs", "rhs"]>, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "compares two bigs or two naturals";
  let arguments = (ins Idr_CmpPredicate:$predicate, Idr_BigOrNat:$lhs,
                       Idr_BigOrNat:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate $lhs `,` $rhs attr-dict custom<Natural>(type($lhs))";
}

// A natural as the Integer it is (Nat's natToInteger): the same big under
// another type. It costs nothing at runtime, and hands its operand's
// reference to its result.
def Idr_NatToBigOp : Idr_Op<"nat.to_big", [Idr_ConsumesOnly<"0">, Idr_Primitive,
    TypesMatchWith<"the Integer is the natural at its grade", "value", "result",
                   "::idr::graded(::idr::gradeOf($_self), ::idr::BigType::get($_self.getContext()))">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "a natural as an Integer";
  let arguments = (ins Idr_NatValue:$value);
  let results = (outs Idr_BigValue:$result);
  let assemblyFormat = "$value attr-dict custom<NatResult>(type($value))";
}

// The only op that makes a natural of an Integer, so the one that must
// keep it non-negative: a negative Integer is 0, as Nat's integerToNat
// and minus (the difference of the Integers, clamped) say.
def Idr_NatFromBigOp : Idr_Op<"nat.from_big", [Idr_CallsRuntime, Idr_Primitive, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "an Integer as a natural, 0 if it is negative";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Res<Idr_NatValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<NatResult>(type($result))";
}

// An integer as an Integer, or, read as unsigned, as a natural: an unsigned
// integer is never negative, so the verifier admits a natural result only
// for one (idr-narrow writes it where a natural leaves a word).
def Idr_BigFromIntOp : Idr_Op<"big.from_int", [Idr_CallsRuntime, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let hasVerifier = 1;
  let summary = "an integer as a big or, unsigned, as a natural";
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value);
  let results = (outs Res<Idr_BigOrNatValue, "", [MemAlloc]>:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
    custom<Natural>(type($result))
  }];
}

// The big or natural of a word proved to fit the small range: idr-narrow
// writes it where a web of values it proved small meets a big. A small holds
// no reference and allocates nothing, so counting has nothing to do for it.
// A word outside the small range has no big here, as an overflowing nsw add
// has no sum: the pass that writes the op is the proof.
def Idr_BigSmallOp : Idr_Op<"big.small", [Pure, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "the small big or natural of a word that fits";
  let arguments = (ins I64:$value);
  let results = (outs Idr_BigOrNatValue:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
}

// A natural's value is its Integer's, so both convert alike.
def Idr_BigToIntOp : Idr_Op<"big.to_int", [Pure, Idr_CallsRuntime, Idr_Primitive, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a big or a natural as an integer, wrapped to its width";
  let arguments = (ins Idr_BigOrNat:$value);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = "$value attr-dict `:` type($result) custom<Natural>(type($value))";
}

// The Double is finite: idr.check.finite guards it.
def Idr_BigFromDoubleOp : Idr_Op<"big.from_double", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a finite Double truncated to a big";
  let arguments = (ins F64:$value);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<BigResult>(type($result))";
}

def Idr_BigToDoubleOp : Idr_Op<"big.to_double", [Pure, Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a big as the nearest Double";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs F64:$result);
  let assemblyFormat = "$value attr-dict";
}

def Idr_BigShowOp : Idr_Op<"big.show", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "the decimal text of a big";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<StrResult>(type($result))";
}

def Idr_BigFromStrOp : Idr_Op<"big.from_str", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/Fold).
  let hasFolder = 1;
  let summary = "a string as a big, as prim__cast_StringInteger reads it";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$str attr-dict custom<BigResult>(type($result))";
}

def Idr_ArrayValue : Type<CPred<"::idr::isArray(::idr::unrestricted($_self))">,
                          "an array of rank 0 or 1 at any grade", "::mlir::Type">;
// What has a length: an array of one dimension, as a buffer and the index
// space of a loop are.
def Idr_Rank1ArrayValue : Type<CPred<"::idr::isRank1Array(::idr::unrestricted($_self))">,
                               "an array of one dimension at any grade", "::mlir::Type">;

//===----------------------------------------------------------------------===//
// IO
//===----------------------------------------------------------------------===//

// Each IO op consumes one world and produces the next.
class Idr_IOOp<string mnemonic, list<Trait> traits = []> : Idr_Op<"io." # mnemonic,
    !listconcat(traits, [Idr_PerformsIO, Idr_CallsRuntime,
                         MemoryEffects<[MemRead<Idr_IOResource>,
                                        MemWrite<Idr_IOResource>]>])>;

def Idr_PutStrOp : Idr_IOOp<"put_str", [Idr_Primitive]> {
  let arguments = (ins Idr_StrType:$str, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$str `,` $world attr-dict";
  let hasCanonicalizer = 1;
}

// The UTF-8 encoding of a character, which is a Unicode scalar value: the
// Prelude's putChar, and what writing a one-character string writes, which
// output fusion makes of put_str.
def Idr_PutCharOp : Idr_IOOp<"put_char", [Idr_Primitive]> {
  let arguments = (ins I32:$ch, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$ch `,` $world attr-dict";
}

def Idr_PutIntOp : Idr_IOOp<"put_int"> {
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value `,` $world attr-dict `:` type($value)
  }];
}

def Idr_PutDoubleOp : Idr_IOOp<"put_double", [Idr_Primitive]> {
  let arguments = (ins F64:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$value `,` $world attr-dict";
}

// One byte of input, or 255 at its end.
def Idr_GetByteOp : Idr_IOOp<"get_byte", [Idr_Primitive]> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I32:$ch, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

// A line of input without its end (the Prelude's getLine): the bytes up to
// the next newline, which is consumed, without it or a carriage return
// right before it, decoded as UTF-8 (idris_rt_io_get_line); the empty
// string at the end of input. A new string, allocated like a builder's.
def Idr_GetLineOp : Idr_IOOp<"get_line", [Idr_Primitive]> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$str, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict custom<StrResult>(type($str))";
}

// A transfer of the bytes [offset, offset + count) of a buffer (an array of
// i8) between it and a handle. The range lies in the buffer: idr.check.range
// guards the offset. The op's effects are its own, as the array ops' are.
class Idr_IOTransferOp<string mnemonic> : Idr_Op<"io." # mnemonic,
    [Idr_PerformsIO, Idr_CallsRuntime, Idr_Primitive,
     DeclareOpInterfaceMethods<MemoryEffectsOpInterface>]> {
  let arguments = (ins I64:$handle, Idr_Rank1ArrayValue:$buffer, I64:$offset, I64:$count,
                       Idr_WorldType:$world);
  let assemblyFormat = [{
    $handle `,` $buffer `[` $offset `,` $count `]` `,` $world attr-dict `:` type($buffer)
  }];
  let hasVerifier = 1;
}

// Bytes of a buffer to a handle: 1 is standard output, through the output
// buffer and in order with every other write to it; 2 is standard error; any
// other is a file the program opened (idr.io.file_open). Gives the count
// written.
def Idr_WriteBytesOp : Idr_IOTransferOp<"write_bytes"> {
  let results = (outs I64:$written, Idr_WorldType:$next);
}

// Bytes from a handle into a buffer: 0 is standard input, through the
// runtime's input buffer, and any other a file the program opened. Gives the
// count read, 0 at the end of input, which it then records (idr.io.eof).
def Idr_ReadBytesOp : Idr_IOTransferOp<"read_bytes"> {
  let results = (outs I64:$read, Idr_WorldType:$next);
}

// 1 once a read on the handle met the end of its input, as C's feof reports
// it, else 0: standard input, or a file the program opened.
def Idr_EofOp : Idr_IOOp<"eof", [Idr_Primitive]> {
  let arguments = (ins I64:$handle, Idr_WorldType:$world);
  let results = (outs I64:$ended, Idr_WorldType:$next);
  let assemblyFormat = "$handle `,` $world attr-dict";
}

// How many processors are online, read when the program asks
// (idris_rt_io_n_processors). A system that does not say gives -1, which
// System.Info.getNProcessors turns into Nothing.
def Idr_NProcessorsOp : Idr_IOOp<"n_processors", [Idr_Primitive]> {
  let arguments = (ins Idr_WorldType:$world);
  let results = (outs I64:$count, Idr_WorldType:$next);
  let assemblyFormat = "$world attr-dict";
}

// The operating system the target triple names, in the spelling Idris's
// Scheme backends share and base tests for: "darwin", "unix", "windows",
// or "unknown". Folded to that string. The triple is the module's
// #llvm.target, which idr-target writes from the target entry.
def Idr_OsOp : Idr_Op<"os", [Pure, Idr_Primitive]> {
  let summary = "the operating system the target triple names";
  let results = (outs Idr_StrValue:$result);
  let assemblyFormat = "attr-dict custom<StrResult>(type($result))";
  let hasFolder = 1;
}

// A machine word in a buffer of bytes, at a byte offset. The span is
// `sizeof` the word, and it lies in the buffer: idr.check.range guards the
// offset, as it guards a byte transfer's. The load and the store are the
// target's own, at alignment 1, so the endianness is the machine's and an
// offset need not be aligned. Not a runtime call: the value's width is the
// op's type.
class Idr_BufferAccessOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<"io." # mnemonic, !listconcat(traits, [
        Idr_PerformsIO, Idr_Primitive,
        DeclareOpInterfaceMethods<MemoryEffectsOpInterface>])>;

def Idr_BufferLoadOp : Idr_BufferAccessOp<"buffer_load"> {
  let summary = "a machine word read from a buffer at a byte offset";
  let arguments = (ins Idr_Rank1ArrayValue:$buffer, I64:$offset, Idr_WorldType:$world);
  let results = (outs AnyTypeOf<[I8, I16, I32, I64, F64]>:$value, Idr_WorldType:$next);
  let assemblyFormat = [{
    $buffer `[` $offset `]` `,` $world attr-dict `:` type($buffer) `->` type($value)
  }];
  let hasVerifier = 1;
}

def Idr_BufferStoreOp : Idr_BufferAccessOp<"buffer_store"> {
  let summary = "a machine word written into a buffer at a byte offset";
  let arguments = (ins Idr_Rank1ArrayValue:$buffer, I64:$offset,
                       AnyTypeOf<[I8, I16, I32, I64, F64]>:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    $buffer `[` $offset `]` `,` $value `,` $world attr-dict `:` type($buffer) `,` type($value)
  }];
  let hasVerifier = 1;
}

// Bytes copied from one buffer into another. The two spans each lie in
// their buffer, each guarded by idr.check.range. Overlap is allowed: the
// copy is memmove.
def Idr_BufferCopyOp : Idr_BufferAccessOp<"buffer_copy", [Idr_CallsRuntime]> {
  let summary = "bytes copied from one buffer into another";
  let arguments = (ins Idr_Rank1ArrayValue:$src, I64:$src_offset, I64:$len,
                       Idr_Rank1ArrayValue:$dst, I64:$dst_offset, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    $src `[` $src_offset `,` $len `]` `,` $dst `[` $dst_offset `]` `,` $world attr-dict
    `:` type($src) `,` type($dst)
  }];
  let hasVerifier = 1;
}

// A string's UTF-8 written at an offset. The span is the string's byte
// length, interior zeros included, and lies in the buffer.
def Idr_BufferSetStringOp : Idr_BufferAccessOp<"buffer_set_string", [Idr_CallsRuntime]> {
  let summary = "a string's bytes written into a buffer";
  let arguments = (ins Idr_Rank1ArrayValue:$buffer, I64:$offset, Idr_StrType:$str,
                       Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    $buffer `[` $offset `]` `,` $str `,` $world attr-dict `:` type($buffer)
  }];
  let hasVerifier = 1;
}

// A buffer's bytes read as a string. Ill-formed UTF-8 is replaced as
// idris_rt_str_from_bytes replaces it. A new string.
def Idr_BufferGetStringOp : Idr_BufferAccessOp<"buffer_get_string", [Idr_CallsRuntime]> {
  let summary = "a buffer's bytes read as a string";
  let arguments = (ins Idr_Rank1ArrayValue:$buffer, I64:$offset, I64:$len, Idr_WorldType:$world);
  let results = (outs Idr_StrValue:$str, Idr_WorldType:$next);
  let assemblyFormat = [{
    $buffer `[` $offset `,` $len `]` `,` $world attr-dict `:` type($buffer)
    custom<StrResult>(type($str))
  }];
  let hasVerifier = 1;
}

// A world forged where a trusted library runs an IO action for a pure
// value (`unsafePerformIO`): the first world of a chain of its own, which
// orders that chain; between chains, the effects order the ops, as they
// order any two IO ops. It opens the IO resource, so no pass merges two,
// moves one past an IO op, or deletes one, and every function that reaches
// one performs IO (idr-effects), which keeps compile-time evaluation off
// it. It has no runtime form.
def Idr_WorldNewOp : Idr_Op<"world.new", [Idr_PerformsIO, Idr_Primitive,
    MemoryEffects<[MemWrite<Idr_IOResource>]>]> {
  let summary = "a forged world, the first of a chain of its own";
  let results = (outs Idr_WorldType:$world);
  let assemblyFormat = "attr-dict";
}

//===----------------------------------------------------------------------===//
// Arrays
//===----------------------------------------------------------------------===//

// An array is a builtin memref of rank 0 or 1, each dimension dynamic,
// over a field type E at no grade: the type the memref and bufferization
// passes know, so no array type of our own. `memref<?xE>` (ArrayData,
// Buffer) holds as many elements as it was made with, `memref<E>` (an
// IORef's Mut) holds one. The ops take one size or one index per
// dimension, as memref.alloc and memref.load do, so an IORef's ops are the
// array ops at none. Its cell holds its elements like a constructor's
// fields, so the array is a counted value, an element moves into it with
// its reference, and an element read takes one of its own
// (Lower/Arrays.cc, runtime idris_rt_array).
def Idr_ArrayType : Type<CPred<"::idr::isArray($_self)">,
                         "an array, memref<?xE> or memref<E> of a field type E",
                         "::mlir::MemRefType">;
// The array ops are IO: each takes the world and gives the next, and
// reads or writes the array's cell in that order. Their effects are their
// own (not Idr_IOOp's, whose runtime call they do not make): the IO
// resource, and an allocation for a new array. An element moves in with its
// reference, which the op takes over.
class Idr_ArrayOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<"array." # mnemonic, !listconcat(traits, [Idr_PerformsIO, Idr_Primitive,
        DeclareOpInterfaceMethods<MemoryEffectsOpInterface>])>;

// A new array of the given sizes, one per dimension, each element the
// value `fill`, which moves in (one reference, held by each element: the
// fill takes the others). A negative size is an empty dimension; an array
// of rank 0 has no size and one element. The array's shape is known from
// its sizes (ReifyRankedShapedTypeOpInterface), so `memref.dim` of it
// folds, as upstream folds the dimension of a `memref.alloc`.
def Idr_ArrayNewOp : Idr_ArrayOp<"new", [Idr_Consumes<"1">,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>]> {
  let summary = "a new array of the given sizes, each element `fill`";
  let arguments = (ins Variadic<I64>:$sizes, AnyType:$fill, Idr_WorldType:$world);
  let results = (outs Idr_ArrayValue:$array, Idr_WorldType:$next);
  let assemblyFormat = [{
    ` ` `[` $sizes `]` `,` $fill `,` $world attr-dict `:` type($fill) `->` type($array)
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// An access (get, set) reads its index within the array: an
// idr.check.in_bounds of the index against the array's length guards it,
// and is the access's own check. A proof is the guard's absence:
// idr-in-bounds erases the guards it proves, and a rewrite that builds a new
// access on an index nothing proved builds the guard too, so no pass can
// leave an access that rests on a fact it did not keep. An array of rank 0
// has one element and no index, so its accesses have nothing to guard.

// The element at `indices`, one per dimension, which are within the array.
// One that `moves` gives the element with the reference the array held,
// takes no reference of its own, and leaves the element's place empty
// until the write its world goes to next, of the same element, fills it
// again. MoveOutBeforeSet claims it only where nothing between the two may
// read the array, so nothing sees the empty place, and the verifier holds
// the two together. A value read only to be rebuilt and written back then
// holds the one reference to its cell while it is rebuilt, and counting
// rebuilds it in that cell.
def Idr_ArrayGetOp : Idr_ArrayOp<"get"> {
  let summary = "the element of an array at an index";
  let arguments = (ins Idr_ArrayValue:$array, Variadic<I64>:$indices, Idr_WorldType:$world,
                       UnitProp:$moves);
  let results = (outs AnyType:$value, Idr_WorldType:$next);
  let assemblyFormat = [{
    $array `[` $indices `]` `,` $world (`moves` $moves^)? attr-dict `:` type($array) `->`
    type($value)
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// Writes `value`, which moves in, over the element at `indices`, which are
// within the array; the old element is released, which releases nothing
// when the read before it moved the element out.
def Idr_ArraySetOp : Idr_ArrayOp<"set", [Idr_Consumes<"2">]> {
  let summary = "writes an element of an array at an index";
  let arguments = (ins Idr_ArrayValue:$array, Variadic<I64>:$indices, AnyType:$value,
                       Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    $array `[` $indices `]` `,` $value `,` $world attr-dict `:` type($array) `,` type($value)
  }];
  let hasVerifier = 1;
  let hasCanonicalizer = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// The two loops over an array's index space, graded region ops: the body
// runs once per index it covers, in index order, and what its ops perform
// the loop performs (RecursiveMemoryEffects). The body is its own
// successor, as an scf.for body's is, so a pass that asks which regions
// run again sees the loop instead of a list of op names. A fold forwards
// its accumulator along both edges (the init into the body, and into the
// result when the array is empty; the yield back into the body and out as
// the result). A generate forwards nothing: the yielded word is stored in
// the new array, not passed as an SSA value. Their elements are machine
// words (an integer or a float type), which a memref holds and a vector
// lane computes; the frontend emits them only then, and the library's own
// definition compiles as written for any other element. Lowering makes
// each a linalg.generic over the array's memory (Lower/Loops.cc), and a
// generate whose body is a fold one generic of two dimensions.

// The body of a region primitive: one block, whose entry block takes
// `numArguments` arguments, as SizedRegion's `blocks` counts the blocks it
// checks. idris-mlir-tblgen reads `arguments` for the Idris side's
// regionArity.
class Idr_BodyRegion<int numArguments> : Region<
    And<[CPred<"::llvm::hasNItems($_self, 1)">,
         CPred<"$_self.front().getNumArguments() == " # numArguments>]>,
    "region with 1 block of " # numArguments # " arguments"> {
  int blocks = 1;
  int arguments = numArguments;
}

// A new array of `size` elements: element 0 is `fill`, and element `i` from
// 1 on the body at `i` (an i64). So the library's loop makes it: base's
// primitive fills the new array with the function at 0, and the loop
// applies the function at each index from 1 on, never at 0 again. `fill`
// moves in as array.new's does. A negative size, the least included, is an
// empty array, and the array's shape is known from its size, as
// array.new's.
def Idr_ArrayGenerateOp : Idr_ArrayOp<"generate", [Idr_Consumes<"1">, RecursiveMemoryEffects, SingleBlock,
    DeclareOpInterfaceMethods<RegionBranchOpInterface, ["getEntrySuccessorOperands"]>,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>]> {
  let summary = "a new array of the body's value at each index";
  let arguments = (ins I64:$size, AnyType:$fill, Idr_WorldType:$world);
  let results = (outs Idr_Rank1ArrayValue:$array, Idr_WorldType:$next);
  let regions = (region Idr_BodyRegion<1>:$body);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// The elements folded from the left in index order: the body takes the
// accumulator (`init` first, which moves in), the element (as array.get
// gives it) and the index (an i64), and yields the next accumulator; the
// result is the last.
def Idr_ArrayFoldOp : Idr_ArrayOp<"fold", [Idr_Consumes<"1">, RecursiveMemoryEffects, SingleBlock,
    DeclareOpInterfaceMethods<RegionBranchOpInterface, [
        "getEntrySuccessorOperands", "getSuccessorInputs", "areTypesCompatible"]>]> {
  let summary = "an array folded from the left in index order";
  let arguments = (ins Idr_Rank1ArrayValue:$array, AnyType:$init, Idr_WorldType:$world);
  let results = (outs AnyType:$result, Idr_WorldType:$next);
  let regions = (region Idr_BodyRegion<3>:$body);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

//===----------------------------------------------------------------------===//
// Ownership (lib/Ownership)
//===----------------------------------------------------------------------===//

// idr-rc makes every reference explicit, in the grades: from then on a
// value that holds references is owned, `!idr.own<T>` (the grade
// (many, own) of T), and holds one reference of its own, which exactly one
// use on every path consumes; or it is a view, plain T, which holds none
// and lives while what it was read from does: a borrowed parameter, a
// field, a match's case argument, an `idr.borrow`, or static data, which
// no count reaches. A module that holds an owned or exclusive value is in
// the owned stage, which its grades say and no attribute restates, and the
// verifier checks the stage's rule there, under idr.program (lib/Ownership/Verify.cppm). The ops
// below read and write the counts in cell headers and may free cells, so no
// pass reorders, merges or drops them.

def Idr_TokenType : Idr_Type<"Token", "token"> {
  let summary = "the memory of a cell whose fields idr.take moved out, or null";
}

// The values that hold references: a string, a big or natural (a small one
// holds none), a box, a closure, a token, an array, and an unboxed sum with
// a slot of any of these; at any grade, since a linear field read from a
// cell that lives on needs a reference of its own.
def Idr_CountedValueType : AnyTypeOf<[Idr_DataType, Idr_BoxType, Idr_FnType, Idr_LazyType,
                                      Idr_StrType, Idr_BigType, Idr_NatType, Idr_TokenType,
                                      Idr_ArrayType]>;
def Idr_CountedType : AnyTypeOf<[Idr_CountedValueType,
    Type<And<[CPred<"::llvm::isa<::idr::QType>($_self)">,
              SubstLeaves<"$_self", "::idr::unrestricted($_self)",
                          Idr_CountedValueType.predicate>]>,
         "a graded value that holds references">]>;

// A value that holds one reference of its own, and a view, which holds
// none.
// The accessors give plain values: idr-rc builds these ops on values it
// grades afterwards.
def Idr_OwnType : Type<CPred<"::idr::isOwned($_self)">, "a value that holds a reference",
                       "::mlir::Type">;
def Idr_ViewType : Type<And<[CPred<"!::idr::isOwned($_self)">, Idr_CountedType.predicate]>,
                        "a value that holds no reference">;

// An op that exists only in the owned stage: before idr-rc nothing counts
// references, so a pass that meets one knows the module's stage.
class Idr_OwnedOp<string mnemonic, list<Trait> traits = []> : Idr_Op<mnemonic, traits> {
  let hasVerifier = 1;
}

def Idr_DupOp : Idr_OwnedOp<"dup"> {
  let summary = "a reference of its own to a value that holds none";
  let description = [{
    The value is a view: what it holds lives on, and the result holds one
    more reference to it. Static data, a small big and an empty slot hold
    no count and are left alone; an unboxed sum adds a reference to each of
    its slots. The result is owned, or exclusive (`-> !idr.excl<T>`) when
    the value is static data that reaches no cell but atoms (a constant
    nullary constructor, or a constant unboxed sum of them), which is in
    every exclusive tree: no take hands out a cell of it.
  }];
  let arguments = (ins Arg<Idr_ViewType, "", [MemRead, MemWrite]>:$value);
  let results = (outs Idr_OwnType:$result);
  let assemblyFormat = [{
    $value attr-dict `:` type($value) custom<OwnedResult>(type($result), ref(type($value)))
  }];
}

def Idr_DropOp : Idr_OwnedOp<"drop", [Idr_Consumes<"0">]> {
  let summary = "consumes a reference, and frees the value with its last";
  let description = [{
    Freeing a cell drops its fields' references in turn. The drop of a
    token frees the memory of its cell, whose fields idr.take already moved
    out.
  }];
  let arguments = (ins Arg<Idr_OwnType, "", [MemRead, MemWrite, MemFree]>:$value);
  let assemblyFormat = "$value attr-dict `:` type($value)";
}

// A view of an owned value: reads (a field, a tag, a match, a borrowed
// argument) take views, and a view lives only while its owner holds its
// reference: every use of it comes before the owner's consuming use on
// each path. It has no runtime form.
def Idr_BorrowOp : Idr_Op<"borrow", [Pure,
    TypesMatchWith<"the view is the value without its reference", "value", "result",
                   "::idr::view($_self)">]> {
  let summary = "a view of an owned value, alive while its owner holds its reference";
  let arguments = (ins Idr_OwnType:$value);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
}

// An owned value given on as owned, whatever it alone reached: an
// exclusive value (`!idr.excl<T>`, which idr-rc proves) given to a position
// that takes an owned one, or a value some view of which took a reference
// of its own (idr.dup) before this, its consuming use. Nothing at runtime.
def Idr_ShareOp : Idr_Op<"share", [Idr_ConsumesOnly<"0">,
    TypesMatchWith<"the result is the value with its exclusivity forgotten", "value", "result",
                   "::idr::owned(::idr::view($_self))">]> {
  let summary = "gives an owned value on as owned, whatever it alone reached";
  let arguments = (ins Idr_OwnType:$value);
  let results = (outs Idr_OwnType:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
}

// A token is always owned: idr.take makes it, idr.reuse or idr.drop
// consumes it.
def Idr_OwnedToken : Type<And<[CPred<"::idr::isOwned($_self)">,
                               CPred<"::llvm::isa<::idr::TokenType>(::idr::unrestricted($_self))">]>,
                          "an owned token", "::mlir::Type"> {
  let builderCall = "::idr::owned(::idr::TokenType::get($_builder.getContext()))";
}

def Idr_ReuseOp : Idr_OwnedOp<"reuse", [Idr_Consumes<"0, 1">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "builds a boxed constructor in a token's cell, or in a new one when it is null";
  let arguments = (ins Arg<Idr_OwnedToken, "", [MemWrite]>:$token, SymbolRefAttr:$ctor,
                       Variadic<AnyType>:$fields);
  let results = (outs Res<Idr_BoxValue, "", [MemAlloc]>:$result);
  let assemblyFormat = [{
    $token $ctor `(` $fields `)` attr-dict `:` functional-type(operands, $result)
  }];
}

// Where a match's scrutinee dies in one of its case regions, which knows
// the constructor: the fields move out of it, so none is counted twice.
def Idr_TakeOp : Idr_OwnedOp<"take", [Idr_Consumes<"0">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "consumes a constructor value, each of its fields keeping a reference of its own";
  let description = [{
    The results are the fields of `ctor`, which built the value, each with
    a reference of its own; for a box, a token comes first. When the box
    held the only reference to its cell, the fields move out of it with no
    count changed and the token is the cell, to build another constructor
    in or to free; otherwise each field gets one more reference, the box
    one fewer, and the token is null. An unboxed sum is its fields already,
    so taking it apart changes no count.
  }];
  let arguments = (ins Arg<Idr_OwnType, "", [MemRead, MemWrite, MemFree]>:$value,
                       SymbolRefAttr:$ctor);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = "$value $ctor attr-dict `:` type($value) `->` custom<ResultTypes>(type($results))";
  let extraClassDeclaration = [{
    // The token, for a box; null for an unboxed sum.
    ::mlir::Value getToken();
    ::mlir::ResultRange getFields();
  }];
}

//===----------------------------------------------------------------------===//
// Specialization keys (lib/Specialize)
//===----------------------------------------------------------------------===//

// idr-specialize keeps the key of each clone it makes in the clone's
// `idr.clone` attribute, so that its later runs share the clone. The labels in a key are names, not
// symbol uses: a key keeps no function alive and refers to none.
class Idr_KeyAttr<string name, string attrMnemonic> : AttrDef<Idr_Dialect, name> {
  let mnemonic = attrMnemonic;
}

def Idr_KeyHoleAttr : Idr_KeyAttr<"KeyHole", "key_hole"> {
  let summary = "a runtime leaf of a key: the clone's parameter that holds it";
  let parameters = (ins "unsigned":$index);
  let assemblyFormat = "`<` $index `>`";
}

def Idr_KeyConAttr : Idr_KeyAttr<"KeyCon", "key_con"> {
  let summary = "a constructor `@data::@ctor` in a key, over the patterns of its fields";
  let parameters = (ins "::mlir::StringAttr":$data, "::mlir::StringAttr":$ctor,
                        "::mlir::ArrayAttr":$fields);
  let assemblyFormat = "`<` $data `,` $ctor `,` $fields `>`";
}

def Idr_KeyClosureAttr : Idr_KeyAttr<"KeyClosure", "key_closure"> {
  let summary = "a closure of `callee` in a key, over the patterns of its captures";
  let parameters = (ins "::mlir::StringAttr":$callee, "::mlir::ArrayAttr":$captures);
  let assemblyFormat = "`<` $callee `,` $captures `>`";
}

// A clone that specializes: the patterns of its origin's parameters, a key
// hole, constructor or closure, or a constant.
def Idr_SpecKeyAttr : Idr_KeyAttr<"SpecKey", "spec_key"> {
  let summary = "the key of a clone that specializes";
  let parameters = (ins "::mlir::StringAttr":$origin, "::mlir::ArrayAttr":$patterns);
  let assemblyFormat = "`<` $origin `,` $patterns `>`";
}

// A clone made by raising, by its callee and what consumes the callee's
// result. The callee's arity is part of the key: remove-dead-values may
// erase parameters later, and the holes of a clone count them.
def Idr_KeyApplyAttr : Idr_KeyAttr<"KeyApply", "key_apply"> {
  let summary = "the key of a clone that applies its callee's result";
  let parameters = (ins "::mlir::StringAttr":$callee, "unsigned":$arity);
  let assemblyFormat = "`<` $callee `,` $arity `>`";
}

def Idr_KeyApplyFieldAttr : Idr_KeyAttr<"KeyApplyField", "key_apply_field"> {
  let summary = "the key of a clone that applies field `index` of `ctor` of its callee's result";
  let parameters = (ins "::mlir::StringAttr":$callee, "unsigned":$arity,
                        "::mlir::StringAttr":$ctor, "unsigned":$index);
  let assemblyFormat = "`<` $callee `,` $arity `,` $ctor `,` $index `>`";
}

// A clone: the function every call of its key calls, those idr-specialize
// makes in later rounds too. So the clone names itself: MLIR's
// interprocedural analyses take a reference that is no call for callers
// they cannot see, and fold nothing its present callers pass into its body
// (sccp), prune nothing only they leave unreachable (dead code), and keep
// its parameters (remove-dead-values), which later callers fill.
def Idr_CloneAttr : AttrDef<Idr_Dialect, "Clone"> {
  let mnemonic = "clone";
  let summary = "a clone, named, and the key it is the function of";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$function, "::mlir::Attribute":$key);
  let assemblyFormat = "`<` $function `,` $key `>`";
}

//===----------------------------------------------------------------------===//
// Linearity
//===----------------------------------------------------------------------===//

// The two ops that move a value into and out of a linear type. Each makes
// a new value, allocated on a resource of its own: an allocation is never
// merged with another (two entries of one value stay two linear values) and
// is removed when unused. Both lower to nothing. An entry used at once, or
// a use entered at once, is the value itself: nothing ran in the linear
// position, and each value that remains keeps its type, so the fold loses
// no quantity. A closure or a suspension holding a linear value is the
// exception: its type does not say that it is used once, so the pair it
// passed stays unless what takes the use takes it once. What is left of a
// binder once inlining has joined its two sides is such a pair, and it
// would hide the value from every fold.

// Idris lets any value fill a quantity-1 binder: what enters is used once
// from then on.
// Neither hides the value from an analysis: the integer range of what
// enters is that of what is used.
def Idr_LinEnterOp : Idr_Op<"lin.enter", [Idr_Consumes<"0">,
    TypesMatchWith<"the operand is the value at any quantity", "result", "value",
                   "::idr::atQuantity($_self, ::idr::Quantity::Many)">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRangesFromOptional"]>]> {
  let summary = "a value handed to a linear position";
  let arguments = (ins AnyType:$value);
  let results = (outs Res<Idr_LinType, "", [MemAlloc<Idr_LinResource>]>:$result);
  let assemblyFormat = "$value attr-dict `:` qualified(type($result))";
  let hasFolder = 1;
}

// The one use of a linear value, where it becomes an ordinary one.
def Idr_LinUseOp : Idr_Op<"lin.use", [Idr_Consumes<"0">,
    TypesMatchWith<"the result is the value at any quantity", "linear", "result",
                   "::idr::atQuantity($_self, ::idr::Quantity::Many)">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRangesFromOptional"]>]> {
  let summary = "the one use of a linear value";
  let arguments = (ins Idr_LinType:$linear);
  let results = (outs Res<AnyType, "", [MemAlloc<Idr_LinResource>]>:$result);
  let assemblyFormat = "$linear attr-dict `:` qualified(type($linear))";
  let hasFolder = 1;
}

// Base's surface beyond the Prelude's: files, directories, the process, the
// terminal, errors, clocks, and the handles that stand for pointers.
include "idr/IdrPlatformOps.td"

#endif // IDR_OPS
