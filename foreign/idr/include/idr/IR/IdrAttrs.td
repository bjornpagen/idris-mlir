// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The attributes of the idr dialect: its constants, what a call may do,
// the keys of specializations, the instances a function or data type is
// of, and the rule a refusal names.

#ifndef IDR_ATTRS
#define IDR_ATTRS

include "idr/IR/IdrTypes.td"

//===----------------------------------------------------------------------===//
// Tags
//===----------------------------------------------------------------------===//

// A constructor's tag (idr::Tag) as an op holds it: stored as an i32 the
// generic form writes as its number, read and built as the tag.
def Idr_TagAttr : TypedSignlessIntegerAttrBase<I32, "::idr::Tag", "a constructor's tag"> {
  let convertFromStorage = "::idr::Tag{static_cast<uint32_t>($_self.getValue().getZExtValue())}";
  let constBuilderCall =
      "$_builder.getIntegerAttr($_builder.getIntegerType(32), static_cast<uint32_t>($0))";
}

// A constructor's tag as an attribute's parameter, written as its number.
def Idr_TagParameter : AttrParameter<"::idr::Tag", "a constructor's tag"> {
  let parser = [{
    [&]() -> ::mlir::FailureOr<::idr::Tag> {
      uint32_t tag;
      if ($_parser.parseInteger(tag))
        return ::mlir::failure();
      return ::idr::Tag{tag};
    }()
  }];
  let printer = "$_printer << static_cast<uint32_t>($_self)";
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
// The constructor is its tag in its data type, which the attribute holds:
// a constant is untyped, and the cells of a run are one type's, so two
// constructors in two types (the `Just` of a `Maybe (Maybe Int)` and of its
// `Maybe Int`) never join. A constant of a label is a use of the label's
// function through its data type, whose sub-elements the labels are. The
// type is the constant's identity, held in place: a value of the type may
// be a box of it.
//
// It is written as it is stored, the constructor by its name: a plain
// constructor as its one cell, `<!T, @C, [fields]>`, and a run as its
// cells, its tail and the field it runs along, `<!T, @C, [a], [b] tail t
// along 1>`, `along 0` left out (lib/IR/ConAttr.cpp). Any form is read into
// the attribute `get` gives for the same value, however it was written.
def Idr_ConAttr : Idr_Attr<"Con", "con",
    (ins "::idr::DataType":$data, Idr_TagParameter:$tag,
         ArrayRefParameter<"::mlir::ArrayAttr">:$cells,
         OptionalParameter<"::mlir::Attribute">:$tail,
         DefaultValuedParameter<"unsigned", "0">:$spine)> {
  let summary = "a constructor of a sum or box, its fields as attributes, a list's cells flat";
  let hasCustomAssemblyFormat = 1;
  let genVerifyDecl = 1;
  let skipDefaultBuilders = 1;
  let builders = [
    // A run when one field is a run of the constructor along that field, or
    // the second cell of one; otherwise the plain con.
    AttrBuilder<(ins "::idr::DataType":$data, "::idr::Tag":$tag, "::mlir::ArrayAttr":$fields)>
  ];
  let extraClassDeclaration = [{
    // What repeated `get` gives for the cells `cells` (each one's fields
    // without the spine field) linked through field `spine` and ending in
    // `tail`, built in O(n).
    static ConAttr getRun(::mlir::MLIRContext *context, ::idr::DataType data, ::idr::Tag tag,
                          unsigned spine, ::llvm::ArrayRef<::mlir::ArrayAttr> cells,
                          ::mlir::Attribute tail);
    // The constructor, in its data type's body. Out of line: the data type is
    // declared after the attributes, whose instances its body holds.
    const ::idr::Ctor &getCtor() const;
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
    // the parser reads them: what `get` gives for the value they say, a run
    // where its cells form one, or null after an error.
    static ConAttr getChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
                              ::mlir::MLIRContext *context, ::idr::DataType data, ::idr::Tag tag,
                              ::llvm::ArrayRef<::mlir::ArrayAttr> cells, ::mlir::Attribute tail,
                              unsigned spine, ::mlir::Type type);
  private:
    // The attribute of stored parameters that get, getRun and the parser
    // have made canonical. ODS completes the storage only in the unit that
    // registers it, so these reach Base::get and Base::getChecked there.
    static ConAttr getStored(::mlir::MLIRContext *context, ::idr::DataType data, ::idr::Tag tag,
                             ::llvm::ArrayRef<::mlir::ArrayAttr> cells, ::mlir::Attribute tail,
                             unsigned spine, ::mlir::Type type);
    static ConAttr getStoredChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
                                    ::mlir::MLIRContext *context, ::idr::DataType data,
                                    ::idr::Tag tag, ::llvm::ArrayRef<::mlir::ArrayAttr> cells,
                                    ::mlir::Attribute tail, unsigned spine, ::mlir::Type type);
  public:
  }];
  let extraClassDefinition = [{
    $cppClass $cppClass::getStored(::mlir::MLIRContext *context, ::idr::DataType data,
                                   ::idr::Tag tag, ::llvm::ArrayRef<::mlir::ArrayAttr> cells,
                                   ::mlir::Attribute tail, unsigned spine, ::mlir::Type type) {
      return Base::get(context, data, tag, cells, tail, spine, type);
    }
    $cppClass $cppClass::getStoredChecked(
        ::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
        ::mlir::MLIRContext *context, ::idr::DataType data, ::idr::Tag tag,
        ::llvm::ArrayRef<::mlir::ArrayAttr> cells, ::mlir::Attribute tail, unsigned spine,
        ::mlir::Type type) {
      return Base::getChecked(emitError, context, data, tag, cells, tail, spine, type);
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

// An integer at its fewest signed bits, so that equal integers are equal
// attributes, written in decimal.
def Idr_IntegerParameter : APIntParameter<"an integer at its fewest signed bits"> {
  let parser = [{
    [&]() -> ::mlir::FailureOr<::llvm::APInt> {
      ::llvm::APInt value;
      if ($_parser.parseInteger(value))
        return ::mlir::failure();
      return value.sextOrTrunc(value.getSignificantBits());
    }()
  }];
  let printer = "$_self.print($_printer.getStream(), /*isSigned=*/true)";
}

def Idr_BigAttr : Idr_Attr<"Big", "big", (ins Idr_IntegerParameter:$value)> {
  let summary = "an integer of any size";
  let assemblyFormat = "`<` $value `>`";
  let builders = [
    // `value` at its fewest signed bits, the one width the attribute holds.
    AttrBuilder<(ins "const ::llvm::APInt &":$value), [{
      return $_get($_ctxt, value.sextOrTrunc(value.getSignificantBits()),
                   ::mlir::NoneType::get($_ctxt));
    }]>
  ];
  let genVerifyDecl = 1;
}

def Idr_CmpPredicate : I64EnumAttr<"CmpPredicate",
    "a comparison of strings or bigs", [
      I64EnumAttrCase<"eq", 0>, I64EnumAttrCase<"lt", 1>,
      I64EnumAttrCase<"lte", 2>, I64EnumAttrCase<"gt", 3>,
      I64EnumAttrCase<"gte", 4>]> {
  let cppNamespace = "::idr";
}

//===----------------------------------------------------------------------===//
// What a function may do
//===----------------------------------------------------------------------===//

// What a run of a function may do besides computing its results: `io`,
// perform IO; `crash`, end the program with a crash; `diverge`, never
// return. It is a fact of an idr.func alone, its `effects`: what its body
// does of itself, which idr::bodyEffect decides, and what each function it
// calls may do. Its absence means every effect. Optimization only removes
// what a function reaches, so a stale value says too much, never too
// little.
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
// Specialization keys
//===----------------------------------------------------------------------===//

// The keys of the functions specialization makes, which a pass prints
// into a name from content. The labels in a key are names, not symbol
// uses: a key keeps no function alive and refers to none.
class Idr_KeyAttr<string name, string attrMnemonic> : AttrDef<Idr_Dialect, name> {
  let mnemonic = attrMnemonic;
}

def Idr_KeyHoleAttr : Idr_KeyAttr<"KeyHole", "key_hole"> {
  let summary = "a runtime leaf of a key: the clone's parameter that holds it";
  let parameters = (ins "unsigned":$index);
  let assemblyFormat = "`<` $index `>`";
}

// A constructor in a key is its tag, as everywhere: the key's position
// says the data type, which the key does not repeat.
def Idr_KeyConAttr : Idr_KeyAttr<"KeyCon", "key_con"> {
  let summary = "the constructor `tag` in a key, over the patterns of its fields";
  let parameters = (ins Idr_TagParameter:$tag, "::mlir::ArrayAttr":$fields);
  let assemblyFormat = "`<` $tag `,` $fields `>`";
}

// A clone that specializes: the patterns of its origin's parameters, a key
// hole or constructor, or a constant.
def Idr_SpecKeyAttr : Idr_KeyAttr<"SpecKey", "spec_key"> {
  let summary = "the key of a clone that specializes";
  let parameters = (ins "::mlir::StringAttr":$origin, "::mlir::ArrayAttr":$patterns);
  let assemblyFormat = "`<` $origin `,` $patterns `>`";
}

// A clone made by raising: its callee and the dispatch that consumes the
// callee's result, by the match's printed form, which says what each case
// does with the label it takes.
def Idr_KeyRaiseAttr : Idr_KeyAttr<"KeyRaise", "key_raise"> {
  let summary = "the key of a clone that dispatches on its callee's result";
  let parameters = (ins "::mlir::StringAttr":$callee, "::mlir::StringAttr":$consumer);
  let assemblyFormat = "`<` $callee `,` $consumer `>`";
}

//===----------------------------------------------------------------------===//
// Instances
//===----------------------------------------------------------------------===//

// What a function or a data type is an instance of, as the frontend
// decided it: the Idris definition and the compile-time values it was
// instantiated at (types, implementations, shapes), each the
// alpha-normalized text the frontend prints. Names, not symbol uses, as
// the specialization keys are: an instance keeps no function alive, refers
// to none and follows no rename. The readable symbol is this key printed;
// no pass reads it.
def Idr_InstanceAttr : AttrDef<Idr_Dialect, "Instance"> {
  let mnemonic = "instance";
  let summary = "the Idris definition and arguments a function or data type is an instance of";
  let parameters = (ins "::mlir::StringAttr":$origin, "::mlir::ArrayAttr":$arguments);
  let assemblyFormat = "`<` $origin `,` $arguments `>`";
  let genVerifyDecl = 1;
}

//===----------------------------------------------------------------------===//
// Refusals
//===----------------------------------------------------------------------===//

// The rule a refusal names, held in the refusal's diagnostic as data
// (idr::refuse), so the driver reads the rule and never the text.
def Idr_RuleAttr : EnumAttr<Idr_Dialect, Idr_Rule, "rule">;

#endif // IDR_ATTRS
