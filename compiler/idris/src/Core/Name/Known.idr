-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| The identifiers the compiler's own code spells: the builtin names it
||| recognizes or makes, the namespaces they live in, the constructors of
||| reflection's types, and the stems of the names it generates. Each is
||| known when the compiler is built, so each has a fixed id, its ordinal,
||| and a session's table of identifiers holds each at that id before it
||| meets any other text: an identifier the code spells is a constant, never
||| looked up.
|||
||| The spelling, the ordinal and its inverse are each one case per
||| identifier; `roundTrip` and `below` check, when the compiler is built,
||| that they agree and that every ordinal is under `knownCount`, the first
||| id a new text gets.
module Core.Name.Known

import Data.So

%default total

public export
data Known
  = KDollar
  | KMinus
  | KArrow
  | KCons
  | KCons1
  | KSnoc
  | KAp
  | KAutoMark
  | KEquals
  | KHomoEq
  | KSeq
  | KBindOp
  | KApp
  | KAutoImplicit
  | KB16
  | KB32
  | KB64
  | KB8
  | KBI
  | KBasic
  | KBasics
  | KBits16Type
  | KBits32Type
  | KBits64Type
  | KBits8Type
  | KBool
  | KBound
  | KBuiltin
  | KBuiltinNatural
  | KCOVERAGE
  | KCaseBlock
  | KCh
  | KCharType
  | KCoveringOnly
  | KDN
  | KDPair
  | KData
  | KDataCon
  | KDb
  | KDecl
  | KDefImplicit
  | KDefaultedValue
  | KDeprecate
  | KDoubleType
  | KElab
  | KEmptyFC
  | KEqOrd
  | KEqual
  | KErased
  | KErasedArg
  | KExplicitArg
  | KExport
  | KExternFn
  | KExternal
  | KFalse
  | KField
  | KFirst
  | KFirstSuccess
  | KForeignExport
  | KForeignFn
  | KFunc
  | KGlobalHint
  | KHint
  | KI
  | KI16
  | KI32
  | KI64
  | KI8
  | KIAlternative
  | KIApp
  | KIAs
  | KIAutoApp
  | KIBindHere
  | KIBindVar
  | KICase
  | KIClaim
  | KIData
  | KIDef
  | KIDelay
  | KIDelayed
  | KIFail
  | KIForce
  | KIHole
  | KILam
  | KILet
  | KILocal
  | KILog
  | KIMustUnify
  | KINamedApp
  | KINamespace
  | KIO
  | KIParameters
  | KIPi
  | KIPrimVal
  | KIQuote
  | KIQuoteDecl
  | KIQuoteName
  | KIRecord
  | KIRewrite
  | KISearch
  | KISetField
  | KISetFieldApp
  | KITransform
  | KIType
  | KIUnquote
  | KIUpdate
  | KIVar
  | KIWithApp
  | KIWithUnambigNames
  | KImplicit
  | KImplicitArg
  | KImpossibleClause
  | KInline
  | KInt16Type
  | KInt32Type
  | KInt64Type
  | KInt8Type
  | KIntType
  | KIntegerToNatural
  | KIntegerType
  | KInteractive
  | KInvertible
  | KJust
  | KLInf
  | KLLazy
  | KLUnknown
  | KLam
  | KLanguage
  | KLater
  | KLin
  | KList
  | KList1
  | KLocal
  | KM0
  | KM1
  | KMN
  | KMW
  | KMacro
  | KMain
  | KMaybe
  | KMkDPair
  | KMkData
  | KMkFC
  | KMkFCVal
  | KMkIClaimData
  | KMkIField
  | KMkLater
  | KMkMI
  | KMkNS
  | KMkNameInfo
  | KMkPair
  | KMkRecord
  | KMkTy
  | KMkUnit
  | KNONE
  | KNS
  | KName
  | KNat
  | KNaturalToInteger
  | KNested
  | KNil
  | KNoHints
  | KNoInline
  | KNoNewtype
  | KNonLinearVar
  | KNotConstructor
  | KNothing
  | KNum
  | KPATTERN
  | KPI
  | KPair
  | KPartialOK
  | KPatClause
  | KPhysicalIdrSrc
  | KPhysicalPkgSrc
  | KPi
  | KPrT
  | KPrelude
  | KPrimIO
  | KPrimVal
  | KPrivate
  | KPublic
  | KRef
  | KRefl
  | KReflection
  | KS
  | KSearchBy
  | KSnocList
  | KSpecArgs
  | KSpecifiedValue
  | KStr
  | KStringType
  | KSyntactic
  | KTCInline
  | KTDelay
  | KTDelayed
  | KTForce
  | KTT
  | KTTImp
  | KTType
  | KTotal
  | KTotality
  | KTrue
  | KTyCon
  | KType
  | KTypes
  | KUN
  | KUnderAppliedCon
  | KUnderscore
  | KUnique
  | KUniqueDefault
  | KUniqueSearch
  | KUnit
  | KUnknownDot
  | KUnsafe
  | KUseLeft
  | KUseRight
  | KUserDotted
  | KVarApplied
  | KVirtual
  | KWithBlock
  | KWithClause
  | KWorldType
  | KWorldVal
  | KZ
  | KElabScript
  | KForeign
  | K_
  | K_PE
  | K__
  | K__con
  | K__infixTupleSection
  | K__leftTupleSection
  | K_cn
  | Ka
  | KaltTy
  | Karg
  | KargTy
  | Kassert_smaller
  | Kassert_total
  | Kbelieve_me
  | Kbind
  | KcaseTy
  | KconArg
  | Kconcat
  | Kconstraint
  | Kconv
  | Kcrash
  | KdefArg
  | KdelayTy
  | Kdelayed
  | KdotTm
  | KdoubleACos
  | KdoubleASin
  | KdoubleATan
  | KdoubleCeiling
  | KdoubleCos
  | KdoubleExp
  | KdoubleFloor
  | KdoubleLog
  | KdoublePow
  | KdoubleSin
  | KdoubleSqrt
  | KdoubleTan
  | Kfvar
  | Kguard
  | Ki_con
  | Kimp
  | KimpArg
  | Kimplicit_type
  | Kinf
  | Kinterpolate
  | Klamc
  | Klcase
  | Km
  | Kmain
  | Knegate
  | KpaRoot
  | KpairFst
  | KpairSnd
  | Kpostpone
  | Kpure
  | Kq
  | Kqv
  | KrangeFrom
  | KrangeFromThen
  | KrangeFromThenTo
  | KrangeFromTo
  | Krec
  | KretTy
  | Krwarg
  | Ksa
  | Kscr
  | KscriptTy
  | Ksearch
  | KsearchTy
  | KstrAppend
  | KstrCons
  | KstrHead
  | KstrIndex
  | KstrLength
  | KstrReverse
  | KstrSubstr
  | KstrTail
  | Kt
  | Ktmp
  | Ktop
  | Ku
  | Kwarg
  | Kx
  | KHeteroEq
  | Kprim__believe_me
  | Kprim__crash
  | Kidris_crash
  | KElabAp
  | KPure
  | KMap
  | KBind
  | KFail
  | KWarn
  | KTry
  | KLogMsg
  | KLogTerm
  | KLogSugaredTerm
  | KResugarTerm
  | KCheck
  | KQuote
  | KLambda
  | KGoal
  | KLocalVars
  | KGenSym
  | KInCurrentNS
  | KGetType
  | KGetInfo
  | KGetVis
  | KGetLocalType
  | KGetCons
  | KGetReferredFns
  | KGetCurrentFn
  | KGetFC
  | KDeclare
  | KReadFile
  | KWriteFile
  | KIdrisDir
  | KProjectDir
  | KSourceDir
  | KCurrentModuleDir
  | KSubmodulesDir
  | KBuildDir
  | Kb
  | Kmsg
  | Kprim__add_Int
  | Kprim__add_Int8
  | Kprim__add_Int16
  | Kprim__add_Int32
  | Kprim__add_Int64
  | Kprim__add_Integer
  | Kprim__add_Bits8
  | Kprim__add_Bits16
  | Kprim__add_Bits32
  | Kprim__add_Bits64
  | Kprim__add_String
  | Kprim__add_Char
  | Kprim__add_Double
  | Kprim__add_PercentWorld
  | Kprim__sub_Int
  | Kprim__sub_Int8
  | Kprim__sub_Int16
  | Kprim__sub_Int32
  | Kprim__sub_Int64
  | Kprim__sub_Integer
  | Kprim__sub_Bits8
  | Kprim__sub_Bits16
  | Kprim__sub_Bits32
  | Kprim__sub_Bits64
  | Kprim__sub_String
  | Kprim__sub_Char
  | Kprim__sub_Double
  | Kprim__sub_PercentWorld
  | Kprim__mul_Int
  | Kprim__mul_Int8
  | Kprim__mul_Int16
  | Kprim__mul_Int32
  | Kprim__mul_Int64
  | Kprim__mul_Integer
  | Kprim__mul_Bits8
  | Kprim__mul_Bits16
  | Kprim__mul_Bits32
  | Kprim__mul_Bits64
  | Kprim__mul_String
  | Kprim__mul_Char
  | Kprim__mul_Double
  | Kprim__mul_PercentWorld
  | Kprim__div_Int
  | Kprim__div_Int8
  | Kprim__div_Int16
  | Kprim__div_Int32
  | Kprim__div_Int64
  | Kprim__div_Integer
  | Kprim__div_Bits8
  | Kprim__div_Bits16
  | Kprim__div_Bits32
  | Kprim__div_Bits64
  | Kprim__div_String
  | Kprim__div_Char
  | Kprim__div_Double
  | Kprim__div_PercentWorld
  | Kprim__mod_Int
  | Kprim__mod_Int8
  | Kprim__mod_Int16
  | Kprim__mod_Int32
  | Kprim__mod_Int64
  | Kprim__mod_Integer
  | Kprim__mod_Bits8
  | Kprim__mod_Bits16
  | Kprim__mod_Bits32
  | Kprim__mod_Bits64
  | Kprim__mod_String
  | Kprim__mod_Char
  | Kprim__mod_Double
  | Kprim__mod_PercentWorld
  | Kprim__negate_Int
  | Kprim__negate_Int8
  | Kprim__negate_Int16
  | Kprim__negate_Int32
  | Kprim__negate_Int64
  | Kprim__negate_Integer
  | Kprim__negate_Bits8
  | Kprim__negate_Bits16
  | Kprim__negate_Bits32
  | Kprim__negate_Bits64
  | Kprim__negate_String
  | Kprim__negate_Char
  | Kprim__negate_Double
  | Kprim__negate_PercentWorld
  | Kprim__shl_Int
  | Kprim__shl_Int8
  | Kprim__shl_Int16
  | Kprim__shl_Int32
  | Kprim__shl_Int64
  | Kprim__shl_Integer
  | Kprim__shl_Bits8
  | Kprim__shl_Bits16
  | Kprim__shl_Bits32
  | Kprim__shl_Bits64
  | Kprim__shl_String
  | Kprim__shl_Char
  | Kprim__shl_Double
  | Kprim__shl_PercentWorld
  | Kprim__shr_Int
  | Kprim__shr_Int8
  | Kprim__shr_Int16
  | Kprim__shr_Int32
  | Kprim__shr_Int64
  | Kprim__shr_Integer
  | Kprim__shr_Bits8
  | Kprim__shr_Bits16
  | Kprim__shr_Bits32
  | Kprim__shr_Bits64
  | Kprim__shr_String
  | Kprim__shr_Char
  | Kprim__shr_Double
  | Kprim__shr_PercentWorld
  | Kprim__and_Int
  | Kprim__and_Int8
  | Kprim__and_Int16
  | Kprim__and_Int32
  | Kprim__and_Int64
  | Kprim__and_Integer
  | Kprim__and_Bits8
  | Kprim__and_Bits16
  | Kprim__and_Bits32
  | Kprim__and_Bits64
  | Kprim__and_String
  | Kprim__and_Char
  | Kprim__and_Double
  | Kprim__and_PercentWorld
  | Kprim__or_Int
  | Kprim__or_Int8
  | Kprim__or_Int16
  | Kprim__or_Int32
  | Kprim__or_Int64
  | Kprim__or_Integer
  | Kprim__or_Bits8
  | Kprim__or_Bits16
  | Kprim__or_Bits32
  | Kprim__or_Bits64
  | Kprim__or_String
  | Kprim__or_Char
  | Kprim__or_Double
  | Kprim__or_PercentWorld
  | Kprim__xor_Int
  | Kprim__xor_Int8
  | Kprim__xor_Int16
  | Kprim__xor_Int32
  | Kprim__xor_Int64
  | Kprim__xor_Integer
  | Kprim__xor_Bits8
  | Kprim__xor_Bits16
  | Kprim__xor_Bits32
  | Kprim__xor_Bits64
  | Kprim__xor_String
  | Kprim__xor_Char
  | Kprim__xor_Double
  | Kprim__xor_PercentWorld
  | Kprim__lt_Int
  | Kprim__lt_Int8
  | Kprim__lt_Int16
  | Kprim__lt_Int32
  | Kprim__lt_Int64
  | Kprim__lt_Integer
  | Kprim__lt_Bits8
  | Kprim__lt_Bits16
  | Kprim__lt_Bits32
  | Kprim__lt_Bits64
  | Kprim__lt_String
  | Kprim__lt_Char
  | Kprim__lt_Double
  | Kprim__lt_PercentWorld
  | Kprim__lte_Int
  | Kprim__lte_Int8
  | Kprim__lte_Int16
  | Kprim__lte_Int32
  | Kprim__lte_Int64
  | Kprim__lte_Integer
  | Kprim__lte_Bits8
  | Kprim__lte_Bits16
  | Kprim__lte_Bits32
  | Kprim__lte_Bits64
  | Kprim__lte_String
  | Kprim__lte_Char
  | Kprim__lte_Double
  | Kprim__lte_PercentWorld
  | Kprim__eq_Int
  | Kprim__eq_Int8
  | Kprim__eq_Int16
  | Kprim__eq_Int32
  | Kprim__eq_Int64
  | Kprim__eq_Integer
  | Kprim__eq_Bits8
  | Kprim__eq_Bits16
  | Kprim__eq_Bits32
  | Kprim__eq_Bits64
  | Kprim__eq_String
  | Kprim__eq_Char
  | Kprim__eq_Double
  | Kprim__eq_PercentWorld
  | Kprim__gte_Int
  | Kprim__gte_Int8
  | Kprim__gte_Int16
  | Kprim__gte_Int32
  | Kprim__gte_Int64
  | Kprim__gte_Integer
  | Kprim__gte_Bits8
  | Kprim__gte_Bits16
  | Kprim__gte_Bits32
  | Kprim__gte_Bits64
  | Kprim__gte_String
  | Kprim__gte_Char
  | Kprim__gte_Double
  | Kprim__gte_PercentWorld
  | Kprim__gt_Int
  | Kprim__gt_Int8
  | Kprim__gt_Int16
  | Kprim__gt_Int32
  | Kprim__gt_Int64
  | Kprim__gt_Integer
  | Kprim__gt_Bits8
  | Kprim__gt_Bits16
  | Kprim__gt_Bits32
  | Kprim__gt_Bits64
  | Kprim__gt_String
  | Kprim__gt_Char
  | Kprim__gt_Double
  | Kprim__gt_PercentWorld
  | Kprim__strLength
  | Kprim__strHead
  | Kprim__strTail
  | Kprim__strIndex
  | Kprim__strCons
  | Kprim__strAppend
  | Kprim__strReverse
  | Kprim__strSubstr
  | Kprim__doubleExp
  | Kprim__doubleLog
  | Kprim__doublePow
  | Kprim__doubleSin
  | Kprim__doubleCos
  | Kprim__doubleTan
  | Kprim__doubleASin
  | Kprim__doubleACos
  | Kprim__doubleATan
  | Kprim__doubleSqrt
  | Kprim__doubleFloor
  | Kprim__doubleCeiling
  | Kprim__cast_IntInt
  | Kprim__cast_IntInt8
  | Kprim__cast_IntInt16
  | Kprim__cast_IntInt32
  | Kprim__cast_IntInt64
  | Kprim__cast_IntInteger
  | Kprim__cast_IntBits8
  | Kprim__cast_IntBits16
  | Kprim__cast_IntBits32
  | Kprim__cast_IntBits64
  | Kprim__cast_IntString
  | Kprim__cast_IntChar
  | Kprim__cast_IntDouble
  | Kprim__cast_IntPercentWorld
  | Kprim__cast_Int8Int
  | Kprim__cast_Int8Int8
  | Kprim__cast_Int8Int16
  | Kprim__cast_Int8Int32
  | Kprim__cast_Int8Int64
  | Kprim__cast_Int8Integer
  | Kprim__cast_Int8Bits8
  | Kprim__cast_Int8Bits16
  | Kprim__cast_Int8Bits32
  | Kprim__cast_Int8Bits64
  | Kprim__cast_Int8String
  | Kprim__cast_Int8Char
  | Kprim__cast_Int8Double
  | Kprim__cast_Int8PercentWorld
  | Kprim__cast_Int16Int
  | Kprim__cast_Int16Int8
  | Kprim__cast_Int16Int16
  | Kprim__cast_Int16Int32
  | Kprim__cast_Int16Int64
  | Kprim__cast_Int16Integer
  | Kprim__cast_Int16Bits8
  | Kprim__cast_Int16Bits16
  | Kprim__cast_Int16Bits32
  | Kprim__cast_Int16Bits64
  | Kprim__cast_Int16String
  | Kprim__cast_Int16Char
  | Kprim__cast_Int16Double
  | Kprim__cast_Int16PercentWorld
  | Kprim__cast_Int32Int
  | Kprim__cast_Int32Int8
  | Kprim__cast_Int32Int16
  | Kprim__cast_Int32Int32
  | Kprim__cast_Int32Int64
  | Kprim__cast_Int32Integer
  | Kprim__cast_Int32Bits8
  | Kprim__cast_Int32Bits16
  | Kprim__cast_Int32Bits32
  | Kprim__cast_Int32Bits64
  | Kprim__cast_Int32String
  | Kprim__cast_Int32Char
  | Kprim__cast_Int32Double
  | Kprim__cast_Int32PercentWorld
  | Kprim__cast_Int64Int
  | Kprim__cast_Int64Int8
  | Kprim__cast_Int64Int16
  | Kprim__cast_Int64Int32
  | Kprim__cast_Int64Int64
  | Kprim__cast_Int64Integer
  | Kprim__cast_Int64Bits8
  | Kprim__cast_Int64Bits16
  | Kprim__cast_Int64Bits32
  | Kprim__cast_Int64Bits64
  | Kprim__cast_Int64String
  | Kprim__cast_Int64Char
  | Kprim__cast_Int64Double
  | Kprim__cast_Int64PercentWorld
  | Kprim__cast_IntegerInt
  | Kprim__cast_IntegerInt8
  | Kprim__cast_IntegerInt16
  | Kprim__cast_IntegerInt32
  | Kprim__cast_IntegerInt64
  | Kprim__cast_IntegerInteger
  | Kprim__cast_IntegerBits8
  | Kprim__cast_IntegerBits16
  | Kprim__cast_IntegerBits32
  | Kprim__cast_IntegerBits64
  | Kprim__cast_IntegerString
  | Kprim__cast_IntegerChar
  | Kprim__cast_IntegerDouble
  | Kprim__cast_IntegerPercentWorld
  | Kprim__cast_Bits8Int
  | Kprim__cast_Bits8Int8
  | Kprim__cast_Bits8Int16
  | Kprim__cast_Bits8Int32
  | Kprim__cast_Bits8Int64
  | Kprim__cast_Bits8Integer
  | Kprim__cast_Bits8Bits8
  | Kprim__cast_Bits8Bits16
  | Kprim__cast_Bits8Bits32
  | Kprim__cast_Bits8Bits64
  | Kprim__cast_Bits8String
  | Kprim__cast_Bits8Char
  | Kprim__cast_Bits8Double
  | Kprim__cast_Bits8PercentWorld
  | Kprim__cast_Bits16Int
  | Kprim__cast_Bits16Int8
  | Kprim__cast_Bits16Int16
  | Kprim__cast_Bits16Int32
  | Kprim__cast_Bits16Int64
  | Kprim__cast_Bits16Integer
  | Kprim__cast_Bits16Bits8
  | Kprim__cast_Bits16Bits16
  | Kprim__cast_Bits16Bits32
  | Kprim__cast_Bits16Bits64
  | Kprim__cast_Bits16String
  | Kprim__cast_Bits16Char
  | Kprim__cast_Bits16Double
  | Kprim__cast_Bits16PercentWorld
  | Kprim__cast_Bits32Int
  | Kprim__cast_Bits32Int8
  | Kprim__cast_Bits32Int16
  | Kprim__cast_Bits32Int32
  | Kprim__cast_Bits32Int64
  | Kprim__cast_Bits32Integer
  | Kprim__cast_Bits32Bits8
  | Kprim__cast_Bits32Bits16
  | Kprim__cast_Bits32Bits32
  | Kprim__cast_Bits32Bits64
  | Kprim__cast_Bits32String
  | Kprim__cast_Bits32Char
  | Kprim__cast_Bits32Double
  | Kprim__cast_Bits32PercentWorld
  | Kprim__cast_Bits64Int
  | Kprim__cast_Bits64Int8
  | Kprim__cast_Bits64Int16
  | Kprim__cast_Bits64Int32
  | Kprim__cast_Bits64Int64
  | Kprim__cast_Bits64Integer
  | Kprim__cast_Bits64Bits8
  | Kprim__cast_Bits64Bits16
  | Kprim__cast_Bits64Bits32
  | Kprim__cast_Bits64Bits64
  | Kprim__cast_Bits64String
  | Kprim__cast_Bits64Char
  | Kprim__cast_Bits64Double
  | Kprim__cast_Bits64PercentWorld
  | Kprim__cast_StringInt
  | Kprim__cast_StringInt8
  | Kprim__cast_StringInt16
  | Kprim__cast_StringInt32
  | Kprim__cast_StringInt64
  | Kprim__cast_StringInteger
  | Kprim__cast_StringBits8
  | Kprim__cast_StringBits16
  | Kprim__cast_StringBits32
  | Kprim__cast_StringBits64
  | Kprim__cast_StringString
  | Kprim__cast_StringChar
  | Kprim__cast_StringDouble
  | Kprim__cast_StringPercentWorld
  | Kprim__cast_CharInt
  | Kprim__cast_CharInt8
  | Kprim__cast_CharInt16
  | Kprim__cast_CharInt32
  | Kprim__cast_CharInt64
  | Kprim__cast_CharInteger
  | Kprim__cast_CharBits8
  | Kprim__cast_CharBits16
  | Kprim__cast_CharBits32
  | Kprim__cast_CharBits64
  | Kprim__cast_CharString
  | Kprim__cast_CharChar
  | Kprim__cast_CharDouble
  | Kprim__cast_CharPercentWorld
  | Kprim__cast_DoubleInt
  | Kprim__cast_DoubleInt8
  | Kprim__cast_DoubleInt16
  | Kprim__cast_DoubleInt32
  | Kprim__cast_DoubleInt64
  | Kprim__cast_DoubleInteger
  | Kprim__cast_DoubleBits8
  | Kprim__cast_DoubleBits16
  | Kprim__cast_DoubleBits32
  | Kprim__cast_DoubleBits64
  | Kprim__cast_DoubleString
  | Kprim__cast_DoubleChar
  | Kprim__cast_DoubleDouble
  | Kprim__cast_DoublePercentWorld
  | Kprim__cast_PercentWorldInt
  | Kprim__cast_PercentWorldInt8
  | Kprim__cast_PercentWorldInt16
  | Kprim__cast_PercentWorldInt32
  | Kprim__cast_PercentWorldInt64
  | Kprim__cast_PercentWorldInteger
  | Kprim__cast_PercentWorldBits8
  | Kprim__cast_PercentWorldBits16
  | Kprim__cast_PercentWorldBits32
  | Kprim__cast_PercentWorldBits64
  | Kprim__cast_PercentWorldString
  | Kprim__cast_PercentWorldChar
  | Kprim__cast_PercentWorldDouble
  | Kprim__cast_PercentWorldPercentWorld
  | KInt
  | KInt8
  | KInt16
  | KInt32
  | KInt64
  | KInteger
  | KBits8
  | KBits16
  | KBits32
  | KBits64
  | KString
  | KChar
  | KDouble
  | Ke
  | Kcov
  | KPercentWorld
  | KfromInteger
  | KfromDouble
  | KProbeBinder
  | KProbeHole
  | KProbeHoleFound
  | KProbeUnknown
  | KProbeRuntime
  | KProbeRuntimeAt
  | KProbeField
  | KProbePattern
  | KProbeForm
  | KProbeAxis
  | KProbeAxisAt
  | KProbeSize
  | KProbeVar
  | KProbeFormal
  | KProbeHeld

