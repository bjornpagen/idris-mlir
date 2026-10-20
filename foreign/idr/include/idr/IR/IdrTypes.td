// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The types of the idr dialect, and the constraints its ops state over them.

#ifndef IDR_TYPES
#define IDR_TYPES

include "idr/IR/IdrInterfaces.td"

//===----------------------------------------------------------------------===//
// Types
//===----------------------------------------------------------------------===//

// Every type of the dialect is the type of a value, and says what a value
// of it holds (lib/IR/Types.cpp).
class Idr_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Idr_Dialect, name,
              !listconcat(traits, [DeclareTypeInterfaceMethods<Idr_ValueFactsTypeInterface>])> {
  let mnemonic = typeMnemonic;
}

// Every runtime value type is an element type of memref, so an array of
// values (idr.array.new) is a builtin memref: what the memref and
// bufferization passes work on, with no array type of our own. A type a
// value is commonly of suggests the printer a name for it (getAsmName): `w`
// the world, `s` a string, `n` an Integer or natural, `f` a closure, `lazy`
// a suspension, `tok` a token; a grade suggests its carrier's.

// A data type, identified by its name, whose body is its declaration: the
// kind of sum it is, its constructors in tag order (each a name, its
// fields' types, its role, the function of a label, and for a memo sum's
// label whether every force runs it), and the Idris instance it is of. The
// body comes with the type, as an LLVM identified struct's does: the type
// is made with it (Declarations::define), every fact in it is decided
// before then, and a pass that would change one makes a new type
// (DataRemap). A type is a name until the group it is defined in is
// sealed, and then whole: its body and what a value of it holds, written
// once, together, and only read after that, by any thread, with no lock.
// Only the parser, the bytecode reader and define see a type as a name,
// and a name read that no table declares is refused by the program's
// verifier, so no reader asks whether it is whole. A pattern or a verifier
// reads the type, never the module. To upstream's walkers the type's sub-elements
// are its labels' functions alone, so a symbol use of a label is a use of
// the type: its fields are types of their own, which the walkers do not
// enter. Written `!idr.data<"T">` wherever it occurs, its body once in its
// program's table of data types (Idr_DataTableAttr, lib/IR/DataBody.cpp),
// in text and in bytecode alike.
def Idr_DataType : Idr_Type<"Data", "data", [MutableType, MemRefElementTypeInterface]> {
  let summary = "a data type, identified by its name, whose body is its constructors";
  let parameters = (ins StringRefParameter<"the data type's identifier">:$name);
  // The kinds of sum a body says it is, which idris-mlir-tblgen writes the
  // body's syntax with, and the roles its constructors play.
  I32EnumAttr bodyKinds = Idr_SumKind;
  I32EnumAttr ctorRoles = Idr_CtorRole;
  let storageClass = "DataTypeStorage";
  let genStorageClass = 0;
  let skipDefaultBuilders = 1;
  let hasCustomAssemblyFormat = 1;
  let extraClassDeclaration = [{
    // A body: the kind of sum, the constructors in tag order, the instance.
    // Each constructor's fields are a view, of storage that outlives the
    // call that hands the body over.
    struct Body {
      ::idr::SumKind kind = ::idr::SumKind::Plain;
      ::llvm::SmallVector<::idr::Ctor> ctors;
      ::idr::InstanceAttr instance;
    };

    // A data type is made, with its body, through Declarations::define
    // (idr/IR/Symbols.h), which declares it in a program's table.

    ::idr::SumKind getKind() const;
    // In tag order.
    ::llvm::ArrayRef<::idr::Ctor> getCtors() const;
    const ::idr::Ctor &getCtor(::idr::Tag tag) const;
    // Every tag of the body, in order, for a reader that goes through the
    // constructors by their tags.
    auto getTags() const {
      return ::llvm::map_range(
          ::llvm::seq<uint32_t>(0, static_cast<uint32_t>(getCtors().size())),
          [](uint32_t tag) { return ::idr::Tag{tag}; });
    }
    ::idr::InstanceAttr getInstance() const;
    // The tag of the constructor named `name`, or nothing: how the parsers
    // read a constructor written by its name. Every other reader holds the
    // tag.
    std::optional<::idr::Tag> getTag(::llvm::StringRef ctor) const;
    bool isMemo() const { return getKind() == ::idr::SumKind::Memo; }
    bool isClosures() const { return getKind() == ::idr::SumKind::Closures; }
    // Whether the constructor `tag` is an atom: it has no fields and is no
    // state of a memo sum, whose cell a force writes, so a value of it
    // needs no cell of its own.
    bool isAtom(::idr::Tag tag) const;
    // The constructor of each role a sum has exactly one of: a memo sum's
    // states, base list's nil and cons. Asked of a sum of another kind, it
    // is the caller's error.
    ::idr::Tag getRunningTag() const { return roleTag(::idr::CtorRole::Running); }
    ::idr::Tag getForcedTag() const { return roleTag(::idr::CtorRole::Forced); }
    ::idr::Tag getNilTag() const { return roleTag(::idr::CtorRole::ListNil); }
    ::idr::Tag getConsTag() const { return roleTag(::idr::CtorRole::ListCons); }
    // Base list's element: cons's first field.
    ::mlir::Type getListElement() const { return getCtor(getConsTag()).fields[0]; }

    // To upstream's walkers and replacers, the type's sub-elements are its
    // labels' functions, in tag order: a symbol use of the type is a use of
    // each, which SymbolDCE and every symbol-use query see.
    static auto getWalkImmediateSubElementsFn() {
      return [](auto instance, ::llvm::function_ref<void(::mlir::Attribute)> walkAttrs,
                ::llvm::function_ref<void(::mlir::Type)>) {
        walkLabels(::llvm::cast<DataType>(instance), walkAttrs);
      };
    }
    static auto getReplaceImmediateSubElementsFn() {
      return [](auto instance, ::llvm::ArrayRef<::mlir::Attribute> labels,
                ::llvm::ArrayRef<::mlir::Type>) -> ::mlir::Type {
        return replaceLabels(::llvm::cast<DataType>(instance), labels);
      };
    }

  private:
    // The program's table of data types reads names into types and seals
    // them, as Declarations::define does.
    friend class ::idr::DataTableAttr;
    friend class ::idr::Declarations;
    // The type of the name, a name alone if the context has no type of
    // that name: what the parser reads a name into and define makes.
    static DataType get(::mlir::MLIRContext *context, ::llvm::StringRef identifier);
    // Seals `group`, every type of it at once: each body checked, what a
    // value of each holds solved over the group, whose types may hold one
    // another in any cycle, and over the sealed types it holds besides; then
    // each type written whole, once. A type sealed already with the same
    // body stays as it is. Failure, with `emitError`'s error for the member
    // it is about, when a body is no well-formed sum, a type is in the
    // group twice or has another body already, or a body holds a type that
    // is a name alone, outside the group; nothing is written then.
    static ::mlir::LogicalResult
    seal(::llvm::ArrayRef<::idr::DataDefinition> group,
         ::llvm::function_ref<::mlir::InFlightDiagnostic(size_t member)> emitError);
    // What a value of each member of `group` holds, in the group's order:
    // the least fixpoint over the containment among the group's types,
    // one pass over its components, callees first, a cycle holding what
    // its members hold (lib/IR/ValueFacts.cpp).
    static ::mlir::FailureOr<::llvm::SmallVector<::idr::Held>>
    solveHeld(::llvm::ArrayRef<::idr::DataDefinition> group,
              ::llvm::function_ref<::mlir::InFlightDiagnostic(size_t member)> emitError);
    ::idr::Tag roleTag(::idr::CtorRole role) const;
    // The rules of a well-formed sum, which a body is checked by once, when
    // it is set (lib/IR/DataBody.cpp).
    static ::mlir::LogicalResult verifyBody(DataType type,
                                            ::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
                                            const Body &body);
    // What a value holds, ValueFactsTypeInterface's answers: solved when
    // the type was sealed, read as it was written.
    ::idr::Held getHeld() const;
    // Whether the type is whole: false while it is a name alone, in a group
    // the parser, the bytecode reader or define has not sealed yet, and for
    // a name read that no table declares, which the program's verifier
    // refuses.
    bool isDefined() const;
    static void walkLabels(DataType type, ::llvm::function_ref<void(::mlir::Attribute)> walk);
    static ::mlir::Type replaceLabels(DataType type, ::llvm::ArrayRef<::mlir::Attribute> labels);

  public:
  }];
}

