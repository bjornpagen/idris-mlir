||| The checks of full Core after `Translate` (CORE-CHECK-1). Scoping holds by
||| construction (`Term n`); what is left is that references resolve and that
||| calls, constructors and alternatives have the right number of arguments.
module IdrisMLIR.Term.Check

import IdrisMLIR.Ids
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.SortedMap

%default covering

public export
Err : Type
Err = (Rule, String)

record Ix where
  constructor MkIx
  fns : SortedMap FnId Nat
  datas : SortedMap DataId Data
  cons : SortedMap ConId Con

require : Bool -> Rule -> String -> Either Err ()
require ok r msg = unless ok (Left (r, msg))

mutual
  term : Ix -> Term n -> Either Err ()
  term ix (PrimApp _ op as) = do
    require (length as == length (opArgs op)) CoreInv2 (show op ++ " with " ++ show (length as) ++ " arguments")
    traverse_ (term ix) as
  term ix (Effect _ op as res) = do
    require (isJust (lookup res ix.datas)) CoreInv3 ("unknown IO result " ++ show res)
    require (length as == S (length (ioArgs op))) CoreInv2 ("io." ++ show op ++ " with the wrong arguments")
    traverse_ (term ix) as
  term ix (Call _ f as) = do
    Just arity <- pure (lookup f ix.fns)
      | Nothing => Left (CoreInv2, "call of unknown function " ++ show f)
    require (length as == arity) CoreInv2 ("call of " ++ show f ++ " with " ++ show (length as) ++ " arguments")
    traverse_ (term ix) as
  term ix (ConApp _ c as) = do
    Just con <- pure (lookup c ix.cons)
      | Nothing => Left (CoreInv2, "unknown constructor " ++ show c)
    require (length as == length con.fields) CoreInv2 ("constructor " ++ show c ++ " with " ++ show (length as) ++ " arguments")
    traverse_ (term ix) as
  term ix (Let _ _ v b) = term ix v >> term ix b
  term ix (Case _ _ alts d) = do
    for_ alts $ \(MkAlt c bs body) => do
      Just con <- pure (lookup c ix.cons)
        | Nothing => Left (CoreInv6, "unknown constructor " ++ show c)
      require (length bs == length con.fields) CoreInv6 ("alternative " ++ show c ++ " binds the wrong number of fields")
      term ix body
    traverse_ (term ix) d
  term ix (CaseLit _ _ alts d) = traverse_ (term ix . snd) alts >> term ix d
  term ix (Lam _ _ _ _ body) = term ix body
  term ix (App _ f a) = term ix f >> term ix a
  term ix (Suspend _ _ _ body) = term ix body
  term ix (Resume _ e) = term ix e
  term ix _ = pure ()

||| The full-Core checks (CORE-CHECK-1), after `Translate`.
export
checkSource : Source -> Either Err ()
checkSource src = do
  let ix = MkIx (fromList [(f.id, f.arity) | f <- src.fns])
                (fromList [(d.id, d) | d <- src.datas])
                (fromList [(c.id, c) | d <- src.datas, c <- d.cons])
  require (isJust (lookup src.root ix.fns)) CoreInv8 "the root is missing"
  for_ src.fns $ \f => mapFst (\(r, m) => (r, show f.id ++ ": " ++ m)) (term ix f.body)