||| How the identifier is spelled.
public export
spelling : Known -> String
spelling KDollar = "$"
spelling KMinus = "-"
spelling KArrow = "->"
spelling KCons = "::"
spelling KCons1 = ":::"
spelling KSnoc = ":<"
spelling KAp = "<*>"
spelling KAutoMark = "<auto>"
spelling KEquals = "="
spelling KHomoEq = "==="
spelling KSeq = ">>"
spelling KBindOp = ">>="
spelling KApp = "App"
spelling KAutoImplicit = "AutoImplicit"
spelling KB16 = "B16"
spelling KB32 = "B32"
spelling KB64 = "B64"
spelling KB8 = "B8"
spelling KBI = "BI"
spelling KBasic = "Basic"
spelling KBasics = "Basics"
spelling KBits16Type = "Bits16Type"
spelling KBits32Type = "Bits32Type"
spelling KBits64Type = "Bits64Type"
spelling KBits8Type = "Bits8Type"
spelling KBool = "Bool"
spelling KBound = "Bound"
spelling KBuiltin = "Builtin"
spelling KBuiltinNatural = "BuiltinNatural"
spelling KCOVERAGE = "COVERAGE"
spelling KCaseBlock = "CaseBlock"
spelling KCh = "Ch"
spelling KCharType = "CharType"
spelling KCoveringOnly = "CoveringOnly"
spelling KDN = "DN"
spelling KDPair = "DPair"
spelling KData = "Data"
spelling KDataCon = "DataCon"
spelling KDb = "Db"
spelling KDecl = "Decl"
spelling KDefImplicit = "DefImplicit"
spelling KDefaultedValue = "DefaultedValue"
spelling KDeprecate = "Deprecate"
spelling KDoubleType = "DoubleType"
spelling KElab = "Elab"
spelling KEmptyFC = "EmptyFC"
spelling KEqOrd = "EqOrd"
spelling KEqual = "Equal"
spelling KErased = "Erased"
spelling KErasedArg = "ErasedArg"
spelling KExplicitArg = "ExplicitArg"
spelling KExport = "Export"
spelling KExternFn = "ExternFn"
spelling KExternal = "External"
spelling KFalse = "False"
spelling KField = "Field"
spelling KFirst = "First"
spelling KFirstSuccess = "FirstSuccess"
spelling KForeignExport = "ForeignExport"
spelling KForeignFn = "ForeignFn"
spelling KFunc = "Func"
spelling KGlobalHint = "GlobalHint"
spelling KHint = "Hint"
spelling KI = "I"
spelling KI16 = "I16"
spelling KI32 = "I32"
spelling KI64 = "I64"
spelling KI8 = "I8"
spelling KIAlternative = "IAlternative"
spelling KIApp = "IApp"
spelling KIAs = "IAs"
spelling KIAutoApp = "IAutoApp"
spelling KIBindHere = "IBindHere"
spelling KIBindVar = "IBindVar"
spelling KICase = "ICase"
spelling KIClaim = "IClaim"
spelling KIData = "IData"
spelling KIDef = "IDef"
spelling KIDelay = "IDelay"
spelling KIDelayed = "IDelayed"
spelling KIFail = "IFail"
spelling KIForce = "IForce"
spelling KIHole = "IHole"
spelling KILam = "ILam"
spelling KILet = "ILet"
spelling KILocal = "ILocal"
spelling KILog = "ILog"
spelling KIMustUnify = "IMustUnify"
spelling KINamedApp = "INamedApp"
spelling KINamespace = "INamespace"
spelling KIO = "IO"
spelling KIParameters = "IParameters"
spelling KIPi = "IPi"
spelling KIPrimVal = "IPrimVal"
spelling KIQuote = "IQuote"
spelling KIQuoteDecl = "IQuoteDecl"
spelling KIQuoteName = "IQuoteName"
spelling KIRecord = "IRecord"
spelling KIRewrite = "IRewrite"
spelling KISearch = "ISearch"
spelling KISetField = "ISetField"
spelling KISetFieldApp = "ISetFieldApp"
spelling KITransform = "ITransform"
spelling KIType = "IType"
spelling KIUnquote = "IUnquote"
spelling KIUpdate = "IUpdate"
spelling KIVar = "IVar"
spelling KIWithApp = "IWithApp"
spelling KIWithUnambigNames = "IWithUnambigNames"
spelling KImplicit = "Implicit"
spelling KImplicitArg = "ImplicitArg"
spelling KImpossibleClause = "ImpossibleClause"
spelling KInline = "Inline"
spelling KInt16Type = "Int16Type"
spelling KInt32Type = "Int32Type"
spelling KInt64Type = "Int64Type"
spelling KInt8Type = "Int8Type"
spelling KIntType = "IntType"
spelling KIntegerToNatural = "IntegerToNatural"
spelling KIntegerType = "IntegerType"
spelling KInteractive = "Interactive"
spelling KInvertible = "Invertible"
spelling KJust = "Just"
spelling KLInf = "LInf"
spelling KLLazy = "LLazy"
spelling KLUnknown = "LUnknown"
spelling KLam = "Lam"
spelling KLanguage = "Language"
spelling KLater = "Later"
spelling KLin = "Lin"
spelling KList = "List"
spelling KList1 = "List1"
spelling KLocal = "Local"
spelling KM0 = "M0"
spelling KM1 = "M1"
spelling KMN = "MN"
spelling KMW = "MW"
spelling KMacro = "Macro"
spelling KMain = "Main"
spelling KMaybe = "Maybe"
spelling KMkDPair = "MkDPair"
spelling KMkData = "MkData"
spelling KMkFC = "MkFC"
spelling KMkFCVal = "MkFCVal"
spelling KMkIClaimData = "MkIClaimData"
spelling KMkIField = "MkIField"
spelling KMkLater = "MkLater"
spelling KMkMI = "MkMI"
spelling KMkNS = "MkNS"
spelling KMkNameInfo = "MkNameInfo"
spelling KMkPair = "MkPair"
spelling KMkRecord = "MkRecord"
spelling KMkTy = "MkTy"
spelling KMkUnit = "MkUnit"
spelling KNONE = "NONE"
spelling KNS = "NS"
spelling KName = "Name"
spelling KNat = "Nat"
spelling KNaturalToInteger = "NaturalToInteger"
spelling KNested = "Nested"
spelling KNil = "Nil"
spelling KNoHints = "NoHints"
spelling KNoInline = "NoInline"
spelling KNoNewtype = "NoNewtype"
spelling KNonLinearVar = "NonLinearVar"
spelling KNotConstructor = "NotConstructor"
spelling KNothing = "Nothing"
spelling KNum = "Num"
spelling KPATTERN = "PATTERN"
spelling KPI = "PI"
spelling KPair = "Pair"
spelling KPartialOK = "PartialOK"
spelling KPatClause = "PatClause"
spelling KPhysicalIdrSrc = "PhysicalIdrSrc"
spelling KPhysicalPkgSrc = "PhysicalPkgSrc"
spelling KPi = "Pi"
spelling KPrT = "PrT"
spelling KPrelude = "Prelude"
spelling KPrimIO = "PrimIO"
spelling KPrimVal = "PrimVal"
spelling KPrivate = "Private"
spelling KPublic = "Public"
spelling KRef = "Ref"
spelling KRefl = "Refl"
spelling KReflection = "Reflection"
spelling KS = "S"
spelling KSearchBy = "SearchBy"
spelling KSnocList = "SnocList"
spelling KSpecArgs = "SpecArgs"
spelling KSpecifiedValue = "SpecifiedValue"
spelling KStr = "Str"
spelling KStringType = "StringType"
spelling KSyntactic = "Syntactic"
spelling KTCInline = "TCInline"
spelling KTDelay = "TDelay"
spelling KTDelayed = "TDelayed"
spelling KTForce = "TForce"
spelling KTT = "TT"
spelling KTTImp = "TTImp"
spelling KTType = "TType"
spelling KTotal = "Total"
spelling KTotality = "Totality"
spelling KTrue = "True"
spelling KTyCon = "TyCon"
spelling KType = "Type"
spelling KTypes = "Types"
spelling KUN = "UN"
spelling KUnderAppliedCon = "UnderAppliedCon"
spelling KUnderscore = "Underscore"
spelling KUnique = "Unique"
spelling KUniqueDefault = "UniqueDefault"
spelling KUniqueSearch = "UniqueSearch"
spelling KUnit = "Unit"
spelling KUnknownDot = "UnknownDot"
spelling KUnsafe = "Unsafe"
spelling KUseLeft = "UseLeft"
spelling KUseRight = "UseRight"
spelling KUserDotted = "UserDotted"
spelling KVarApplied = "VarApplied"
spelling KVirtual = "Virtual"
spelling KWithBlock = "WithBlock"
spelling KWithClause = "WithClause"
spelling KWorldType = "WorldType"
spelling KWorldVal = "WorldVal"
spelling KZ = "Z"
spelling KElabScript = "[elaborator script]"
spelling KForeign = "[foreign]"
spelling K_ = "_"
spelling K_PE = "_PE"
spelling K__ = "__"
spelling K__con = "__con"
spelling K__infixTupleSection = "__infixTupleSection"
spelling K__leftTupleSection = "__leftTupleSection"
spelling K_cn = "_cn"
spelling Ka = "a"
spelling KaltTy = "altTy"
spelling Karg = "arg"
spelling KargTy = "argTy"
spelling Kassert_smaller = "assert_smaller"
spelling Kassert_total = "assert_total"
spelling Kbelieve_me = "believe_me"
spelling Kbind = "bind"
spelling KcaseTy = "caseTy"
spelling KconArg = "conArg"
spelling Kconcat = "concat"
spelling Kconstraint = "constraint"
spelling Kconv = "conv"
spelling Kcrash = "crash"
spelling KdefArg = "defArg"
spelling KdelayTy = "delayTy"
spelling Kdelayed = "delayed"
spelling KdotTm = "dotTm"
spelling KdoubleACos = "doubleACos"
spelling KdoubleASin = "doubleASin"
spelling KdoubleATan = "doubleATan"
spelling KdoubleCeiling = "doubleCeiling"
spelling KdoubleCos = "doubleCos"
spelling KdoubleExp = "doubleExp"
spelling KdoubleFloor = "doubleFloor"
spelling KdoubleLog = "doubleLog"
spelling KdoublePow = "doublePow"
spelling KdoubleSin = "doubleSin"
spelling KdoubleSqrt = "doubleSqrt"
spelling KdoubleTan = "doubleTan"
spelling Kfvar = "fvar"
spelling Kguard = "guard"
spelling Ki_con = "i_con"
spelling Kimp = "imp"
spelling KimpArg = "impArg"
spelling Kimplicit_type = "implicit_type"
spelling Kinf = "inf"
spelling Kinterpolate = "interpolate"
spelling Klamc = "lamc"
spelling Klcase = "lcase"
spelling Km = "m"
spelling Kmain = "main"
spelling Knegate = "negate"
spelling KpaRoot = "paRoot"
spelling KpairFst = "pairFst"
spelling KpairSnd = "pairSnd"
spelling Kpostpone = "postpone"
spelling Kpure = "pure"
spelling Kq = "q"
spelling Kqv = "qv"
spelling KrangeFrom = "rangeFrom"
spelling KrangeFromThen = "rangeFromThen"
spelling KrangeFromThenTo = "rangeFromThenTo"
spelling KrangeFromTo = "rangeFromTo"
spelling Krec = "rec"
spelling KretTy = "retTy"
spelling Krwarg = "rwarg"
spelling Ksa = "sa"
spelling Kscr = "scr"
spelling KscriptTy = "scriptTy"
spelling Ksearch = "search"
spelling KsearchTy = "searchTy"
spelling KstrAppend = "strAppend"
spelling KstrCons = "strCons"
spelling KstrHead = "strHead"
spelling KstrIndex = "strIndex"
spelling KstrLength = "strLength"
spelling KstrReverse = "strReverse"
spelling KstrSubstr = "strSubstr"
spelling KstrTail = "strTail"
spelling Kt = "t"
spelling Ktmp = "tmp"
spelling Ktop = "top"
spelling Ku = "u"
spelling Kwarg = "warg"
spelling Kx = "x"
spelling KHeteroEq = "~=~"
spelling Kprim__believe_me = "prim__believe_me"
spelling Kprim__crash = "prim__crash"
spelling Kidris_crash = "idris_crash"
spelling KElabAp = "Ap"
spelling KPure = "Pure"
spelling KMap = "Map"
spelling KBind = "Bind"
spelling KFail = "Fail"
spelling KWarn = "Warn"
spelling KTry = "Try"
spelling KLogMsg = "LogMsg"
spelling KLogTerm = "LogTerm"
spelling KLogSugaredTerm = "LogSugaredTerm"
spelling KResugarTerm = "ResugarTerm"
spelling KCheck = "Check"
spelling KQuote = "Quote"
spelling KLambda = "Lambda"
spelling KGoal = "Goal"
spelling KLocalVars = "LocalVars"
spelling KGenSym = "GenSym"
spelling KInCurrentNS = "InCurrentNS"
spelling KGetType = "GetType"
spelling KGetInfo = "GetInfo"
spelling KGetVis = "GetVis"
spelling KGetLocalType = "GetLocalType"
spelling KGetCons = "GetCons"
spelling KGetReferredFns = "GetReferredFns"
spelling KGetCurrentFn = "GetCurrentFn"
spelling KGetFC = "GetFC"
spelling KDeclare = "Declare"
spelling KReadFile = "ReadFile"
spelling KWriteFile = "WriteFile"
spelling KIdrisDir = "IdrisDir"
spelling KProjectDir = "ProjectDir"
spelling KSourceDir = "SourceDir"
spelling KCurrentModuleDir = "CurrentModuleDir"
spelling KSubmodulesDir = "SubmodulesDir"
spelling KBuildDir = "BuildDir"
spelling Kb = "b"
spelling Kmsg = "msg"
spelling Kprim__add_Int = "prim__add_Int"
spelling Kprim__add_Int8 = "prim__add_Int8"
spelling Kprim__add_Int16 = "prim__add_Int16"
spelling Kprim__add_Int32 = "prim__add_Int32"
spelling Kprim__add_Int64 = "prim__add_Int64"
spelling Kprim__add_Integer = "prim__add_Integer"
spelling Kprim__add_Bits8 = "prim__add_Bits8"
spelling Kprim__add_Bits16 = "prim__add_Bits16"
spelling Kprim__add_Bits32 = "prim__add_Bits32"
spelling Kprim__add_Bits64 = "prim__add_Bits64"
spelling Kprim__add_String = "prim__add_String"
spelling Kprim__add_Char = "prim__add_Char"
spelling Kprim__add_Double = "prim__add_Double"
spelling Kprim__add_PercentWorld = "prim__add_%World"
spelling Kprim__sub_Int = "prim__sub_Int"
spelling Kprim__sub_Int8 = "prim__sub_Int8"
spelling Kprim__sub_Int16 = "prim__sub_Int16"
spelling Kprim__sub_Int32 = "prim__sub_Int32"
spelling Kprim__sub_Int64 = "prim__sub_Int64"
spelling Kprim__sub_Integer = "prim__sub_Integer"
spelling Kprim__sub_Bits8 = "prim__sub_Bits8"
spelling Kprim__sub_Bits16 = "prim__sub_Bits16"
spelling Kprim__sub_Bits32 = "prim__sub_Bits32"
spelling Kprim__sub_Bits64 = "prim__sub_Bits64"
spelling Kprim__sub_String = "prim__sub_String"
spelling Kprim__sub_Char = "prim__sub_Char"
spelling Kprim__sub_Double = "prim__sub_Double"
spelling Kprim__sub_PercentWorld = "prim__sub_%World"
spelling Kprim__mul_Int = "prim__mul_Int"
spelling Kprim__mul_Int8 = "prim__mul_Int8"
spelling Kprim__mul_Int16 = "prim__mul_Int16"
spelling Kprim__mul_Int32 = "prim__mul_Int32"
spelling Kprim__mul_Int64 = "prim__mul_Int64"
spelling Kprim__mul_Integer = "prim__mul_Integer"
spelling Kprim__mul_Bits8 = "prim__mul_Bits8"
spelling Kprim__mul_Bits16 = "prim__mul_Bits16"
spelling Kprim__mul_Bits32 = "prim__mul_Bits32"
spelling Kprim__mul_Bits64 = "prim__mul_Bits64"
spelling Kprim__mul_String = "prim__mul_String"
spelling Kprim__mul_Char = "prim__mul_Char"
spelling Kprim__mul_Double = "prim__mul_Double"
spelling Kprim__mul_PercentWorld = "prim__mul_%World"
spelling Kprim__div_Int = "prim__div_Int"
spelling Kprim__div_Int8 = "prim__div_Int8"
spelling Kprim__div_Int16 = "prim__div_Int16"
spelling Kprim__div_Int32 = "prim__div_Int32"
spelling Kprim__div_Int64 = "prim__div_Int64"
spelling Kprim__div_Integer = "prim__div_Integer"
spelling Kprim__div_Bits8 = "prim__div_Bits8"
spelling Kprim__div_Bits16 = "prim__div_Bits16"
spelling Kprim__div_Bits32 = "prim__div_Bits32"
spelling Kprim__div_Bits64 = "prim__div_Bits64"
spelling Kprim__div_String = "prim__div_String"
spelling Kprim__div_Char = "prim__div_Char"
spelling Kprim__div_Double = "prim__div_Double"
spelling Kprim__div_PercentWorld = "prim__div_%World"
spelling Kprim__mod_Int = "prim__mod_Int"
spelling Kprim__mod_Int8 = "prim__mod_Int8"
spelling Kprim__mod_Int16 = "prim__mod_Int16"
spelling Kprim__mod_Int32 = "prim__mod_Int32"
spelling Kprim__mod_Int64 = "prim__mod_Int64"
spelling Kprim__mod_Integer = "prim__mod_Integer"
spelling Kprim__mod_Bits8 = "prim__mod_Bits8"
spelling Kprim__mod_Bits16 = "prim__mod_Bits16"
spelling Kprim__mod_Bits32 = "prim__mod_Bits32"
spelling Kprim__mod_Bits64 = "prim__mod_Bits64"
spelling Kprim__mod_String = "prim__mod_String"
spelling Kprim__mod_Char = "prim__mod_Char"
spelling Kprim__mod_Double = "prim__mod_Double"
spelling Kprim__mod_PercentWorld = "prim__mod_%World"
spelling Kprim__negate_Int = "prim__negate_Int"
spelling Kprim__negate_Int8 = "prim__negate_Int8"
spelling Kprim__negate_Int16 = "prim__negate_Int16"
spelling Kprim__negate_Int32 = "prim__negate_Int32"
spelling Kprim__negate_Int64 = "prim__negate_Int64"
spelling Kprim__negate_Integer = "prim__negate_Integer"
spelling Kprim__negate_Bits8 = "prim__negate_Bits8"
spelling Kprim__negate_Bits16 = "prim__negate_Bits16"
spelling Kprim__negate_Bits32 = "prim__negate_Bits32"
spelling Kprim__negate_Bits64 = "prim__negate_Bits64"
spelling Kprim__negate_String = "prim__negate_String"
spelling Kprim__negate_Char = "prim__negate_Char"
spelling Kprim__negate_Double = "prim__negate_Double"
spelling Kprim__negate_PercentWorld = "prim__negate_%World"
spelling Kprim__shl_Int = "prim__shl_Int"
spelling Kprim__shl_Int8 = "prim__shl_Int8"
spelling Kprim__shl_Int16 = "prim__shl_Int16"
spelling Kprim__shl_Int32 = "prim__shl_Int32"
spelling Kprim__shl_Int64 = "prim__shl_Int64"
spelling Kprim__shl_Integer = "prim__shl_Integer"
spelling Kprim__shl_Bits8 = "prim__shl_Bits8"
spelling Kprim__shl_Bits16 = "prim__shl_Bits16"
spelling Kprim__shl_Bits32 = "prim__shl_Bits32"
spelling Kprim__shl_Bits64 = "prim__shl_Bits64"
spelling Kprim__shl_String = "prim__shl_String"
spelling Kprim__shl_Char = "prim__shl_Char"
spelling Kprim__shl_Double = "prim__shl_Double"
spelling Kprim__shl_PercentWorld = "prim__shl_%World"
spelling Kprim__shr_Int = "prim__shr_Int"
spelling Kprim__shr_Int8 = "prim__shr_Int8"
spelling Kprim__shr_Int16 = "prim__shr_Int16"
spelling Kprim__shr_Int32 = "prim__shr_Int32"
spelling Kprim__shr_Int64 = "prim__shr_Int64"
spelling Kprim__shr_Integer = "prim__shr_Integer"
spelling Kprim__shr_Bits8 = "prim__shr_Bits8"
spelling Kprim__shr_Bits16 = "prim__shr_Bits16"
spelling Kprim__shr_Bits32 = "prim__shr_Bits32"
spelling Kprim__shr_Bits64 = "prim__shr_Bits64"
spelling Kprim__shr_String = "prim__shr_String"
spelling Kprim__shr_Char = "prim__shr_Char"
spelling Kprim__shr_Double = "prim__shr_Double"
spelling Kprim__shr_PercentWorld = "prim__shr_%World"
spelling Kprim__and_Int = "prim__and_Int"
spelling Kprim__and_Int8 = "prim__and_Int8"
spelling Kprim__and_Int16 = "prim__and_Int16"
spelling Kprim__and_Int32 = "prim__and_Int32"
spelling Kprim__and_Int64 = "prim__and_Int64"
spelling Kprim__and_Integer = "prim__and_Integer"
spelling Kprim__and_Bits8 = "prim__and_Bits8"
spelling Kprim__and_Bits16 = "prim__and_Bits16"
spelling Kprim__and_Bits32 = "prim__and_Bits32"
spelling Kprim__and_Bits64 = "prim__and_Bits64"
spelling Kprim__and_String = "prim__and_String"
spelling Kprim__and_Char = "prim__and_Char"
spelling Kprim__and_Double = "prim__and_Double"
spelling Kprim__and_PercentWorld = "prim__and_%World"
spelling Kprim__or_Int = "prim__or_Int"
spelling Kprim__or_Int8 = "prim__or_Int8"
spelling Kprim__or_Int16 = "prim__or_Int16"
spelling Kprim__or_Int32 = "prim__or_Int32"
spelling Kprim__or_Int64 = "prim__or_Int64"
spelling Kprim__or_Integer = "prim__or_Integer"
spelling Kprim__or_Bits8 = "prim__or_Bits8"
spelling Kprim__or_Bits16 = "prim__or_Bits16"
spelling Kprim__or_Bits32 = "prim__or_Bits32"
spelling Kprim__or_Bits64 = "prim__or_Bits64"
spelling Kprim__or_String = "prim__or_String"
spelling Kprim__or_Char = "prim__or_Char"
spelling Kprim__or_Double = "prim__or_Double"
spelling Kprim__or_PercentWorld = "prim__or_%World"
spelling Kprim__xor_Int = "prim__xor_Int"
spelling Kprim__xor_Int8 = "prim__xor_Int8"
spelling Kprim__xor_Int16 = "prim__xor_Int16"
spelling Kprim__xor_Int32 = "prim__xor_Int32"
spelling Kprim__xor_Int64 = "prim__xor_Int64"
spelling Kprim__xor_Integer = "prim__xor_Integer"
spelling Kprim__xor_Bits8 = "prim__xor_Bits8"
spelling Kprim__xor_Bits16 = "prim__xor_Bits16"
spelling Kprim__xor_Bits32 = "prim__xor_Bits32"
spelling Kprim__xor_Bits64 = "prim__xor_Bits64"
spelling Kprim__xor_String = "prim__xor_String"
spelling Kprim__xor_Char = "prim__xor_Char"
spelling Kprim__xor_Double = "prim__xor_Double"
spelling Kprim__xor_PercentWorld = "prim__xor_%World"
spelling Kprim__lt_Int = "prim__lt_Int"
spelling Kprim__lt_Int8 = "prim__lt_Int8"
spelling Kprim__lt_Int16 = "prim__lt_Int16"
spelling Kprim__lt_Int32 = "prim__lt_Int32"
spelling Kprim__lt_Int64 = "prim__lt_Int64"
spelling Kprim__lt_Integer = "prim__lt_Integer"
spelling Kprim__lt_Bits8 = "prim__lt_Bits8"
spelling Kprim__lt_Bits16 = "prim__lt_Bits16"
spelling Kprim__lt_Bits32 = "prim__lt_Bits32"
spelling Kprim__lt_Bits64 = "prim__lt_Bits64"
spelling Kprim__lt_String = "prim__lt_String"
spelling Kprim__lt_Char = "prim__lt_Char"
spelling Kprim__lt_Double = "prim__lt_Double"
spelling Kprim__lt_PercentWorld = "prim__lt_%World"
spelling Kprim__lte_Int = "prim__lte_Int"
spelling Kprim__lte_Int8 = "prim__lte_Int8"
spelling Kprim__lte_Int16 = "prim__lte_Int16"
spelling Kprim__lte_Int32 = "prim__lte_Int32"
spelling Kprim__lte_Int64 = "prim__lte_Int64"
spelling Kprim__lte_Integer = "prim__lte_Integer"
spelling Kprim__lte_Bits8 = "prim__lte_Bits8"
spelling Kprim__lte_Bits16 = "prim__lte_Bits16"
spelling Kprim__lte_Bits32 = "prim__lte_Bits32"
spelling Kprim__lte_Bits64 = "prim__lte_Bits64"
spelling Kprim__lte_String = "prim__lte_String"
spelling Kprim__lte_Char = "prim__lte_Char"
spelling Kprim__lte_Double = "prim__lte_Double"
spelling Kprim__lte_PercentWorld = "prim__lte_%World"
spelling Kprim__eq_Int = "prim__eq_Int"
spelling Kprim__eq_Int8 = "prim__eq_Int8"
spelling Kprim__eq_Int16 = "prim__eq_Int16"
spelling Kprim__eq_Int32 = "prim__eq_Int32"
spelling Kprim__eq_Int64 = "prim__eq_Int64"
spelling Kprim__eq_Integer = "prim__eq_Integer"
spelling Kprim__eq_Bits8 = "prim__eq_Bits8"
spelling Kprim__eq_Bits16 = "prim__eq_Bits16"
spelling Kprim__eq_Bits32 = "prim__eq_Bits32"
spelling Kprim__eq_Bits64 = "prim__eq_Bits64"
spelling Kprim__eq_String = "prim__eq_String"
spelling Kprim__eq_Char = "prim__eq_Char"
spelling Kprim__eq_Double = "prim__eq_Double"
spelling Kprim__eq_PercentWorld = "prim__eq_%World"
spelling Kprim__gte_Int = "prim__gte_Int"
spelling Kprim__gte_Int8 = "prim__gte_Int8"
spelling Kprim__gte_Int16 = "prim__gte_Int16"
spelling Kprim__gte_Int32 = "prim__gte_Int32"
spelling Kprim__gte_Int64 = "prim__gte_Int64"
spelling Kprim__gte_Integer = "prim__gte_Integer"
spelling Kprim__gte_Bits8 = "prim__gte_Bits8"
spelling Kprim__gte_Bits16 = "prim__gte_Bits16"
spelling Kprim__gte_Bits32 = "prim__gte_Bits32"
spelling Kprim__gte_Bits64 = "prim__gte_Bits64"
spelling Kprim__gte_String = "prim__gte_String"
spelling Kprim__gte_Char = "prim__gte_Char"
spelling Kprim__gte_Double = "prim__gte_Double"
spelling Kprim__gte_PercentWorld = "prim__gte_%World"
spelling Kprim__gt_Int = "prim__gt_Int"
spelling Kprim__gt_Int8 = "prim__gt_Int8"
spelling Kprim__gt_Int16 = "prim__gt_Int16"
spelling Kprim__gt_Int32 = "prim__gt_Int32"
spelling Kprim__gt_Int64 = "prim__gt_Int64"
spelling Kprim__gt_Integer = "prim__gt_Integer"
spelling Kprim__gt_Bits8 = "prim__gt_Bits8"
spelling Kprim__gt_Bits16 = "prim__gt_Bits16"
spelling Kprim__gt_Bits32 = "prim__gt_Bits32"
spelling Kprim__gt_Bits64 = "prim__gt_Bits64"
spelling Kprim__gt_String = "prim__gt_String"
spelling Kprim__gt_Char = "prim__gt_Char"
spelling Kprim__gt_Double = "prim__gt_Double"
spelling Kprim__gt_PercentWorld = "prim__gt_%World"
spelling Kprim__strLength = "prim__strLength"
spelling Kprim__strHead = "prim__strHead"
spelling Kprim__strTail = "prim__strTail"
spelling Kprim__strIndex = "prim__strIndex"
spelling Kprim__strCons = "prim__strCons"
spelling Kprim__strAppend = "prim__strAppend"
spelling Kprim__strReverse = "prim__strReverse"
spelling Kprim__strSubstr = "prim__strSubstr"
spelling Kprim__doubleExp = "prim__doubleExp"
spelling Kprim__doubleLog = "prim__doubleLog"
spelling Kprim__doublePow = "prim__doublePow"
spelling Kprim__doubleSin = "prim__doubleSin"
spelling Kprim__doubleCos = "prim__doubleCos"
spelling Kprim__doubleTan = "prim__doubleTan"
spelling Kprim__doubleASin = "prim__doubleASin"
spelling Kprim__doubleACos = "prim__doubleACos"
spelling Kprim__doubleATan = "prim__doubleATan"
spelling Kprim__doubleSqrt = "prim__doubleSqrt"
spelling Kprim__doubleFloor = "prim__doubleFloor"
spelling Kprim__doubleCeiling = "prim__doubleCeiling"
spelling Kprim__cast_IntInt = "prim__cast_IntInt"
spelling Kprim__cast_IntInt8 = "prim__cast_IntInt8"
spelling Kprim__cast_IntInt16 = "prim__cast_IntInt16"
spelling Kprim__cast_IntInt32 = "prim__cast_IntInt32"
spelling Kprim__cast_IntInt64 = "prim__cast_IntInt64"
spelling Kprim__cast_IntInteger = "prim__cast_IntInteger"
spelling Kprim__cast_IntBits8 = "prim__cast_IntBits8"
spelling Kprim__cast_IntBits16 = "prim__cast_IntBits16"
spelling Kprim__cast_IntBits32 = "prim__cast_IntBits32"
spelling Kprim__cast_IntBits64 = "prim__cast_IntBits64"
spelling Kprim__cast_IntString = "prim__cast_IntString"
spelling Kprim__cast_IntChar = "prim__cast_IntChar"
spelling Kprim__cast_IntDouble = "prim__cast_IntDouble"
spelling Kprim__cast_IntPercentWorld = "prim__cast_Int%World"
spelling Kprim__cast_Int8Int = "prim__cast_Int8Int"
spelling Kprim__cast_Int8Int8 = "prim__cast_Int8Int8"
spelling Kprim__cast_Int8Int16 = "prim__cast_Int8Int16"
spelling Kprim__cast_Int8Int32 = "prim__cast_Int8Int32"
spelling Kprim__cast_Int8Int64 = "prim__cast_Int8Int64"
spelling Kprim__cast_Int8Integer = "prim__cast_Int8Integer"
spelling Kprim__cast_Int8Bits8 = "prim__cast_Int8Bits8"
spelling Kprim__cast_Int8Bits16 = "prim__cast_Int8Bits16"
spelling Kprim__cast_Int8Bits32 = "prim__cast_Int8Bits32"
spelling Kprim__cast_Int8Bits64 = "prim__cast_Int8Bits64"
spelling Kprim__cast_Int8String = "prim__cast_Int8String"
spelling Kprim__cast_Int8Char = "prim__cast_Int8Char"
spelling Kprim__cast_Int8Double = "prim__cast_Int8Double"
spelling Kprim__cast_Int8PercentWorld = "prim__cast_Int8%World"
spelling Kprim__cast_Int16Int = "prim__cast_Int16Int"
spelling Kprim__cast_Int16Int8 = "prim__cast_Int16Int8"
spelling Kprim__cast_Int16Int16 = "prim__cast_Int16Int16"
spelling Kprim__cast_Int16Int32 = "prim__cast_Int16Int32"
spelling Kprim__cast_Int16Int64 = "prim__cast_Int16Int64"
spelling Kprim__cast_Int16Integer = "prim__cast_Int16Integer"
spelling Kprim__cast_Int16Bits8 = "prim__cast_Int16Bits8"
spelling Kprim__cast_Int16Bits16 = "prim__cast_Int16Bits16"
spelling Kprim__cast_Int16Bits32 = "prim__cast_Int16Bits32"
spelling Kprim__cast_Int16Bits64 = "prim__cast_Int16Bits64"
spelling Kprim__cast_Int16String = "prim__cast_Int16String"
spelling Kprim__cast_Int16Char = "prim__cast_Int16Char"
spelling Kprim__cast_Int16Double = "prim__cast_Int16Double"
spelling Kprim__cast_Int16PercentWorld = "prim__cast_Int16%World"
spelling Kprim__cast_Int32Int = "prim__cast_Int32Int"
spelling Kprim__cast_Int32Int8 = "prim__cast_Int32Int8"
spelling Kprim__cast_Int32Int16 = "prim__cast_Int32Int16"
spelling Kprim__cast_Int32Int32 = "prim__cast_Int32Int32"
spelling Kprim__cast_Int32Int64 = "prim__cast_Int32Int64"
spelling Kprim__cast_Int32Integer = "prim__cast_Int32Integer"
spelling Kprim__cast_Int32Bits8 = "prim__cast_Int32Bits8"
spelling Kprim__cast_Int32Bits16 = "prim__cast_Int32Bits16"
spelling Kprim__cast_Int32Bits32 = "prim__cast_Int32Bits32"
spelling Kprim__cast_Int32Bits64 = "prim__cast_Int32Bits64"
spelling Kprim__cast_Int32String = "prim__cast_Int32String"
spelling Kprim__cast_Int32Char = "prim__cast_Int32Char"
spelling Kprim__cast_Int32Double = "prim__cast_Int32Double"
spelling Kprim__cast_Int32PercentWorld = "prim__cast_Int32%World"
spelling Kprim__cast_Int64Int = "prim__cast_Int64Int"
spelling Kprim__cast_Int64Int8 = "prim__cast_Int64Int8"
spelling Kprim__cast_Int64Int16 = "prim__cast_Int64Int16"
spelling Kprim__cast_Int64Int32 = "prim__cast_Int64Int32"
spelling Kprim__cast_Int64Int64 = "prim__cast_Int64Int64"
spelling Kprim__cast_Int64Integer = "prim__cast_Int64Integer"
spelling Kprim__cast_Int64Bits8 = "prim__cast_Int64Bits8"
spelling Kprim__cast_Int64Bits16 = "prim__cast_Int64Bits16"
spelling Kprim__cast_Int64Bits32 = "prim__cast_Int64Bits32"
spelling Kprim__cast_Int64Bits64 = "prim__cast_Int64Bits64"
spelling Kprim__cast_Int64String = "prim__cast_Int64String"
spelling Kprim__cast_Int64Char = "prim__cast_Int64Char"
spelling Kprim__cast_Int64Double = "prim__cast_Int64Double"
spelling Kprim__cast_Int64PercentWorld = "prim__cast_Int64%World"
spelling Kprim__cast_IntegerInt = "prim__cast_IntegerInt"
spelling Kprim__cast_IntegerInt8 = "prim__cast_IntegerInt8"
spelling Kprim__cast_IntegerInt16 = "prim__cast_IntegerInt16"
spelling Kprim__cast_IntegerInt32 = "prim__cast_IntegerInt32"
spelling Kprim__cast_IntegerInt64 = "prim__cast_IntegerInt64"
spelling Kprim__cast_IntegerInteger = "prim__cast_IntegerInteger"
spelling Kprim__cast_IntegerBits8 = "prim__cast_IntegerBits8"
spelling Kprim__cast_IntegerBits16 = "prim__cast_IntegerBits16"
spelling Kprim__cast_IntegerBits32 = "prim__cast_IntegerBits32"
spelling Kprim__cast_IntegerBits64 = "prim__cast_IntegerBits64"
spelling Kprim__cast_IntegerString = "prim__cast_IntegerString"
spelling Kprim__cast_IntegerChar = "prim__cast_IntegerChar"
spelling Kprim__cast_IntegerDouble = "prim__cast_IntegerDouble"
spelling Kprim__cast_IntegerPercentWorld = "prim__cast_Integer%World"
spelling Kprim__cast_Bits8Int = "prim__cast_Bits8Int"
spelling Kprim__cast_Bits8Int8 = "prim__cast_Bits8Int8"
spelling Kprim__cast_Bits8Int16 = "prim__cast_Bits8Int16"
spelling Kprim__cast_Bits8Int32 = "prim__cast_Bits8Int32"
spelling Kprim__cast_Bits8Int64 = "prim__cast_Bits8Int64"
spelling Kprim__cast_Bits8Integer = "prim__cast_Bits8Integer"
spelling Kprim__cast_Bits8Bits8 = "prim__cast_Bits8Bits8"
spelling Kprim__cast_Bits8Bits16 = "prim__cast_Bits8Bits16"
spelling Kprim__cast_Bits8Bits32 = "prim__cast_Bits8Bits32"
spelling Kprim__cast_Bits8Bits64 = "prim__cast_Bits8Bits64"
spelling Kprim__cast_Bits8String = "prim__cast_Bits8String"
spelling Kprim__cast_Bits8Char = "prim__cast_Bits8Char"
spelling Kprim__cast_Bits8Double = "prim__cast_Bits8Double"
spelling Kprim__cast_Bits8PercentWorld = "prim__cast_Bits8%World"
spelling Kprim__cast_Bits16Int = "prim__cast_Bits16Int"
spelling Kprim__cast_Bits16Int8 = "prim__cast_Bits16Int8"
spelling Kprim__cast_Bits16Int16 = "prim__cast_Bits16Int16"
spelling Kprim__cast_Bits16Int32 = "prim__cast_Bits16Int32"
spelling Kprim__cast_Bits16Int64 = "prim__cast_Bits16Int64"
spelling Kprim__cast_Bits16Integer = "prim__cast_Bits16Integer"
spelling Kprim__cast_Bits16Bits8 = "prim__cast_Bits16Bits8"
spelling Kprim__cast_Bits16Bits16 = "prim__cast_Bits16Bits16"
spelling Kprim__cast_Bits16Bits32 = "prim__cast_Bits16Bits32"
spelling Kprim__cast_Bits16Bits64 = "prim__cast_Bits16Bits64"
spelling Kprim__cast_Bits16String = "prim__cast_Bits16String"
spelling Kprim__cast_Bits16Char = "prim__cast_Bits16Char"
spelling Kprim__cast_Bits16Double = "prim__cast_Bits16Double"
spelling Kprim__cast_Bits16PercentWorld = "prim__cast_Bits16%World"
spelling Kprim__cast_Bits32Int = "prim__cast_Bits32Int"
spelling Kprim__cast_Bits32Int8 = "prim__cast_Bits32Int8"
spelling Kprim__cast_Bits32Int16 = "prim__cast_Bits32Int16"
spelling Kprim__cast_Bits32Int32 = "prim__cast_Bits32Int32"
spelling Kprim__cast_Bits32Int64 = "prim__cast_Bits32Int64"
spelling Kprim__cast_Bits32Integer = "prim__cast_Bits32Integer"
spelling Kprim__cast_Bits32Bits8 = "prim__cast_Bits32Bits8"
spelling Kprim__cast_Bits32Bits16 = "prim__cast_Bits32Bits16"
spelling Kprim__cast_Bits32Bits32 = "prim__cast_Bits32Bits32"
spelling Kprim__cast_Bits32Bits64 = "prim__cast_Bits32Bits64"
spelling Kprim__cast_Bits32String = "prim__cast_Bits32String"
spelling Kprim__cast_Bits32Char = "prim__cast_Bits32Char"
spelling Kprim__cast_Bits32Double = "prim__cast_Bits32Double"
spelling Kprim__cast_Bits32PercentWorld = "prim__cast_Bits32%World"
spelling Kprim__cast_Bits64Int = "prim__cast_Bits64Int"
spelling Kprim__cast_Bits64Int8 = "prim__cast_Bits64Int8"
spelling Kprim__cast_Bits64Int16 = "prim__cast_Bits64Int16"
spelling Kprim__cast_Bits64Int32 = "prim__cast_Bits64Int32"
spelling Kprim__cast_Bits64Int64 = "prim__cast_Bits64Int64"
spelling Kprim__cast_Bits64Integer = "prim__cast_Bits64Integer"
spelling Kprim__cast_Bits64Bits8 = "prim__cast_Bits64Bits8"
spelling Kprim__cast_Bits64Bits16 = "prim__cast_Bits64Bits16"
spelling Kprim__cast_Bits64Bits32 = "prim__cast_Bits64Bits32"
spelling Kprim__cast_Bits64Bits64 = "prim__cast_Bits64Bits64"
spelling Kprim__cast_Bits64String = "prim__cast_Bits64String"
spelling Kprim__cast_Bits64Char = "prim__cast_Bits64Char"
spelling Kprim__cast_Bits64Double = "prim__cast_Bits64Double"
spelling Kprim__cast_Bits64PercentWorld = "prim__cast_Bits64%World"
spelling Kprim__cast_StringInt = "prim__cast_StringInt"
spelling Kprim__cast_StringInt8 = "prim__cast_StringInt8"
spelling Kprim__cast_StringInt16 = "prim__cast_StringInt16"
spelling Kprim__cast_StringInt32 = "prim__cast_StringInt32"
spelling Kprim__cast_StringInt64 = "prim__cast_StringInt64"
spelling Kprim__cast_StringInteger = "prim__cast_StringInteger"
spelling Kprim__cast_StringBits8 = "prim__cast_StringBits8"
spelling Kprim__cast_StringBits16 = "prim__cast_StringBits16"
spelling Kprim__cast_StringBits32 = "prim__cast_StringBits32"
spelling Kprim__cast_StringBits64 = "prim__cast_StringBits64"
spelling Kprim__cast_StringString = "prim__cast_StringString"
spelling Kprim__cast_StringChar = "prim__cast_StringChar"
spelling Kprim__cast_StringDouble = "prim__cast_StringDouble"
spelling Kprim__cast_StringPercentWorld = "prim__cast_String%World"
spelling Kprim__cast_CharInt = "prim__cast_CharInt"
spelling Kprim__cast_CharInt8 = "prim__cast_CharInt8"
spelling Kprim__cast_CharInt16 = "prim__cast_CharInt16"
spelling Kprim__cast_CharInt32 = "prim__cast_CharInt32"
spelling Kprim__cast_CharInt64 = "prim__cast_CharInt64"
spelling Kprim__cast_CharInteger = "prim__cast_CharInteger"
spelling Kprim__cast_CharBits8 = "prim__cast_CharBits8"
spelling Kprim__cast_CharBits16 = "prim__cast_CharBits16"
spelling Kprim__cast_CharBits32 = "prim__cast_CharBits32"
spelling Kprim__cast_CharBits64 = "prim__cast_CharBits64"
spelling Kprim__cast_CharString = "prim__cast_CharString"
spelling Kprim__cast_CharChar = "prim__cast_CharChar"
spelling Kprim__cast_CharDouble = "prim__cast_CharDouble"
spelling Kprim__cast_CharPercentWorld = "prim__cast_Char%World"
spelling Kprim__cast_DoubleInt = "prim__cast_DoubleInt"
spelling Kprim__cast_DoubleInt8 = "prim__cast_DoubleInt8"
spelling Kprim__cast_DoubleInt16 = "prim__cast_DoubleInt16"
spelling Kprim__cast_DoubleInt32 = "prim__cast_DoubleInt32"
spelling Kprim__cast_DoubleInt64 = "prim__cast_DoubleInt64"
spelling Kprim__cast_DoubleInteger = "prim__cast_DoubleInteger"
spelling Kprim__cast_DoubleBits8 = "prim__cast_DoubleBits8"
spelling Kprim__cast_DoubleBits16 = "prim__cast_DoubleBits16"
spelling Kprim__cast_DoubleBits32 = "prim__cast_DoubleBits32"
spelling Kprim__cast_DoubleBits64 = "prim__cast_DoubleBits64"
spelling Kprim__cast_DoubleString = "prim__cast_DoubleString"
spelling Kprim__cast_DoubleChar = "prim__cast_DoubleChar"
spelling Kprim__cast_DoubleDouble = "prim__cast_DoubleDouble"
spelling Kprim__cast_DoublePercentWorld = "prim__cast_Double%World"
spelling Kprim__cast_PercentWorldInt = "prim__cast_%WorldInt"
spelling Kprim__cast_PercentWorldInt8 = "prim__cast_%WorldInt8"
spelling Kprim__cast_PercentWorldInt16 = "prim__cast_%WorldInt16"
spelling Kprim__cast_PercentWorldInt32 = "prim__cast_%WorldInt32"
spelling Kprim__cast_PercentWorldInt64 = "prim__cast_%WorldInt64"
spelling Kprim__cast_PercentWorldInteger = "prim__cast_%WorldInteger"
spelling Kprim__cast_PercentWorldBits8 = "prim__cast_%WorldBits8"
spelling Kprim__cast_PercentWorldBits16 = "prim__cast_%WorldBits16"
spelling Kprim__cast_PercentWorldBits32 = "prim__cast_%WorldBits32"
spelling Kprim__cast_PercentWorldBits64 = "prim__cast_%WorldBits64"
spelling Kprim__cast_PercentWorldString = "prim__cast_%WorldString"
spelling Kprim__cast_PercentWorldChar = "prim__cast_%WorldChar"
spelling Kprim__cast_PercentWorldDouble = "prim__cast_%WorldDouble"
spelling Kprim__cast_PercentWorldPercentWorld = "prim__cast_%World%World"
spelling KInt = "Int"
spelling KInt8 = "Int8"
spelling KInt16 = "Int16"
spelling KInt32 = "Int32"
spelling KInt64 = "Int64"
spelling KInteger = "Integer"
spelling KBits8 = "Bits8"
spelling KBits16 = "Bits16"
spelling KBits32 = "Bits32"
spelling KBits64 = "Bits64"
spelling KString = "String"
spelling KChar = "Char"
spelling KDouble = "Double"
spelling Ke = "e"
spelling Kcov = "cov"
spelling KPercentWorld = "%World"
spelling KfromInteger = "fromInteger"
spelling KfromDouble = "fromDouble"
spelling KProbeBinder = "idris-mlir-binder"
spelling KProbeHole = "idris-mlir-hole"
spelling KProbeHoleFound = "idris-mlir-hole-found"
spelling KProbeUnknown = "idris-mlir-unknown"
spelling KProbeRuntime = "idris-mlir-runtime"
spelling KProbeRuntimeAt = "idris-mlir-runtime-at"
spelling KProbeField = "idris-mlir-field"
spelling KProbePattern = "idris-mlir-pattern"
spelling KProbeForm = "idris-mlir-form"
spelling KProbeAxis = "idris-mlir-axis"
spelling KProbeAxisAt = "idris-mlir-axis-at"
spelling KProbeSize = "idris-mlir-size"
spelling KProbeVar = "idris-mlir-var"
spelling KProbeFormal = "idris-mlir-formal"
spelling KProbeHeld = "idris-mlir-held"