// A value of a data type held through a cell: a reference to the cell,
// which holds the constructor's tag in its header. Boxing is the value's
// type alone, never a fact of the data type: a type that contains itself in
// place is held through a box, which layout::fit decides from the module's
// types and makes everywhere the type is held.
def Idr_BoxType : Idr_Type<"Box", "box", [MemRefElementTypeInterface]> {
  let summary = "a reference to a cell that holds a value of a data type";
  let parameters = (ins "::idr::DataType":$data);
  let assemblyFormat = "`<` qualified($data) `>`";
  let builders = [
    TypeBuilderWithInferredContext<(ins "::idr::DataType":$data), [{
      return $_get(data.getContext(), data);
    }]>
  ];
}

// `!idr.fn<(A...) -> R>`: the closure's signature is a function type, held
// as one and written as MLIR writes one (a single result without
// parentheses, which the parser reads either way). A suspension is
// `!idr.lazy<T>`, not a function: defunctionalization would turn a
// function into a sum and the cell would no longer be the one that was
// forced.
def Idr_FnType : Idr_Type<"Fn", "fn", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
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
// lazy type a memo sum (a data type of kind `memo`, held in a box): the
// constructor the cell holds is its state, one per label until it is
// forced, `running` while its force runs, and `forced` with the value after.
// A flag beside the payload could disagree with the state; the constructor
// cannot.
def Idr_LazyType : Idr_Type<"Lazy", "lazy", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "a suspension of one value, forced once into this cell";
  let parameters = (ins "::mlir::Type":$value);
  let assemblyFormat = "`<` $value `>`";
  let builders = [
    TypeBuilderWithInferredContext<(ins "::mlir::Type":$value), [{
      return $_get(value.getContext(), value);
    }]>
  ];
}

