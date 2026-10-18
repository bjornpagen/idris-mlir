// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The attributes of the idr dialect: its constants, the keys of
// specializations, the instances a function or data type is of, the rule a
// refusal names and a refusal the frontend found.

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

// A value, which holds no type of its own: its type is that of the
// idr.constant holding it, written before it, or of the field or capture it
// fills.
class Idr_Attr<string name, string attrMnemonic, dag params = (ins)>
    : AttrDef<Idr_Dialect, name> {
  let mnemonic = attrMnemonic;
  let parameters = params;
}

// A constructor with its fields, held as a run of its cells: one or more
// cells of one constructor, each linked to the next through one field, the
// spine, held flat, so that a list constant is one level deep to the
// printer, the parser, bytecode and every walk, however long it is. Every
// cell but the last holds the constructor's fields without the spine field,
// which is the next cell; the last holds all of them. A plain constructor
// is the run of one cell, whose spine is 0: one cell is a length, never a
// form of its own. A walker steps through the cells (walkFields,
// fieldOfCell), never through getFields along the spine, which builds the
// rest of the run at each step. One value has one attribute: `get` makes
// the longest run its cells form, and the verifier rejects any other. The
// generated walk and replace see each cell as an ArrayAttr, so a run is one
// level deep to them. A replace rebuilds from the replaced parameters
// (Base::get) without canonicalizing, so it can make a run that is not
// canonical, which the verifier rejects.
//
// The constructor is its tag in its data type, which the attribute holds:
// a constant holds no type, and the cells of a run are one type's, so two
// constructors in two types (the `Just` of a `Maybe (Maybe Int)` and of its
// `Maybe Int`) never join. A constant of a label is a use of the label's
// function through its data type, whose sub-elements the labels are. The
// type is the constant's identity, held in place: a value of the type may
// be a box of it.
//
// It is written as it is stored, the constructor by its name: a plain
// constructor as its one cell, `<!T, @C, [fields]>`, and a run as its cells
// and the field it runs along, `<!T, @C, [1], [2], [3, #idr.con<!T, @Nil,
// []>] along 1>`, `along 0` left out (lib/IR/ConAttr.cpp). Any form is read
// into the attribute `get` gives for the same value, however it was written.
def Idr_ConAttr : Idr_Attr<"Con", "con",
    (ins "::idr::DataType":$data, Idr_TagParameter:$tag,
         ArrayRefParameter<"::mlir::ArrayAttr">:$cells,
         DefaultValuedParameter<"unsigned", "0">:$spine)> {
  let summary = "a constructor of a sum or box, its fields as attributes, a list's cells flat";
  let hasCustomAssemblyFormat = 1;
  let genVerifyDecl = 1;
  let skipDefaultBuilders = 1;
  let builders = [
    // The longest run its cells form: a run when one field is a run of the
    // constructor along that field, or a cell that continues it; otherwise
    // the one cell.
    AttrBuilder<(ins "::idr::DataType":$data, "::idr::Tag":$tag, "::mlir::ArrayAttr":$fields)>
  ];
  let extraClassDeclaration = [{
    // What repeated `get` gives for the cells `cells`, every one but the
    // last without the spine field, linked through field `spine`, built in
    // O(n) and canonical however they were linked.
    static ConAttr getRun(::mlir::MLIRContext *context, ::idr::DataType data, ::idr::Tag tag,
                          unsigned spine, ::llvm::ArrayRef<::mlir::ArrayAttr> cells);
    // The constructor, in its data type's body. Out of line: the data type is
    // declared after the attributes, whose instances its body holds.
    const ::idr::Ctor &getCtor() const;
    // The number of cells: 1 for a plain constructor.
    unsigned getRunLength() const { return static_cast<unsigned>(getCells().size()); }
    // The index in the constructor of position `position` of cell `cell`:
    // the last cell holds every field, so its position is the field; every
    // other cell holds every field but the spine.
    unsigned fieldOfCell(unsigned cell, unsigned position) const {
      return cell + 1 == getRunLength() || position < getSpine() ? position : position + 1;
    }
    // Every field of every cell, in order, with its index in the
    // constructor: the run walked by its cells, never through its spine.
    void walkFields(::llvm::function_ref<void(::mlir::Attribute, unsigned)> each) const;
    // Field `index` of the first cell: O(1) off the spine, and on it the run
    // from the second cell.
    ::mlir::Attribute getField(unsigned index) const;
    // The first cell's fields: O(n) on a run, which builds the rest of the
    // run.
    ::mlir::ArrayAttr getFields() const;
    // The attribute of a constructor written as its stored parameters, as
    // the parser reads them: what `get` gives for the value they say, or
    // null after an error.
    static ConAttr getChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
                              ::mlir::MLIRContext *context, ::idr::DataType data, ::idr::Tag tag,
                              ::llvm::ArrayRef<::mlir::ArrayAttr> cells, unsigned spine);
  private:
    // The attribute of stored parameters that get and getRun have made
    // canonical. ODS completes the storage only in the unit that registers
    // it, so this reaches Base::get there.
    static ConAttr getStored(::mlir::MLIRContext *context, ::idr::DataType data, ::idr::Tag tag,
                             ::llvm::ArrayRef<::mlir::ArrayAttr> cells, unsigned spine);
  public:
  }];
  let extraClassDefinition = [{
    $cppClass $cppClass::getStored(::mlir::MLIRContext *context, ::idr::DataType data,
                                   ::idr::Tag tag, ::llvm::ArrayRef<::mlir::ArrayAttr> cells,
                                   unsigned spine) {
      return Base::get(context, data, tag, cells, spine);
    }
  }];
}

