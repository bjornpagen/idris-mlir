## C02 Inherent facts on ops

Producer: U01. Decisions: 0004 D19, D28, D29, D37, D38, D31, §6 (the rows
for `idr.stack`, `idr.program`, `break_last`, `CloneAttr`). Every fact a
pass reads is an op's own property or a type; the dialect declares no
discardable attribute (`IdrBase.td:58` goes, and the dialect's attribute
verifier refuses every `idr.*` attribute on an op or an argument,
`Verify/Attributes.cpp`).

### 1. Constructor references

Every op and attribute that names a constructor names it by its name within
the data type of the value it builds or reads, as a `FlatSymbolRefAttr`
(`@Cons`); the tag is the constructor's position in the type's body (C01).
Today's nested `@T::@C` (`idr.con`, `idr.reuse`, `idr.take`, `#idr.con`)
goes. For a label of a `closures` or `memo` sum the name is the label
function's symbol, so the reference is a symbol use of the label.

| Op or attribute | Property | The data type it names a constructor of |
| --- | --- | --- |
| `idr.con` | `FlatSymbolRefAttr:$ctor` | its result's (`dataTypeOf`) |
| `idr.field` | `FlatSymbolRefAttr:$ctor` (unchanged) | its operand's |
| `idr.dest.of` | `FlatSymbolRefAttr:$ctor` (unchanged) | its operand's |
| `idr.reuse` | `FlatSymbolRefAttr:$ctor` | its result's |
| `idr.take` | `FlatSymbolRefAttr:$ctor` | its operand's |
| `idr.match` | `ArrayAttr:$cases` of `FlatSymbolRefAttr` (unchanged) | its scrutinee's |
| `#idr.con` | `"::idr::DataType":$data`, then `"::mlir::FlatSymbolRefAttr":$ctor` | its own `data`: a constant is untyped, and a run's cells are one type's, so two types' constructors of one name (`Just` of `Maybe (Maybe Int)` and of `Maybe Int`) never join |

Each op of the first six rows gains, in ODS `extraClassDeclaration`,
defined in the op's `lib/IR/Ops*.cpp`:

```cpp
DataType getDataType();      // the column's type; never null on a verified op
unsigned getTag();           // its constructor's tag (MatchOp: getCaseTag(unsigned index))
```

Each op's own `verify()` (no symbol table) checks that the type has a body
and the constructor is in it, and the fields' types (`OpsCon.cpp:59-79,
109-121, 261-271`, `OpsOwnership.cpp:17-36`, `OpsMatch.cpp:99-115` move
there). Builders: `ConOp::create(b, loc, resultType, ctor, fields)` with
`ctor` a `FlatSymbolRefAttr`; the others as generated.

Assembly, unchanged but for the reference: `idr.con @Cons(%x, %xs) :
(i64, !List) -> !List`, `idr.reuse %tok @Cons(%x, %xs) : ...`, `idr.take %v
@Cons : !List -> ...`, `#idr.con<!List, @Cons, [...]>`. C++:
`ConAttr::get(ctx, DataType data, FlatSymbolRefAttr ctor, ArrayAttr fields)`,
`ConAttr::getRun(ctx, data, ctor, spine, cells, tail)`, `getData()`,
`getCtor()`, `getTag()`. The data type is the constant's identity, held in
place: a constant of `!idr.box<T>` names `T`, and `DataRemap` remaps it
without boxing it. The generated Idris constructor is `ConAttr : (data' :
ty) -> (ctor : String) -> (cells : List (List at)) -> (tail : Maybe at) ->
(spine : Nat) -> IdrAttr ty at`.

### 2. `idr.con`: the stack cell is inherent

```tablegen
let arguments = (ins FlatSymbolRefAttr:$ctor, Variadic<AnyType>:$fields, UnitAttr:$stack);
let assemblyFormat = [{
  $ctor `(` $fields `)` (`stack` $stack^)? attr-dict `:` functional-type($fields, $result)
}];
let hasVerifier = 1;   // `stack` only on a box
```

Written by idr-stack (U08) with `setStack(true)`; read with `getStack()` by
U08 (`Reuses`, `Exclusivity`), U10 (`Cells.cpp:52`), U01 (`ConOp::getEffects`,
`Verify/Owned.cpp:208`). `StackAttrHelper` and every reader through it go.

