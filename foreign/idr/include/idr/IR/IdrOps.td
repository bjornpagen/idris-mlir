// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect: the contract between the Idris compiler and the C++ side.
// Every fact about an op is declared once, in this file or in the family it
// includes; the C++ in lib/IR and every pass derive from it. TableGen reads
// the dialect from here.

#ifndef IDR_OPS
#define IDR_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"

//===----------------------------------------------------------------------===//
// What an op reads
//===----------------------------------------------------------------------===//

// A value an op reads in place and does not take over: plain before idr-rc,
// and after it the view the owned stage grades Borrow. A value used once,
// or one that holds a reference of its own, is no read: taking it is a
// move, which a reading op does not make. Every op family names its read
// operands by these.
class Idr_Read<string cppType, string name>
    : Type<And<[CPred<"::llvm::isa<" # cppType # ">(::idr::unrestricted($_self))">,
                CPred<"::idr::quantityOf($_self) == ::idr::Quantity::Many">,
                CPred<"!::idr::isOwned($_self)">]>, name, "::mlir::Type">;
def Idr_StrRead : Idr_Read<"::idr::StrType", "a string, read in place">;
def Idr_BigRead : Idr_Read<"::idr::BigType", "an Integer, read in place">;
def Idr_NatRead : Idr_Read<"::idr::NatType", "a natural, read in place">;
def Idr_BigOrNatRead : Idr_Read<"::idr::BigType, ::idr::NatType",
                                "an Integer or a natural, read in place">;
def Idr_SumRead : Idr_Read<"::idr::DataType, ::idr::BoxType", "a constructor value, read in place">;

//===----------------------------------------------------------------------===//
// The program
//===----------------------------------------------------------------------===//

// What a program's functions may hold, the stage the pipeline has brought
// it to: `higher`, closures and suspensions, before idr-defunctionalize;
// `first`, the first-order program it makes, every closure a sum and every
// force a call; `owned`, every reference counted, after idr-rc; `lowered`,
// after idr-lower, upstream's functions and globals in place of idr.func,
// whose root keeps the visibility upstream stores for it. The stage is the
// program's, said once, so that no pass finds it by walking the functions
// and no verifier guesses it from a grade.
def Idr_Stage : I32EnumAttr<"Stage", "what the functions of a program may hold", [
    I32EnumAttrCase<"Higher", 0, "higher">, I32EnumAttrCase<"First", 1, "first">,
    I32EnumAttrCase<"Owned", 2, "owned">, I32EnumAttrCase<"Lowered", 3, "lowered">]> {
  let cppNamespace = "::idr";
}

// A closed program: its functions, every one defined, and the one that
// runs it, `root`, a property of the program: a function's visibility is
// read from it, never stored, so nothing counts public functions to find
// the root. Its symbol-use verifier runs the program's rules
// (verify::program) once per verification of the module that holds it,
// after every op is verified, and never when a pass manager verifies the
// program or one of its functions. Other symbols a pass puts in it (the
// globals of static data) live beside the functions. It is the one program
// of a module, the closed world every pass reads, so a pass reaches it from
// its module and no two programs are ever rewritten or printed beside each
// other.
def Idr_ProgramOp : Idr_Op<"program", [SymbolTable, IsolatedFromAbove, SingleBlock,
    NoTerminator, Symbol, SymbolName, HasParent<"::mlir::ModuleOp">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "a closed program: its functions, its root and its stage";
  let arguments = (ins SymbolNameAttr:$sym_name, FlatSymbolRefAttr:$root, Idr_Stage:$stage);
  let regions = (region SizedRegion<1>:$bodyRegion);
  let assemblyFormat = [{
    $sym_name `root` `(` $root `)` `stage` `(` $stage `)` attr-dict-with-keyword $bodyRegion
  }];
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let skipDefaultBuilders = 1;
  let builders = [
    // An empty program, its block made.
    OpBuilder<(ins "::llvm::StringRef":$name, "::llvm::StringRef":$root, "::idr::Stage":$stage)>
  ];
  let extraClassDeclaration = [{
    // The root, found in the program's own table, while it is an idr.func:
    // null once the program is lowered, when the root is upstream's
    // function that getRoot names.
    FuncOp lookupRoot();
    // A program is the whole of what runs: nothing outside it discards it.
    ::mlir::SymbolTable::Visibility getVisibility() {
      return ::mlir::SymbolTable::Visibility::Public;
    }
    void setVisibility(::mlir::SymbolTable::Visibility) {}
  }];
}

