## C04 Refusals as data: one rule enum

Producer: U01. Decision: 0004 D42 (and D40, D48). The reasons for a
refusal are one enum, declared once in the dialect's ODS; C++ gets it from
ODS, Idris from `idris-mlir-tblgen`. `compiler/src/IdrisMLIR/Rule.idr` is
deleted. The text of every refusal is unchanged, so every reject test's
expected output holds.

### 1. ODS (`include/idr/IR/IdrBase.td`, `IdrAttrs.td`)

```tablegen
def Idr_Rule : I32EnumAttr<"Rule", "the rule a refusal of a program names", [
    I32EnumAttrCase<"ProgramShape", 0, "program">,
    I32EnumAttrCase<"TrustedLibrary", 1, "library">,
    I32EnumAttrCase<"WorldUse", 2, "world">,
    I32EnumAttrCase<"IOPrimitive", 3, "io primitive">,
    I32EnumAttrCase<"ValueType", 4, "type">,
    I32EnumAttrCase<"DependentField", 5, "dependent field">,
    I32EnumAttrCase<"DictionaryField", 6, "dictionary field">,
    I32EnumAttrCase<"DataType", 7, "data type">,
    I32EnumAttrCase<"DefinitionShape", 8, "definition">,
    I32EnumAttrCase<"Match", 9, "match">,
    I32EnumAttrCase<"StaticArgument", 10, "static argument">,
    I32EnumAttrCase<"Polymorphism", 11, "polymorphism">,
    I32EnumAttrCase<"Laziness", 12, "laziness">,
    I32EnumAttrCase<"Primitive", 13, "primitive">,
    I32EnumAttrCase<"StringPrimitive", 14, "string primitive">,
    I32EnumAttrCase<"RuntimeClosure", 15, "runtime closure">,
    I32EnumAttrCase<"EscapeHatch", 16, "escape hatch">,
    I32EnumAttrCase<"UserPragma", 17, "pragma">,
    I32EnumAttrCase<"Threads", 18, "threads">,
    I32EnumAttrCase<"Finalizer", 19, "finalizer">,
    I32EnumAttrCase<"RawPointer", 20, "raw pointer">,
    I32EnumAttrCase<"Signal", 21, "signal">,
    I32EnumAttrCase<"Process", 22, "process">,
    I32EnumAttrCase<"CompiledModule", 23, "compiled module">,
    I32EnumAttrCase<"IdentityHook", 24, "identity hook">,
    I32EnumAttrCase<"HookShape", 25, "hook">,
    I32EnumAttrCase<"Deprecated", 26, "deprecated">,
    I32EnumAttrCase<"Layout", 27, "layout">,
    I32EnumAttrCase<"Uniqueness", 28, "uniqueness">,
    I32EnumAttrCase<"Cycle", 29, "cycle">,
    I32EnumAttrCase<"Runtime", 30, "runtime">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
  // A phrase of two words is no keyword: written as a string.
  let parameterPrinter = "$_printer.printKeywordOrString(::idr::stringifyRule($_self))";
}
def Idr_RuleAttr : EnumAttr<Idr_Dialect, Idr_Rule, "rule">;   // #idr.rule<layout>
```

`CompileBudget` (`Rule.idr:37, 69`) is not a case (D17, D40). The four C++
rules after the cutover are `layout`, `uniqueness`, `cycle`, `runtime`
(D42). A new rule is a new case here and nowhere else.

### 2. C++ (`include/idr/IR/IdrDialect.h`, defined in `lib/IR/Attrs.cpp`)

```cpp
namespace idr {
// `unsupported (<phrase>)`: the words every refusal begins with, the phrase
// the rule's ODS case spells. The one place the words are written.
std::string refusalHead(Rule rule);
// A refusal of the program: an error at `loc` (at `op`'s location) whose
// message begins `refusalHead(rule)` and ": ", and whose metadata
// (mlir::Diagnostic::getMetadata) holds #idr.rule<rule>. The caller streams
// what was found after it.
mlir::InFlightDiagnostic refuse(mlir::Location loc, Rule rule);
mlir::InFlightDiagnostic refuse(mlir::Operation *op, Rule rule);
// The rule a diagnostic refuses the program by, read from its metadata;
// nothing for any other diagnostic.
std::optional<Rule> refusalRule(mlir::Diagnostic &diagnostic);
}
```