### 3. `idr.func`

```tablegen
let arguments = (ins SymbolNameAttr:$sym_name, TypeAttrOf<FunctionType>:$function_type,
                     OptionalAttr<StrAttr>:$sym_visibility,
                     OptionalAttr<DictArrayAttr>:$arg_attrs, OptionalAttr<DictArrayAttr>:$res_attrs,
                     UnitAttr:$total, UnitAttr:$no_inline,
                     OptionalAttr<Idr_EffectAttr>:$effects,
                     OptionalAttr<Idr_InstanceAttr>:$instance);
```

`break_last` and `clone` go, with `CloneAttr`, `KeyClosureAttr`,
`KeyApplyAttr` and `KeyApplyFieldAttr` (`IdrAttrs.td:202-243`): a clone is
an ordinary private function, named from its key (C21), with no property
naming the key, and after defunctionalization no `idr.apply` is left to
key a raise by. `KeyHoleAttr`, `KeyConAttr` and `SpecKeyAttr` stay, and
raising's key is new (the coordinator's decision from C09 §2, §5):

```tablegen
def Idr_KeyRaiseAttr : Idr_KeyAttr<"KeyRaise", "key_raise"> {
  let summary = "the key of a clone that dispatches on its callee's result";
  let parameters = (ins "::mlir::StringAttr":$callee, "::mlir::StringAttr":$consumer);
  let assemblyFormat = "`<` $callee `,` $consumer `>`";
}
```

`consumer` is the dispatch match's printed form (C09). A pass prints these
into a key; no op holds one. `absorb`,
`isExternal`, `getCallableRegion` stay (`IdrOps.td:44-56`); the verifier
makes `isExternal()` false on every verified `idr.func` (C03).

### 4. `idr.call`'s effects are its callee's

`CallOp::verifySymbolUses` (`Func/Call.cpp:41-74`) checks equality, absence
meaning every effect on both sides: `mayDo(call.effects) ==
mayDo(callee.effects)`. A pass that creates a call, or changes its callee,
writes the callee's `effects` (or none when the callee has none). The
comment at `IdrOps.td:59-65` loses "the closures it is given".

### 5. `idr.delay %value`

```tablegen
def Idr_DelayOp : Idr_Op<"delay", [Idr_ConsumesOnly<"0">,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmResultNames"]>]> {
  let summary = "a suspension already evaluated: it holds its operand";
  let arguments = (ins AnyType:$value);
  let results = (outs Idr_LazyValue:$result);
  let assemblyFormat = "$value attr-dict `:` type($value) `->` type($result)";
  let hasVerifier = 1;   // unrestricted(value) == unrestricted(lazy's value)
}
```

`idr.delay` with a region, `idr.lambda`, `EvaluateDelay`
(`OpsClosures.cpp:87-119`) and `idr::evaluatedValue` (`IdrDialect.h:300-305`)
go: a delay's value is `getValue()`. `ForceOp::fold` reads it. `idr.yield`'s
parents are `idr.match` and `idr.match_lit` (C11 drops the unordered array
ops' bodies). Its flow edge (into the forced-state anchor) is C05's.

### 6. The buffer boundary ops (C14 §3, the coordinator's decision)

`idr::OwnAdoptOp` (`idr.own.adopt %m : memref<...>`, result
`!idr.own<memref<...>>`, `Pure`; its verifier: the operand is a
`memref.alloc`'s result of one use) and `idr::OwnGiveOp` (`idr.own.give %v
: !idr.own<T>`, result `T`, `Idr_Consumes<"0">`, effects `consumedEffects`;
its verifier: its one use is the value of a `memref.store` into a buffer of
counted `T`), in `IdrOwnershipOps.td`, exactly as C14 §3 writes them.
`Idr_CountedValueType` takes every memref. No op declares the flow
interface in ODS (C05): every op's flow is an external model in U02's
`lib/IR/Flow.cpp`.

### 7. Consumers

U02 (constructor references, `idr.delay %value`, flow traits), U03
(`absorb`, call effects at readiness), U04 (keys without `CloneAttr`), U05
(writes `effects`), U08 (`stack`), U09 (references, no clone key), U10
(`stack`, references), U14/U15 (C22: the emitted forms), U16 (no
`break_last`), U17 (fixtures).