||| The identifier's id in every session's table.
public export
ordinal : Known -> Int
ordinal KDollar = 0
ordinal KMinus = 1
ordinal KArrow = 2
ordinal KCons = 3
ordinal KCons1 = 4
ordinal KSnoc = 5
ordinal KAp = 6
ordinal KAutoMark = 7
ordinal KEquals = 8
ordinal KHomoEq = 9
ordinal KSeq = 10
ordinal KBindOp = 11
ordinal KApp = 12
ordinal KAutoImplicit = 13
ordinal KB16 = 14
ordinal KB32 = 15
ordinal KB64 = 16
ordinal KB8 = 17
ordinal KBI = 18
ordinal KBasic = 19
ordinal KBasics = 20
ordinal KBits16Type = 21
ordinal KBits32Type = 22
ordinal KBits64Type = 23
ordinal KBits8Type = 24
ordinal KBool = 25
ordinal KBound = 26
ordinal KBuiltin = 27
ordinal KBuiltinNatural = 28
ordinal KCOVERAGE = 29
ordinal KCaseBlock = 30
ordinal KCh = 31
ordinal KCharType = 32
ordinal KCoveringOnly = 33
ordinal KDN = 34
ordinal KDPair = 35
ordinal KData = 36
ordinal KDataCon = 37
ordinal KDb = 38
ordinal KDecl = 39
ordinal KDefImplicit = 40
ordinal KDefaultedValue = 41
ordinal KDeprecate = 42
ordinal KDoubleType = 43
ordinal KElab = 44
ordinal KEmptyFC = 45
ordinal KEqOrd = 46
ordinal KEqual = 47
ordinal KErased = 48
ordinal KErasedArg = 49
ordinal KExplicitArg = 50
ordinal KExport = 51
ordinal KExternFn = 52
ordinal KExternal = 53
ordinal KFalse = 54
ordinal KField = 55
ordinal KFirst = 56
ordinal KFirstSuccess = 57
ordinal KForeignExport = 58
ordinal KForeignFn = 59
ordinal KFunc = 60
ordinal KGlobalHint = 61
ordinal KHint = 62
ordinal KI = 63
ordinal KI16 = 64
ordinal KI32 = 65
ordinal KI64 = 66
ordinal KI8 = 67
ordinal KIAlternative = 68
ordinal KIApp = 69
ordinal KIAs = 70
ordinal KIAutoApp = 71
ordinal KIBindHere = 72
ordinal KIBindVar = 73
ordinal KICase = 74
ordinal KIClaim = 75
ordinal KIData = 76
ordinal KIDef = 77
ordinal KIDelay = 78
ordinal KIDelayed = 79
ordinal KIFail = 80
ordinal KIForce = 81
ordinal KIHole = 82
ordinal KILam = 83
ordinal KILet = 84
ordinal KILocal = 85
ordinal KILog = 86
ordinal KIMustUnify = 87
ordinal KINamedApp = 88
ordinal KINamespace = 89
ordinal KIO = 90
ordinal KIParameters = 91
ordinal KIPi = 92
ordinal KIPrimVal = 93
ordinal KIQuote = 94
ordinal KIQuoteDecl = 95
ordinal KIQuoteName = 96
ordinal KIRecord = 97
ordinal KIRewrite = 98
ordinal KISearch = 99
ordinal KISetField = 100
ordinal KISetFieldApp = 101
ordinal KITransform = 102
ordinal KIType = 103
ordinal KIUnquote = 104
ordinal KIUpdate = 105
ordinal KIVar = 106
ordinal KIWithApp = 107
ordinal KIWithUnambigNames = 108
ordinal KImplicit = 109
ordinal KImplicitArg = 110
ordinal KImpossibleClause = 111
ordinal KInline = 112
ordinal KInt16Type = 113
ordinal KInt32Type = 114
ordinal KInt64Type = 115
ordinal KInt8Type = 116
ordinal KIntType = 117
ordinal KIntegerToNatural = 118
ordinal KIntegerType = 119
ordinal KInteractive = 120
ordinal KInvertible = 121
ordinal KJust = 122
ordinal KLInf = 123
ordinal KLLazy = 124
ordinal KLUnknown = 125
ordinal KLam = 126
ordinal KLanguage = 127
ordinal KLater = 128
ordinal KLin = 129
ordinal KList = 130
ordinal KList1 = 131
ordinal KLocal = 132
ordinal KM0 = 133
ordinal KM1 = 134
ordinal KMN = 135
ordinal KMW = 136
ordinal KMacro = 137
ordinal KMain = 138
ordinal KMaybe = 139
ordinal KMkDPair = 140
ordinal KMkData = 141
ordinal KMkFC = 142
ordinal KMkFCVal = 143
ordinal KMkIClaimData = 144
ordinal KMkIField = 145
ordinal KMkLater = 146
ordinal KMkMI = 147
ordinal KMkNS = 148
ordinal KMkNameInfo = 149
ordinal KMkPair = 150
ordinal KMkRecord = 151
ordinal KMkTy = 152
ordinal KMkUnit = 153
ordinal KNONE = 154
ordinal KNS = 155
ordinal KName = 156
ordinal KNat = 157
ordinal KNaturalToInteger = 158
ordinal KNested = 159
ordinal KNil = 160
ordinal KNoHints = 161
ordinal KNoInline = 162
ordinal KNoNewtype = 163
ordinal KNonLinearVar = 164
ordinal KNotConstructor = 165
ordinal KNothing = 166
ordinal KNum = 167
ordinal KPATTERN = 168
ordinal KPI = 169
ordinal KPair = 170
ordinal KPartialOK = 171
ordinal KPatClause = 172
ordinal KPhysicalIdrSrc = 173
ordinal KPhysicalPkgSrc = 174
ordinal KPi = 175
ordinal KPrT = 176
ordinal KPrelude = 177
ordinal KPrimIO = 178
ordinal KPrimVal = 179
ordinal KPrivate = 180
ordinal KPublic = 181
ordinal KRef = 182
ordinal KRefl = 183
ordinal KReflection = 184
ordinal KS = 185
ordinal KSearchBy = 186
ordinal KSnocList = 187
ordinal KSpecArgs = 188
ordinal KSpecifiedValue = 189
ordinal KStr = 190
ordinal KStringType = 191
ordinal KSyntactic = 192
ordinal KTCInline = 193
ordinal KTDelay = 194
ordinal KTDelayed = 195
ordinal KTForce = 196
ordinal KTT = 197
ordinal KTTImp = 198
ordinal KTType = 199
ordinal KTotal = 200
ordinal KTotality = 201
ordinal KTrue = 202
ordinal KTyCon = 203
ordinal KType = 204
ordinal KTypes = 205
ordinal KUN = 206
ordinal KUnderAppliedCon = 207
ordinal KUnderscore = 208
ordinal KUnique = 209
ordinal KUniqueDefault = 210
ordinal KUniqueSearch = 211
ordinal KUnit = 212
ordinal KUnknownDot = 213
ordinal KUnsafe = 214
ordinal KUseLeft = 215
ordinal KUseRight = 216
ordinal KUserDotted = 217
ordinal KVarApplied = 218
ordinal KVirtual = 219
ordinal KWithBlock = 220
ordinal KWithClause = 221
ordinal KWorldType = 222
ordinal KWorldVal = 223
ordinal KZ = 224
ordinal KElabScript = 225
ordinal KForeign = 226
ordinal K_ = 227
ordinal K_PE = 228
ordinal K__ = 229
ordinal K__con = 230
ordinal K__infixTupleSection = 231
ordinal K__leftTupleSection = 232
ordinal K_cn = 233
ordinal Ka = 234
ordinal KaltTy = 235
ordinal Karg = 236
ordinal KargTy = 237
ordinal Kassert_smaller = 238
ordinal Kassert_total = 239
ordinal Kbelieve_me = 240
ordinal Kbind = 241
ordinal KcaseTy = 242
ordinal KconArg = 243
ordinal Kconcat = 244
ordinal Kconstraint = 245
ordinal Kconv = 246
ordinal Kcrash = 247
ordinal KdefArg = 248
ordinal KdelayTy = 249
ordinal Kdelayed = 250
ordinal KdotTm = 251
ordinal KdoubleACos = 252
ordinal KdoubleASin = 253
ordinal KdoubleATan = 254
ordinal KdoubleCeiling = 255
ordinal KdoubleCos = 256
ordinal KdoubleExp = 257
ordinal KdoubleFloor = 258
ordinal KdoubleLog = 259
ordinal KdoublePow = 260
ordinal KdoubleSin = 261
ordinal KdoubleSqrt = 262
ordinal KdoubleTan = 263
ordinal Kfvar = 264
ordinal Kguard = 265
ordinal Ki_con = 266
ordinal Kimp = 267
ordinal KimpArg = 268
ordinal Kimplicit_type = 269
ordinal Kinf = 270
ordinal Kinterpolate = 271
ordinal Klamc = 272
ordinal Klcase = 273
ordinal Km = 274
ordinal Kmain = 275
ordinal Knegate = 276
ordinal KpaRoot = 277
ordinal KpairFst = 278
ordinal KpairSnd = 279
ordinal Kpostpone = 280
ordinal Kpure = 281
ordinal Kq = 282
ordinal Kqv = 283
ordinal KrangeFrom = 284
ordinal KrangeFromThen = 285
ordinal KrangeFromThenTo = 286
ordinal KrangeFromTo = 287
ordinal Krec = 288
ordinal KretTy = 289
ordinal Krwarg = 290
ordinal Ksa = 291
ordinal Kscr = 292
ordinal KscriptTy = 293
ordinal Ksearch = 294
ordinal KsearchTy = 295
ordinal KstrAppend = 296
ordinal KstrCons = 297
ordinal KstrHead = 298
ordinal KstrIndex = 299
ordinal KstrLength = 300
ordinal KstrReverse = 301
ordinal KstrSubstr = 302
ordinal KstrTail = 303
ordinal Kt = 304
ordinal Ktmp = 305
ordinal Ktop = 306
ordinal Ku = 307
ordinal Kwarg = 308
ordinal Kx = 309
ordinal KHeteroEq = 310
ordinal Kprim__believe_me = 311
ordinal Kprim__crash = 312
ordinal Kidris_crash = 313
ordinal KElabAp = 314
ordinal KPure = 315
ordinal KMap = 316
ordinal KBind = 317
ordinal KFail = 318
ordinal KWarn = 319
ordinal KTry = 320
ordinal KLogMsg = 321
ordinal KLogTerm = 322
ordinal KLogSugaredTerm = 323
ordinal KResugarTerm = 324
ordinal KCheck = 325
ordinal KQuote = 326
ordinal KLambda = 327
ordinal KGoal = 328
ordinal KLocalVars = 329
ordinal KGenSym = 330
ordinal KInCurrentNS = 331
ordinal KGetType = 332
ordinal KGetInfo = 333
ordinal KGetVis = 334
ordinal KGetLocalType = 335
ordinal KGetCons = 336
ordinal KGetReferredFns = 337
ordinal KGetCurrentFn = 338
ordinal KGetFC = 339
ordinal KDeclare = 340
ordinal KReadFile = 341
ordinal KWriteFile = 342
ordinal KIdrisDir = 343
ordinal KProjectDir = 344
ordinal KSourceDir = 345
ordinal KCurrentModuleDir = 346
ordinal KSubmodulesDir = 347
ordinal KBuildDir = 348
ordinal Kb = 349
ordinal Kmsg = 350
ordinal Kprim__add_Int = 351
ordinal Kprim__add_Int8 = 352
ordinal Kprim__add_Int16 = 353
ordinal Kprim__add_Int32 = 354
ordinal Kprim__add_Int64 = 355
ordinal Kprim__add_Integer = 356
ordinal Kprim__add_Bits8 = 357
ordinal Kprim__add_Bits16 = 358
ordinal Kprim__add_Bits32 = 359
ordinal Kprim__add_Bits64 = 360
ordinal Kprim__add_String = 361
ordinal Kprim__add_Char = 362
ordinal Kprim__add_Double = 363
ordinal Kprim__add_PercentWorld = 364
ordinal Kprim__sub_Int = 365
ordinal Kprim__sub_Int8 = 366
ordinal Kprim__sub_Int16 = 367
ordinal Kprim__sub_Int32 = 368
ordinal Kprim__sub_Int64 = 369
ordinal Kprim__sub_Integer = 370
ordinal Kprim__sub_Bits8 = 371
ordinal Kprim__sub_Bits16 = 372
ordinal Kprim__sub_Bits32 = 373
ordinal Kprim__sub_Bits64 = 374
ordinal Kprim__sub_String = 375
ordinal Kprim__sub_Char = 376
ordinal Kprim__sub_Double = 377
ordinal Kprim__sub_PercentWorld = 378
ordinal Kprim__mul_Int = 379
ordinal Kprim__mul_Int8 = 380
ordinal Kprim__mul_Int16 = 381
ordinal Kprim__mul_Int32 = 382
ordinal Kprim__mul_Int64 = 383
ordinal Kprim__mul_Integer = 384
ordinal Kprim__mul_Bits8 = 385
ordinal Kprim__mul_Bits16 = 386
ordinal Kprim__mul_Bits32 = 387
ordinal Kprim__mul_Bits64 = 388
ordinal Kprim__mul_String = 389
ordinal Kprim__mul_Char = 390
ordinal Kprim__mul_Double = 391
ordinal Kprim__mul_PercentWorld = 392
ordinal Kprim__div_Int = 393
ordinal Kprim__div_Int8 = 394
ordinal Kprim__div_Int16 = 395
ordinal Kprim__div_Int32 = 396
ordinal Kprim__div_Int64 = 397
ordinal Kprim__div_Integer = 398
ordinal Kprim__div_Bits8 = 399
ordinal Kprim__div_Bits16 = 400
ordinal Kprim__div_Bits32 = 401
ordinal Kprim__div_Bits64 = 402
ordinal Kprim__div_String = 403
ordinal Kprim__div_Char = 404
ordinal Kprim__div_Double = 405
ordinal Kprim__div_PercentWorld = 406
ordinal Kprim__mod_Int = 407
ordinal Kprim__mod_Int8 = 408
ordinal Kprim__mod_Int16 = 409
ordinal Kprim__mod_Int32 = 410
ordinal Kprim__mod_Int64 = 411
ordinal Kprim__mod_Integer = 412
ordinal Kprim__mod_Bits8 = 413
ordinal Kprim__mod_Bits16 = 414
ordinal Kprim__mod_Bits32 = 415
ordinal Kprim__mod_Bits64 = 416
ordinal Kprim__mod_String = 417
ordinal Kprim__mod_Char = 418
ordinal Kprim__mod_Double = 419
ordinal Kprim__mod_PercentWorld = 420
ordinal Kprim__negate_Int = 421
ordinal Kprim__negate_Int8 = 422
ordinal Kprim__negate_Int16 = 423
ordinal Kprim__negate_Int32 = 424
ordinal Kprim__negate_Int64 = 425
ordinal Kprim__negate_Integer = 426
ordinal Kprim__negate_Bits8 = 427
ordinal Kprim__negate_Bits16 = 428
ordinal Kprim__negate_Bits32 = 429
ordinal Kprim__negate_Bits64 = 430
ordinal Kprim__negate_String = 431
ordinal Kprim__negate_Char = 432
ordinal Kprim__negate_Double = 433
ordinal Kprim__negate_PercentWorld = 434
ordinal Kprim__shl_Int = 435
ordinal Kprim__shl_Int8 = 436
ordinal Kprim__shl_Int16 = 437
ordinal Kprim__shl_Int32 = 438
ordinal Kprim__shl_Int64 = 439
ordinal Kprim__shl_Integer = 440
ordinal Kprim__shl_Bits8 = 441
ordinal Kprim__shl_Bits16 = 442
ordinal Kprim__shl_Bits32 = 443
ordinal Kprim__shl_Bits64 = 444
ordinal Kprim__shl_String = 445
ordinal Kprim__shl_Char = 446
ordinal Kprim__shl_Double = 447
ordinal Kprim__shl_PercentWorld = 448
ordinal Kprim__shr_Int = 449
ordinal Kprim__shr_Int8 = 450
ordinal Kprim__shr_Int16 = 451
ordinal Kprim__shr_Int32 = 452
ordinal Kprim__shr_Int64 = 453
ordinal Kprim__shr_Integer = 454
ordinal Kprim__shr_Bits8 = 455
ordinal Kprim__shr_Bits16 = 456
ordinal Kprim__shr_Bits32 = 457
ordinal Kprim__shr_Bits64 = 458
ordinal Kprim__shr_String = 459
ordinal Kprim__shr_Char = 460
ordinal Kprim__shr_Double = 461
ordinal Kprim__shr_PercentWorld = 462
ordinal Kprim__and_Int = 463
ordinal Kprim__and_Int8 = 464
ordinal Kprim__and_Int16 = 465
ordinal Kprim__and_Int32 = 466
ordinal Kprim__and_Int64 = 467
ordinal Kprim__and_Integer = 468
ordinal Kprim__and_Bits8 = 469
ordinal Kprim__and_Bits16 = 470
ordinal Kprim__and_Bits32 = 471
ordinal Kprim__and_Bits64 = 472
ordinal Kprim__and_String = 473
ordinal Kprim__and_Char = 474
ordinal Kprim__and_Double = 475
ordinal Kprim__and_PercentWorld = 476
ordinal Kprim__or_Int = 477
ordinal Kprim__or_Int8 = 478
ordinal Kprim__or_Int16 = 479
ordinal Kprim__or_Int32 = 480
ordinal Kprim__or_Int64 = 481
ordinal Kprim__or_Integer = 482
ordinal Kprim__or_Bits8 = 483
ordinal Kprim__or_Bits16 = 484
ordinal Kprim__or_Bits32 = 485
ordinal Kprim__or_Bits64 = 486
ordinal Kprim__or_String = 487
ordinal Kprim__or_Char = 488
ordinal Kprim__or_Double = 489
ordinal Kprim__or_PercentWorld = 490
ordinal Kprim__xor_Int = 491
ordinal Kprim__xor_Int8 = 492
ordinal Kprim__xor_Int16 = 493
ordinal Kprim__xor_Int32 = 494
ordinal Kprim__xor_Int64 = 495
ordinal Kprim__xor_Integer = 496
ordinal Kprim__xor_Bits8 = 497
ordinal Kprim__xor_Bits16 = 498
ordinal Kprim__xor_Bits32 = 499
ordinal Kprim__xor_Bits64 = 500
ordinal Kprim__xor_String = 501
ordinal Kprim__xor_Char = 502
ordinal Kprim__xor_Double = 503
ordinal Kprim__xor_PercentWorld = 504
ordinal Kprim__lt_Int = 505
ordinal Kprim__lt_Int8 = 506
ordinal Kprim__lt_Int16 = 507
ordinal Kprim__lt_Int32 = 508
ordinal Kprim__lt_Int64 = 509
ordinal Kprim__lt_Integer = 510
ordinal Kprim__lt_Bits8 = 511
ordinal Kprim__lt_Bits16 = 512
ordinal Kprim__lt_Bits32 = 513
ordinal Kprim__lt_Bits64 = 514
ordinal Kprim__lt_String = 515
ordinal Kprim__lt_Char = 516
ordinal Kprim__lt_Double = 517
ordinal Kprim__lt_PercentWorld = 518
ordinal Kprim__lte_Int = 519
ordinal Kprim__lte_Int8 = 520
ordinal Kprim__lte_Int16 = 521
ordinal Kprim__lte_Int32 = 522
ordinal Kprim__lte_Int64 = 523
ordinal Kprim__lte_Integer = 524
ordinal Kprim__lte_Bits8 = 525
ordinal Kprim__lte_Bits16 = 526
ordinal Kprim__lte_Bits32 = 527
ordinal Kprim__lte_Bits64 = 528
ordinal Kprim__lte_String = 529
ordinal Kprim__lte_Char = 530
ordinal Kprim__lte_Double = 531
ordinal Kprim__lte_PercentWorld = 532
ordinal Kprim__eq_Int = 533
ordinal Kprim__eq_Int8 = 534
ordinal Kprim__eq_Int16 = 535
ordinal Kprim__eq_Int32 = 536
ordinal Kprim__eq_Int64 = 537
ordinal Kprim__eq_Integer = 538
ordinal Kprim__eq_Bits8 = 539
ordinal Kprim__eq_Bits16 = 540
ordinal Kprim__eq_Bits32 = 541
ordinal Kprim__eq_Bits64 = 542
ordinal Kprim__eq_String = 543
ordinal Kprim__eq_Char = 544
ordinal Kprim__eq_Double = 545
ordinal Kprim__eq_PercentWorld = 546
ordinal Kprim__gte_Int = 547
ordinal Kprim__gte_Int8 = 548
ordinal Kprim__gte_Int16 = 549
ordinal Kprim__gte_Int32 = 550
ordinal Kprim__gte_Int64 = 551
ordinal Kprim__gte_Integer = 552
ordinal Kprim__gte_Bits8 = 553
ordinal Kprim__gte_Bits16 = 554
ordinal Kprim__gte_Bits32 = 555
ordinal Kprim__gte_Bits64 = 556
ordinal Kprim__gte_String = 557
ordinal Kprim__gte_Char = 558
ordinal Kprim__gte_Double = 559
ordinal Kprim__gte_PercentWorld = 560
ordinal Kprim__gt_Int = 561
ordinal Kprim__gt_Int8 = 562
ordinal Kprim__gt_Int16 = 563
ordinal Kprim__gt_Int32 = 564
ordinal Kprim__gt_Int64 = 565
ordinal Kprim__gt_Integer = 566
ordinal Kprim__gt_Bits8 = 567
ordinal Kprim__gt_Bits16 = 568
ordinal Kprim__gt_Bits32 = 569
ordinal Kprim__gt_Bits64 = 570
ordinal Kprim__gt_String = 571
ordinal Kprim__gt_Char = 572
ordinal Kprim__gt_Double = 573
ordinal Kprim__gt_PercentWorld = 574
ordinal Kprim__strLength = 575
ordinal Kprim__strHead = 576
ordinal Kprim__strTail = 577
ordinal Kprim__strIndex = 578
ordinal Kprim__strCons = 579
ordinal Kprim__strAppend = 580
ordinal Kprim__strReverse = 581
ordinal Kprim__strSubstr = 582
ordinal Kprim__doubleExp = 583
ordinal Kprim__doubleLog = 584
ordinal Kprim__doublePow = 585
ordinal Kprim__doubleSin = 586
ordinal Kprim__doubleCos = 587
ordinal Kprim__doubleTan = 588
ordinal Kprim__doubleASin = 589
ordinal Kprim__doubleACos = 590
ordinal Kprim__doubleATan = 591
ordinal Kprim__doubleSqrt = 592
ordinal Kprim__doubleFloor = 593
ordinal Kprim__doubleCeiling = 594
ordinal Kprim__cast_IntInt = 595
ordinal Kprim__cast_IntInt8 = 596
ordinal Kprim__cast_IntInt16 = 597
ordinal Kprim__cast_IntInt32 = 598
ordinal Kprim__cast_IntInt64 = 599
ordinal Kprim__cast_IntInteger = 600
ordinal Kprim__cast_IntBits8 = 601
ordinal Kprim__cast_IntBits16 = 602
ordinal Kprim__cast_IntBits32 = 603
ordinal Kprim__cast_IntBits64 = 604
ordinal Kprim__cast_IntString = 605
ordinal Kprim__cast_IntChar = 606
ordinal Kprim__cast_IntDouble = 607
ordinal Kprim__cast_IntPercentWorld = 608
ordinal Kprim__cast_Int8Int = 609
ordinal Kprim__cast_Int8Int8 = 610
ordinal Kprim__cast_Int8Int16 = 611
ordinal Kprim__cast_Int8Int32 = 612
ordinal Kprim__cast_Int8Int64 = 613
ordinal Kprim__cast_Int8Integer = 614
ordinal Kprim__cast_Int8Bits8 = 615
ordinal Kprim__cast_Int8Bits16 = 616
ordinal Kprim__cast_Int8Bits32 = 617
ordinal Kprim__cast_Int8Bits64 = 618
ordinal Kprim__cast_Int8String = 619
ordinal Kprim__cast_Int8Char = 620
ordinal Kprim__cast_Int8Double = 621
ordinal Kprim__cast_Int8PercentWorld = 622
ordinal Kprim__cast_Int16Int = 623
ordinal Kprim__cast_Int16Int8 = 624
ordinal Kprim__cast_Int16Int16 = 625
ordinal Kprim__cast_Int16Int32 = 626
ordinal Kprim__cast_Int16Int64 = 627
ordinal Kprim__cast_Int16Integer = 628
ordinal Kprim__cast_Int16Bits8 = 629
ordinal Kprim__cast_Int16Bits16 = 630
ordinal Kprim__cast_Int16Bits32 = 631
ordinal Kprim__cast_Int16Bits64 = 632
ordinal Kprim__cast_Int16String = 633
ordinal Kprim__cast_Int16Char = 634
ordinal Kprim__cast_Int16Double = 635
ordinal Kprim__cast_Int16PercentWorld = 636
ordinal Kprim__cast_Int32Int = 637
ordinal Kprim__cast_Int32Int8 = 638
ordinal Kprim__cast_Int32Int16 = 639
ordinal Kprim__cast_Int32Int32 = 640
ordinal Kprim__cast_Int32Int64 = 641
ordinal Kprim__cast_Int32Integer = 642
ordinal Kprim__cast_Int32Bits8 = 643
ordinal Kprim__cast_Int32Bits16 = 644
ordinal Kprim__cast_Int32Bits32 = 645
ordinal Kprim__cast_Int32Bits64 = 646
ordinal Kprim__cast_Int32String = 647
ordinal Kprim__cast_Int32Char = 648
ordinal Kprim__cast_Int32Double = 649
ordinal Kprim__cast_Int32PercentWorld = 650
ordinal Kprim__cast_Int64Int = 651
ordinal Kprim__cast_Int64Int8 = 652
ordinal Kprim__cast_Int64Int16 = 653
ordinal Kprim__cast_Int64Int32 = 654
ordinal Kprim__cast_Int64Int64 = 655
ordinal Kprim__cast_Int64Integer = 656
ordinal Kprim__cast_Int64Bits8 = 657
ordinal Kprim__cast_Int64Bits16 = 658
ordinal Kprim__cast_Int64Bits32 = 659
ordinal Kprim__cast_Int64Bits64 = 660
ordinal Kprim__cast_Int64String = 661
ordinal Kprim__cast_Int64Char = 662
ordinal Kprim__cast_Int64Double = 663
ordinal Kprim__cast_Int64PercentWorld = 664
ordinal Kprim__cast_IntegerInt = 665
ordinal Kprim__cast_IntegerInt8 = 666
ordinal Kprim__cast_IntegerInt16 = 667
ordinal Kprim__cast_IntegerInt32 = 668
ordinal Kprim__cast_IntegerInt64 = 669
ordinal Kprim__cast_IntegerInteger = 670
ordinal Kprim__cast_IntegerBits8 = 671
ordinal Kprim__cast_IntegerBits16 = 672
ordinal Kprim__cast_IntegerBits32 = 673
ordinal Kprim__cast_IntegerBits64 = 674
ordinal Kprim__cast_IntegerString = 675
ordinal Kprim__cast_IntegerChar = 676
ordinal Kprim__cast_IntegerDouble = 677
ordinal Kprim__cast_IntegerPercentWorld = 678
ordinal Kprim__cast_Bits8Int = 679
ordinal Kprim__cast_Bits8Int8 = 680
ordinal Kprim__cast_Bits8Int16 = 681
ordinal Kprim__cast_Bits8Int32 = 682
ordinal Kprim__cast_Bits8Int64 = 683
ordinal Kprim__cast_Bits8Integer = 684
ordinal Kprim__cast_Bits8Bits8 = 685
ordinal Kprim__cast_Bits8Bits16 = 686
ordinal Kprim__cast_Bits8Bits32 = 687
ordinal Kprim__cast_Bits8Bits64 = 688
ordinal Kprim__cast_Bits8String = 689
ordinal Kprim__cast_Bits8Char = 690
ordinal Kprim__cast_Bits8Double = 691
ordinal Kprim__cast_Bits8PercentWorld = 692
ordinal Kprim__cast_Bits16Int = 693
ordinal Kprim__cast_Bits16Int8 = 694
ordinal Kprim__cast_Bits16Int16 = 695
ordinal Kprim__cast_Bits16Int32 = 696
ordinal Kprim__cast_Bits16Int64 = 697
ordinal Kprim__cast_Bits16Integer = 698
ordinal Kprim__cast_Bits16Bits8 = 699
ordinal Kprim__cast_Bits16Bits16 = 700
ordinal Kprim__cast_Bits16Bits32 = 701
ordinal Kprim__cast_Bits16Bits64 = 702
ordinal Kprim__cast_Bits16String = 703
ordinal Kprim__cast_Bits16Char = 704
ordinal Kprim__cast_Bits16Double = 705
ordinal Kprim__cast_Bits16PercentWorld = 706
ordinal Kprim__cast_Bits32Int = 707
ordinal Kprim__cast_Bits32Int8 = 708
ordinal Kprim__cast_Bits32Int16 = 709
ordinal Kprim__cast_Bits32Int32 = 710
ordinal Kprim__cast_Bits32Int64 = 711
ordinal Kprim__cast_Bits32Integer = 712
ordinal Kprim__cast_Bits32Bits8 = 713
ordinal Kprim__cast_Bits32Bits16 = 714
ordinal Kprim__cast_Bits32Bits32 = 715
ordinal Kprim__cast_Bits32Bits64 = 716
ordinal Kprim__cast_Bits32String = 717
ordinal Kprim__cast_Bits32Char = 718
ordinal Kprim__cast_Bits32Double = 719
ordinal Kprim__cast_Bits32PercentWorld = 720
ordinal Kprim__cast_Bits64Int = 721
ordinal Kprim__cast_Bits64Int8 = 722
ordinal Kprim__cast_Bits64Int16 = 723
ordinal Kprim__cast_Bits64Int32 = 724
ordinal Kprim__cast_Bits64Int64 = 725
ordinal Kprim__cast_Bits64Integer = 726
ordinal Kprim__cast_Bits64Bits8 = 727
ordinal Kprim__cast_Bits64Bits16 = 728
ordinal Kprim__cast_Bits64Bits32 = 729
ordinal Kprim__cast_Bits64Bits64 = 730
ordinal Kprim__cast_Bits64String = 731
ordinal Kprim__cast_Bits64Char = 732
ordinal Kprim__cast_Bits64Double = 733
ordinal Kprim__cast_Bits64PercentWorld = 734
ordinal Kprim__cast_StringInt = 735
ordinal Kprim__cast_StringInt8 = 736
ordinal Kprim__cast_StringInt16 = 737
ordinal Kprim__cast_StringInt32 = 738
ordinal Kprim__cast_StringInt64 = 739
ordinal Kprim__cast_StringInteger = 740
ordinal Kprim__cast_StringBits8 = 741
ordinal Kprim__cast_StringBits16 = 742
ordinal Kprim__cast_StringBits32 = 743
ordinal Kprim__cast_StringBits64 = 744
ordinal Kprim__cast_StringString = 745
ordinal Kprim__cast_StringChar = 746
ordinal Kprim__cast_StringDouble = 747
ordinal Kprim__cast_StringPercentWorld = 748
ordinal Kprim__cast_CharInt = 749
ordinal Kprim__cast_CharInt8 = 750
ordinal Kprim__cast_CharInt16 = 751
ordinal Kprim__cast_CharInt32 = 752
ordinal Kprim__cast_CharInt64 = 753
ordinal Kprim__cast_CharInteger = 754
ordinal Kprim__cast_CharBits8 = 755
ordinal Kprim__cast_CharBits16 = 756
ordinal Kprim__cast_CharBits32 = 757
ordinal Kprim__cast_CharBits64 = 758
ordinal Kprim__cast_CharString = 759
ordinal Kprim__cast_CharChar = 760
ordinal Kprim__cast_CharDouble = 761
ordinal Kprim__cast_CharPercentWorld = 762
ordinal Kprim__cast_DoubleInt = 763
ordinal Kprim__cast_DoubleInt8 = 764
ordinal Kprim__cast_DoubleInt16 = 765
ordinal Kprim__cast_DoubleInt32 = 766
ordinal Kprim__cast_DoubleInt64 = 767
ordinal Kprim__cast_DoubleInteger = 768
ordinal Kprim__cast_DoubleBits8 = 769
ordinal Kprim__cast_DoubleBits16 = 770
ordinal Kprim__cast_DoubleBits32 = 771
ordinal Kprim__cast_DoubleBits64 = 772
ordinal Kprim__cast_DoubleString = 773
ordinal Kprim__cast_DoubleChar = 774
ordinal Kprim__cast_DoubleDouble = 775
ordinal Kprim__cast_DoublePercentWorld = 776
ordinal Kprim__cast_PercentWorldInt = 777
ordinal Kprim__cast_PercentWorldInt8 = 778
ordinal Kprim__cast_PercentWorldInt16 = 779
ordinal Kprim__cast_PercentWorldInt32 = 780
ordinal Kprim__cast_PercentWorldInt64 = 781
ordinal Kprim__cast_PercentWorldInteger = 782
ordinal Kprim__cast_PercentWorldBits8 = 783
ordinal Kprim__cast_PercentWorldBits16 = 784
ordinal Kprim__cast_PercentWorldBits32 = 785
ordinal Kprim__cast_PercentWorldBits64 = 786
ordinal Kprim__cast_PercentWorldString = 787
ordinal Kprim__cast_PercentWorldChar = 788
ordinal Kprim__cast_PercentWorldDouble = 789
ordinal Kprim__cast_PercentWorldPercentWorld = 790
ordinal KInt = 791
ordinal KInt8 = 792
ordinal KInt16 = 793
ordinal KInt32 = 794
ordinal KInt64 = 795
ordinal KInteger = 796
ordinal KBits8 = 797
ordinal KBits16 = 798
ordinal KBits32 = 799
ordinal KBits64 = 800
ordinal KString = 801
ordinal KChar = 802
ordinal KDouble = 803
ordinal Ke = 804
ordinal Kcov = 805
ordinal KPercentWorld = 806
ordinal KfromInteger = 807
ordinal KfromDouble = 808
ordinal KProbeBinder = 809
ordinal KProbeHole = 810
ordinal KProbeHoleFound = 811
ordinal KProbeUnknown = 812
ordinal KProbeRuntime = 813
ordinal KProbeRuntimeAt = 814
ordinal KProbeField = 815
ordinal KProbePattern = 816
ordinal KProbeForm = 817
ordinal KProbeAxis = 818
ordinal KProbeAxisAt = 819
ordinal KProbeSize = 820
ordinal KProbeVar = 821
ordinal KProbeFormal = 822
ordinal KProbeHeld = 823

