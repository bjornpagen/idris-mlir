// The canonicalizations of the idr dialect that DRR can state. The others are
// in Canonicalize.cc.

#ifndef IDR_CANONICALIZE
#define IDR_CANONICALIZE

include "mlir/IR/PatternBase.td"
include "idr/IdrOps.td"

def Idr_IsInteger : Constraint<CPred<"::llvm::isa<::mlir::IntegerType>($0.getType())">,
                               "an integer">;
def Idr_IsDouble : Constraint<CPred<"::llvm::isa<::mlir::FloatType>($0.getType())">,
                              "a Double">;

//===----------------------------------------------------------------------===//
// Output fusion. A string built only to be written is
// written piece by piece, in the same order, through the world.
//===----------------------------------------------------------------------===//

def Idr_PutStrOfAppend : Pat<(Idr_PutStrOp (Idr_StrAppendOp $a, $b), $w),
                             (Idr_PutStrOp $b, (Idr_PutStrOp $a, $w))>;

def Idr_PutStrOfCons : Pat<(Idr_PutStrOp (Idr_StrConsOp $c, $s), $w),
                           (Idr_PutStrOp $s, (Idr_PutCharOp $c, $w))>;

def Idr_PutStrOfFromChar : Pat<(Idr_PutStrOp (Idr_StrFromCharOp $c), $w),
                               (Idr_PutCharOp $c, $w)>;

def Idr_PutStrOfShowInt : Pat<(Idr_PutStrOp (Idr_StrShowOp $isSigned, $x), $w),
                              (Idr_PutIntOp $isSigned, $x, $w), [(Idr_IsInteger $x)]>;

def Idr_PutStrOfShowDouble : Pat<(Idr_PutStrOp (Idr_StrShowOp $isSigned, $x), $w),
                                 (Idr_PutDoubleOp $x, $w), [(Idr_IsDouble $x)]>;

// A list packed or concatenated only to be written: its elements are
// written as the list is walked, and the string is never built. A string
// with another use is built anyway, and writing it is a copy.
def Idr_OnlyUse : Constraint<CPred<"$0.hasOneUse()">, "used only here">;

def Idr_PutStrOfPack : Pat<(Idr_PutStrOp (Idr_StrPackOp:$s $list), $w),
                           (Idr_PutListOp $list, $w), [(Idr_OnlyUse $s)]>;

def Idr_PutStrOfConcat : Pat<(Idr_PutStrOp (Idr_StrConcatOp:$s $list), $w),
                             (Idr_PutListOp $list, $w), [(Idr_OnlyUse $s)]>;

//===----------------------------------------------------------------------===//
// The first character of a string built at runtime.
//===----------------------------------------------------------------------===//

def Idr_HeadOfCons : Pat<(Idr_StrHeadOp (Idr_StrConsOp $c, $s)), (replaceWithValue $c)>;

def Idr_HeadOfShowInt : Pat<(Idr_StrHeadOp (Idr_StrShowOp $isSigned, $x)),
                            (Idr_IntHeadOp $isSigned, $x), [(Idr_IsInteger $x)]>;

def Idr_HeadOfShowDouble : Pat<(Idr_StrHeadOp (Idr_StrShowOp $isSigned, $x)),
                               (Idr_DoubleHeadOp $x), [(Idr_IsDouble $x)]>;

// Emit guards the string a head reads (idr.check.nonempty). These read the
// head off the builder while the guard is still there; the patterns above
// read it once the guard has folded away, as it does on these builders.
def Idr_HeadOfCheckedCons : Pat<
    (Idr_StrHeadOp (Idr_CheckNonemptyOp (Idr_StrConsOp $c, $s), $_)),
    (replaceWithValue $c)>;
def Idr_HeadOfCheckedShowInt : Pat<
    (Idr_StrHeadOp (Idr_CheckNonemptyOp (Idr_StrShowOp $isSigned, $x), $_)),
    (Idr_IntHeadOp $isSigned, $x), [(Idr_IsInteger $x)]>;
def Idr_HeadOfCheckedShowDouble : Pat<
    (Idr_StrHeadOp (Idr_CheckNonemptyOp (Idr_StrShowOp $isSigned, $x), $_)),
    (Idr_DoubleHeadOp $x), [(Idr_IsDouble $x)]>;

#endif // IDR_CANONICALIZE
