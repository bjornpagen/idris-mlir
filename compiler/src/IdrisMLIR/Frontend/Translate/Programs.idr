||| Function instances and programs: each instance requested is translated
||| in turn, and the program is assembled with each data instance's
||| representation.
module IdrisMLIR.Frontend.Translate.Programs

import Core.Context
import Core.Core
import Core.TT
import Core.Termination

import IdrisMLIR.Facts
import IdrisMLIR.Frontend.Translate.Cases
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Graph
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default covering

||| Idris's termination checker reports the definition terminating.
isTotal : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core Bool
isTotal fc n = do
  t <- catch (checkTotal fc n) (\_ => pure Unchecked)
  pure (case t of
          IsTerminating => True
          _ => False)

||| Translates one function instance.
translateInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Pending -> Core ()
translateInstance p = do
  update TState { current := Just p.inst }
  def <- lookupDef EmptyFC (show p.name) p.name
  let owner = show (fullname def)
  -- A definition the checks refused is left out, and so is what only it
  -- reaches.
  False <- pure (contains owner (!(get TState)).refused)
    | True => pure ()
  let fc = location def
  PMDef _ args treeCT _ _ <- pure (definition def)
    | _ => reject fc owner DefinitionShape "not a pattern-matching definition"
  -- A missing case crashes.
  let complete = case isCovering (totality def) of
                   MissingCases _ => False
                   _ => True
  (kinds, resTy) <- classify fc owner (length args) (type def) (givenArgs p.kinds)
  result <- coreType fc owner ValueType !(normaliseClosed resTy)
  -- Parameter i is variable i, as in the case tree's scope.
  let env = zipWith info (Data.Fin.List.allFins (length kinds)) kinds
  body <- tree (MkCtx owner fc complete) env (telescope (length args) (type def)) treeCT
  loc <- toLoc fc
  tot <- isTotal fc p.name
  let facts = MkFacts (MkFact tot FromIdris)
  update TState { fns $= insert p.inst (MkTFn p.inst (shown owner) (length kinds)
                                              (map runtimeBinder (fromList kinds)) result body loc facts)
                , fnOrder $= (:< p.inst) }
  where
    info : Fin k -> PKind -> VarInfo (Fin k)
    info i (TypeParam t) = TypeValue t
    info i (DictParam t) = Static t
    info i (ValueParam b Nothing) = Runtime i (Just (typeOf b))
    info i (ValueParam b (Just shape)) = shaped i (typeOf b) shape

||| Translates every instance requested, until none is left or a
||| construction site voids the pass (`Dictionaries`). A rejected instance
||| is recorded and leaves the state as it was before it, the instances it
||| requested included, but for the rejections and what they refused: what
||| it would have reached is reported once it is fixed, and every
||| rejection the translation reports is independent.
drain : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Core ()
drain = do
  st <- get TState
  case st.queue of
    [] => pure ()
    (p :: rest) => do
      let before = { queue := rest } st
      put TState before
      Nothing <- noting (translateInstance p)
        | Just () => do
            st' <- get TState
            unless st'.restart drain
      after <- get TState
      put TState ({ rejected := after.rejected, refused := after.refused } before)
      drain

||| The program's instances from its root, in as many passes as the
||| dictionary fields matched before they were built need: each pass starts
||| from the dictionaries the last one found.
translateFrom : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> Name -> Core (Maybe FnId)
translateFrom fc main = do
  update TState nextPass
  Just inst <- noting (request fc (show main) main [])
    | Nothing => pure Nothing
  drain
  st <- get TState
  if st.restart then translateFrom fc main else pure (Just inst)

||| The program, with each data instance's representation: a box when it
||| contains itself, through the fields of any data (not through closures,
||| which are values of their own), and an unboxed sum otherwise. A record
||| decided Sop here may still become a box in idr-defunctionalize, when a
||| cell holding its values would count more references than a header can:
||| that measure is idr.layout's, not one held here too.
assemble : {auto s : Ref TState TS} -> FnId -> Core Source
assemble root = do
  st <- get TState
  let decls = the (List Decl) (mapMaybe (\n => lookup n st.datas) (st.dataOrder <>> []))
  let contained = \d => maybe [] (\decl => concatMap (mapMaybe dataField . (.fields)) decl.cons)
                                 (lookup d st.datas)
  let boxes = cyclic contained (map (.id) decls)
  let datas = map (\d : Decl => MkData d.id d.idrisName d.cons d.loc (if contains d.id boxes then Box else Sop)) decls
  let fns = mapMaybe (\n => lookup n st.fns) (st.fnOrder <>> [])
  pure (MkSource datas fns root)
  where
    dataField : Binder -> Maybe DataId
    dataField (Held _ (DataT d)) = Just d
    dataField _ = Nothing

||| An IO program. The root is `unsafePerformIO main` written
||| directly as world-passing code, which is what `unsafePerformIO`,
||| `unsafeCreateWorld` and `unsafeDestroyWorld` mean:
|||   root w = case main of MkIO f => f w
||| It returns the `IORes` of `main`'s result and the last world, so the
||| world is used exactly once. `%MkWorld` never appears. Nothing when an
||| instance was rejected (`rejections`).
export
translateIOProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                     FC -> Name -> Core (Maybe Source)
translateIOProgram fc main = do
  Just inst <- translateFrom fc main
    | Nothing => pure Nothing
  st <- get TState
  let [<] = st.rejected
    | _ => pure Nothing
  let owner = show main
  let notIO = reject fc owner ProgramShape "main must have type IO ()"
  let Just mainFn = lookup inst st.fns
    | Nothing => internal fc "main was not translated"
  let DataT ioInst = mainFn.result
    | _ => notIO
  let Just [mkIO] = (.cons) <$> lookup ioInst st.datas
    | _ => notIO
  let [action@(Held _ (FunT (Held _ WorldT) res@(DataT _)))] = mkIO.fields
    | _ => notIO
  loc <- toLoc (location !(lookupDef fc owner main))
  -- w is the parameter; `m` is main's value, and `f` its action.
  let body : Term (Fin 1)
      body = Let loc Many (Call loc inst Nothing [])                          -- m
               (Case loc (Bound FZ)
                  [MkAlt mkIO.id [action]                                    -- f
                     (App loc (Var loc (Bound FZ)) (Var loc (Free (Free FZ))))]
                  Nothing)
  let rootId = MkFnId "$idris-mlir.root"
  src <- assemble rootId
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`: its
  -- facts are the registry's, and it terminates when main does.
  let facts = MkFacts (MkFact mainFn.facts.terminating.holds FromRegistry)
  pure (Just ({ fns $= (++ [MkTFn rootId (shown rootId.name) 1 [Held Once WorldT] res body loc facts]) } src))
