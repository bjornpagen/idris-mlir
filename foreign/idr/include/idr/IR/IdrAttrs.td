// The attributes of the idr dialect: its constants, what a call may do,
// the keys of clones and the instances a declaration is of.

#ifndef IDR_ATTRS
#define IDR_ATTRS

include "idr/IR/IdrTypes.td"

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

def Idr_CmpPredicate : I64EnumAttr<"CmpPredicate",
    "a comparison of strings or bigs", [
      I64EnumAttrCase<"eq", 0>, I64EnumAttrCase<"lt", 1>,
      I64EnumAttrCase<"lte", 2>, I64EnumAttrCase<"gt", 3>,
      I64EnumAttrCase<"gte", 4>]> {
  let cppNamespace = "::idr";
}

//===----------------------------------------------------------------------===//
// What a call may do
//===----------------------------------------------------------------------===//

// What a call of a function may do besides computing its results, as
// idr-effects finds it: `io`, perform IO, which takes a world, so only a
// function that takes one can, or anything at all, as a function without
// a body may; `crash`, end the program with a crash; `diverge`, never
// return, which a function may where its own body loops without Idris's
// proof (no `total`) or where it reaches one that may. It is the `effects`
// of every idr.func and of every idr.call, which idr-effects writes each
// round. Simplification only removes what a function reaches, so a stale
// value says too much, never too little; a function or call without it may
// do anything.
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

// idr-specialize keeps the key of each clone it makes in the clone's
// `clone` attribute, so that its later runs share the clone. The labels in
// a key are names, not symbol uses: a key keeps no function alive and
// refers to none.
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
// Instances
//===----------------------------------------------------------------------===//

// What a function or a data declaration is an instance of, as the frontend
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

#endif // IDR_ATTRS
