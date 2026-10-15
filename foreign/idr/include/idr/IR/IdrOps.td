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
// Functions
//===----------------------------------------------------------------------===//

// The function of a monomorphic program, and what is known of it: what
// Idris proved (total), what the passes find (effects), what keeps a cell
// shared (no_inline) and what it is an instance of. Each is inherent, so
// no pass drops one without changing the op, and every reader uses the
// generated accessor. The program is closed: every function has a body,
// and the one public function is the root, whose symbol-use verifier runs
// the module's rules (verify::program) once per verification of the
// module, after every op is verified and never when a pass manager
// verifies one function. Its region verifier owns the rules of one
// function: every linear value used once on every path, and the owned
// stage's counting. effects absent means the function may do anything; no
// writer stores the full set io, crash, diverge: it removes the attribute.
def Idr_FuncOp : Idr_Op<"func", [AffineScope, AutomaticAllocationScope,
    SymbolName, SymbolVisibility, FunctionOpInterface, IsolatedFromAbove,
    OpAsmOpInterface, DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "a function of the program, with the facts known of it";
  let arguments = (ins SymbolNameAttr:$sym_name,
                       TypeAttrOf<FunctionType>:$function_type,
                       OptionalAttr<StrAttr>:$sym_visibility,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs,
                       UnitAttr:$total, UnitAttr:$no_inline,
                       OptionalAttr<Idr_EffectAttr>:$effects,
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
  }];
}

// A call of a function by name. What it may do is its own effects, a copy
// of its callee's kept because an effect query has no symbol table; a call
// without one may do anything. The callee's effects is the authority:
// verifySymbolUses refuses a call whose effects is not its callee's, so a
// pass that makes a call, or changes its callee, writes the callee's. It
// takes over an argument the callee's parameter owns: consumesOperand
// reads the operand's type, which verifySymbolUses makes the parameter's.
def Idr_CallOp : Idr_Op<"call", [CallOpInterface,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<Idr_ConsumingOpInterface, ["consumesOperand"]>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a call of a function by name";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$args,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs,
                       OptionalAttr<Idr_EffectAttr>:$effects);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = [{
    $callee `(` $args `)` (`arg_attrs` `=` $arg_attrs^)?
    (`res_attrs` `=` $res_attrs^)? (`effects` `=` $effects^)? attr-dict `:`
    functional-type($args, $results)
  }];
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
    ReturnLike, Terminator]> {
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
// makes its fields owned, which it takes over. The constructor is named
// within the result's data type: a label's, of a closure or memo sum, is
// the label function's symbol, so building one is a use of the label.
// `stack`: idr-stack's cell that never leaves its frame, stack memory.
def Idr_ConOp : Idr_Op<"con", [
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>,
    Idr_Consumes<"0">]> {
  let summary = "builds a constructor value";
  let arguments = (ins FlatSymbolRefAttr:$ctor, Variadic<AnyType>:$fields, UnitAttr:$stack);
  let results = (outs Idr_SumValue:$result);
  let assemblyFormat = [{
    $ctor `(` $fields `)` (`stack` $stack^)? attr-dict `:` functional-type($fields, $result)
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    // The data type of the result, and the constructor's tag in it.
    ::idr::DataType getDataType();
    unsigned getTag();
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
// is live: it is written when it is built (a field built pending once more,
// through its destination, before anything reads it), and reused only
// through the token of a box idr.take consumed. In the owned stage, where
// references end, the verifier refuses a read through a view once the
// reference the view borrows is gone, so a pass that moves a read past its
// cell's drop fails there instead of reading a freed cell.
def Idr_FieldOp : Idr_Op<"field", [NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>]> {
  let summary = "reads a field of a constructor value";
  let arguments = (ins Idr_SumType:$value, FlatSymbolRefAttr:$ctor,
                       I64Attr:$index);
  let results = (outs AnyType:$result);
  let assemblyFormat = [{
    $value `[` $ctor `,` $index `]` attr-dict `:` type($value) `->` type($result)
  }];
  let hasFolder = 1;
  let hasCanonicalizeMethod = 1;
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    // The data type of the value read, and the constructor's tag in it.
    ::idr::DataType getDataType();
    unsigned getTag();
  }];
}

// The tag is in [0, n-1] for n constructors, the number the value's data
// type has. It is Pure though it may load the cell's header, for
// idr.field's reason: a cell never changes while a reference to it is
// live, and the owned stage refuses a read once the reference is gone.
def Idr_TagOp : Idr_Op<"tag", [Pure,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "the constructor tag of a value";
  let arguments = (ins Idr_SumType:$value);
  let results = (outs I64:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasFolder = 1;
}

//===----------------------------------------------------------------------===//
// Destinations
//===----------------------------------------------------------------------===//

// A recursion that returns a constructor around its own result, `Cons x
// (copy xs)`, builds the constructor first, without that field, and gives
// the field to the recursive call as a destination to write once it has
// the value: a cell's field is then written top down and the recursion is
// a tail call, so idr-tail-loops makes it a loop.

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

def Idr_DestOfOp : Idr_Op<"dest.of", [Pure]> {
  let summary = "the destination that is a pending field of a cell just built";
  let arguments = (ins Idr_BoxType:$value, FlatSymbolRefAttr:$ctor, I64Attr:$index);
  let results = (outs Idr_DestType:$result);
  let assemblyFormat = [{
    $value `[` $ctor `,` $index `]` attr-dict `:` type($value) `->` type($result)
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    // The data type of the cell, and the constructor's tag in it.
    ::idr::DataType getDataType();
    unsigned getTag();
  }];
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