||| The known identifier at an id, if the id is one.
public export
fromOrdinal : Int -> Maybe Known
fromOrdinal 0 = Just KDollar
fromOrdinal 1 = Just KMinus
fromOrdinal 2 = Just KArrow
fromOrdinal 3 = Just KCons
fromOrdinal 4 = Just KCons1
fromOrdinal 5 = Just KSnoc
fromOrdinal 6 = Just KAp
fromOrdinal 7 = Just KAutoMark
fromOrdinal 8 = Just KEquals
fromOrdinal 9 = Just KHomoEq
fromOrdinal 10 = Just KSeq
fromOrdinal 11 = Just KBindOp
fromOrdinal 12 = Just KApp
fromOrdinal 13 = Just KAutoImplicit
fromOrdinal 14 = Just KB16
fromOrdinal 15 = Just KB32
fromOrdinal 16 = Just KB64
fromOrdinal 17 = Just KB8
fromOrdinal 18 = Just KBI
fromOrdinal 19 = Just KBasic
fromOrdinal 20 = Just KBasics
fromOrdinal 21 = Just KBits16Type
fromOrdinal 22 = Just KBits32Type
fromOrdinal 23 = Just KBits64Type
fromOrdinal 24 = Just KBits8Type
fromOrdinal 25 = Just KBool
fromOrdinal 26 = Just KBound
fromOrdinal 27 = Just KBuiltin
fromOrdinal 28 = Just KBuiltinNatural
fromOrdinal 29 = Just KCOVERAGE
fromOrdinal 30 = Just KCaseBlock
fromOrdinal 31 = Just KCh
fromOrdinal 32 = Just KCharType
fromOrdinal 33 = Just KCoveringOnly
fromOrdinal 34 = Just KDN
fromOrdinal 35 = Just KDPair
fromOrdinal 36 = Just KData
fromOrdinal 37 = Just KDataCon
fromOrdinal 38 = Just KDb
fromOrdinal 39 = Just KDecl
fromOrdinal 40 = Just KDefImplicit
fromOrdinal 41 = Just KDefaultedValue
fromOrdinal 42 = Just KDeprecate
fromOrdinal 43 = Just KDoubleType
fromOrdinal 44 = Just KElab
fromOrdinal 45 = Just KEmptyFC
fromOrdinal 46 = Just KEqOrd
fromOrdinal 47 = Just KEqual
fromOrdinal 48 = Just KErased
fromOrdinal 49 = Just KErasedArg
fromOrdinal 50 = Just KExplicitArg
fromOrdinal 51 = Just KExport
fromOrdinal 52 = Just KExternFn
fromOrdinal 53 = Just KExternal
fromOrdinal 54 = Just KFalse
fromOrdinal 55 = Just KField
fromOrdinal 56 = Just KFirst
fromOrdinal 57 = Just KFirstSuccess
fromOrdinal 58 = Just KForeignExport
fromOrdinal 59 = Just KForeignFn
fromOrdinal 60 = Just KFunc
fromOrdinal 61 = Just KGlobalHint
fromOrdinal 62 = Just KHint
fromOrdinal 63 = Just KI
fromOrdinal 64 = Just KI16
fromOrdinal 65 = Just KI32
fromOrdinal 66 = Just KI64
fromOrdinal 67 = Just KI8
fromOrdinal 68 = Just KIAlternative
fromOrdinal 69 = Just KIApp
fromOrdinal 70 = Just KIAs
fromOrdinal 71 = Just KIAutoApp
fromOrdinal 72 = Just KIBindHere
fromOrdinal 73 = Just KIBindVar
fromOrdinal 74 = Just KICase
fromOrdinal 75 = Just KIClaim
fromOrdinal 76 = Just KIData
fromOrdinal 77 = Just KIDef
fromOrdinal 78 = Just KIDelay
fromOrdinal 79 = Just KIDelayed
fromOrdinal 80 = Just KIFail
fromOrdinal 81 = Just KIForce
fromOrdinal 82 = Just KIHole
fromOrdinal 83 = Just KILam
fromOrdinal 84 = Just KILet
fromOrdinal 85 = Just KILocal
fromOrdinal 86 = Just KILog
fromOrdinal 87 = Just KIMustUnify
fromOrdinal 88 = Just KINamedApp
fromOrdinal 89 = Just KINamespace
fromOrdinal 90 = Just KIO
fromOrdinal 91 = Just KIParameters
fromOrdinal 92 = Just KIPi
fromOrdinal 93 = Just KIPrimVal
fromOrdinal 94 = Just KIQuote
fromOrdinal 95 = Just KIQuoteDecl
fromOrdinal 96 = Just KIQuoteName
fromOrdinal 97 = Just KIRecord
fromOrdinal 98 = Just KIRewrite
fromOrdinal 99 = Just KISearch
fromOrdinal 100 = Just KISetField
fromOrdinal 101 = Just KISetFieldApp
fromOrdinal 102 = Just KITransform
fromOrdinal 103 = Just KIType
fromOrdinal 104 = Just KIUnquote
fromOrdinal 105 = Just KIUpdate
fromOrdinal 106 = Just KIVar
fromOrdinal 107 = Just KIWithApp
fromOrdinal 108 = Just KIWithUnambigNames
fromOrdinal 109 = Just KImplicit
fromOrdinal 110 = Just KImplicitArg
fromOrdinal 111 = Just KImpossibleClause
fromOrdinal 112 = Just KInline
fromOrdinal 113 = Just KInt16Type
fromOrdinal 114 = Just KInt32Type
fromOrdinal 115 = Just KInt64Type
fromOrdinal 116 = Just KInt8Type
fromOrdinal 117 = Just KIntType
fromOrdinal 118 = Just KIntegerToNatural
fromOrdinal 119 = Just KIntegerType
fromOrdinal 120 = Just KInteractive
fromOrdinal 121 = Just KInvertible
fromOrdinal 122 = Just KJust
fromOrdinal 123 = Just KLInf
fromOrdinal 124 = Just KLLazy
fromOrdinal 125 = Just KLUnknown
fromOrdinal 126 = Just KLam
fromOrdinal 127 = Just KLanguage
fromOrdinal 128 = Just KLater
fromOrdinal 129 = Just KLin
fromOrdinal 130 = Just KList
fromOrdinal 131 = Just KList1
fromOrdinal 132 = Just KLocal
fromOrdinal 133 = Just KM0
fromOrdinal 134 = Just KM1
fromOrdinal 135 = Just KMN
fromOrdinal 136 = Just KMW
fromOrdinal 137 = Just KMacro
fromOrdinal 138 = Just KMain
fromOrdinal 139 = Just KMaybe
fromOrdinal 140 = Just KMkDPair
fromOrdinal 141 = Just KMkData
fromOrdinal 142 = Just KMkFC
fromOrdinal 143 = Just KMkFCVal
fromOrdinal 144 = Just KMkIClaimData
fromOrdinal 145 = Just KMkIField
fromOrdinal 146 = Just KMkLater
fromOrdinal 147 = Just KMkMI
fromOrdinal 148 = Just KMkNS
fromOrdinal 149 = Just KMkNameInfo
fromOrdinal 150 = Just KMkPair
fromOrdinal 151 = Just KMkRecord
fromOrdinal 152 = Just KMkTy
fromOrdinal 153 = Just KMkUnit
fromOrdinal 154 = Just KNONE
fromOrdinal 155 = Just KNS
fromOrdinal 156 = Just KName
fromOrdinal 157 = Just KNat
fromOrdinal 158 = Just KNaturalToInteger
fromOrdinal 159 = Just KNested
fromOrdinal 160 = Just KNil
fromOrdinal 161 = Just KNoHints
fromOrdinal 162 = Just KNoInline
fromOrdinal 163 = Just KNoNewtype
fromOrdinal 164 = Just KNonLinearVar
fromOrdinal 165 = Just KNotConstructor
fromOrdinal 166 = Just KNothing
fromOrdinal 167 = Just KNum
fromOrdinal 168 = Just KPATTERN
fromOrdinal 169 = Just KPI
fromOrdinal 170 = Just KPair
fromOrdinal 171 = Just KPartialOK
fromOrdinal 172 = Just KPatClause
fromOrdinal 173 = Just KPhysicalIdrSrc
fromOrdinal 174 = Just KPhysicalPkgSrc
fromOrdinal 175 = Just KPi
fromOrdinal 176 = Just KPrT
fromOrdinal 177 = Just KPrelude
fromOrdinal 178 = Just KPrimIO
fromOrdinal 179 = Just KPrimVal
fromOrdinal 180 = Just KPrivate
fromOrdinal 181 = Just KPublic
fromOrdinal 182 = Just KRef
fromOrdinal 183 = Just KRefl
fromOrdinal 184 = Just KReflection
fromOrdinal 185 = Just KS
fromOrdinal 186 = Just KSearchBy
fromOrdinal 187 = Just KSnocList
fromOrdinal 188 = Just KSpecArgs
fromOrdinal 189 = Just KSpecifiedValue
fromOrdinal 190 = Just KStr
fromOrdinal 191 = Just KStringType
fromOrdinal 192 = Just KSyntactic
fromOrdinal 193 = Just KTCInline
fromOrdinal 194 = Just KTDelay
fromOrdinal 195 = Just KTDelayed
fromOrdinal 196 = Just KTForce
fromOrdinal 197 = Just KTT
fromOrdinal 198 = Just KTTImp
fromOrdinal 199 = Just KTType
fromOrdinal 200 = Just KTotal
fromOrdinal 201 = Just KTotality
fromOrdinal 202 = Just KTrue
fromOrdinal 203 = Just KTyCon
fromOrdinal 204 = Just KType
fromOrdinal 205 = Just KTypes
fromOrdinal 206 = Just KUN
fromOrdinal 207 = Just KUnderAppliedCon
fromOrdinal 208 = Just KUnderscore
fromOrdinal 209 = Just KUnique
fromOrdinal 210 = Just KUniqueDefault
fromOrdinal 211 = Just KUniqueSearch
fromOrdinal 212 = Just KUnit
fromOrdinal 213 = Just KUnknownDot
fromOrdinal 214 = Just KUnsafe
fromOrdinal 215 = Just KUseLeft
fromOrdinal 216 = Just KUseRight
fromOrdinal 217 = Just KUserDotted
fromOrdinal 218 = Just KVarApplied
fromOrdinal 219 = Just KVirtual
fromOrdinal 220 = Just KWithBlock
fromOrdinal 221 = Just KWithClause
fromOrdinal 222 = Just KWorldType
fromOrdinal 223 = Just KWorldVal
fromOrdinal 224 = Just KZ
fromOrdinal 225 = Just KElabScript
fromOrdinal 226 = Just KForeign
fromOrdinal 227 = Just K_
fromOrdinal 228 = Just K_PE
fromOrdinal 229 = Just K__
fromOrdinal 230 = Just K__con
fromOrdinal 231 = Just K__infixTupleSection
fromOrdinal 232 = Just K__leftTupleSection
fromOrdinal 233 = Just K_cn
fromOrdinal 234 = Just Ka
fromOrdinal 235 = Just KaltTy
fromOrdinal 236 = Just Karg
fromOrdinal 237 = Just KargTy
fromOrdinal 238 = Just Kassert_smaller
fromOrdinal 239 = Just Kassert_total
fromOrdinal 240 = Just Kbelieve_me
fromOrdinal 241 = Just Kbind
fromOrdinal 242 = Just KcaseTy
fromOrdinal 243 = Just KconArg
fromOrdinal 244 = Just Kconcat
fromOrdinal 245 = Just Kconstraint
fromOrdinal 246 = Just Kconv
fromOrdinal 247 = Just Kcrash
fromOrdinal 248 = Just KdefArg
fromOrdinal 249 = Just KdelayTy
fromOrdinal 250 = Just Kdelayed
fromOrdinal 251 = Just KdotTm
fromOrdinal 252 = Just KdoubleACos
fromOrdinal 253 = Just KdoubleASin
fromOrdinal 254 = Just KdoubleATan
fromOrdinal 255 = Just KdoubleCeiling
fromOrdinal 256 = Just KdoubleCos
fromOrdinal 257 = Just KdoubleExp
fromOrdinal 258 = Just KdoubleFloor
fromOrdinal 259 = Just KdoubleLog
fromOrdinal 260 = Just KdoublePow
fromOrdinal 261 = Just KdoubleSin
fromOrdinal 262 = Just KdoubleSqrt
fromOrdinal 263 = Just KdoubleTan
fromOrdinal 264 = Just Kfvar
fromOrdinal 265 = Just Kguard
fromOrdinal 266 = Just Ki_con
fromOrdinal 267 = Just Kimp
fromOrdinal 268 = Just KimpArg
fromOrdinal 269 = Just Kimplicit_type
fromOrdinal 270 = Just Kinf
fromOrdinal 271 = Just Kinterpolate
fromOrdinal 272 = Just Klamc
fromOrdinal 273 = Just Klcase
fromOrdinal 274 = Just Km
fromOrdinal 275 = Just Kmain
fromOrdinal 276 = Just Knegate
fromOrdinal 277 = Just KpaRoot
fromOrdinal 278 = Just KpairFst
fromOrdinal 279 = Just KpairSnd
fromOrdinal 280 = Just Kpostpone
fromOrdinal 281 = Just Kpure
fromOrdinal 282 = Just Kq
fromOrdinal 283 = Just Kqv
fromOrdinal 284 = Just KrangeFrom
fromOrdinal 285 = Just KrangeFromThen
fromOrdinal 286 = Just KrangeFromThenTo
fromOrdinal 287 = Just KrangeFromTo
fromOrdinal 288 = Just Krec
fromOrdinal 289 = Just KretTy
fromOrdinal 290 = Just Krwarg
fromOrdinal 291 = Just Ksa
fromOrdinal 292 = Just Kscr
fromOrdinal 293 = Just KscriptTy
fromOrdinal 294 = Just Ksearch
fromOrdinal 295 = Just KsearchTy
fromOrdinal 296 = Just KstrAppend
fromOrdinal 297 = Just KstrCons
fromOrdinal 298 = Just KstrHead
fromOrdinal 299 = Just KstrIndex
fromOrdinal 300 = Just KstrLength
fromOrdinal 301 = Just KstrReverse
fromOrdinal 302 = Just KstrSubstr
fromOrdinal 303 = Just KstrTail
fromOrdinal 304 = Just Kt
fromOrdinal 305 = Just Ktmp
fromOrdinal 306 = Just Ktop
fromOrdinal 307 = Just Ku
fromOrdinal 308 = Just Kwarg
fromOrdinal 309 = Just Kx
fromOrdinal 310 = Just KHeteroEq
fromOrdinal 311 = Just Kprim__believe_me
fromOrdinal 312 = Just Kprim__crash
fromOrdinal 313 = Just Kidris_crash
fromOrdinal 314 = Just KElabAp
fromOrdinal 315 = Just KPure
fromOrdinal 316 = Just KMap
fromOrdinal 317 = Just KBind
fromOrdinal 318 = Just KFail
fromOrdinal 319 = Just KWarn
fromOrdinal 320 = Just KTry
fromOrdinal 321 = Just KLogMsg
fromOrdinal 322 = Just KLogTerm
fromOrdinal 323 = Just KLogSugaredTerm
fromOrdinal 324 = Just KResugarTerm
fromOrdinal 325 = Just KCheck
fromOrdinal 326 = Just KQuote
fromOrdinal 327 = Just KLambda
fromOrdinal 328 = Just KGoal
fromOrdinal 329 = Just KLocalVars
fromOrdinal 330 = Just KGenSym
fromOrdinal 331 = Just KInCurrentNS
fromOrdinal 332 = Just KGetType
fromOrdinal 333 = Just KGetInfo
fromOrdinal 334 = Just KGetVis
fromOrdinal 335 = Just KGetLocalType
fromOrdinal 336 = Just KGetCons
fromOrdinal 337 = Just KGetReferredFns
fromOrdinal 338 = Just KGetCurrentFn
fromOrdinal 339 = Just KGetFC
fromOrdinal 340 = Just KDeclare
fromOrdinal 341 = Just KReadFile
fromOrdinal 342 = Just KWriteFile
fromOrdinal 343 = Just KIdrisDir
fromOrdinal 344 = Just KProjectDir
fromOrdinal 345 = Just KSourceDir
fromOrdinal 346 = Just KCurrentModuleDir
fromOrdinal 347 = Just KSubmodulesDir
fromOrdinal 348 = Just KBuildDir
fromOrdinal 349 = Just Kb
fromOrdinal 350 = Just Kmsg
fromOrdinal 351 = Just Kprim__add_Int
fromOrdinal 352 = Just Kprim__add_Int8
fromOrdinal 353 = Just Kprim__add_Int16
fromOrdinal 354 = Just Kprim__add_Int32
fromOrdinal 355 = Just Kprim__add_Int64
fromOrdinal 356 = Just Kprim__add_Integer
fromOrdinal 357 = Just Kprim__add_Bits8
fromOrdinal 358 = Just Kprim__add_Bits16
fromOrdinal 359 = Just Kprim__add_Bits32
fromOrdinal 360 = Just Kprim__add_Bits64
fromOrdinal 361 = Just Kprim__add_String
fromOrdinal 362 = Just Kprim__add_Char
fromOrdinal 363 = Just Kprim__add_Double
fromOrdinal 364 = Just Kprim__add_PercentWorld
fromOrdinal 365 = Just Kprim__sub_Int
fromOrdinal 366 = Just Kprim__sub_Int8
fromOrdinal 367 = Just Kprim__sub_Int16
fromOrdinal 368 = Just Kprim__sub_Int32
fromOrdinal 369 = Just Kprim__sub_Int64
fromOrdinal 370 = Just Kprim__sub_Integer
fromOrdinal 371 = Just Kprim__sub_Bits8
fromOrdinal 372 = Just Kprim__sub_Bits16
fromOrdinal 373 = Just Kprim__sub_Bits32
fromOrdinal 374 = Just Kprim__sub_Bits64
fromOrdinal 375 = Just Kprim__sub_String
fromOrdinal 376 = Just Kprim__sub_Char
fromOrdinal 377 = Just Kprim__sub_Double
fromOrdinal 378 = Just Kprim__sub_PercentWorld
fromOrdinal 379 = Just Kprim__mul_Int
fromOrdinal 380 = Just Kprim__mul_Int8
fromOrdinal 381 = Just Kprim__mul_Int16
fromOrdinal 382 = Just Kprim__mul_Int32
fromOrdinal 383 = Just Kprim__mul_Int64
fromOrdinal 384 = Just Kprim__mul_Integer
fromOrdinal 385 = Just Kprim__mul_Bits8
fromOrdinal 386 = Just Kprim__mul_Bits16
fromOrdinal 387 = Just Kprim__mul_Bits32
fromOrdinal 388 = Just Kprim__mul_Bits64
fromOrdinal 389 = Just Kprim__mul_String
fromOrdinal 390 = Just Kprim__mul_Char
fromOrdinal 391 = Just Kprim__mul_Double
fromOrdinal 392 = Just Kprim__mul_PercentWorld
fromOrdinal 393 = Just Kprim__div_Int
fromOrdinal 394 = Just Kprim__div_Int8
fromOrdinal 395 = Just Kprim__div_Int16
fromOrdinal 396 = Just Kprim__div_Int32
fromOrdinal 397 = Just Kprim__div_Int64
fromOrdinal 398 = Just Kprim__div_Integer
fromOrdinal 399 = Just Kprim__div_Bits8
fromOrdinal 400 = Just Kprim__div_Bits16
fromOrdinal 401 = Just Kprim__div_Bits32
fromOrdinal 402 = Just Kprim__div_Bits64
fromOrdinal 403 = Just Kprim__div_String
fromOrdinal 404 = Just Kprim__div_Char
fromOrdinal 405 = Just Kprim__div_Double
fromOrdinal 406 = Just Kprim__div_PercentWorld
fromOrdinal 407 = Just Kprim__mod_Int
fromOrdinal 408 = Just Kprim__mod_Int8
fromOrdinal 409 = Just Kprim__mod_Int16
fromOrdinal 410 = Just Kprim__mod_Int32
fromOrdinal 411 = Just Kprim__mod_Int64
fromOrdinal 412 = Just Kprim__mod_Integer
fromOrdinal 413 = Just Kprim__mod_Bits8
fromOrdinal 414 = Just Kprim__mod_Bits16
fromOrdinal 415 = Just Kprim__mod_Bits32
fromOrdinal 416 = Just Kprim__mod_Bits64
fromOrdinal 417 = Just Kprim__mod_String
fromOrdinal 418 = Just Kprim__mod_Char
fromOrdinal 419 = Just Kprim__mod_Double
fromOrdinal 420 = Just Kprim__mod_PercentWorld
fromOrdinal 421 = Just Kprim__negate_Int
fromOrdinal 422 = Just Kprim__negate_Int8
fromOrdinal 423 = Just Kprim__negate_Int16
fromOrdinal 424 = Just Kprim__negate_Int32
fromOrdinal 425 = Just Kprim__negate_Int64
fromOrdinal 426 = Just Kprim__negate_Integer
fromOrdinal 427 = Just Kprim__negate_Bits8
fromOrdinal 428 = Just Kprim__negate_Bits16
fromOrdinal 429 = Just Kprim__negate_Bits32
fromOrdinal 430 = Just Kprim__negate_Bits64
fromOrdinal 431 = Just Kprim__negate_String
fromOrdinal 432 = Just Kprim__negate_Char
fromOrdinal 433 = Just Kprim__negate_Double
fromOrdinal 434 = Just Kprim__negate_PercentWorld
fromOrdinal 435 = Just Kprim__shl_Int
fromOrdinal 436 = Just Kprim__shl_Int8
fromOrdinal 437 = Just Kprim__shl_Int16
fromOrdinal 438 = Just Kprim__shl_Int32
fromOrdinal 439 = Just Kprim__shl_Int64
fromOrdinal 440 = Just Kprim__shl_Integer
fromOrdinal 441 = Just Kprim__shl_Bits8
fromOrdinal 442 = Just Kprim__shl_Bits16
fromOrdinal 443 = Just Kprim__shl_Bits32
fromOrdinal 444 = Just Kprim__shl_Bits64
fromOrdinal 445 = Just Kprim__shl_String
fromOrdinal 446 = Just Kprim__shl_Char
fromOrdinal 447 = Just Kprim__shl_Double
fromOrdinal 448 = Just Kprim__shl_PercentWorld
fromOrdinal 449 = Just Kprim__shr_Int
fromOrdinal 450 = Just Kprim__shr_Int8
fromOrdinal 451 = Just Kprim__shr_Int16
fromOrdinal 452 = Just Kprim__shr_Int32
fromOrdinal 453 = Just Kprim__shr_Int64
fromOrdinal 454 = Just Kprim__shr_Integer
fromOrdinal 455 = Just Kprim__shr_Bits8
fromOrdinal 456 = Just Kprim__shr_Bits16
fromOrdinal 457 = Just Kprim__shr_Bits32
fromOrdinal 458 = Just Kprim__shr_Bits64
fromOrdinal 459 = Just Kprim__shr_String
fromOrdinal 460 = Just Kprim__shr_Char
fromOrdinal 461 = Just Kprim__shr_Double
fromOrdinal 462 = Just Kprim__shr_PercentWorld
fromOrdinal 463 = Just Kprim__and_Int
fromOrdinal 464 = Just Kprim__and_Int8
fromOrdinal 465 = Just Kprim__and_Int16
fromOrdinal 466 = Just Kprim__and_Int32
fromOrdinal 467 = Just Kprim__and_Int64
fromOrdinal 468 = Just Kprim__and_Integer
fromOrdinal 469 = Just Kprim__and_Bits8
fromOrdinal 470 = Just Kprim__and_Bits16
fromOrdinal 471 = Just Kprim__and_Bits32
fromOrdinal 472 = Just Kprim__and_Bits64
fromOrdinal 473 = Just Kprim__and_String
fromOrdinal 474 = Just Kprim__and_Char
fromOrdinal 475 = Just Kprim__and_Double
fromOrdinal 476 = Just Kprim__and_PercentWorld
fromOrdinal 477 = Just Kprim__or_Int
fromOrdinal 478 = Just Kprim__or_Int8
fromOrdinal 479 = Just Kprim__or_Int16
fromOrdinal 480 = Just Kprim__or_Int32
fromOrdinal 481 = Just Kprim__or_Int64
fromOrdinal 482 = Just Kprim__or_Integer
fromOrdinal 483 = Just Kprim__or_Bits8
fromOrdinal 484 = Just Kprim__or_Bits16
fromOrdinal 485 = Just Kprim__or_Bits32
fromOrdinal 486 = Just Kprim__or_Bits64
fromOrdinal 487 = Just Kprim__or_String
fromOrdinal 488 = Just Kprim__or_Char
fromOrdinal 489 = Just Kprim__or_Double
fromOrdinal 490 = Just Kprim__or_PercentWorld
fromOrdinal 491 = Just Kprim__xor_Int
fromOrdinal 492 = Just Kprim__xor_Int8
fromOrdinal 493 = Just Kprim__xor_Int16
fromOrdinal 494 = Just Kprim__xor_Int32
fromOrdinal 495 = Just Kprim__xor_Int64
fromOrdinal 496 = Just Kprim__xor_Integer
fromOrdinal 497 = Just Kprim__xor_Bits8
fromOrdinal 498 = Just Kprim__xor_Bits16
fromOrdinal 499 = Just Kprim__xor_Bits32
fromOrdinal 500 = Just Kprim__xor_Bits64
fromOrdinal 501 = Just Kprim__xor_String
fromOrdinal 502 = Just Kprim__xor_Char
fromOrdinal 503 = Just Kprim__xor_Double
fromOrdinal 504 = Just Kprim__xor_PercentWorld
fromOrdinal 505 = Just Kprim__lt_Int
fromOrdinal 506 = Just Kprim__lt_Int8
fromOrdinal 507 = Just Kprim__lt_Int16
fromOrdinal 508 = Just Kprim__lt_Int32
fromOrdinal 509 = Just Kprim__lt_Int64
fromOrdinal 510 = Just Kprim__lt_Integer
fromOrdinal 511 = Just Kprim__lt_Bits8
fromOrdinal 512 = Just Kprim__lt_Bits16
fromOrdinal 513 = Just Kprim__lt_Bits32
fromOrdinal 514 = Just Kprim__lt_Bits64
fromOrdinal 515 = Just Kprim__lt_String
fromOrdinal 516 = Just Kprim__lt_Char
fromOrdinal 517 = Just Kprim__lt_Double
fromOrdinal 518 = Just Kprim__lt_PercentWorld
fromOrdinal 519 = Just Kprim__lte_Int
fromOrdinal 520 = Just Kprim__lte_Int8
fromOrdinal 521 = Just Kprim__lte_Int16
fromOrdinal 522 = Just Kprim__lte_Int32
fromOrdinal 523 = Just Kprim__lte_Int64
fromOrdinal 524 = Just Kprim__lte_Integer
fromOrdinal 525 = Just Kprim__lte_Bits8
fromOrdinal 526 = Just Kprim__lte_Bits16
fromOrdinal 527 = Just Kprim__lte_Bits32
fromOrdinal 528 = Just Kprim__lte_Bits64
fromOrdinal 529 = Just Kprim__lte_String
fromOrdinal 530 = Just Kprim__lte_Char
fromOrdinal 531 = Just Kprim__lte_Double
fromOrdinal 532 = Just Kprim__lte_PercentWorld
fromOrdinal 533 = Just Kprim__eq_Int
fromOrdinal 534 = Just Kprim__eq_Int8
fromOrdinal 535 = Just Kprim__eq_Int16
fromOrdinal 536 = Just Kprim__eq_Int32
fromOrdinal 537 = Just Kprim__eq_Int64
fromOrdinal 538 = Just Kprim__eq_Integer
fromOrdinal 539 = Just Kprim__eq_Bits8
fromOrdinal 540 = Just Kprim__eq_Bits16
fromOrdinal 541 = Just Kprim__eq_Bits32
fromOrdinal 542 = Just Kprim__eq_Bits64
fromOrdinal 543 = Just Kprim__eq_String
fromOrdinal 544 = Just Kprim__eq_Char
fromOrdinal 545 = Just Kprim__eq_Double
fromOrdinal 546 = Just Kprim__eq_PercentWorld
fromOrdinal 547 = Just Kprim__gte_Int
fromOrdinal 548 = Just Kprim__gte_Int8
fromOrdinal 549 = Just Kprim__gte_Int16
fromOrdinal 550 = Just Kprim__gte_Int32
fromOrdinal 551 = Just Kprim__gte_Int64
fromOrdinal 552 = Just Kprim__gte_Integer
fromOrdinal 553 = Just Kprim__gte_Bits8
fromOrdinal 554 = Just Kprim__gte_Bits16
fromOrdinal 555 = Just Kprim__gte_Bits32
fromOrdinal 556 = Just Kprim__gte_Bits64
fromOrdinal 557 = Just Kprim__gte_String
fromOrdinal 558 = Just Kprim__gte_Char
fromOrdinal 559 = Just Kprim__gte_Double
fromOrdinal 560 = Just Kprim__gte_PercentWorld
fromOrdinal 561 = Just Kprim__gt_Int
fromOrdinal 562 = Just Kprim__gt_Int8
fromOrdinal 563 = Just Kprim__gt_Int16
fromOrdinal 564 = Just Kprim__gt_Int32
fromOrdinal 565 = Just Kprim__gt_Int64
fromOrdinal 566 = Just Kprim__gt_Integer
fromOrdinal 567 = Just Kprim__gt_Bits8
fromOrdinal 568 = Just Kprim__gt_Bits16
fromOrdinal 569 = Just Kprim__gt_Bits32
fromOrdinal 570 = Just Kprim__gt_Bits64
fromOrdinal 571 = Just Kprim__gt_String
fromOrdinal 572 = Just Kprim__gt_Char
fromOrdinal 573 = Just Kprim__gt_Double
fromOrdinal 574 = Just Kprim__gt_PercentWorld
fromOrdinal 575 = Just Kprim__strLength
fromOrdinal 576 = Just Kprim__strHead
fromOrdinal 577 = Just Kprim__strTail
fromOrdinal 578 = Just Kprim__strIndex
fromOrdinal 579 = Just Kprim__strCons
fromOrdinal 580 = Just Kprim__strAppend
fromOrdinal 581 = Just Kprim__strReverse
fromOrdinal 582 = Just Kprim__strSubstr
fromOrdinal 583 = Just Kprim__doubleExp
fromOrdinal 584 = Just Kprim__doubleLog
fromOrdinal 585 = Just Kprim__doublePow
fromOrdinal 586 = Just Kprim__doubleSin
fromOrdinal 587 = Just Kprim__doubleCos
fromOrdinal 588 = Just Kprim__doubleTan
fromOrdinal 589 = Just Kprim__doubleASin
fromOrdinal 590 = Just Kprim__doubleACos
fromOrdinal 591 = Just Kprim__doubleATan
fromOrdinal 592 = Just Kprim__doubleSqrt
fromOrdinal 593 = Just Kprim__doubleFloor
fromOrdinal 594 = Just Kprim__doubleCeiling
fromOrdinal 595 = Just Kprim__cast_IntInt
fromOrdinal 596 = Just Kprim__cast_IntInt8
fromOrdinal 597 = Just Kprim__cast_IntInt16
fromOrdinal 598 = Just Kprim__cast_IntInt32
fromOrdinal 599 = Just Kprim__cast_IntInt64
fromOrdinal 600 = Just Kprim__cast_IntInteger
fromOrdinal 601 = Just Kprim__cast_IntBits8
fromOrdinal 602 = Just Kprim__cast_IntBits16
fromOrdinal 603 = Just Kprim__cast_IntBits32
fromOrdinal 604 = Just Kprim__cast_IntBits64
fromOrdinal 605 = Just Kprim__cast_IntString
fromOrdinal 606 = Just Kprim__cast_IntChar
fromOrdinal 607 = Just Kprim__cast_IntDouble
fromOrdinal 608 = Just Kprim__cast_IntPercentWorld
fromOrdinal 609 = Just Kprim__cast_Int8Int
fromOrdinal 610 = Just Kprim__cast_Int8Int8
fromOrdinal 611 = Just Kprim__cast_Int8Int16
fromOrdinal 612 = Just Kprim__cast_Int8Int32
fromOrdinal 613 = Just Kprim__cast_Int8Int64
fromOrdinal 614 = Just Kprim__cast_Int8Integer
fromOrdinal 615 = Just Kprim__cast_Int8Bits8
fromOrdinal 616 = Just Kprim__cast_Int8Bits16
fromOrdinal 617 = Just Kprim__cast_Int8Bits32
fromOrdinal 618 = Just Kprim__cast_Int8Bits64
fromOrdinal 619 = Just Kprim__cast_Int8String
fromOrdinal 620 = Just Kprim__cast_Int8Char
fromOrdinal 621 = Just Kprim__cast_Int8Double
fromOrdinal 622 = Just Kprim__cast_Int8PercentWorld
fromOrdinal 623 = Just Kprim__cast_Int16Int
fromOrdinal 624 = Just Kprim__cast_Int16Int8
fromOrdinal 625 = Just Kprim__cast_Int16Int16
fromOrdinal 626 = Just Kprim__cast_Int16Int32
fromOrdinal 627 = Just Kprim__cast_Int16Int64
fromOrdinal 628 = Just Kprim__cast_Int16Integer
fromOrdinal 629 = Just Kprim__cast_Int16Bits8
fromOrdinal 630 = Just Kprim__cast_Int16Bits16
fromOrdinal 631 = Just Kprim__cast_Int16Bits32
fromOrdinal 632 = Just Kprim__cast_Int16Bits64
fromOrdinal 633 = Just Kprim__cast_Int16String
fromOrdinal 634 = Just Kprim__cast_Int16Char
fromOrdinal 635 = Just Kprim__cast_Int16Double
fromOrdinal 636 = Just Kprim__cast_Int16PercentWorld
fromOrdinal 637 = Just Kprim__cast_Int32Int
fromOrdinal 638 = Just Kprim__cast_Int32Int8
fromOrdinal 639 = Just Kprim__cast_Int32Int16
fromOrdinal 640 = Just Kprim__cast_Int32Int32
fromOrdinal 641 = Just Kprim__cast_Int32Int64
fromOrdinal 642 = Just Kprim__cast_Int32Integer
fromOrdinal 643 = Just Kprim__cast_Int32Bits8
fromOrdinal 644 = Just Kprim__cast_Int32Bits16
fromOrdinal 645 = Just Kprim__cast_Int32Bits32
fromOrdinal 646 = Just Kprim__cast_Int32Bits64
fromOrdinal 647 = Just Kprim__cast_Int32String
fromOrdinal 648 = Just Kprim__cast_Int32Char
fromOrdinal 649 = Just Kprim__cast_Int32Double
fromOrdinal 650 = Just Kprim__cast_Int32PercentWorld
fromOrdinal 651 = Just Kprim__cast_Int64Int
fromOrdinal 652 = Just Kprim__cast_Int64Int8
fromOrdinal 653 = Just Kprim__cast_Int64Int16
fromOrdinal 654 = Just Kprim__cast_Int64Int32
fromOrdinal 655 = Just Kprim__cast_Int64Int64
fromOrdinal 656 = Just Kprim__cast_Int64Integer
fromOrdinal 657 = Just Kprim__cast_Int64Bits8
fromOrdinal 658 = Just Kprim__cast_Int64Bits16
fromOrdinal 659 = Just Kprim__cast_Int64Bits32
fromOrdinal 660 = Just Kprim__cast_Int64Bits64
fromOrdinal 661 = Just Kprim__cast_Int64String
fromOrdinal 662 = Just Kprim__cast_Int64Char
fromOrdinal 663 = Just Kprim__cast_Int64Double
fromOrdinal 664 = Just Kprim__cast_Int64PercentWorld
fromOrdinal 665 = Just Kprim__cast_IntegerInt
fromOrdinal 666 = Just Kprim__cast_IntegerInt8
fromOrdinal 667 = Just Kprim__cast_IntegerInt16
fromOrdinal 668 = Just Kprim__cast_IntegerInt32
fromOrdinal 669 = Just Kprim__cast_IntegerInt64
fromOrdinal 670 = Just Kprim__cast_IntegerInteger
fromOrdinal 671 = Just Kprim__cast_IntegerBits8
fromOrdinal 672 = Just Kprim__cast_IntegerBits16
fromOrdinal 673 = Just Kprim__cast_IntegerBits32
fromOrdinal 674 = Just Kprim__cast_IntegerBits64
fromOrdinal 675 = Just Kprim__cast_IntegerString
fromOrdinal 676 = Just Kprim__cast_IntegerChar
fromOrdinal 677 = Just Kprim__cast_IntegerDouble
fromOrdinal 678 = Just Kprim__cast_IntegerPercentWorld
fromOrdinal 679 = Just Kprim__cast_Bits8Int
fromOrdinal 680 = Just Kprim__cast_Bits8Int8
fromOrdinal 681 = Just Kprim__cast_Bits8Int16
fromOrdinal 682 = Just Kprim__cast_Bits8Int32
fromOrdinal 683 = Just Kprim__cast_Bits8Int64
fromOrdinal 684 = Just Kprim__cast_Bits8Integer
fromOrdinal 685 = Just Kprim__cast_Bits8Bits8
fromOrdinal 686 = Just Kprim__cast_Bits8Bits16
fromOrdinal 687 = Just Kprim__cast_Bits8Bits32
fromOrdinal 688 = Just Kprim__cast_Bits8Bits64
fromOrdinal 689 = Just Kprim__cast_Bits8String
fromOrdinal 690 = Just Kprim__cast_Bits8Char
fromOrdinal 691 = Just Kprim__cast_Bits8Double
fromOrdinal 692 = Just Kprim__cast_Bits8PercentWorld
fromOrdinal 693 = Just Kprim__cast_Bits16Int
fromOrdinal 694 = Just Kprim__cast_Bits16Int8
fromOrdinal 695 = Just Kprim__cast_Bits16Int16
fromOrdinal 696 = Just Kprim__cast_Bits16Int32
fromOrdinal 697 = Just Kprim__cast_Bits16Int64
fromOrdinal 698 = Just Kprim__cast_Bits16Integer
fromOrdinal 699 = Just Kprim__cast_Bits16Bits8
fromOrdinal 700 = Just Kprim__cast_Bits16Bits16
fromOrdinal 701 = Just Kprim__cast_Bits16Bits32
fromOrdinal 702 = Just Kprim__cast_Bits16Bits64
fromOrdinal 703 = Just Kprim__cast_Bits16String
fromOrdinal 704 = Just Kprim__cast_Bits16Char
fromOrdinal 705 = Just Kprim__cast_Bits16Double
fromOrdinal 706 = Just Kprim__cast_Bits16PercentWorld
fromOrdinal 707 = Just Kprim__cast_Bits32Int
fromOrdinal 708 = Just Kprim__cast_Bits32Int8
fromOrdinal 709 = Just Kprim__cast_Bits32Int16
fromOrdinal 710 = Just Kprim__cast_Bits32Int32
fromOrdinal 711 = Just Kprim__cast_Bits32Int64
fromOrdinal 712 = Just Kprim__cast_Bits32Integer
fromOrdinal 713 = Just Kprim__cast_Bits32Bits8
fromOrdinal 714 = Just Kprim__cast_Bits32Bits16
fromOrdinal 715 = Just Kprim__cast_Bits32Bits32
fromOrdinal 716 = Just Kprim__cast_Bits32Bits64
fromOrdinal 717 = Just Kprim__cast_Bits32String
fromOrdinal 718 = Just Kprim__cast_Bits32Char
fromOrdinal 719 = Just Kprim__cast_Bits32Double
fromOrdinal 720 = Just Kprim__cast_Bits32PercentWorld
fromOrdinal 721 = Just Kprim__cast_Bits64Int
fromOrdinal 722 = Just Kprim__cast_Bits64Int8
fromOrdinal 723 = Just Kprim__cast_Bits64Int16
fromOrdinal 724 = Just Kprim__cast_Bits64Int32
fromOrdinal 725 = Just Kprim__cast_Bits64Int64
fromOrdinal 726 = Just Kprim__cast_Bits64Integer
fromOrdinal 727 = Just Kprim__cast_Bits64Bits8
fromOrdinal 728 = Just Kprim__cast_Bits64Bits16
fromOrdinal 729 = Just Kprim__cast_Bits64Bits32
fromOrdinal 730 = Just Kprim__cast_Bits64Bits64
fromOrdinal 731 = Just Kprim__cast_Bits64String
fromOrdinal 732 = Just Kprim__cast_Bits64Char
fromOrdinal 733 = Just Kprim__cast_Bits64Double
fromOrdinal 734 = Just Kprim__cast_Bits64PercentWorld
fromOrdinal 735 = Just Kprim__cast_StringInt
fromOrdinal 736 = Just Kprim__cast_StringInt8
fromOrdinal 737 = Just Kprim__cast_StringInt16
fromOrdinal 738 = Just Kprim__cast_StringInt32
fromOrdinal 739 = Just Kprim__cast_StringInt64
fromOrdinal 740 = Just Kprim__cast_StringInteger
fromOrdinal 741 = Just Kprim__cast_StringBits8
fromOrdinal 742 = Just Kprim__cast_StringBits16
fromOrdinal 743 = Just Kprim__cast_StringBits32
fromOrdinal 744 = Just Kprim__cast_StringBits64
fromOrdinal 745 = Just Kprim__cast_StringString
fromOrdinal 746 = Just Kprim__cast_StringChar
fromOrdinal 747 = Just Kprim__cast_StringDouble
fromOrdinal 748 = Just Kprim__cast_StringPercentWorld
fromOrdinal 749 = Just Kprim__cast_CharInt
fromOrdinal 750 = Just Kprim__cast_CharInt8
fromOrdinal 751 = Just Kprim__cast_CharInt16
fromOrdinal 752 = Just Kprim__cast_CharInt32
fromOrdinal 753 = Just Kprim__cast_CharInt64
fromOrdinal 754 = Just Kprim__cast_CharInteger
fromOrdinal 755 = Just Kprim__cast_CharBits8
fromOrdinal 756 = Just Kprim__cast_CharBits16
fromOrdinal 757 = Just Kprim__cast_CharBits32
fromOrdinal 758 = Just Kprim__cast_CharBits64
fromOrdinal 759 = Just Kprim__cast_CharString
fromOrdinal 760 = Just Kprim__cast_CharChar
fromOrdinal 761 = Just Kprim__cast_CharDouble
fromOrdinal 762 = Just Kprim__cast_CharPercentWorld
fromOrdinal 763 = Just Kprim__cast_DoubleInt
fromOrdinal 764 = Just Kprim__cast_DoubleInt8
fromOrdinal 765 = Just Kprim__cast_DoubleInt16
fromOrdinal 766 = Just Kprim__cast_DoubleInt32
fromOrdinal 767 = Just Kprim__cast_DoubleInt64
fromOrdinal 768 = Just Kprim__cast_DoubleInteger
fromOrdinal 769 = Just Kprim__cast_DoubleBits8
fromOrdinal 770 = Just Kprim__cast_DoubleBits16
fromOrdinal 771 = Just Kprim__cast_DoubleBits32
fromOrdinal 772 = Just Kprim__cast_DoubleBits64
fromOrdinal 773 = Just Kprim__cast_DoubleString
fromOrdinal 774 = Just Kprim__cast_DoubleChar
fromOrdinal 775 = Just Kprim__cast_DoubleDouble
fromOrdinal 776 = Just Kprim__cast_DoublePercentWorld
fromOrdinal 777 = Just Kprim__cast_PercentWorldInt
fromOrdinal 778 = Just Kprim__cast_PercentWorldInt8
fromOrdinal 779 = Just Kprim__cast_PercentWorldInt16
fromOrdinal 780 = Just Kprim__cast_PercentWorldInt32
fromOrdinal 781 = Just Kprim__cast_PercentWorldInt64
fromOrdinal 782 = Just Kprim__cast_PercentWorldInteger
fromOrdinal 783 = Just Kprim__cast_PercentWorldBits8
fromOrdinal 784 = Just Kprim__cast_PercentWorldBits16
fromOrdinal 785 = Just Kprim__cast_PercentWorldBits32
fromOrdinal 786 = Just Kprim__cast_PercentWorldBits64
fromOrdinal 787 = Just Kprim__cast_PercentWorldString
fromOrdinal 788 = Just Kprim__cast_PercentWorldChar
fromOrdinal 789 = Just Kprim__cast_PercentWorldDouble
fromOrdinal 790 = Just Kprim__cast_PercentWorldPercentWorld
fromOrdinal 791 = Just KInt
fromOrdinal 792 = Just KInt8
fromOrdinal 793 = Just KInt16
fromOrdinal 794 = Just KInt32
fromOrdinal 795 = Just KInt64
fromOrdinal 796 = Just KInteger
fromOrdinal 797 = Just KBits8
fromOrdinal 798 = Just KBits16
fromOrdinal 799 = Just KBits32
fromOrdinal 800 = Just KBits64
fromOrdinal 801 = Just KString
fromOrdinal 802 = Just KChar
fromOrdinal 803 = Just KDouble
fromOrdinal 804 = Just Ke
fromOrdinal 805 = Just Kcov
fromOrdinal 806 = Just KPercentWorld
fromOrdinal 807 = Just KfromInteger
fromOrdinal 808 = Just KfromDouble
fromOrdinal 809 = Just KProbeBinder
fromOrdinal 810 = Just KProbeHole
fromOrdinal 811 = Just KProbeHoleFound
fromOrdinal 812 = Just KProbeUnknown
fromOrdinal 813 = Just KProbeRuntime
fromOrdinal 814 = Just KProbeRuntimeAt
fromOrdinal 815 = Just KProbeField
fromOrdinal 816 = Just KProbePattern
fromOrdinal 817 = Just KProbeForm
fromOrdinal 818 = Just KProbeAxis
fromOrdinal 819 = Just KProbeAxisAt
fromOrdinal 820 = Just KProbeSize
fromOrdinal 821 = Just KProbeVar
fromOrdinal 822 = Just KProbeFormal
fromOrdinal 823 = Just KProbeHeld
fromOrdinal _ = Nothing

