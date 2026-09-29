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
  def <- lookupDef EmptyFC (show p.name) p.name
  let owner = show (fullname def)
  let fc = location def
  PMDef _ args treeCT _ _ <- pure (definition def)
    | _ => reject fc owner DefinitionShape "not a pattern-matching definition"
  -- A missing case crashes.
  let complete = case isCovering (totality def) of
                   MissingCases _ => False
                   _ => True
  (kinds, resTy) <- classify fc owner (length args) (type def) (map (map known) p.statics)
  result <- coreType fc owner ValueType !(normaliseClosed resTy)
  -- Parameter i is variable i, as in the case tree's scope.
  let env = zipWith info (Data.Fin.List.allFins (length kinds)) kinds
  body <- tree (MkCtx owner fc complete) env treeCT
  loc <- toLoc fc
  tot <- isTotal fc p.name
  let facts = MkFacts (MkFact tot FromIdris)
  update TState { fns $= insert p.inst (MkTFn p.inst (shown owner) (length kinds) (map binder (fromList kinds))
                                              result body loc facts)
                , fnOrder $= (:< p.inst) }
  where
    binder : (Quantity, PKind) -> Binder
    binder (q, RuntimeParam t) = MkBinder q t
    binder _ = MkBinder Q0 ErasedT
    info : Fin k -> (Quantity, PKind) -> VarInfo (Fin k)
    info i (_, TypeParam t) = TypeValue t
    info i (_, DictParam t) = Static t
    info i (_, RuntimeParam t) = Runtime i (Just t)
    info i _ = Runtime i (Just ErasedT)

drain : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Core ()
drain = do
  st <- get TState
  case st.queue of
    [] => pure ()
    (p :: rest) => do
      put TState ({ queue := rest, current := p.path } st)
      translateInstance p
      drain

||| The program, with each data instance's representation: a box when it
||| contains itself, through the fields of any data (not through closures,
||| which are values of their own), and an unboxed sum otherwise.
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
    dataField : Field -> Maybe DataId
    dataField (MkField _ (DataT d)) = Just d
    dataField _ = Nothing

||| A `main : Int` program: the root is `main` itself.
export
translateIntProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core Source
translateIntProgram main = do
  root <- request EmptyFC (show main) main []
  drain
  assemble root

||| An IO program. The root is `unsafePerformIO main` written
||| directly as world-passing code, which is what `unsafePerformIO`,
||| `unsafeCreateWorld` and `unsafeDestroyWorld` mean:
|||   root w = case main of MkIO f => f w
||| It returns the `IORes` of `main`'s result and the last world, so the
||| world is used exactly once. `%MkWorld` never appears.
export
translateIOProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                     FC -> Name -> Core Source
translateIOProgram fc main = do
  inst <- request fc (show main) main []
  drain
  st <- get TState
  let owner = show main
  let notIO = reject fc owner ProgramShape "main must have type IO ()"
  let Just mainFn = lookup inst st.fns
    | Nothing => internal fc "main was not translated"
  let DataT ioInst = mainFn.result
    | _ => notIO
  let Just [mkIO] = (.cons) <$> lookup ioInst st.datas
    | _ => notIO
  let [MkField _ action@(FunT _ WorldT res@(DataT _))] = mkIO.fields
    | _ => notIO
  loc <- toLoc (location !(lookupDef fc owner main))
  -- w is the parameter; `m` is main's value, and `f` its action.
  let body : Term (Fin 1)
      body = Let loc QW (Call loc inst [])                                    -- m
               (Case loc (Bound FZ)
                  [MkAlt mkIO.id [MkBinder QW action]                        -- f
                     (App loc (Var loc (Bound FZ)) (Var loc (Free (Free FZ))))]
                  Nothing)
  let rootId = MkFnId "$idris-mlir.root"
  src <- assemble rootId
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`: its
  -- facts are the registry's, and it terminates when main does.
  let facts = MkFacts (MkFact mainFn.facts.terminating.holds FromRegistry)
  pure ({ fns $= (++ [MkTFn rootId (shown rootId.name) 1 [MkBinder Q1 WorldT] res body loc facts]) } src)