def Idr_ClosureAttr : Idr_Attr<"Closure", "closure",
    (ins "::mlir::FlatSymbolRefAttr":$callee, "::mlir::ArrayAttr":$captures)> {
  let summary = "a closure of a function with its captures as attributes";
  let assemblyFormat = "`<` $callee `,` $captures `>`";
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
  // One `get` of an integer, which takes any width: the default builder
  // would be a second, which no call could choose between.
  let skipDefaultBuilders = 1;
  let builders = [
    // `value` at its fewest signed bits, the one width the attribute holds.
    AttrBuilder<(ins "const ::llvm::APInt &":$value), [{
      return $_get($_ctxt, value.sextOrTrunc(value.getSignificantBits()));
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
// return. An idr.func holds it as its `effects` property, what its body
// does of itself (idr::bodyEffect) and what each function it calls may do,
// and so does each idr.call, at least its callee's. The property's default,
// anyEffect, is every effect: a function or call nothing has narrowed may
// do anything. The property prints itself (NamedEnumProp), its bits bare
// and comma-separated, `effects<io, crash>`, and `effects<none>` for none,
// so no attribute holds the enum and no printer of ours writes it.
// Optimization only removes what a function reaches, so a stale value says
// too much, never too little.
def Idr_Effect : I32BitEnumAttr<"Effect", "what a call of a function may do", [
      I32BitEnumAttrCaseNone<"none">,
      I32BitEnumAttrCaseBit<"io", 0>,
      I32BitEnumAttrCaseBit<"crash", 1>,
      I32BitEnumAttrCaseBit<"diverge", 2>]> {
  let cppNamespace = "::idr";
  let separator = ", ";
  let printBitEnumQuoted = 0;
  let genSpecializedAttr = 0;
}

//===----------------------------------------------------------------------===//
// Specialization keys
//===----------------------------------------------------------------------===//

// The keys of the functions specialization makes, which a pass prints
// into a name from content. They are attributes for MLIR's uniquing, which
// the specializer's memo tables key on; no op holds one, so the Idris side
// has no syntax for them (`idris`, which idris-mlir-tblgen reads). The
// labels in a key are names, not symbol uses: a key keeps no function alive
// and refers to none.
class Idr_KeyAttr<string name, string attrMnemonic> : AttrDef<Idr_Dialect, name> {
  let mnemonic = attrMnemonic;
  bit idris = 0;
}

// A hole is its place: the i-th hole of a key, in pre-order, is the
// clone's parameter i, so it holds no index.
def Idr_KeyHoleAttr : Idr_KeyAttr<"KeyHole", "key_hole"> {
  let summary = "a runtime leaf of a key: the clone's parameter at its pre-order place";
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
// callee's result, by reference to its uniqued form: `form` is the digest
// name the run's table of consumer forms gives it, which names its entry
// there, never the consumer's text.
def Idr_KeyRaiseAttr : Idr_KeyAttr<"KeyRaise", "key_raise"> {
  let summary = "the key of a clone that dispatches on its callee's result";
  let parameters = (ins "::mlir::StringAttr":$callee, "::mlir::StringAttr":$form);
  let assemblyFormat = "`<` $callee `,` $form `>`";
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
//
// A list of attributes written in brackets, `["Nat"]`, and the empty one
// `[]`: a list without delimiters, an ArrayRefParameter's default, cannot
// be empty. The Idris generator reads the class and writes the brackets.
class Idr_SquareListParameter<string element, string desc>
    : ArrayRefParameter<element, desc> {
  let parser = [{
    [&]() -> ::mlir::FailureOr<::llvm::SmallVector<}] # element # [{>> {
      ::llvm::SmallVector<}] # element # [{> elements;
      if ($_parser.parseCommaSeparatedList(::mlir::AsmParser::Delimiter::Square, [&]() {
            return $_parser.parseAttribute(elements.emplace_back());
          }))
        return ::mlir::failure();
      return elements;
    }()
  }];
  let printer = [{
    $_printer << '[';
    ::llvm::interleaveComma($_self, $_printer);
    $_printer << ']'
  }];
}

def Idr_InstanceArguments
    : Idr_SquareListParameter<"::mlir::StringAttr", "the text of each argument of an instance">;

def Idr_InstanceAttr : AttrDef<Idr_Dialect, "Instance"> {
  let mnemonic = "instance";
  let summary = "the Idris definition and arguments a function or data type is an instance of";
  let parameters = (ins "::mlir::StringAttr":$origin, Idr_InstanceArguments:$arguments);
  let assemblyFormat = "`<` $origin `,` $arguments `>`";
}

//===----------------------------------------------------------------------===//
// Refusals
//===----------------------------------------------------------------------===//

// The rule a refusal names, held in the refusal's diagnostic as data
// (idr::refuse), so the driver reads the rule and never the text.
def Idr_RuleAttr : EnumAttr<Idr_Dialect, Idr_Rule, "rule">;

// A refusal of the program the frontend found, which it writes into the
// module it gives the driver: the rule, where, and the words for a human.
// The driver re-emits each through idr::refuse, the one printer of a
// refusal, so the verdict is read from the rule, never from text.
def Idr_RefusalAttr : AttrDef<Idr_Dialect, "Refusal"> {
  let mnemonic = "refusal";
  let summary = "a refusal of the program the frontend found, which the driver reports";
  let parameters = (ins EnumParameter<Idr_Rule>:$rule, "::mlir::LocationAttr":$loc,
                        StringRefParameter<"what was found, for a human">:$message);
  let assemblyFormat = "`<` $rule `,` $loc `,` $message `>`";
}

#endif // IDR_ATTRS