// A string's literal is a quoted string, a big's and a natural's a
// #idr.big, a natural's never negative (Idr_LiteralTypeInterface).
def Idr_StrType : Idr_Type<"Str", "str", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>,
    DeclareTypeInterfaceMethods<Idr_LiteralTypeInterface>]>, Idr_AbiWord<"Str", Idr_BytesOf> {
  let summary = "a string (UTF-8)";
}

def Idr_BigType : Idr_Type<"Big", "big", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>,
    DeclareTypeInterfaceMethods<Idr_LiteralTypeInterface>]>, Idr_AbiWord<"Big", Idr_NoCount> {
  let summary = "an Integer";
}

// Nat, and every type Idris shapes like it (a nullary constructor and a
// unary successor, Fin among them): a big at runtime, never negative. Every
// op that produces one keeps it non-negative (a sum, a product, a
// predecessor of a value that is not zero), and the only way in from an
// Integer, idr.nat.from_big, clamps, so the type itself proves the range,
// which idr::ranges::ofType states: integer range analysis seeds [0, +inf)
// from it for block arguments and results it cannot see computed.
def Idr_NatType : Idr_Type<"Nat", "nat", [MemRefElementTypeInterface,
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>,
    DeclareTypeInterfaceMethods<Idr_LiteralTypeInterface>]>, Idr_AbiWord<"Big", Idr_NoCount> {
  let summary = "a natural number: a non-negative big";
}

// The values a big op computes on: an Integer, or a natural where the
// operation keeps naturals natural.
def Idr_BigOrNat : AnyTypeOf<[Idr_BigType, Idr_NatType]>;

// The IO world token. Every world is used exactly once, which its type
// says (isLinearByType), as a destination's and a cell's do: it takes no
// grade. It has no runtime form.
def Idr_WorldType : Idr_Type<"World", "world", [
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]>,
    Idr_AbiWord<"World", Idr_NoCount> {
  let summary = "the IO world token, used exactly once by its type";
}

// A grade lives in the type, where no pass can drop it. It is a pair
// (u, p) (idr::Grade): u is the quantity Idris proved, one or many, and p
// is what the value owns, plain (nothing to say), borrow, own or excl. A
// plain type T is (many, plain) and is never written as !idr.q. The type
// is `!idr.q<quantity, permission, value>`, and the common grades have
// spellings, which the dialect reads and writes from one table
// (lib/IR/Types.cpp): !idr.lin<T> is (one, plain) of T, and !idr.own<T>
// and !idr.excl<T> are (many, own) and (many, excl) of T. A value of
// quantity one is used at most once on every path; its one use is
// idr.lin.use, or a position that is linear itself (a parameter, a field,
// a capture or a result of the same type). A type whose every value is used
// exactly once by the type alone (the world, a destination, a cell:
// isLinearByType) takes no grade: its quantity is its type's.
// A lifetime as a grade's parameter: heap when it is not written.
class Idr_LifetimeParam : EnumParameter<Idr_Lifetime> {
  let defaultValue = "::idr::Lifetime()";
}
def Idr_LifetimeParameter : Idr_LifetimeParam;