||| The first id a text the vocabulary does not spell gets.
public export
knownCount : Int
knownCount = 824

||| Each identifier is found again from its ordinal, so no two share one.
export
0 roundTrip : (k : Known) -> fromOrdinal (ordinal k) = Just k
roundTrip KDollar = Refl
roundTrip KMinus = Refl
roundTrip KArrow = Refl
roundTrip KCons = Refl
roundTrip KCons1 = Refl
roundTrip KSnoc = Refl
roundTrip KAp = Refl
roundTrip KAutoMark = Refl
roundTrip KEquals = Refl
roundTrip KHomoEq = Refl
roundTrip KSeq = Refl
roundTrip KBindOp = Refl
roundTrip KApp = Refl
roundTrip KAutoImplicit = Refl
roundTrip KB16 = Refl
roundTrip KB32 = Refl
roundTrip KB64 = Refl
roundTrip KB8 = Refl
roundTrip KBI = Refl
roundTrip KBasic = Refl
roundTrip KBasics = Refl
roundTrip KBits16Type = Refl
roundTrip KBits32Type = Refl
roundTrip KBits64Type = Refl
roundTrip KBits8Type = Refl
roundTrip KBool = Refl
roundTrip KBound = Refl
roundTrip KBuiltin = Refl
roundTrip KBuiltinNatural = Refl
roundTrip KCOVERAGE = Refl
roundTrip KCaseBlock = Refl
roundTrip KCh = Refl
roundTrip KCharType = Refl
roundTrip KCoveringOnly = Refl
roundTrip KDN = Refl
roundTrip KDPair = Refl
roundTrip KData = Refl
roundTrip KDataCon = Refl
roundTrip KDb = Refl
roundTrip KDecl = Refl
roundTrip KDefImplicit = Refl
roundTrip KDefaultedValue = Refl
roundTrip KDeprecate = Refl
roundTrip KDoubleType = Refl
roundTrip KElab = Refl
roundTrip KEmptyFC = Refl
roundTrip KEqOrd = Refl
roundTrip KEqual = Refl
roundTrip KErased = Refl
roundTrip KErasedArg = Refl
roundTrip KExplicitArg = Refl
roundTrip KExport = Refl
roundTrip KExternFn = Refl
roundTrip KExternal = Refl
roundTrip KFalse = Refl
roundTrip KField = Refl
roundTrip KFirst = Refl
roundTrip KFirstSuccess = Refl
roundTrip KForeignExport = Refl
roundTrip KForeignFn = Refl
roundTrip KFunc = Refl
roundTrip KGlobalHint = Refl
roundTrip KHint = Refl
roundTrip KI = Refl
roundTrip KI16 = Refl
roundTrip KI32 = Refl
roundTrip KI64 = Refl
roundTrip KI8 = Refl
roundTrip KIAlternative = Refl
roundTrip KIApp = Refl
roundTrip KIAs = Refl
roundTrip KIAutoApp = Refl
roundTrip KIBindHere = Refl
roundTrip KIBindVar = Refl
roundTrip KICase = Refl
roundTrip KIClaim = Refl
roundTrip KIData = Refl
roundTrip KIDef = Refl
roundTrip KIDelay = Refl
roundTrip KIDelayed = Refl
roundTrip KIFail = Refl
roundTrip KIForce = Refl
roundTrip KIHole = Refl
roundTrip KILam = Refl
roundTrip KILet = Refl
roundTrip KILocal = Refl
roundTrip KILog = Refl
roundTrip KIMustUnify = Refl
roundTrip KINamedApp = Refl
roundTrip KINamespace = Refl
roundTrip KIO = Refl
roundTrip KIParameters = Refl
roundTrip KIPi = Refl
roundTrip KIPrimVal = Refl
roundTrip KIQuote = Refl
roundTrip KIQuoteDecl = Refl
roundTrip KIQuoteName = Refl
roundTrip KIRecord = Refl
roundTrip KIRewrite = Refl
roundTrip KISearch = Refl
roundTrip KISetField = Refl
roundTrip KISetFieldApp = Refl
roundTrip KITransform = Refl
roundTrip KIType = Refl
roundTrip KIUnquote = Refl
roundTrip KIUpdate = Refl
roundTrip KIVar = Refl
roundTrip KIWithApp = Refl
roundTrip KIWithUnambigNames = Refl
roundTrip KImplicit = Refl
roundTrip KImplicitArg = Refl
roundTrip KImpossibleClause = Refl
roundTrip KInline = Refl
roundTrip KInt16Type = Refl
roundTrip KInt32Type = Refl
roundTrip KInt64Type = Refl
roundTrip KInt8Type = Refl
roundTrip KIntType = Refl
roundTrip KIntegerToNatural = Refl
roundTrip KIntegerType = Refl
roundTrip KInteractive = Refl
roundTrip KInvertible = Refl
roundTrip KJust = Refl
roundTrip KLInf = Refl
roundTrip KLLazy = Refl
roundTrip KLUnknown = Refl
roundTrip KLam = Refl
roundTrip KLanguage = Refl
roundTrip KLater = Refl
roundTrip KLin = Refl
roundTrip KList = Refl
roundTrip KList1 = Refl
roundTrip KLocal = Refl
roundTrip KM0 = Refl
roundTrip KM1 = Refl
roundTrip KMN = Refl
roundTrip KMW = Refl
roundTrip KMacro = Refl
roundTrip KMain = Refl
roundTrip KMaybe = Refl
roundTrip KMkDPair = Refl
roundTrip KMkData = Refl
roundTrip KMkFC = Refl
roundTrip KMkFCVal = Refl
roundTrip KMkIClaimData = Refl
roundTrip KMkIField = Refl
roundTrip KMkLater = Refl
roundTrip KMkMI = Refl
roundTrip KMkNS = Refl
roundTrip KMkNameInfo = Refl
roundTrip KMkPair = Refl
roundTrip KMkRecord = Refl
roundTrip KMkTy = Refl
roundTrip KMkUnit = Refl
roundTrip KNONE = Refl
roundTrip KNS = Refl
roundTrip KName = Refl
roundTrip KNat = Refl
roundTrip KNaturalToInteger = Refl
roundTrip KNested = Refl
roundTrip KNil = Refl
roundTrip KNoHints = Refl
roundTrip KNoInline = Refl
roundTrip KNoNewtype = Refl
roundTrip KNonLinearVar = Refl
roundTrip KNotConstructor = Refl
roundTrip KNothing = Refl
roundTrip KNum = Refl
roundTrip KPATTERN = Refl
roundTrip KPI = Refl
roundTrip KPair = Refl
roundTrip KPartialOK = Refl
roundTrip KPatClause = Refl
roundTrip KPhysicalIdrSrc = Refl
roundTrip KPhysicalPkgSrc = Refl
roundTrip KPi = Refl
roundTrip KPrT = Refl
roundTrip KPrelude = Refl
roundTrip KPrimIO = Refl
roundTrip KPrimVal = Refl
roundTrip KPrivate = Refl
roundTrip KPublic = Refl
roundTrip KRef = Refl
roundTrip KRefl = Refl
roundTrip KReflection = Refl
roundTrip KS = Refl
roundTrip KSearchBy = Refl
roundTrip KSnocList = Refl
roundTrip KSpecArgs = Refl
roundTrip KSpecifiedValue = Refl
roundTrip KStr = Refl
roundTrip KStringType = Refl
roundTrip KSyntactic = Refl
roundTrip KTCInline = Refl
roundTrip KTDelay = Refl
roundTrip KTDelayed = Refl
roundTrip KTForce = Refl
roundTrip KTT = Refl
roundTrip KTTImp = Refl
roundTrip KTType = Refl
roundTrip KTotal = Refl
roundTrip KTotality = Refl
roundTrip KTrue = Refl
roundTrip KTyCon = Refl
roundTrip KType = Refl
roundTrip KTypes = Refl
roundTrip KUN = Refl
roundTrip KUnderAppliedCon = Refl
roundTrip KUnderscore = Refl
roundTrip KUnique = Refl
roundTrip KUniqueDefault = Refl
roundTrip KUniqueSearch = Refl
roundTrip KUnit = Refl
roundTrip KUnknownDot = Refl
roundTrip KUnsafe = Refl
roundTrip KUseLeft = Refl
roundTrip KUseRight = Refl
roundTrip KUserDotted = Refl
roundTrip KVarApplied = Refl
roundTrip KVirtual = Refl
roundTrip KWithBlock = Refl
roundTrip KWithClause = Refl
roundTrip KWorldType = Refl
roundTrip KWorldVal = Refl
roundTrip KZ = Refl
roundTrip KElabScript = Refl
roundTrip KForeign = Refl
roundTrip K_ = Refl
roundTrip K_PE = Refl
roundTrip K__ = Refl
roundTrip K__con = Refl
roundTrip K__infixTupleSection = Refl
roundTrip K__leftTupleSection = Refl
roundTrip K_cn = Refl
roundTrip Ka = Refl
roundTrip KaltTy = Refl
roundTrip Karg = Refl
roundTrip KargTy = Refl
roundTrip Kassert_smaller = Refl
roundTrip Kassert_total = Refl
roundTrip Kbelieve_me = Refl
roundTrip Kbind = Refl
roundTrip KcaseTy = Refl
roundTrip KconArg = Refl
roundTrip Kconcat = Refl
roundTrip Kconstraint = Refl
roundTrip Kconv = Refl
roundTrip Kcrash = Refl
roundTrip KdefArg = Refl
roundTrip KdelayTy = Refl
roundTrip Kdelayed = Refl
roundTrip KdotTm = Refl
roundTrip KdoubleACos = Refl
roundTrip KdoubleASin = Refl
roundTrip KdoubleATan = Refl
roundTrip KdoubleCeiling = Refl
roundTrip KdoubleCos = Refl
roundTrip KdoubleExp = Refl
roundTrip KdoubleFloor = Refl
roundTrip KdoubleLog = Refl
roundTrip KdoublePow = Refl
roundTrip KdoubleSin = Refl
roundTrip KdoubleSqrt = Refl
roundTrip KdoubleTan = Refl
roundTrip Kfvar = Refl
roundTrip Kguard = Refl
roundTrip Ki_con = Refl
roundTrip Kimp = Refl
roundTrip KimpArg = Refl
roundTrip Kimplicit_type = Refl
roundTrip Kinf = Refl
roundTrip Kinterpolate = Refl
roundTrip Klamc = Refl
roundTrip Klcase = Refl
roundTrip Km = Refl
roundTrip Kmain = Refl
roundTrip Knegate = Refl
roundTrip KpaRoot = Refl
roundTrip KpairFst = Refl
roundTrip KpairSnd = Refl
roundTrip Kpostpone = Refl
roundTrip Kpure = Refl
roundTrip Kq = Refl
roundTrip Kqv = Refl
roundTrip KrangeFrom = Refl
roundTrip KrangeFromThen = Refl
roundTrip KrangeFromThenTo = Refl
roundTrip KrangeFromTo = Refl
roundTrip Krec = Refl
roundTrip KretTy = Refl
roundTrip Krwarg = Refl
roundTrip Ksa = Refl
roundTrip Kscr = Refl
roundTrip KscriptTy = Refl
roundTrip Ksearch = Refl
roundTrip KsearchTy = Refl
roundTrip KstrAppend = Refl
roundTrip KstrCons = Refl
roundTrip KstrHead = Refl
roundTrip KstrIndex = Refl
roundTrip KstrLength = Refl
roundTrip KstrReverse = Refl
roundTrip KstrSubstr = Refl
roundTrip KstrTail = Refl
roundTrip Kt = Refl
roundTrip Ktmp = Refl
roundTrip Ktop = Refl
roundTrip Ku = Refl
roundTrip Kwarg = Refl
roundTrip Kx = Refl
roundTrip KHeteroEq = Refl
roundTrip Kprim__believe_me = Refl
roundTrip Kprim__crash = Refl
roundTrip Kidris_crash = Refl
roundTrip KElabAp = Refl
roundTrip KPure = Refl
roundTrip KMap = Refl
roundTrip KBind = Refl
roundTrip KFail = Refl
roundTrip KWarn = Refl
roundTrip KTry = Refl
roundTrip KLogMsg = Refl
roundTrip KLogTerm = Refl
roundTrip KLogSugaredTerm = Refl
roundTrip KResugarTerm = Refl
roundTrip KCheck = Refl
roundTrip KQuote = Refl
roundTrip KLambda = Refl
roundTrip KGoal = Refl
roundTrip KLocalVars = Refl
roundTrip KGenSym = Refl
roundTrip KInCurrentNS = Refl
roundTrip KGetType = Refl
roundTrip KGetInfo = Refl
roundTrip KGetVis = Refl
roundTrip KGetLocalType = Refl
roundTrip KGetCons = Refl
roundTrip KGetReferredFns = Refl
roundTrip KGetCurrentFn = Refl
roundTrip KGetFC = Refl
roundTrip KDeclare = Refl
roundTrip KReadFile = Refl
roundTrip KWriteFile = Refl
roundTrip KIdrisDir = Refl
roundTrip KProjectDir = Refl
roundTrip KSourceDir = Refl
roundTrip KCurrentModuleDir = Refl
roundTrip KSubmodulesDir = Refl
roundTrip KBuildDir = Refl
roundTrip Kb = Refl
roundTrip Kmsg = Refl
roundTrip Kprim__add_Int = Refl
roundTrip Kprim__add_Int8 = Refl
roundTrip Kprim__add_Int16 = Refl
roundTrip Kprim__add_Int32 = Refl
roundTrip Kprim__add_Int64 = Refl
roundTrip Kprim__add_Integer = Refl
roundTrip Kprim__add_Bits8 = Refl
roundTrip Kprim__add_Bits16 = Refl
roundTrip Kprim__add_Bits32 = Refl
roundTrip Kprim__add_Bits64 = Refl
roundTrip Kprim__add_String = Refl
roundTrip Kprim__add_Char = Refl
roundTrip Kprim__add_Double = Refl
roundTrip Kprim__add_PercentWorld = Refl
roundTrip Kprim__sub_Int = Refl
roundTrip Kprim__sub_Int8 = Refl
roundTrip Kprim__sub_Int16 = Refl
roundTrip Kprim__sub_Int32 = Refl
roundTrip Kprim__sub_Int64 = Refl
roundTrip Kprim__sub_Integer = Refl
roundTrip Kprim__sub_Bits8 = Refl
roundTrip Kprim__sub_Bits16 = Refl
roundTrip Kprim__sub_Bits32 = Refl
roundTrip Kprim__sub_Bits64 = Refl
roundTrip Kprim__sub_String = Refl
roundTrip Kprim__sub_Char = Refl
roundTrip Kprim__sub_Double = Refl
roundTrip Kprim__sub_PercentWorld = Refl
roundTrip Kprim__mul_Int = Refl
roundTrip Kprim__mul_Int8 = Refl
roundTrip Kprim__mul_Int16 = Refl
roundTrip Kprim__mul_Int32 = Refl
roundTrip Kprim__mul_Int64 = Refl
roundTrip Kprim__mul_Integer = Refl
roundTrip Kprim__mul_Bits8 = Refl
roundTrip Kprim__mul_Bits16 = Refl
roundTrip Kprim__mul_Bits32 = Refl
roundTrip Kprim__mul_Bits64 = Refl
roundTrip Kprim__mul_String = Refl
roundTrip Kprim__mul_Char = Refl
roundTrip Kprim__mul_Double = Refl
roundTrip Kprim__mul_PercentWorld = Refl
roundTrip Kprim__div_Int = Refl
roundTrip Kprim__div_Int8 = Refl
roundTrip Kprim__div_Int16 = Refl
roundTrip Kprim__div_Int32 = Refl
roundTrip Kprim__div_Int64 = Refl
roundTrip Kprim__div_Integer = Refl
roundTrip Kprim__div_Bits8 = Refl
roundTrip Kprim__div_Bits16 = Refl
roundTrip Kprim__div_Bits32 = Refl
roundTrip Kprim__div_Bits64 = Refl
roundTrip Kprim__div_String = Refl
roundTrip Kprim__div_Char = Refl
roundTrip Kprim__div_Double = Refl
roundTrip Kprim__div_PercentWorld = Refl
roundTrip Kprim__mod_Int = Refl
roundTrip Kprim__mod_Int8 = Refl
roundTrip Kprim__mod_Int16 = Refl
roundTrip Kprim__mod_Int32 = Refl
roundTrip Kprim__mod_Int64 = Refl
roundTrip Kprim__mod_Integer = Refl
roundTrip Kprim__mod_Bits8 = Refl
roundTrip Kprim__mod_Bits16 = Refl
roundTrip Kprim__mod_Bits32 = Refl
roundTrip Kprim__mod_Bits64 = Refl
roundTrip Kprim__mod_String = Refl
roundTrip Kprim__mod_Char = Refl
roundTrip Kprim__mod_Double = Refl
roundTrip Kprim__mod_PercentWorld = Refl
roundTrip Kprim__negate_Int = Refl
roundTrip Kprim__negate_Int8 = Refl
roundTrip Kprim__negate_Int16 = Refl
roundTrip Kprim__negate_Int32 = Refl
roundTrip Kprim__negate_Int64 = Refl
roundTrip Kprim__negate_Integer = Refl
roundTrip Kprim__negate_Bits8 = Refl
roundTrip Kprim__negate_Bits16 = Refl
roundTrip Kprim__negate_Bits32 = Refl
roundTrip Kprim__negate_Bits64 = Refl
roundTrip Kprim__negate_String = Refl
roundTrip Kprim__negate_Char = Refl
roundTrip Kprim__negate_Double = Refl
roundTrip Kprim__negate_PercentWorld = Refl
roundTrip Kprim__shl_Int = Refl
roundTrip Kprim__shl_Int8 = Refl
roundTrip Kprim__shl_Int16 = Refl
roundTrip Kprim__shl_Int32 = Refl
roundTrip Kprim__shl_Int64 = Refl
roundTrip Kprim__shl_Integer = Refl
roundTrip Kprim__shl_Bits8 = Refl
roundTrip Kprim__shl_Bits16 = Refl
roundTrip Kprim__shl_Bits32 = Refl
roundTrip Kprim__shl_Bits64 = Refl
roundTrip Kprim__shl_String = Refl
roundTrip Kprim__shl_Char = Refl
roundTrip Kprim__shl_Double = Refl
roundTrip Kprim__shl_PercentWorld = Refl
roundTrip Kprim__shr_Int = Refl
roundTrip Kprim__shr_Int8 = Refl
roundTrip Kprim__shr_Int16 = Refl
roundTrip Kprim__shr_Int32 = Refl
roundTrip Kprim__shr_Int64 = Refl
roundTrip Kprim__shr_Integer = Refl
roundTrip Kprim__shr_Bits8 = Refl
roundTrip Kprim__shr_Bits16 = Refl
roundTrip Kprim__shr_Bits32 = Refl
roundTrip Kprim__shr_Bits64 = Refl
roundTrip Kprim__shr_String = Refl
roundTrip Kprim__shr_Char = Refl
roundTrip Kprim__shr_Double = Refl
roundTrip Kprim__shr_PercentWorld = Refl
roundTrip Kprim__and_Int = Refl
roundTrip Kprim__and_Int8 = Refl
roundTrip Kprim__and_Int16 = Refl
roundTrip Kprim__and_Int32 = Refl
roundTrip Kprim__and_Int64 = Refl
roundTrip Kprim__and_Integer = Refl
roundTrip Kprim__and_Bits8 = Refl
roundTrip Kprim__and_Bits16 = Refl
roundTrip Kprim__and_Bits32 = Refl
roundTrip Kprim__and_Bits64 = Refl
roundTrip Kprim__and_String = Refl
roundTrip Kprim__and_Char = Refl
roundTrip Kprim__and_Double = Refl
roundTrip Kprim__and_PercentWorld = Refl
roundTrip Kprim__or_Int = Refl
roundTrip Kprim__or_Int8 = Refl
roundTrip Kprim__or_Int16 = Refl
roundTrip Kprim__or_Int32 = Refl
roundTrip Kprim__or_Int64 = Refl
roundTrip Kprim__or_Integer = Refl
roundTrip Kprim__or_Bits8 = Refl
roundTrip Kprim__or_Bits16 = Refl
roundTrip Kprim__or_Bits32 = Refl
roundTrip Kprim__or_Bits64 = Refl
roundTrip Kprim__or_String = Refl
roundTrip Kprim__or_Char = Refl
roundTrip Kprim__or_Double = Refl
roundTrip Kprim__or_PercentWorld = Refl
roundTrip Kprim__xor_Int = Refl
roundTrip Kprim__xor_Int8 = Refl
roundTrip Kprim__xor_Int16 = Refl
roundTrip Kprim__xor_Int32 = Refl
roundTrip Kprim__xor_Int64 = Refl
roundTrip Kprim__xor_Integer = Refl
roundTrip Kprim__xor_Bits8 = Refl
roundTrip Kprim__xor_Bits16 = Refl
roundTrip Kprim__xor_Bits32 = Refl
roundTrip Kprim__xor_Bits64 = Refl
roundTrip Kprim__xor_String = Refl
roundTrip Kprim__xor_Char = Refl
roundTrip Kprim__xor_Double = Refl
roundTrip Kprim__xor_PercentWorld = Refl
roundTrip Kprim__lt_Int = Refl
roundTrip Kprim__lt_Int8 = Refl
roundTrip Kprim__lt_Int16 = Refl
roundTrip Kprim__lt_Int32 = Refl
roundTrip Kprim__lt_Int64 = Refl
roundTrip Kprim__lt_Integer = Refl
roundTrip Kprim__lt_Bits8 = Refl
roundTrip Kprim__lt_Bits16 = Refl
roundTrip Kprim__lt_Bits32 = Refl
roundTrip Kprim__lt_Bits64 = Refl
roundTrip Kprim__lt_String = Refl
roundTrip Kprim__lt_Char = Refl
roundTrip Kprim__lt_Double = Refl
roundTrip Kprim__lt_PercentWorld = Refl
roundTrip Kprim__lte_Int = Refl
roundTrip Kprim__lte_Int8 = Refl
roundTrip Kprim__lte_Int16 = Refl
roundTrip Kprim__lte_Int32 = Refl
roundTrip Kprim__lte_Int64 = Refl
roundTrip Kprim__lte_Integer = Refl
roundTrip Kprim__lte_Bits8 = Refl
roundTrip Kprim__lte_Bits16 = Refl
roundTrip Kprim__lte_Bits32 = Refl
roundTrip Kprim__lte_Bits64 = Refl
roundTrip Kprim__lte_String = Refl
roundTrip Kprim__lte_Char = Refl
roundTrip Kprim__lte_Double = Refl
roundTrip Kprim__lte_PercentWorld = Refl
roundTrip Kprim__eq_Int = Refl
roundTrip Kprim__eq_Int8 = Refl
roundTrip Kprim__eq_Int16 = Refl
roundTrip Kprim__eq_Int32 = Refl
roundTrip Kprim__eq_Int64 = Refl
roundTrip Kprim__eq_Integer = Refl
roundTrip Kprim__eq_Bits8 = Refl
roundTrip Kprim__eq_Bits16 = Refl
roundTrip Kprim__eq_Bits32 = Refl
roundTrip Kprim__eq_Bits64 = Refl
roundTrip Kprim__eq_String = Refl
roundTrip Kprim__eq_Char = Refl
roundTrip Kprim__eq_Double = Refl
roundTrip Kprim__eq_PercentWorld = Refl
roundTrip Kprim__gte_Int = Refl
roundTrip Kprim__gte_Int8 = Refl
roundTrip Kprim__gte_Int16 = Refl
roundTrip Kprim__gte_Int32 = Refl
roundTrip Kprim__gte_Int64 = Refl
roundTrip Kprim__gte_Integer = Refl
roundTrip Kprim__gte_Bits8 = Refl
roundTrip Kprim__gte_Bits16 = Refl
roundTrip Kprim__gte_Bits32 = Refl
roundTrip Kprim__gte_Bits64 = Refl
roundTrip Kprim__gte_String = Refl
roundTrip Kprim__gte_Char = Refl
roundTrip Kprim__gte_Double = Refl
roundTrip Kprim__gte_PercentWorld = Refl
roundTrip Kprim__gt_Int = Refl
roundTrip Kprim__gt_Int8 = Refl
roundTrip Kprim__gt_Int16 = Refl
roundTrip Kprim__gt_Int32 = Refl
roundTrip Kprim__gt_Int64 = Refl
roundTrip Kprim__gt_Integer = Refl
roundTrip Kprim__gt_Bits8 = Refl
roundTrip Kprim__gt_Bits16 = Refl
roundTrip Kprim__gt_Bits32 = Refl
roundTrip Kprim__gt_Bits64 = Refl
roundTrip Kprim__gt_String = Refl
roundTrip Kprim__gt_Char = Refl
roundTrip Kprim__gt_Double = Refl
roundTrip Kprim__gt_PercentWorld = Refl
roundTrip Kprim__strLength = Refl
roundTrip Kprim__strHead = Refl
roundTrip Kprim__strTail = Refl
roundTrip Kprim__strIndex = Refl
roundTrip Kprim__strCons = Refl
roundTrip Kprim__strAppend = Refl
roundTrip Kprim__strReverse = Refl
roundTrip Kprim__strSubstr = Refl
roundTrip Kprim__doubleExp = Refl
roundTrip Kprim__doubleLog = Refl
roundTrip Kprim__doublePow = Refl
roundTrip Kprim__doubleSin = Refl
roundTrip Kprim__doubleCos = Refl
roundTrip Kprim__doubleTan = Refl
roundTrip Kprim__doubleASin = Refl
roundTrip Kprim__doubleACos = Refl
roundTrip Kprim__doubleATan = Refl
roundTrip Kprim__doubleSqrt = Refl
roundTrip Kprim__doubleFloor = Refl
roundTrip Kprim__doubleCeiling = Refl
roundTrip Kprim__cast_IntInt = Refl
roundTrip Kprim__cast_IntInt8 = Refl
roundTrip Kprim__cast_IntInt16 = Refl
roundTrip Kprim__cast_IntInt32 = Refl
roundTrip Kprim__cast_IntInt64 = Refl
roundTrip Kprim__cast_IntInteger = Refl
roundTrip Kprim__cast_IntBits8 = Refl
roundTrip Kprim__cast_IntBits16 = Refl
roundTrip Kprim__cast_IntBits32 = Refl
roundTrip Kprim__cast_IntBits64 = Refl
roundTrip Kprim__cast_IntString = Refl
roundTrip Kprim__cast_IntChar = Refl
roundTrip Kprim__cast_IntDouble = Refl
roundTrip Kprim__cast_IntPercentWorld = Refl
roundTrip Kprim__cast_Int8Int = Refl
roundTrip Kprim__cast_Int8Int8 = Refl
roundTrip Kprim__cast_Int8Int16 = Refl
roundTrip Kprim__cast_Int8Int32 = Refl
roundTrip Kprim__cast_Int8Int64 = Refl
roundTrip Kprim__cast_Int8Integer = Refl
roundTrip Kprim__cast_Int8Bits8 = Refl
roundTrip Kprim__cast_Int8Bits16 = Refl
roundTrip Kprim__cast_Int8Bits32 = Refl
roundTrip Kprim__cast_Int8Bits64 = Refl
roundTrip Kprim__cast_Int8String = Refl
roundTrip Kprim__cast_Int8Char = Refl
roundTrip Kprim__cast_Int8Double = Refl
roundTrip Kprim__cast_Int8PercentWorld = Refl
roundTrip Kprim__cast_Int16Int = Refl
roundTrip Kprim__cast_Int16Int8 = Refl
roundTrip Kprim__cast_Int16Int16 = Refl
roundTrip Kprim__cast_Int16Int32 = Refl
roundTrip Kprim__cast_Int16Int64 = Refl
roundTrip Kprim__cast_Int16Integer = Refl
roundTrip Kprim__cast_Int16Bits8 = Refl
roundTrip Kprim__cast_Int16Bits16 = Refl
roundTrip Kprim__cast_Int16Bits32 = Refl
roundTrip Kprim__cast_Int16Bits64 = Refl
roundTrip Kprim__cast_Int16String = Refl
roundTrip Kprim__cast_Int16Char = Refl
roundTrip Kprim__cast_Int16Double = Refl
roundTrip Kprim__cast_Int16PercentWorld = Refl
roundTrip Kprim__cast_Int32Int = Refl
roundTrip Kprim__cast_Int32Int8 = Refl
roundTrip Kprim__cast_Int32Int16 = Refl
roundTrip Kprim__cast_Int32Int32 = Refl
roundTrip Kprim__cast_Int32Int64 = Refl
roundTrip Kprim__cast_Int32Integer = Refl
roundTrip Kprim__cast_Int32Bits8 = Refl
roundTrip Kprim__cast_Int32Bits16 = Refl
roundTrip Kprim__cast_Int32Bits32 = Refl
roundTrip Kprim__cast_Int32Bits64 = Refl
roundTrip Kprim__cast_Int32String = Refl
roundTrip Kprim__cast_Int32Char = Refl
roundTrip Kprim__cast_Int32Double = Refl
roundTrip Kprim__cast_Int32PercentWorld = Refl
roundTrip Kprim__cast_Int64Int = Refl
roundTrip Kprim__cast_Int64Int8 = Refl
roundTrip Kprim__cast_Int64Int16 = Refl
roundTrip Kprim__cast_Int64Int32 = Refl
roundTrip Kprim__cast_Int64Int64 = Refl
roundTrip Kprim__cast_Int64Integer = Refl
roundTrip Kprim__cast_Int64Bits8 = Refl
roundTrip Kprim__cast_Int64Bits16 = Refl
roundTrip Kprim__cast_Int64Bits32 = Refl
roundTrip Kprim__cast_Int64Bits64 = Refl
roundTrip Kprim__cast_Int64String = Refl
roundTrip Kprim__cast_Int64Char = Refl
roundTrip Kprim__cast_Int64Double = Refl
roundTrip Kprim__cast_Int64PercentWorld = Refl
roundTrip Kprim__cast_IntegerInt = Refl
roundTrip Kprim__cast_IntegerInt8 = Refl
roundTrip Kprim__cast_IntegerInt16 = Refl
roundTrip Kprim__cast_IntegerInt32 = Refl
roundTrip Kprim__cast_IntegerInt64 = Refl
roundTrip Kprim__cast_IntegerInteger = Refl
roundTrip Kprim__cast_IntegerBits8 = Refl
roundTrip Kprim__cast_IntegerBits16 = Refl
roundTrip Kprim__cast_IntegerBits32 = Refl
roundTrip Kprim__cast_IntegerBits64 = Refl
roundTrip Kprim__cast_IntegerString = Refl
roundTrip Kprim__cast_IntegerChar = Refl
roundTrip Kprim__cast_IntegerDouble = Refl
roundTrip Kprim__cast_IntegerPercentWorld = Refl
roundTrip Kprim__cast_Bits8Int = Refl
roundTrip Kprim__cast_Bits8Int8 = Refl
roundTrip Kprim__cast_Bits8Int16 = Refl
roundTrip Kprim__cast_Bits8Int32 = Refl
roundTrip Kprim__cast_Bits8Int64 = Refl
roundTrip Kprim__cast_Bits8Integer = Refl
roundTrip Kprim__cast_Bits8Bits8 = Refl
roundTrip Kprim__cast_Bits8Bits16 = Refl
roundTrip Kprim__cast_Bits8Bits32 = Refl
roundTrip Kprim__cast_Bits8Bits64 = Refl
roundTrip Kprim__cast_Bits8String = Refl
roundTrip Kprim__cast_Bits8Char = Refl
roundTrip Kprim__cast_Bits8Double = Refl
roundTrip Kprim__cast_Bits8PercentWorld = Refl
roundTrip Kprim__cast_Bits16Int = Refl
roundTrip Kprim__cast_Bits16Int8 = Refl
roundTrip Kprim__cast_Bits16Int16 = Refl
roundTrip Kprim__cast_Bits16Int32 = Refl
roundTrip Kprim__cast_Bits16Int64 = Refl
roundTrip Kprim__cast_Bits16Integer = Refl
roundTrip Kprim__cast_Bits16Bits8 = Refl
roundTrip Kprim__cast_Bits16Bits16 = Refl
roundTrip Kprim__cast_Bits16Bits32 = Refl
roundTrip Kprim__cast_Bits16Bits64 = Refl
roundTrip Kprim__cast_Bits16String = Refl
roundTrip Kprim__cast_Bits16Char = Refl
roundTrip Kprim__cast_Bits16Double = Refl
roundTrip Kprim__cast_Bits16PercentWorld = Refl
roundTrip Kprim__cast_Bits32Int = Refl
roundTrip Kprim__cast_Bits32Int8 = Refl
roundTrip Kprim__cast_Bits32Int16 = Refl
roundTrip Kprim__cast_Bits32Int32 = Refl
roundTrip Kprim__cast_Bits32Int64 = Refl
roundTrip Kprim__cast_Bits32Integer = Refl
roundTrip Kprim__cast_Bits32Bits8 = Refl
roundTrip Kprim__cast_Bits32Bits16 = Refl
roundTrip Kprim__cast_Bits32Bits32 = Refl
roundTrip Kprim__cast_Bits32Bits64 = Refl
roundTrip Kprim__cast_Bits32String = Refl
roundTrip Kprim__cast_Bits32Char = Refl
roundTrip Kprim__cast_Bits32Double = Refl
roundTrip Kprim__cast_Bits32PercentWorld = Refl
roundTrip Kprim__cast_Bits64Int = Refl
roundTrip Kprim__cast_Bits64Int8 = Refl
roundTrip Kprim__cast_Bits64Int16 = Refl
roundTrip Kprim__cast_Bits64Int32 = Refl
roundTrip Kprim__cast_Bits64Int64 = Refl
roundTrip Kprim__cast_Bits64Integer = Refl
roundTrip Kprim__cast_Bits64Bits8 = Refl
roundTrip Kprim__cast_Bits64Bits16 = Refl
roundTrip Kprim__cast_Bits64Bits32 = Refl
roundTrip Kprim__cast_Bits64Bits64 = Refl
roundTrip Kprim__cast_Bits64String = Refl
roundTrip Kprim__cast_Bits64Char = Refl
roundTrip Kprim__cast_Bits64Double = Refl
roundTrip Kprim__cast_Bits64PercentWorld = Refl
roundTrip Kprim__cast_StringInt = Refl
roundTrip Kprim__cast_StringInt8 = Refl
roundTrip Kprim__cast_StringInt16 = Refl
roundTrip Kprim__cast_StringInt32 = Refl
roundTrip Kprim__cast_StringInt64 = Refl
roundTrip Kprim__cast_StringInteger = Refl
roundTrip Kprim__cast_StringBits8 = Refl
roundTrip Kprim__cast_StringBits16 = Refl
roundTrip Kprim__cast_StringBits32 = Refl
roundTrip Kprim__cast_StringBits64 = Refl
roundTrip Kprim__cast_StringString = Refl
roundTrip Kprim__cast_StringChar = Refl
roundTrip Kprim__cast_StringDouble = Refl
roundTrip Kprim__cast_StringPercentWorld = Refl
roundTrip Kprim__cast_CharInt = Refl
roundTrip Kprim__cast_CharInt8 = Refl
roundTrip Kprim__cast_CharInt16 = Refl
roundTrip Kprim__cast_CharInt32 = Refl
roundTrip Kprim__cast_CharInt64 = Refl
roundTrip Kprim__cast_CharInteger = Refl
roundTrip Kprim__cast_CharBits8 = Refl
roundTrip Kprim__cast_CharBits16 = Refl
roundTrip Kprim__cast_CharBits32 = Refl
roundTrip Kprim__cast_CharBits64 = Refl
roundTrip Kprim__cast_CharString = Refl
roundTrip Kprim__cast_CharChar = Refl
roundTrip Kprim__cast_CharDouble = Refl
roundTrip Kprim__cast_CharPercentWorld = Refl
roundTrip Kprim__cast_DoubleInt = Refl
roundTrip Kprim__cast_DoubleInt8 = Refl
roundTrip Kprim__cast_DoubleInt16 = Refl
roundTrip Kprim__cast_DoubleInt32 = Refl
roundTrip Kprim__cast_DoubleInt64 = Refl
roundTrip Kprim__cast_DoubleInteger = Refl
roundTrip Kprim__cast_DoubleBits8 = Refl
roundTrip Kprim__cast_DoubleBits16 = Refl
roundTrip Kprim__cast_DoubleBits32 = Refl
roundTrip Kprim__cast_DoubleBits64 = Refl
roundTrip Kprim__cast_DoubleString = Refl
roundTrip Kprim__cast_DoubleChar = Refl
roundTrip Kprim__cast_DoubleDouble = Refl
roundTrip Kprim__cast_DoublePercentWorld = Refl
roundTrip Kprim__cast_PercentWorldInt = Refl
roundTrip Kprim__cast_PercentWorldInt8 = Refl
roundTrip Kprim__cast_PercentWorldInt16 = Refl
roundTrip Kprim__cast_PercentWorldInt32 = Refl
roundTrip Kprim__cast_PercentWorldInt64 = Refl
roundTrip Kprim__cast_PercentWorldInteger = Refl
roundTrip Kprim__cast_PercentWorldBits8 = Refl
roundTrip Kprim__cast_PercentWorldBits16 = Refl
roundTrip Kprim__cast_PercentWorldBits32 = Refl
roundTrip Kprim__cast_PercentWorldBits64 = Refl
roundTrip Kprim__cast_PercentWorldString = Refl
roundTrip Kprim__cast_PercentWorldChar = Refl
roundTrip Kprim__cast_PercentWorldDouble = Refl
roundTrip Kprim__cast_PercentWorldPercentWorld = Refl
roundTrip KInt = Refl
roundTrip KInt8 = Refl
roundTrip KInt16 = Refl
roundTrip KInt32 = Refl
roundTrip KInt64 = Refl
roundTrip KInteger = Refl
roundTrip KBits8 = Refl
roundTrip KBits16 = Refl
roundTrip KBits32 = Refl
roundTrip KBits64 = Refl
roundTrip KString = Refl
roundTrip KChar = Refl
roundTrip KDouble = Refl
roundTrip Ke = Refl
roundTrip Kcov = Refl
roundTrip KPercentWorld = Refl
roundTrip KfromInteger = Refl
roundTrip KfromDouble = Refl
roundTrip KProbeBinder = Refl
roundTrip KProbeHole = Refl
roundTrip KProbeHoleFound = Refl
roundTrip KProbeUnknown = Refl
roundTrip KProbeRuntime = Refl
roundTrip KProbeRuntimeAt = Refl
roundTrip KProbeField = Refl
roundTrip KProbePattern = Refl
roundTrip KProbeForm = Refl
roundTrip KProbeAxis = Refl
roundTrip KProbeAxisAt = Refl
roundTrip KProbeSize = Refl
roundTrip KProbeVar = Refl
roundTrip KProbeFormal = Refl
roundTrip KProbeHeld = Refl