//===----------------------------------------------------------------------===//
// Functions
//===----------------------------------------------------------------------===//

def Idr_FuncOp : Idr_Op<"func", [AffineScope, AutomaticAllocationScope,
    SymbolName, FunctionOpInterface, IsolatedFromAbove,
    HasParent<"ProgramOp">, OpAsmOpInterface]> {
  let summary = "a function of the program, with the facts known of it";
  let description = [{
    The function of a program, and what is known of it: what Idris proved
    (`total`), what the passes find (`effects`), what keeps a cell shared
    (`no_inline`) and what it is an instance of (`instance`). Each is
    inherent, so no pass drops one without changing the op, and every
    reader uses the generated accessor. Every function is defined. Its
    visibility is no fact of its own: it is public exactly when it is its
    program's root, which nothing in the program calls and no pass may
    discard, and private otherwise, so that upstream's symbol walks, which
    never read the program's `root`, keep the root and may drop any other
    function without uses. Its region verifier owns the rules of one
    function at its program's stage: the flow of closures before
    idr-defunctionalize, every linear value used once on every path, and
    the owned stage's counting.

    `total`: every loop of the body's own ends. The frontend writes it
    where Idris proved every loop of the body terminating, and on a
    lambda's or a delay's function, which has no loop of its own;
    idr-defunctionalize writes it on each force function, whose body is a
    match and calls. A copy keeps it, and `absorb` clears it when a body
    takes in a callee without it (inlining, contification). No other pass
    writes it. A call of a function without it is no loop of the caller's
    own: whether the callee returns is in the callee's `effects`.

    `no_inline`: written only by the frontend, on a function of no
    parameters whose result is lazy, whose cell every use shares.

    `effects`: what a run of the function may do, by default everything
    (`idr::anyEffect`): a function no pass has solved may do anything,
    which its accessor says. The default's one form is the attribute's
    absence, which the verifier holds, so that equal functions have equal
    attributes. A solve (idr-effects, idr-optimize's ready set) writes it,
    and a stale value says too much, never too little. The program's
    verifier holds that it covers the body's own part (`idr::bodyEffect`),
    its callees' effects, and (before idr-defunctionalize) everything for an
    apply or a force.

    `instance`: what the function is an instance of, as the frontend wrote
    it.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name,
                       TypeAttrOf<FunctionType>:$function_type,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs,
                       UnitAttr:$total, UnitAttr:$no_inline,
                       DefaultValuedOptionalAttr<Idr_EffectAttr, "::idr::anyEffect">:$effects,
                       OptionalAttr<Idr_InstanceAttr>:$instance);
  let regions = (region AnyRegion:$body);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    static ::llvm::StringRef getDefaultDialect() { return "idr"; }
    ::mlir::Region *getCallableRegion() { return &getBody(); }
    ::llvm::ArrayRef<::mlir::Type> getArgumentTypes() { return getFunctionType().getInputs(); }
    ::llvm::ArrayRef<::mlir::Type> getResultTypes() { return getFunctionType().getResults(); }
    ::mlir::Type cloneTypeWith(::mlir::TypeRange inputs, ::mlir::TypeRange results) {
      return ::mlir::FunctionType::get(getContext(), inputs, results);
    }
    // FunctionOpInterface's question, false on every verified idr.func.
    bool isExternal() { return getBody().empty(); }
    // A body that takes in a callee without Idris's proof of termination
    // loses its own: what inlining and contification record.
    void absorb(FuncOp callee) { if (!callee || !callee.getTotal()) setTotal(false); }
    // The program this function is of.
    ProgramOp getProgram();
    // Whether this is its program's root.
    bool isRoot();
    // Symbol's visibility, read off the program's root: public for the
    // root, private for every other function. isPublic, isPrivate and
    // canDiscardOnUseEmpty all ask this. Setting it changes nothing: the
    // root is the program's to name.
    ::mlir::SymbolTable::Visibility getVisibility() {
      return isRoot() ? ::mlir::SymbolTable::Visibility::Public
                      : ::mlir::SymbolTable::Visibility::Private;
    }
    void setVisibility(::mlir::SymbolTable::Visibility) {}
  }];
}