def Idr_QType : Idr_Type<"Q", "q", [
    DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>]> {
  let summary = "a value at a grade: its quantity, what it owns and how long what it reaches lives";
  let parameters = (ins EnumParameter<Idr_Quantity>:$quantity,
                        EnumParameter<Idr_Permission>:$permission, "::mlir::Type":$value,
                        Idr_LifetimeParameter:$lifetime);
  // The lifetime is written after the value, and only when it is not heap.
  let assemblyFormat = "`<` $quantity `,` $permission `,` $value (`,` $lifetime^)? `>`";
  let genVerifyDecl = 1;
  let skipDefaultBuilders = 1;
  let builders = [
    TypeBuilder<(ins "::idr::Quantity":$quantity, "::idr::Permission":$permission,
                     "::mlir::Type":$value, CArg<"::idr::Lifetime", "::idr::Lifetime()">:$lifetime), [{
      return $_get($_ctxt, quantity, permission, value, lifetime);
    }]>,
    TypeBuilder<(ins "::idr::Grade":$grade, "::mlir::Type":$value), [{
      return $_get($_ctxt, grade.quantity, grade.permission, value, grade.lifetime);
    }]>
  ];
  let extraClassDeclaration = [{
    ::idr::Grade getGrade() const { return {getQuantity(), getPermission(), getLifetime()}; }
  }];
}

// A linear value: one that entered its grade, and is used out of it.
def Idr_LinType : Type<CPred<"::idr::isLinear($_self)">, "a value graded at quantity 1",
                       "::idr::QType">;

def Idr_SumType : AnyTypeOf<[Idr_DataType, Idr_BoxType]>;
def Idr_Int : AnyTypeOf<[I8, I16, I32, I64]>;
// An integer an op reads as Idris's IntN or as its BitsN: one op per
// signedness, as arith's divsi and divui are, and the C ABI's word extends
// it as the op reads it.
def Idr_SInt : AnyTypeOf<[I8, I16, I32, I64], "an integer read as signed">,
               Idr_AbiWord<"Signed", Idr_NoCount>;
def Idr_UInt : AnyTypeOf<[I8, I16, I32, I64], "an integer read as unsigned">,
               Idr_AbiWord<"Unsigned", Idr_NoCount>;

// A value of a type at any grade: what an op that makes one produces,
// plain before idr-rc and owned after it.
class Idr_AtAnyGrade<string cppType, string name>
    : Type<CPred<"::llvm::isa<" # cppType # ">(::idr::unrestricted($_self))">, name, "::mlir::Type">;
def Idr_StrValue : Idr_AtAnyGrade<"::idr::StrType", "a string at any grade">,
                   Idr_AbiWord<"Str", Idr_BytesOf>;
def Idr_BigValue : Idr_AtAnyGrade<"::idr::BigType", "an Integer at any grade">,
                   Idr_AbiWord<"Big", Idr_NoCount>;
def Idr_NatValue : Idr_AtAnyGrade<"::idr::NatType", "a natural at any grade">,
                   Idr_AbiWord<"Big", Idr_NoCount>;
def Idr_BigOrNatValue : Idr_AtAnyGrade<"::idr::BigType, ::idr::NatType",
                                       "an Integer or a natural at any grade">,
                        Idr_AbiWord<"Big", Idr_NoCount>;
def Idr_BoxValue : Idr_AtAnyGrade<"::idr::BoxType", "a box at any grade">;
// The cell, plain before idr-rc and owned after it. The value inside stays
// the carrier: ownership is the grade of this reference, not a second type.
def Idr_LazyValue : Idr_AtAnyGrade<"::idr::LazyType", "a suspension at any grade">;
def Idr_SumValue : Idr_AtAnyGrade<"::idr::DataType, ::idr::BoxType", "a constructor value at any grade">;
// A constructor value at any quantity that holds no reference of its own:
// what a match takes apart, whose regions bind its fields at its grade.
def Idr_SumView : Type<And<[Idr_SumValue.predicate, CPred<"!::idr::isOwned($_self)">]>,
                       "a constructor value at any quantity, not owned", "::mlir::Type">;

// A destination: a field of a cell built without it (idr.dest.of), the
// word a later write fills with a box's reference, so the field is a box.
// It is written exactly once, which its type says (isLinearByType).
def Idr_DestType : Idr_Type<"Dest", "dest"> {
  let summary = "a field of a cell built without it, to be written exactly once";
  let parameters = (ins "::idr::BoxType":$value);
  let assemblyFormat = "`<` qualified($value) `>`";
}

#endif // IDR_TYPES
