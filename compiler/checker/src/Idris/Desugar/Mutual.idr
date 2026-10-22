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
-- Everything else on the second pass
getDecl : Pass -> PDecl-> Maybe PDecl
getDecl p (MkFCVal fc $ PImplementation vis opts _ is cons n ps iname nusing ds)
    = Just (MkFCVal fc $ PImplementation vis opts p is cons n ps iname nusing ds)

getDecl p (MkFCVal fc $ PNamespace ns ds)
    = Just (MkFCVal fc $ PNamespace ns (assert_total $ mapMaybe (getDecl p) ds))

getDecl AsType d@(MkFCVal _ $ PClaim _) = Just d
getDecl AsType (MkFCVal fc $ PData doc vis mbtot (MkPData dfc tyn (Just tyc) _ _))
    = Just (MkFCVal fc $ PData doc vis mbtot (MkPLater dfc tyn tyc))
getDecl AsType d@(MkFCVal _ $ PInterface {}) = Just d
getDecl AsType d@(MkFCVal fc $ PRecord doc vis mbtot (MkPRecord n ps _ _ _))
    = Just (MkFCVal fc $ PData doc vis mbtot (MkPLater d.fc n (mkRecType ps)))
  where
    mkRecType : List PBinder -> PTerm
    mkRecType [] = PType d.fc
    mkRecType (MkPBinder p (MkBasicMultiBinder c (n ::: []) t) :: ts)
      = PPi d.fc c p (Just n.val) t (mkRecType ts)
    mkRecType (MkPBinder p (MkBasicMultiBinder c (n ::: x :: xs) t) :: ts)
      = PPi d.fc c p (Just n.val) t
          (assert_total $ mkRecType (MkPBinder p (MkBasicMultiBinder c (x ::: xs) t) :: ts))
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
    = Just (MkFCVal fc $ PParameters ps (assert_total $ mapMaybe (getDecl p) pds))
getDecl p (MkFCVal fc $ PUsing ps pds)
    = Just (MkFCVal fc $ PUsing ps (assert_total $ mapMaybe (getDecl p) pds))

getDecl Single d = Just d

export
splitMutual : List PDecl -> (List PDecl, List PDecl)
splitMutual ds = (mapMaybe (getDecl AsType) ds, mapMaybe (getDecl AsDef) ds)