// A call of a function by name. What it may do is its callee's effects,
// which only a symbol table reaches (a CalleeEffects, idr::ownEffects): to
// a query without one, such as an upstream pass's, a call may do anything a function may,
// so none drops, merges or moves one past another effect. Its arguments
// move into its callee's parameters (its flow), each taken over where the
// parameter owns it.
def Idr_CallOp : Idr_Op<"call", [CallOpInterface,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a call of a function by name";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$args,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = [{
    $callee `(` $args `)` (`arg_attrs` `=` $arg_attrs^)?
    (`res_attrs` `=` $res_attrs^)? attr-dict `:` functional-type($args, $results)
  }];
  let builders = [
    // A call of `callee`, whose results are the function's.
    OpBuilder<(ins "FuncOp":$callee, CArg<"::mlir::ValueRange", "{}">:$args)>
  ];
  let extraClassDeclaration = [{
    ::mlir::CallInterfaceCallable getCallableForCallee() { return getCalleeAttr(); }
    void setCalleeFromCallable(::mlir::CallInterfaceCallable callee) {
      setCalleeAttr(::llvm::cast<::mlir::FlatSymbolRefAttr>(::llvm::cast<::mlir::SymbolRefAttr>(callee)));
    }
    ::mlir::Operation::operand_range getArgOperands() { return getArgs(); }
    ::mlir::MutableOperandRange getArgOperandsMutable() { return getArgsMutable(); }
  }];
}