||| Every ordinal is an id the table holds before any new text.
export
0 below : (k : Known) -> So (ordinal k < knownCount)
below KDollar = Oh
below KMinus = Oh
below KArrow = Oh
below KCons = Oh
below KCons1 = Oh
below KSnoc = Oh
below KAp = Oh
below KAutoMark = Oh
below KEquals = Oh
below KHomoEq = Oh
below KSeq = Oh
below KBindOp = Oh
below KApp = Oh
below KAutoImplicit = Oh
below KB16 = Oh
below KB32 = Oh
below KB64 = Oh
below KB8 = Oh
below KBI = Oh
below KBasic = Oh
below KBasics = Oh
below KBits16Type = Oh
below KBits32Type = Oh
below KBits64Type = Oh
below KBits8Type = Oh
below KBool = Oh
below KBound = Oh
below KBuiltin = Oh
below KBuiltinNatural = Oh
below KCOVERAGE = Oh
below KCaseBlock = Oh
below KCh = Oh
below KCharType = Oh
below KCoveringOnly = Oh
below KDN = Oh
below KDPair = Oh
below KData = Oh
below KDataCon = Oh
below KDb = Oh
below KDecl = Oh
below KDefImplicit = Oh
below KDefaultedValue = Oh
below KDeprecate = Oh
below KDoubleType = Oh
below KElab = Oh
below KEmptyFC = Oh
below KEqOrd = Oh
below KEqual = Oh
below KErased = Oh
below KErasedArg = Oh
below KExplicitArg = Oh
below KExport = Oh
below KExternFn = Oh
below KExternal = Oh
below KFalse = Oh
below KField = Oh
below KFirst = Oh
below KFirstSuccess = Oh
below KForeignExport = Oh
below KForeignFn = Oh
below KFunc = Oh
below KGlobalHint = Oh
below KHint = Oh
below KI = Oh
below KI16 = Oh
below KI32 = Oh
below KI64 = Oh
below KI8 = Oh
below KIAlternative = Oh
below KIApp = Oh
below KIAs = Oh
below KIAutoApp = Oh
below KIBindHere = Oh
below KIBindVar = Oh
below KICase = Oh
below KIClaim = Oh
below KIData = Oh
below KIDef = Oh
below KIDelay = Oh
below KIDelayed = Oh
below KIFail = Oh
below KIForce = Oh
below KIHole = Oh
below KILam = Oh
below KILet = Oh
below KILocal = Oh
below KILog = Oh
below KIMustUnify = Oh
below KINamedApp = Oh
below KINamespace = Oh
below KIO = Oh
below KIParameters = Oh
below KIPi = Oh
below KIPrimVal = Oh
below KIQuote = Oh
below KIQuoteDecl = Oh
below KIQuoteName = Oh
below KIRecord = Oh
below KIRewrite = Oh
below KISearch = Oh
below KISetField = Oh
below KISetFieldApp = Oh
below KITransform = Oh
below KIType = Oh
below KIUnquote = Oh
below KIUpdate = Oh
below KIVar = Oh
below KIWithApp = Oh
below KIWithUnambigNames = Oh
below KImplicit = Oh
below KImplicitArg = Oh
below KImpossibleClause = Oh
below KInline = Oh
below KInt16Type = Oh
below KInt32Type = Oh
below KInt64Type = Oh
below KInt8Type = Oh
below KIntType = Oh
below KIntegerToNatural = Oh
below KIntegerType = Oh
below KInteractive = Oh
below KInvertible = Oh
below KJust = Oh
below KLInf = Oh
below KLLazy = Oh
below KLUnknown = Oh
below KLam = Oh
below KLanguage = Oh
below KLater = Oh
below KLin = Oh
below KList = Oh
below KList1 = Oh
below KLocal = Oh
below KM0 = Oh
below KM1 = Oh
below KMN = Oh
below KMW = Oh
below KMacro = Oh
below KMain = Oh
below KMaybe = Oh
below KMkDPair = Oh
below KMkData = Oh
below KMkFC = Oh
below KMkFCVal = Oh
below KMkIClaimData = Oh
below KMkIField = Oh
below KMkLater = Oh
below KMkMI = Oh
below KMkNS = Oh
below KMkNameInfo = Oh
below KMkPair = Oh
below KMkRecord = Oh
below KMkTy = Oh
below KMkUnit = Oh
below KNONE = Oh
below KNS = Oh
below KName = Oh
below KNat = Oh
below KNaturalToInteger = Oh
below KNested = Oh
below KNil = Oh
below KNoHints = Oh
below KNoInline = Oh
below KNoNewtype = Oh
below KNonLinearVar = Oh
below KNotConstructor = Oh
below KNothing = Oh
below KNum = Oh
below KPATTERN = Oh
below KPI = Oh
below KPair = Oh
below KPartialOK = Oh
below KPatClause = Oh
below KPhysicalIdrSrc = Oh
below KPhysicalPkgSrc = Oh
below KPi = Oh
below KPrT = Oh
below KPrelude = Oh
below KPrimIO = Oh
below KPrimVal = Oh
below KPrivate = Oh
below KPublic = Oh
below KRef = Oh
below KRefl = Oh
below KReflection = Oh
below KS = Oh
below KSearchBy = Oh
below KSnocList = Oh
below KSpecArgs = Oh
below KSpecifiedValue = Oh
below KStr = Oh
below KStringType = Oh
below KSyntactic = Oh
below KTCInline = Oh
below KTDelay = Oh
below KTDelayed = Oh
below KTForce = Oh
below KTT = Oh
below KTTImp = Oh
below KTType = Oh
below KTotal = Oh
below KTotality = Oh
below KTrue = Oh
below KTyCon = Oh
below KType = Oh
below KTypes = Oh
below KUN = Oh
below KUnderAppliedCon = Oh
below KUnderscore = Oh
below KUnique = Oh
below KUniqueDefault = Oh
below KUniqueSearch = Oh
below KUnit = Oh
below KUnknownDot = Oh
below KUnsafe = Oh
below KUseLeft = Oh
below KUseRight = Oh
below KUserDotted = Oh
below KVarApplied = Oh
below KVirtual = Oh
below KWithBlock = Oh
below KWithClause = Oh
below KWorldType = Oh
below KWorldVal = Oh
below KZ = Oh
below KElabScript = Oh
below KForeign = Oh
below K_ = Oh
below K_PE = Oh
below K__ = Oh
below K__con = Oh
below K__infixTupleSection = Oh
below K__leftTupleSection = Oh
below K_cn = Oh
below Ka = Oh
below KaltTy = Oh
below Karg = Oh
below KargTy = Oh
below Kassert_smaller = Oh
below Kassert_total = Oh
below Kbelieve_me = Oh
below Kbind = Oh
below KcaseTy = Oh
below KconArg = Oh
below Kconcat = Oh
below Kconstraint = Oh
below Kconv = Oh
below Kcrash = Oh
below KdefArg = Oh
below KdelayTy = Oh
below Kdelayed = Oh
below KdotTm = Oh
below KdoubleACos = Oh
below KdoubleASin = Oh
below KdoubleATan = Oh
below KdoubleCeiling = Oh
below KdoubleCos = Oh
below KdoubleExp = Oh
below KdoubleFloor = Oh
below KdoubleLog = Oh
below KdoublePow = Oh
below KdoubleSin = Oh
below KdoubleSqrt = Oh
below KdoubleTan = Oh
below Kfvar = Oh
below Kguard = Oh
below Ki_con = Oh
below Kimp = Oh
below KimpArg = Oh
below Kimplicit_type = Oh
below Kinf = Oh
below Kinterpolate = Oh
below Klamc = Oh
below Klcase = Oh
below Km = Oh
below Kmain = Oh
below Knegate = Oh
below KpaRoot = Oh
below KpairFst = Oh
below KpairSnd = Oh
below Kpostpone = Oh
below Kpure = Oh
below Kq = Oh
below Kqv = Oh
below KrangeFrom = Oh
below KrangeFromThen = Oh
below KrangeFromThenTo = Oh
below KrangeFromTo = Oh
below Krec = Oh
below KretTy = Oh
below Krwarg = Oh
below Ksa = Oh
below Kscr = Oh
below KscriptTy = Oh
below Ksearch = Oh
below KsearchTy = Oh
below KstrAppend = Oh
below KstrCons = Oh
below KstrHead = Oh
below KstrIndex = Oh
below KstrLength = Oh
below KstrReverse = Oh
below KstrSubstr = Oh
below KstrTail = Oh
below Kt = Oh
below Ktmp = Oh
below Ktop = Oh
below Ku = Oh
below Kwarg = Oh
below Kx = Oh
below KHeteroEq = Oh
below Kprim__believe_me = Oh
below Kprim__crash = Oh
below Kidris_crash = Oh
below KElabAp = Oh
below KPure = Oh
below KMap = Oh
below KBind = Oh
below KFail = Oh
below KWarn = Oh
below KTry = Oh
below KLogMsg = Oh
below KLogTerm = Oh
below KLogSugaredTerm = Oh
below KResugarTerm = Oh
below KCheck = Oh
below KQuote = Oh
below KLambda = Oh
below KGoal = Oh
below KLocalVars = Oh
below KGenSym = Oh
below KInCurrentNS = Oh
below KGetType = Oh
below KGetInfo = Oh
below KGetVis = Oh
below KGetLocalType = Oh
below KGetCons = Oh
below KGetReferredFns = Oh
below KGetCurrentFn = Oh
below KGetFC = Oh
below KDeclare = Oh
below KReadFile = Oh
below KWriteFile = Oh
below KIdrisDir = Oh
below KProjectDir = Oh
below KSourceDir = Oh
below KCurrentModuleDir = Oh
below KSubmodulesDir = Oh
below KBuildDir = Oh
below Kb = Oh
below Kmsg = Oh
below Kprim__add_Int = Oh
below Kprim__add_Int8 = Oh
below Kprim__add_Int16 = Oh
below Kprim__add_Int32 = Oh
below Kprim__add_Int64 = Oh
below Kprim__add_Integer = Oh
below Kprim__add_Bits8 = Oh
below Kprim__add_Bits16 = Oh
below Kprim__add_Bits32 = Oh
below Kprim__add_Bits64 = Oh
below Kprim__add_String = Oh
below Kprim__add_Char = Oh
below Kprim__add_Double = Oh
below Kprim__add_PercentWorld = Oh
below Kprim__sub_Int = Oh
below Kprim__sub_Int8 = Oh
below Kprim__sub_Int16 = Oh
below Kprim__sub_Int32 = Oh
below Kprim__sub_Int64 = Oh
below Kprim__sub_Integer = Oh
below Kprim__sub_Bits8 = Oh
below Kprim__sub_Bits16 = Oh
below Kprim__sub_Bits32 = Oh
below Kprim__sub_Bits64 = Oh
below Kprim__sub_String = Oh
below Kprim__sub_Char = Oh
below Kprim__sub_Double = Oh
below Kprim__sub_PercentWorld = Oh
below Kprim__mul_Int = Oh
below Kprim__mul_Int8 = Oh
below Kprim__mul_Int16 = Oh
below Kprim__mul_Int32 = Oh
below Kprim__mul_Int64 = Oh
below Kprim__mul_Integer = Oh
below Kprim__mul_Bits8 = Oh
below Kprim__mul_Bits16 = Oh
below Kprim__mul_Bits32 = Oh
below Kprim__mul_Bits64 = Oh
below Kprim__mul_String = Oh
below Kprim__mul_Char = Oh
below Kprim__mul_Double = Oh
below Kprim__mul_PercentWorld = Oh
below Kprim__div_Int = Oh
below Kprim__div_Int8 = Oh
below Kprim__div_Int16 = Oh
below Kprim__div_Int32 = Oh
below Kprim__div_Int64 = Oh
below Kprim__div_Integer = Oh
below Kprim__div_Bits8 = Oh
below Kprim__div_Bits16 = Oh
below Kprim__div_Bits32 = Oh
below Kprim__div_Bits64 = Oh
below Kprim__div_String = Oh
below Kprim__div_Char = Oh
below Kprim__div_Double = Oh
below Kprim__div_PercentWorld = Oh
below Kprim__mod_Int = Oh
below Kprim__mod_Int8 = Oh
below Kprim__mod_Int16 = Oh
below Kprim__mod_Int32 = Oh
below Kprim__mod_Int64 = Oh
below Kprim__mod_Integer = Oh
below Kprim__mod_Bits8 = Oh
below Kprim__mod_Bits16 = Oh
below Kprim__mod_Bits32 = Oh
below Kprim__mod_Bits64 = Oh
below Kprim__mod_String = Oh
below Kprim__mod_Char = Oh
below Kprim__mod_Double = Oh
below Kprim__mod_PercentWorld = Oh
below Kprim__negate_Int = Oh
below Kprim__negate_Int8 = Oh
below Kprim__negate_Int16 = Oh
below Kprim__negate_Int32 = Oh
below Kprim__negate_Int64 = Oh
below Kprim__negate_Integer = Oh
below Kprim__negate_Bits8 = Oh
below Kprim__negate_Bits16 = Oh
below Kprim__negate_Bits32 = Oh
below Kprim__negate_Bits64 = Oh
below Kprim__negate_String = Oh
below Kprim__negate_Char = Oh
below Kprim__negate_Double = Oh
below Kprim__negate_PercentWorld = Oh
below Kprim__shl_Int = Oh
below Kprim__shl_Int8 = Oh
below Kprim__shl_Int16 = Oh
below Kprim__shl_Int32 = Oh
below Kprim__shl_Int64 = Oh
below Kprim__shl_Integer = Oh
below Kprim__shl_Bits8 = Oh
below Kprim__shl_Bits16 = Oh
below Kprim__shl_Bits32 = Oh
below Kprim__shl_Bits64 = Oh
below Kprim__shl_String = Oh
below Kprim__shl_Char = Oh
below Kprim__shl_Double = Oh
below Kprim__shl_PercentWorld = Oh
below Kprim__shr_Int = Oh
below Kprim__shr_Int8 = Oh
below Kprim__shr_Int16 = Oh
below Kprim__shr_Int32 = Oh
below Kprim__shr_Int64 = Oh
below Kprim__shr_Integer = Oh
below Kprim__shr_Bits8 = Oh
below Kprim__shr_Bits16 = Oh
below Kprim__shr_Bits32 = Oh
below Kprim__shr_Bits64 = Oh
below Kprim__shr_String = Oh
below Kprim__shr_Char = Oh
below Kprim__shr_Double = Oh
below Kprim__shr_PercentWorld = Oh
below Kprim__and_Int = Oh
below Kprim__and_Int8 = Oh
below Kprim__and_Int16 = Oh
below Kprim__and_Int32 = Oh
below Kprim__and_Int64 = Oh
below Kprim__and_Integer = Oh
below Kprim__and_Bits8 = Oh
below Kprim__and_Bits16 = Oh
below Kprim__and_Bits32 = Oh
below Kprim__and_Bits64 = Oh
below Kprim__and_String = Oh
below Kprim__and_Char = Oh
below Kprim__and_Double = Oh
below Kprim__and_PercentWorld = Oh
below Kprim__or_Int = Oh
below Kprim__or_Int8 = Oh
below Kprim__or_Int16 = Oh
below Kprim__or_Int32 = Oh
below Kprim__or_Int64 = Oh
below Kprim__or_Integer = Oh
below Kprim__or_Bits8 = Oh
below Kprim__or_Bits16 = Oh
below Kprim__or_Bits32 = Oh
below Kprim__or_Bits64 = Oh
below Kprim__or_String = Oh
below Kprim__or_Char = Oh
below Kprim__or_Double = Oh
below Kprim__or_PercentWorld = Oh
below Kprim__xor_Int = Oh
below Kprim__xor_Int8 = Oh
below Kprim__xor_Int16 = Oh
below Kprim__xor_Int32 = Oh
below Kprim__xor_Int64 = Oh
below Kprim__xor_Integer = Oh
below Kprim__xor_Bits8 = Oh
below Kprim__xor_Bits16 = Oh
below Kprim__xor_Bits32 = Oh
below Kprim__xor_Bits64 = Oh
below Kprim__xor_String = Oh
below Kprim__xor_Char = Oh
below Kprim__xor_Double = Oh
below Kprim__xor_PercentWorld = Oh
below Kprim__lt_Int = Oh
below Kprim__lt_Int8 = Oh
below Kprim__lt_Int16 = Oh
below Kprim__lt_Int32 = Oh
below Kprim__lt_Int64 = Oh
below Kprim__lt_Integer = Oh
below Kprim__lt_Bits8 = Oh
below Kprim__lt_Bits16 = Oh
below Kprim__lt_Bits32 = Oh
below Kprim__lt_Bits64 = Oh
below Kprim__lt_String = Oh
below Kprim__lt_Char = Oh
below Kprim__lt_Double = Oh
below Kprim__lt_PercentWorld = Oh
below Kprim__lte_Int = Oh
below Kprim__lte_Int8 = Oh
below Kprim__lte_Int16 = Oh
below Kprim__lte_Int32 = Oh
below Kprim__lte_Int64 = Oh
below Kprim__lte_Integer = Oh
below Kprim__lte_Bits8 = Oh
below Kprim__lte_Bits16 = Oh
below Kprim__lte_Bits32 = Oh
below Kprim__lte_Bits64 = Oh
below Kprim__lte_String = Oh
below Kprim__lte_Char = Oh
below Kprim__lte_Double = Oh
below Kprim__lte_PercentWorld = Oh
below Kprim__eq_Int = Oh
below Kprim__eq_Int8 = Oh
below Kprim__eq_Int16 = Oh
below Kprim__eq_Int32 = Oh
below Kprim__eq_Int64 = Oh
below Kprim__eq_Integer = Oh
below Kprim__eq_Bits8 = Oh
below Kprim__eq_Bits16 = Oh
below Kprim__eq_Bits32 = Oh
below Kprim__eq_Bits64 = Oh
below Kprim__eq_String = Oh
below Kprim__eq_Char = Oh
below Kprim__eq_Double = Oh
below Kprim__eq_PercentWorld = Oh
below Kprim__gte_Int = Oh
below Kprim__gte_Int8 = Oh
below Kprim__gte_Int16 = Oh
below Kprim__gte_Int32 = Oh
below Kprim__gte_Int64 = Oh
below Kprim__gte_Integer = Oh
below Kprim__gte_Bits8 = Oh
below Kprim__gte_Bits16 = Oh
below Kprim__gte_Bits32 = Oh
below Kprim__gte_Bits64 = Oh
below Kprim__gte_String = Oh
below Kprim__gte_Char = Oh
below Kprim__gte_Double = Oh
below Kprim__gte_PercentWorld = Oh
below Kprim__gt_Int = Oh
below Kprim__gt_Int8 = Oh
below Kprim__gt_Int16 = Oh
below Kprim__gt_Int32 = Oh
below Kprim__gt_Int64 = Oh
below Kprim__gt_Integer = Oh
below Kprim__gt_Bits8 = Oh
below Kprim__gt_Bits16 = Oh
below Kprim__gt_Bits32 = Oh
below Kprim__gt_Bits64 = Oh
below Kprim__gt_String = Oh
below Kprim__gt_Char = Oh
below Kprim__gt_Double = Oh
below Kprim__gt_PercentWorld = Oh
below Kprim__strLength = Oh
below Kprim__strHead = Oh
below Kprim__strTail = Oh
below Kprim__strIndex = Oh
below Kprim__strCons = Oh
below Kprim__strAppend = Oh
below Kprim__strReverse = Oh
below Kprim__strSubstr = Oh
below Kprim__doubleExp = Oh
below Kprim__doubleLog = Oh
below Kprim__doublePow = Oh
below Kprim__doubleSin = Oh
below Kprim__doubleCos = Oh
below Kprim__doubleTan = Oh
below Kprim__doubleASin = Oh
below Kprim__doubleACos = Oh
below Kprim__doubleATan = Oh
below Kprim__doubleSqrt = Oh
below Kprim__doubleFloor = Oh
below Kprim__doubleCeiling = Oh
below Kprim__cast_IntInt = Oh
below Kprim__cast_IntInt8 = Oh
below Kprim__cast_IntInt16 = Oh
below Kprim__cast_IntInt32 = Oh
below Kprim__cast_IntInt64 = Oh
below Kprim__cast_IntInteger = Oh
below Kprim__cast_IntBits8 = Oh
below Kprim__cast_IntBits16 = Oh
below Kprim__cast_IntBits32 = Oh
below Kprim__cast_IntBits64 = Oh
below Kprim__cast_IntString = Oh
below Kprim__cast_IntChar = Oh
below Kprim__cast_IntDouble = Oh
below Kprim__cast_IntPercentWorld = Oh
below Kprim__cast_Int8Int = Oh
below Kprim__cast_Int8Int8 = Oh
below Kprim__cast_Int8Int16 = Oh
below Kprim__cast_Int8Int32 = Oh
below Kprim__cast_Int8Int64 = Oh
below Kprim__cast_Int8Integer = Oh
below Kprim__cast_Int8Bits8 = Oh
below Kprim__cast_Int8Bits16 = Oh
below Kprim__cast_Int8Bits32 = Oh
below Kprim__cast_Int8Bits64 = Oh
below Kprim__cast_Int8String = Oh
below Kprim__cast_Int8Char = Oh
below Kprim__cast_Int8Double = Oh
below Kprim__cast_Int8PercentWorld = Oh
below Kprim__cast_Int16Int = Oh
below Kprim__cast_Int16Int8 = Oh
below Kprim__cast_Int16Int16 = Oh
below Kprim__cast_Int16Int32 = Oh
below Kprim__cast_Int16Int64 = Oh
below Kprim__cast_Int16Integer = Oh
below Kprim__cast_Int16Bits8 = Oh
below Kprim__cast_Int16Bits16 = Oh
below Kprim__cast_Int16Bits32 = Oh
below Kprim__cast_Int16Bits64 = Oh
below Kprim__cast_Int16String = Oh
below Kprim__cast_Int16Char = Oh
below Kprim__cast_Int16Double = Oh
below Kprim__cast_Int16PercentWorld = Oh
below Kprim__cast_Int32Int = Oh
below Kprim__cast_Int32Int8 = Oh
below Kprim__cast_Int32Int16 = Oh
below Kprim__cast_Int32Int32 = Oh
below Kprim__cast_Int32Int64 = Oh
below Kprim__cast_Int32Integer = Oh
below Kprim__cast_Int32Bits8 = Oh
below Kprim__cast_Int32Bits16 = Oh
below Kprim__cast_Int32Bits32 = Oh
below Kprim__cast_Int32Bits64 = Oh
below Kprim__cast_Int32String = Oh
below Kprim__cast_Int32Char = Oh
below Kprim__cast_Int32Double = Oh
below Kprim__cast_Int32PercentWorld = Oh
below Kprim__cast_Int64Int = Oh
below Kprim__cast_Int64Int8 = Oh
below Kprim__cast_Int64Int16 = Oh
below Kprim__cast_Int64Int32 = Oh
below Kprim__cast_Int64Int64 = Oh
below Kprim__cast_Int64Integer = Oh
below Kprim__cast_Int64Bits8 = Oh
below Kprim__cast_Int64Bits16 = Oh
below Kprim__cast_Int64Bits32 = Oh
below Kprim__cast_Int64Bits64 = Oh
below Kprim__cast_Int64String = Oh
below Kprim__cast_Int64Char = Oh
below Kprim__cast_Int64Double = Oh
below Kprim__cast_Int64PercentWorld = Oh
below Kprim__cast_IntegerInt = Oh
below Kprim__cast_IntegerInt8 = Oh
below Kprim__cast_IntegerInt16 = Oh
below Kprim__cast_IntegerInt32 = Oh
below Kprim__cast_IntegerInt64 = Oh
below Kprim__cast_IntegerInteger = Oh
below Kprim__cast_IntegerBits8 = Oh
below Kprim__cast_IntegerBits16 = Oh
below Kprim__cast_IntegerBits32 = Oh
below Kprim__cast_IntegerBits64 = Oh
below Kprim__cast_IntegerString = Oh
below Kprim__cast_IntegerChar = Oh
below Kprim__cast_IntegerDouble = Oh
below Kprim__cast_IntegerPercentWorld = Oh
below Kprim__cast_Bits8Int = Oh
below Kprim__cast_Bits8Int8 = Oh
below Kprim__cast_Bits8Int16 = Oh
below Kprim__cast_Bits8Int32 = Oh
below Kprim__cast_Bits8Int64 = Oh
below Kprim__cast_Bits8Integer = Oh
below Kprim__cast_Bits8Bits8 = Oh
below Kprim__cast_Bits8Bits16 = Oh
below Kprim__cast_Bits8Bits32 = Oh
below Kprim__cast_Bits8Bits64 = Oh
below Kprim__cast_Bits8String = Oh
below Kprim__cast_Bits8Char = Oh
below Kprim__cast_Bits8Double = Oh
below Kprim__cast_Bits8PercentWorld = Oh
below Kprim__cast_Bits16Int = Oh
below Kprim__cast_Bits16Int8 = Oh
below Kprim__cast_Bits16Int16 = Oh
below Kprim__cast_Bits16Int32 = Oh
below Kprim__cast_Bits16Int64 = Oh
below Kprim__cast_Bits16Integer = Oh
below Kprim__cast_Bits16Bits8 = Oh
below Kprim__cast_Bits16Bits16 = Oh
below Kprim__cast_Bits16Bits32 = Oh
below Kprim__cast_Bits16Bits64 = Oh
below Kprim__cast_Bits16String = Oh
below Kprim__cast_Bits16Char = Oh
below Kprim__cast_Bits16Double = Oh
below Kprim__cast_Bits16PercentWorld = Oh
below Kprim__cast_Bits32Int = Oh
below Kprim__cast_Bits32Int8 = Oh
below Kprim__cast_Bits32Int16 = Oh
below Kprim__cast_Bits32Int32 = Oh
below Kprim__cast_Bits32Int64 = Oh
below Kprim__cast_Bits32Integer = Oh
below Kprim__cast_Bits32Bits8 = Oh
below Kprim__cast_Bits32Bits16 = Oh
below Kprim__cast_Bits32Bits32 = Oh
below Kprim__cast_Bits32Bits64 = Oh
below Kprim__cast_Bits32String = Oh
below Kprim__cast_Bits32Char = Oh
below Kprim__cast_Bits32Double = Oh
below Kprim__cast_Bits32PercentWorld = Oh
below Kprim__cast_Bits64Int = Oh
below Kprim__cast_Bits64Int8 = Oh
below Kprim__cast_Bits64Int16 = Oh
below Kprim__cast_Bits64Int32 = Oh
below Kprim__cast_Bits64Int64 = Oh
below Kprim__cast_Bits64Integer = Oh
below Kprim__cast_Bits64Bits8 = Oh
below Kprim__cast_Bits64Bits16 = Oh
below Kprim__cast_Bits64Bits32 = Oh
below Kprim__cast_Bits64Bits64 = Oh
below Kprim__cast_Bits64String = Oh
below Kprim__cast_Bits64Char = Oh
below Kprim__cast_Bits64Double = Oh
below Kprim__cast_Bits64PercentWorld = Oh
below Kprim__cast_StringInt = Oh
below Kprim__cast_StringInt8 = Oh
below Kprim__cast_StringInt16 = Oh
below Kprim__cast_StringInt32 = Oh
below Kprim__cast_StringInt64 = Oh
below Kprim__cast_StringInteger = Oh
below Kprim__cast_StringBits8 = Oh
below Kprim__cast_StringBits16 = Oh
below Kprim__cast_StringBits32 = Oh
below Kprim__cast_StringBits64 = Oh
below Kprim__cast_StringString = Oh
below Kprim__cast_StringChar = Oh
below Kprim__cast_StringDouble = Oh
below Kprim__cast_StringPercentWorld = Oh
below Kprim__cast_CharInt = Oh
below Kprim__cast_CharInt8 = Oh
below Kprim__cast_CharInt16 = Oh
below Kprim__cast_CharInt32 = Oh
below Kprim__cast_CharInt64 = Oh
below Kprim__cast_CharInteger = Oh
below Kprim__cast_CharBits8 = Oh
below Kprim__cast_CharBits16 = Oh
below Kprim__cast_CharBits32 = Oh
below Kprim__cast_CharBits64 = Oh
below Kprim__cast_CharString = Oh
below Kprim__cast_CharChar = Oh
below Kprim__cast_CharDouble = Oh
below Kprim__cast_CharPercentWorld = Oh
below Kprim__cast_DoubleInt = Oh
below Kprim__cast_DoubleInt8 = Oh
below Kprim__cast_DoubleInt16 = Oh
below Kprim__cast_DoubleInt32 = Oh
below Kprim__cast_DoubleInt64 = Oh
below Kprim__cast_DoubleInteger = Oh
below Kprim__cast_DoubleBits8 = Oh
below Kprim__cast_DoubleBits16 = Oh
below Kprim__cast_DoubleBits32 = Oh
below Kprim__cast_DoubleBits64 = Oh
below Kprim__cast_DoubleString = Oh
below Kprim__cast_DoubleChar = Oh
below Kprim__cast_DoubleDouble = Oh
below Kprim__cast_DoublePercentWorld = Oh
below Kprim__cast_PercentWorldInt = Oh
below Kprim__cast_PercentWorldInt8 = Oh
below Kprim__cast_PercentWorldInt16 = Oh
below Kprim__cast_PercentWorldInt32 = Oh
below Kprim__cast_PercentWorldInt64 = Oh
below Kprim__cast_PercentWorldInteger = Oh
below Kprim__cast_PercentWorldBits8 = Oh
below Kprim__cast_PercentWorldBits16 = Oh
below Kprim__cast_PercentWorldBits32 = Oh
below Kprim__cast_PercentWorldBits64 = Oh
below Kprim__cast_PercentWorldString = Oh
below Kprim__cast_PercentWorldChar = Oh
below Kprim__cast_PercentWorldDouble = Oh
below Kprim__cast_PercentWorldPercentWorld = Oh
below KInt = Oh
below KInt8 = Oh
below KInt16 = Oh
below KInt32 = Oh
below KInt64 = Oh
below KInteger = Oh
below KBits8 = Oh
below KBits16 = Oh
below KBits32 = Oh
below KBits64 = Oh
below KString = Oh
below KChar = Oh
below KDouble = Oh
below Ke = Oh
below Kcov = Oh
below KPercentWorld = Oh
below KfromInteger = Oh
below KfromDouble = Oh
below KProbeBinder = Oh
below KProbeHole = Oh
below KProbeHoleFound = Oh
below KProbeUnknown = Oh
below KProbeRuntime = Oh
below KProbeRuntimeAt = Oh
below KProbeField = Oh
below KProbePattern = Oh
below KProbeForm = Oh
below KProbeAxis = Oh
below KProbeAxisAt = Oh
below KProbeSize = Oh
below KProbeVar = Oh
below KProbeFormal = Oh
below KProbeHeld = Oh