The rule rides in the diagnostic's metadata, upstream's list of arguments
that are not printed (`M/include/mlir/IR/Diagnostics.h:299-331`), not as a
printed argument: an attribute among the arguments prints as `#idr.rule<…>`
and would change every expected text. This is D42's "first argument",
placed where it is data and not text.

Sites (each `emitError() << "unsupported (…): …"` becomes `refuse(…, Rule::…)
<< "…"`): `layout` at `IR/Layout/Layouts.cpp:95` and the module rule (C03);
`cycle` at `IR/Verify/Knots.cpp:100` (U01); `uniqueness` at
`Transforms/Demand/Demand.cpp:79` (U08); `layout` at `Conversion/Arrays.cpp:49`
(U10, if it stays); `runtime` at `Driver/ReadRuntime.cpp:161` (U06), which
is a `Report()`, not a diagnostic: it writes `refusalHead(Rule::Runtime)`.
The driver's handler reads `refusalRule(diagnostic)` instead of
`starts_with("unsupported (")` (`Driver/Run.cpp:248-254`, U06).

### 3. Idris (generated into `compiler/src/IdrisMLIR/Syntax/Idr.idr`)

The syntax module already holds the dialect's enums; `Rule` is one of them,
beside `Dialect/Idr.idr`:

```idris
namespace Rule
  ||| the rule a refusal of a program names
  public export
  data Rule = ProgramShape | TrustedLibrary | WorldUse | IOPrimitive | ValueType
            | DependentField | DictionaryField | DataType | DefinitionShape | Match
            | StaticArgument | Polymorphism | Laziness | Primitive | StringPrimitive
            | RuntimeClosure | EscapeHatch | UserPragma | Threads | Finalizer
            | RawPointer | Signal | Process | CompiledModule | IdentityHook | HookShape
            | Deprecated | Layout | Uniqueness | Cycle | Runtime

export
Prelude.EqOrd.Eq Rule where ...      -- as every generated enum's

export
Show Rule where
  show Rule.ProgramShape = "program"
  ...                                  -- each case's ODS string
```

### 4. The generator's rules for every enum (U01, `tools/idris-mlir-tblgen.cpp`)

- Every enum gets an exported `Show` whose `show` is its case's ODS string
  (`Show Rule` above, `Show Quantity` "one", "many", ...).
- The private `<enum>Spelling` the syntax writers use writes a case as MLIR's
  enum parser reads it (`parseKeywordOrString`, `M/include/mlir/IR/EnumAttr.td:329-335`):
  the string itself when it is a bare identifier, else a quoted string. For
  every enum of today the text is unchanged.

### 5. Consumers

- U14: every importer of `IdrisMLIR.Rule` (`Frontend/Program.idr:17`,
  `Translate/Cases.idr:23`, `Profile.idr:28`, `Types.idr:25`,
  `Dictionaries.idr:46`, `Recursion.idr:26`, `Instances.idr:23`,
  `Programs.idr:25`, `Terms.idr:32`, `Closed.idr:19`, `Errors.idr:17`,
  `Registry/Recognized.idr:14`, `Entry.idr:10`, `Primitives.idr:17`) imports
  `IdrisMLIR.Syntax.Idr` instead; `show rule` is unchanged
  (`Errors.idr:37`); `CompileBudget` goes with `instanceBudget`;
  `IdrisMLIR.Rule` leaves `compiler/idris-mlir.ipkg:10`.
- U06: the driver's verdict from `refusalRule`; `ReadRuntime.cpp:161`
  from `refusalHead`.
- U08 (`Demand.cpp:79`), U10 (`Arrays.cpp:49` while it exists): `refuse`.
- U18: `rejection_skip` reads the rule; spec checks: no `"unsupported ("`
  literal in `foreign/idr` but in `lib/IR/Attrs.cpp`, no rule naming a
  budget, no `compiler/src/IdrisMLIR/Rule.idr`.
- U17: fixtures of the C++ refusals, text unchanged.