// idr.func's body holds several blocks only after the inliner takes in a
// callee that ends in ub.unreachable, until canonicalize erases the
// unreachable block; idr.return ends a block of the body. A pass that
// lists the returns of a function reads the terminators of the body's
// blocks.
def Idr_ReturnOp : Idr_Op<"return", [Idr_ConsumesOnly<"0">, HasParent<"FuncOp">,
    ReturnLike, Terminator, DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "returns from a function";
  let arguments = (ins Variadic<AnyType>:$operands);
  let assemblyFormat = "attr-dict ($operands^ `:` type($operands))?";
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Values
//===----------------------------------------------------------------------===//

// A constant big or natural has its value's range (lib/IR/OpsBigs.cpp);
// any other constant is not an integer, and has none.
def Idr_ConstantOp : Idr_Op<"constant", [ConstantLike, Pure,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "a constant: a constructor, closure, string or big";
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
// makes its fields owned, which it takes over. The constructor is its tag
// in the result's data type, written by name. A field it is built without,
// a hole, is written later, once, through the destination the op gives for
// it: a recursion that returns a constructor around its own result, `Cons
// x (copy xs)`, builds the constructor first and gives the hole to the
// recursive call to write once it has the value, so a cell's fields are
// written top down and the recursion is a tail call, which idr-tail-loops
// makes a loop. `holes` are the holes' field indices, ascending; the fields
// given are the rest, in order; the results are the value and then one
// destination per hole. A constructor with a hole is never static, and
// nothing reads the hole before it is written. `stack`: idr-stack's cell
// that never leaves its frame, stack memory.
def Idr_ConOp : Idr_Op<"con", [
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "builds a constructor value";
  let arguments = (ins Idr_TagAttr:$tag, Variadic<AnyType>:$fields,
                       DefaultValuedAttr<DenseI32ArrayAttr, "{}">:$holes, UnitAttr:$stack);
  let results = (outs Idr_SumValue:$result, Variadic<Idr_DestType>:$dests);
  // `idr.con !T @Cons(%x : i64, dest)`: the value's type, then the
  // constructor's name in it, then the fields, a hole written `dest`; each
  // hole's destination is the word of its field.
  let assemblyFormat = [{
    type($result) custom<CtorRef>(ref(type($result)), $tag)
    custom<Fields>($fields, type($fields), $holes) (`stack` $stack^)? attr-dict
    custom<Dests>(type($dests), ref(type($result)), ref($tag), ref($holes))
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
  let builders = [
    // The constructor `tag` of `type` with `fields`, and a destination for
    // each of `holes`.
    OpBuilder<(ins "::mlir::Type":$type, "::idr::Tag":$tag, "::mlir::ValueRange":$fields,
                   CArg<"::llvm::ArrayRef<int32_t>", "{}">:$holes,
                   CArg<"bool", "false">:$stack)>
  ];
  let extraClassDeclaration = [{
    // The data type of the result.
    ::idr::DataType getDataType();
    // The value given for field `index` of the constructor, or null for a
    // hole; and the destination of a hole, or null for a field given.
    ::mlir::Value getField(unsigned index);
    ::mlir::Value getDest(unsigned index);
  }];
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
// is live: it is written when it is built (a hole once more, through its
// destination, before anything reads it), and reused only through the
// token of a box idr.take consumed. In the owned stage, where references
// end, the verifier refuses a read through a view once the reference the
// view borrows is gone, so a pass that moves a read past its cell's drop
// fails there instead of reading a freed cell. The constructor is its tag,
// written by name.
def Idr_FieldOp : Idr_Op<"field", [NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "reads a field of a constructor value";
  let arguments = (ins Idr_SumRead:$value, Idr_TagAttr:$tag, I64Attr:$index);
  let results = (outs AnyType:$result);
  // `idr.field %v : !T @Cons[1] -> i64`
  let assemblyFormat = [{
    $value `:` type($value) custom<CtorRef>(ref(type($value)), $tag) `[` $index `]` attr-dict
    `->` type($result)
  }];
  let hasFolder = 1;
  let hasCanonicalizeMethod = 1;
  let hasVerifier = 1;
  let builders = [
    // Field `index` of the constructor `tag` of `value`, read at the
    // value's grade times the field's.
    OpBuilder<(ins "::mlir::Value":$value, "::idr::Tag":$tag, "unsigned":$index)>
  ];
  let extraClassDeclaration = [{
    // The data type of the value read.
    ::idr::DataType getDataType();
  }];
}

// The tag is in [0, n-1] for n constructors, the number the value's data
// type has. It is Pure though it may load the cell's header, for
// idr.field's reason: a cell never changes while a reference to it is
// live, and the owned stage refuses a read once the reference is gone.
def Idr_TagOp : Idr_Op<"tag", [Pure, DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the constructor tag of a value";
  let arguments = (ins Idr_SumRead:$value);
  let results = (outs I64:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasFolder = 1;
}

// The value is what the destination holds, owned or exclusive.
def Idr_DestWriteOp : Idr_Op<"dest.write", [
    PredOpTrait<"the value is what the destination holds, owned",
      And<[CPred<"::idr::isOwned($value.getType())">,
           CPred<"::idr::unrestricted($value.getType()) == ::idr::unrestricted(::llvm::cast<::idr::DestType>($dest.getType()).getValue())">]>>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>]> {
  let summary = "writes the value of a hole, consuming its reference";
  let arguments = (ins Arg<Idr_DestType, "", [MemWrite]>:$dest, AnyType:$value);
  let assemblyFormat = "$dest `,` $value attr-dict `:` type($dest) `,` type($value)";
}

// The op families, and base's surface beyond the Prelude's: files,
// directories, the process, the terminal, errors, clocks, and the handles
// that stand for pointers.
include "idr/IR/IdrMatchOps.td"
include "idr/IR/IdrClosureOps.td"
include "idr/IR/IdrCheckOps.td"
include "idr/IR/IdrScalarOps.td"
include "idr/IR/IdrStringOps.td"
include "idr/IR/IdrBigOps.td"
include "idr/IR/IdrIOOps.td"
include "idr/IR/IdrArrayOps.td"
include "idr/IR/IdrOwnershipOps.td"
include "idr/IR/IdrPlatformOps.td"

#endif // IDR_OPS
