-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Desugar.Mutual

import Idris.Syntax
import TTImp.TTImp

%default total

-- Get the declaration to process on each pass of a mutual block
-- Essentially: types on the first pass
--  i.e. type constructors of data declarations
--       function types
--       interfaces (in full, since it includes function types)
--       records (just the generated type constructor)
--       implementation headers (i.e. note their existence, but not the bodies)
-- Everything else on the second pass.
-- The declarations a declaration holds are walked by getDecls rather than
-- by `mapMaybe`, so that each recursive call is on a part of the
-- declaration it was given.
mutual
  getDecl : Pass -> PDecl-> Maybe PDecl
  getDecl p (MkFCVal fc $ PImplementation vis opts _ is cons n ps iname nusing ds)
      = Just (MkFCVal fc $ PImplementation vis opts p is cons n ps iname nusing ds)

  getDecl p (MkFCVal fc $ PNamespace ns ds)
      = Just (MkFCVal fc $ PNamespace ns (getDecls p ds))

  getDecl AsType d@(MkFCVal _ $ PClaim _) = Just d
  getDecl AsType (MkFCVal fc $ PData doc vis mbtot (MkPData dfc tyn (Just tyc) _ _))
      = Just (MkFCVal fc $ PData doc vis mbtot (MkPLater dfc tyn tyc))
  getDecl AsType d@(MkFCVal _ $ PInterface {}) = Just d
  getDecl AsType d@(MkFCVal fc $ PRecord doc vis mbtot (MkPRecord n ps _ _ _))
      = Just (MkFCVal fc $ PData doc vis mbtot (MkPLater d.fc n (mkRecType ps)))
    where
      -- Each name a binder gives one type is a Pi of its own, in order.
      piNames : PiInfo PTerm -> RigCount -> WithFC Name -> List (WithFC Name) ->
                PTerm -> PTerm -> PTerm
      piNames info rig n [] t sc = PPi d.fc rig info (Just n.val) t sc
      piNames info rig n (n' :: ns) t sc
        = PPi d.fc rig info (Just n.val) t (piNames info rig n' ns t sc)

      mkRecType : List PBinder -> PTerm
      mkRecType [] = PType d.fc
      mkRecType (MkPBinder info (MkBasicMultiBinder rig (n ::: ns) t) :: ts)
        = piNames info rig n ns t (mkRecType ts)
  getDecl AsType d@(MkFCVal _ $ PFixity _ ) = Just d
  getDecl AsType d@(MkFCVal _ $ PDirective _) = Just d
  getDecl AsType d = Nothing

  getDecl AsDef (MkFCVal _ $ PClaim _) = Nothing
  getDecl AsDef d@(MkFCVal _ $ PData _ _ _ (MkPLater {})) = Just d
  getDecl AsDef (MkFCVal _ $ PInterface {}) = Nothing
  getDecl AsDef d@(MkFCVal _ $ PRecord _ _ _ (MkPRecordLater {})) = Just d
  getDecl AsDef (MkFCVal _ $ PFixity _ ) = Nothing
  getDecl AsDef (MkFCVal _ $ PDirective _) = Nothing
  getDecl AsDef d = Just d

  getDecl p (MkFCVal fc $ PParameters ps pds)
      = Just (MkFCVal fc $ PParameters ps (getDecls p pds))
  getDecl p (MkFCVal fc $ PUsing ps pds)
      = Just (MkFCVal fc $ PUsing ps (getDecls p pds))

  getDecl Single d = Just d

  getDecls : Pass -> List PDecl -> List PDecl
  getDecls p [] = []
  getDecls p (d :: ds) = case getDecl p d of
                              Just d' => d' :: getDecls p ds
                              Nothing => getDecls p ds

export
splitMutual : List PDecl -> (List PDecl, List PDecl)
splitMutual ds = (mapMaybe (getDecl AsType) ds, mapMaybe (getDecl AsDef) ds)
