module TTImp.TTImp.Functor

import Core.TT
import Core.WithData
import TTImp.TTImp

%default covering

-- Each map is a function of its own, recursive through the others, and
-- each `Functor` is that function: a `map` inside an implementation would
-- be the implementation itself, which then reaches its own method at
-- types it is given rather than its own.
mutual
  export
  mapRawImp : (a -> b) -> RawImp' a -> RawImp' b
  mapRawImp f (IVar fc nm) = IVar fc (f nm)
  mapRawImp f (IPi fc rig info nm a sc)
    = IPi fc rig (map (mapRawImp f) info) nm (mapRawImp f a) (mapRawImp f sc)
  mapRawImp f (ILam fc rig info nm a sc)
    = ILam fc rig (map (mapRawImp f) info) nm (mapRawImp f a) (mapRawImp f sc)
  mapRawImp f (ILet fc lhsFC rig nm ty val sc)
    = ILet fc lhsFC rig nm (mapRawImp f ty) (mapRawImp f val) (mapRawImp f sc)
  mapRawImp f (ICase fc opts sc ty cls)
    = ICase fc (map (mapFnOpt f) opts) (mapRawImp f sc) (mapRawImp f ty) (map (mapClause f) cls)
  mapRawImp f (ILocal fc ds sc)
    = ILocal fc (map (mapDecl f) ds) (mapRawImp f sc)
  mapRawImp f (ICaseLocal fc userN intN args sc)
    = ICaseLocal fc userN intN args (mapRawImp f sc)
  mapRawImp f (IUpdate fc upds rec)
    = IUpdate fc (map (mapFieldUpdate f) upds) (mapRawImp f rec)
  mapRawImp f (IApp fc fn t)
    = IApp fc (mapRawImp f fn) (mapRawImp f t)
  mapRawImp f (IAutoApp fc fn t)
    = IAutoApp fc (mapRawImp f fn) (mapRawImp f t)
  mapRawImp f (INamedApp fc fn nm t)
    = INamedApp fc (mapRawImp f fn) nm (mapRawImp f t)
  mapRawImp f (IWithApp fc fn t)
    = IWithApp fc (mapRawImp f fn) (mapRawImp f t)
  mapRawImp f (ISearch fc n)
    = ISearch fc n
  mapRawImp f (IAlternative fc alt ts)
    = IAlternative fc (mapAltType f alt) (map (mapRawImp f) ts)
  mapRawImp f (IRewrite fc e t)
    = IRewrite fc (mapRawImp f e) (mapRawImp f t)
  mapRawImp f (ICoerced fc e)
    = ICoerced fc (mapRawImp f e)
  mapRawImp f (IBindHere fc bd t)
    = IBindHere fc bd (mapRawImp f t)
  mapRawImp f (IBindVar fc str)
    = IBindVar fc str
  mapRawImp f (IAs fc nmFC side nm t)
    = IAs fc nmFC side nm (mapRawImp f t)
  mapRawImp f (IMustUnify fc reason t)
    = IMustUnify fc reason (mapRawImp f t)
  mapRawImp f (IDelayed fc reason t)
    = IDelayed fc reason (mapRawImp f t)
  mapRawImp f (IDelay fc t)
    = IDelay fc (mapRawImp f t)
  mapRawImp f (IForce fc t)
    = IForce fc (mapRawImp f t)
  mapRawImp f (IQuote fc t)
    = IQuote fc (mapRawImp f t)
  mapRawImp f (IQuoteName fc nm)
    = IQuoteName fc nm
  mapRawImp f (IQuoteDecl fc ds)
    = IQuoteDecl fc (map (mapDecl f) ds)
  mapRawImp f (IUnquote fc t)
    = IUnquote fc (mapRawImp f t)
  mapRawImp f (IRunElab fc re t)
    = IRunElab fc re (mapRawImp f t)
  mapRawImp f (IPrimVal fc c)
    = IPrimVal fc c
  mapRawImp f (IType fc)
    = IType fc
  mapRawImp f (IHole fc str)
    = IHole fc str
  mapRawImp f (IUnifyLog fc lvl t)
    = IUnifyLog fc lvl (mapRawImp f t)
  mapRawImp f (Implicit fc b)
    = Implicit fc b
  mapRawImp f (IWithUnambigNames fc ns t)
    = IWithUnambigNames fc ns (mapRawImp f t)

  export
  mapClause : (a -> b) -> ImpClause' a -> ImpClause' b
  mapClause f (PatClause fc lhs rhs)
    = PatClause fc (mapRawImp f lhs) (mapRawImp f rhs)
  mapClause f (WithClause fc lhs rig wval prf flags xs)
    = WithClause fc (mapRawImp f lhs) rig (mapRawImp f wval) prf flags (map (mapClause f) xs)
  mapClause f (ImpossibleClause fc lhs)
    = ImpossibleClause fc (mapRawImp f lhs)

  export
  mapClaim : (a -> b) -> IClaimData a -> IClaimData b
  mapClaim f (MkIClaimData rig vis opts ty)
    = MkIClaimData rig vis (map (mapFnOpt f) opts) (map (mapRawImp f) ty)

  export
  mapDecl : (a -> b) -> ImpDecl' a -> ImpDecl' b
  mapDecl f (IClaim c)
    = IClaim (map (mapClaim f) c)
  mapDecl f (IData fc vis mbtot dt)
    = IData fc vis mbtot (mapData f dt)
  mapDecl f (IDef fc nm cls)
    = IDef fc nm (map (mapClause f) cls)
  mapDecl f (IParameters fc ps ds)
    = IParameters fc (map (map (map (mapRawImp f))) ps) (map (mapDecl f) ds)
  mapDecl f (IRecord fc cs vis mbtot rec)
    = IRecord fc cs vis mbtot (map (mapRecord f) rec)
  mapDecl f (IFail fc msg ds)
    = IFail fc msg (map (mapDecl f) ds)
  mapDecl f (INamespace fc ns ds)
    = INamespace fc ns (map (mapDecl f) ds)
  mapDecl f (ITransform fc n lhs rhs)
    = ITransform fc n (mapRawImp f lhs) (mapRawImp f rhs)
  mapDecl f (IRunElabDecl fc t)
    = IRunElabDecl fc (mapRawImp f t)
  mapDecl f (IPragma fc xs k) = IPragma fc xs k
  mapDecl f (ILog x) = ILog x
  mapDecl f (IBuiltin fc ty n) = IBuiltin fc ty n

  export
  mapFnOpt : (a -> b) -> FnOpt' a -> FnOpt' b
  mapFnOpt f Unsafe = Unsafe
  mapFnOpt f Inline = Inline
  mapFnOpt f NoInline = NoInline
  mapFnOpt f Deprecate = Deprecate
  mapFnOpt f TCInline = TCInline
  mapFnOpt f (Hint b) = Hint b
  mapFnOpt f (GlobalHint b) = GlobalHint b
  mapFnOpt f ExternFn = ExternFn
  mapFnOpt f (ForeignFn ts) = ForeignFn (map (mapRawImp f) ts)
  mapFnOpt f (ForeignExport ts) = ForeignExport (map (mapRawImp f) ts)
  mapFnOpt f Invertible = Invertible
  mapFnOpt f (Totality tot) = Totality tot
  mapFnOpt f Macro = Macro
  mapFnOpt f (SpecArgs ns) = SpecArgs ns

  export
  mapData : (a -> b) -> ImpData' a -> ImpData' b
  mapData f (MkImpData fc n tycon opts datacons)
    = MkImpData fc n (map (mapRawImp f) tycon) opts (map (map (mapRawImp f)) datacons)
  mapData f (MkImpLater fc n tycon)
    = MkImpLater fc n (mapRawImp f tycon)

  export
  mapRecord : (a -> b) -> ImpRecordData a -> ImpRecordData b
  mapRecord f (MkImpRecord header body)
    = MkImpRecord (map (map (map (map (mapRawImp f)))) header)
                  (map (map (map (map (mapRawImp f)))) body)

  export
  mapFieldUpdate : (a -> b) -> IFieldUpdate' a -> IFieldUpdate' b
  mapFieldUpdate f (ISetField path t) = ISetField path (mapRawImp f t)
  mapFieldUpdate f (ISetFieldApp path t) = ISetFieldApp path (mapRawImp f t)

  export
  mapAltType : (a -> b) -> AltType' a -> AltType' b
  mapAltType f FirstSuccess = FirstSuccess
  mapAltType f Unique = Unique
  mapAltType f (UniqueDefault t) = UniqueDefault (mapRawImp f t)

export
Functor RawImp' where
  map = mapRawImp

export
Functor ImpClause' where
  map = mapClause

export
Functor IClaimData where
  map = mapClaim

export
Functor ImpDecl' where
  map = mapDecl

export
Functor FnOpt' where
  map = mapFnOpt

export
Functor ImpData' where
  map = mapData

export
Functor ImpRecordData where
  map = mapRecord

export
Functor IFieldUpdate' where
  map = mapFieldUpdate

export
Functor AltType' where
  map = mapAltType
