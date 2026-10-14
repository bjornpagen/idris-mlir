||| Audit instrumentation only (never committed): cumulative call counts and
||| nanoseconds per key, kept in a global IORef, dumped to stderr.
module IdrisMLIR.Frontend.Translate.Prof

import Core.Core
import Core.Hash
import Core.TT
import Core.Name

import Data.IORef
import Data.List
import Data.Maybe
import Data.SortedMap
import Data.String
import System
import System.Clock
import System.File

%default covering

||| Distinct arguments keep common subexpression elimination from
||| merging two references into one.
export
%noinline
mkRef : Int -> a -> IO (IORef a)
mkRef _ v = newIORef v

public export
record Stat where
  constructor MkStat
  calls : Integer
  ns : Integer      -- inclusive, counted once per outermost activation
  self : Integer    -- exclusive
  size : Integer

record Frame where
  constructor MkFrame
  key : String
  start : Integer
  child : Integer

%noinline
statsRef : Lazy (IORef (SortedMap String Stat))
statsRef = delay (unsafePerformIO (mkRef 1 empty))

%noinline
stackRef : Lazy (IORef (List Frame))
stackRef = delay (unsafePerformIO (mkRef 2 []))

%noinline
traceRef : Lazy (IORef Bool)
traceRef = delay (unsafePerformIO (mkRef 3 False))

%noinline
traceKey : Lazy (Maybe String)
traceKey = delay (unsafePerformIO (getEnv "IDRIS_MLIR_TRACE"))

%noinline
progressOn : Lazy Bool
progressOn = delay (unsafePerformIO (isJust <$> getEnv "IDRIS_MLIR_PROGRESS"))

%noinline
repeatOn : Lazy Bool
repeatOn = delay (unsafePerformIO (isJust <$> getEnv "IDRIS_MLIR_REPEATS"))

||| Seen inputs per key, bucketed by hash, for counting exact repeats.
%noinline
seenRef : Lazy (IORef (SortedMap (String, Int) (List ClosedTerm)))
seenRef = delay (unsafePerformIO (mkRef 4 empty))

export
nowNs : Core Integer
nowNs = toNano <$> coreLift (clockTime Monotonic)

noteFull : String -> Integer -> Integer -> Integer -> Core ()
noteFull key ns self sz = coreLift $ modifyIORef (force statsRef) (\m => insert key (add (lookup key m)) m)
  where
    add : Maybe Stat -> Stat
    add Nothing = MkStat 1 ns self sz
    add (Just s) = MkStat (s.calls + 1) (s.ns + ns) (s.self + self) (s.size + sz)

export
note : String -> Integer -> Integer -> Core ()
note key ns sz = noteFull key ns ns sz

export
count : String -> Core ()
count key = noteFull key 0 0 0

finish : Integer -> Core ()
finish sz = do
  t1 <- nowNs
  (f :: rest) <- coreLift (readIORef (force stackRef))
    | [] => pure ()
  let el = t1 - f.start
  let rest' = case rest of
                (p :: ps) => { child $= (+ el) } p :: ps
                [] => []
  coreLift (writeIORef (force stackRef) rest')
  -- inclusive time only for the outermost activation of a key
  let incl = if any (\g => g.key == f.key) rest then 0 else el
  noteFull f.key incl (el - f.child) sz

export
timedSz : String -> Integer -> Core a -> Core a
timedSz key sz act = do
  t0 <- nowNs
  coreLift (modifyIORef (force stackRef) (MkFrame key t0 0 ::))
  r <- catch act (\e => do finish sz; throw e)
  finish sz
  pure r

export
timed : String -> Core a -> Core a
timed key = timedSz key 0

export
tracing : Core Bool
tracing = coreLift (readIORef (force traceRef))

export
setTracing : String -> Core ()
setTracing inst = coreLift (writeIORef (force traceRef) (maybe False (\k => isInfixOf k inst) (force traceKey)))

export
progress : String -> Core ()
progress msg = when (force progressOn) $ do
  t <- nowNs
  ignore (coreLift (fPutStrLn stderr (show (t `div` 1000000) ++ " " ++ msg)))

export
trace : String -> Core ()
trace msg = when !tracing $ do
  t <- nowNs
  ignore (coreLift (fPutStrLn stderr (show (t `div` 1000000) ++ " TRACE " ++ msg)))

export
ttSize : Term vs -> Integer
ttSize (Bind _ _ b sc) = 1 + ttSize (binderType b) + bval b + ttSize sc
  where
    bval : Binder (Term vs) -> Integer
    bval (Let _ _ v _) = ttSize v
    bval (PLet _ _ v _) = ttSize v
    bval _ = 0
ttSize (App _ f a) = 1 + ttSize f + ttSize a
ttSize (As _ _ a p) = 1 + ttSize p
ttSize (TDelayed _ _ t) = 1 + ttSize t
ttSize (TDelay _ _ t a) = 1 + ttSize t + ttSize a
ttSize (TForce _ _ t) = 1 + ttSize t
ttSize (Meta _ _ _ args) = 1 + sum (map ttSize args)
ttSize _ = 1

whyEq : WhyErased a -> WhyErased b -> Bool
whyEq Placeholder Placeholder = True
whyEq Impossible Impossible = True
whyEq (Dotted _) (Dotted _) = True
whyEq _ _ = False

||| Structural equality including binder names (what a cache keyed on
||| exact terms would compare).
export
exactEq : Term vs -> Term ws -> Bool
exactEq (Local _ _ i _) (Local _ _ j _) = i == j
exactEq (Ref _ nt n) (Ref _ nt' m) = n == m
exactEq (Meta _ n i as) (Meta _ m j bs) = n == m && i == j && length as == length bs && all (uncurry exactEq) (zip as bs)
exactEq (Bind _ x b sc) (Bind _ y c sc') = x == y && binderEq b c && exactEq sc sc'
  where
    binderEq : Binder (Term vs) -> Binder (Term ws) -> Bool
    binderEq (Lam _ r p t) (Lam _ r' p' t') = r == r' && exactEq t t'
    binderEq (Let _ r v t) (Let _ r' v' t') = r == r' && exactEq v v' && exactEq t t'
    binderEq (Pi _ r p t) (Pi _ r' p' t') = r == r' && exactEq t t'
    binderEq (PVar _ r p t) (PVar _ r' p' t') = r == r' && exactEq t t'
    binderEq (PLet _ r v t) (PLet _ r' v' t') = r == r' && exactEq v v' && exactEq t t'
    binderEq (PVTy _ r t) (PVTy _ r' t') = r == r' && exactEq t t'
    binderEq _ _ = False
exactEq (App _ f a) (App _ g b) = exactEq f g && exactEq a b
exactEq (As _ s a p) (As _ s' b q) = exactEq a b && exactEq p q
exactEq (TDelayed _ r t) (TDelayed _ r' u) = r == r' && exactEq t u
exactEq (TDelay _ r t a) (TDelay _ r' u b) = r == r' && exactEq t u && exactEq a b
exactEq (TForce _ r t) (TForce _ r' u) = r == r' && exactEq t u
exactEq (PrimVal _ c) (PrimVal _ d) = c == d
exactEq (Erased _ w) (Erased _ w') = whyEq w w'
exactEq (TType _ u) (TType _ v) = u == v
exactEq _ _ = False

||| Counts whether this exact input was seen before under the key.
export
seenBefore : String -> ClosedTerm -> Core ()
seenBefore key tm = when (force repeatOn) $ do
  let h = hash tm
  m <- coreLift (readIORef (force seenRef))
  let bucket = fromMaybe [] (lookup (key, h) m)
  if any (exactEq tm) bucket
     then count (key ++ ".repeat-exact")
     else do
       when (any (== tm) bucket) $ count (key ++ ".repeat-alpha-only")
       coreLift (writeIORef (force seenRef) (insert (key, h) (tm :: bucket) m))

pad : Nat -> String -> String
pad n s = s ++ pack (replicate (minus n (length s)) ' ')

lpad : Nat -> String -> String
lpad n s = pack (replicate (minus n (length s)) ' ') ++ s

export
dump : String -> Core ()
dump title = when (force progressOn) $ do
  m <- coreLift (readIORef (force statsRef))
  let rows = sortBy (\(_, a), (_, b) => compare b.ns a.ns) (SortedMap.toList m)
  let rows = sortBy (\(_, a), (_, b) => compare b.self a.self) (SortedMap.toList m)
  let lines = map (\(k, s) => pad 44 k ++ lpad 10 (show s.calls) ++ lpad 10 (show (s.self `div` 1000000)) ++ " self"
                               ++ lpad 10 (show (s.ns `div` 1000000)) ++ " incl"
                               ++ (if s.size > 0 then lpad 14 (show s.size) ++ " sz" else "")) rows
  ignore (coreLift (fPutStrLn stderr ("== PROF " ++ title ++ "\n" ++ unlines lines ++ "== END PROF")))

%noinline
tickRef : Lazy (IORef Integer)
tickRef = delay (unsafePerformIO (mkRef 5 0))

%noinline
noTotal : Lazy Bool
noTotal = delay (unsafePerformIO (isJust <$> getEnv "IDRIS_MLIR_NOTOTAL"))

export
stubTotal : Bool
stubTotal = force noTotal

||| Counts an instance, and dumps the table every 250.
export
tick : Core ()
tick = do
  n <- coreLift (readIORef (force tickRef))
  coreLift (writeIORef (force tickRef) (n + 1))
  when (force progressOn && (n + 1) `mod` 250 == 0) $ dump ("after " ++ show (n + 1) ++ " instances")

%noinline
fixLocOn : Lazy Bool
fixLocOn = delay (unsafePerformIO (isJust <$> getEnv "IDRIS_MLIR_FIX_TOLOC"))

export
fixLoc : Bool
fixLoc = force fixLocOn

%noinline
fixTPOn : Lazy Bool
fixTPOn = delay (unsafePerformIO (isJust <$> getEnv "IDRIS_MLIR_FIX_TYPEPARAMS"))

export
fixTP : Bool
fixTP = force fixTPOn

%noinline
fixReprOn : Lazy Bool
fixReprOn = delay (unsafePerformIO (isJust <$> getEnv "IDRIS_MLIR_FIX_REPR"))

export
fixRepr : Bool
fixRepr = force fixReprOn

||| Memo tables for the measured fixes, keyed by printed name.
%noinline
locMemo : Lazy (IORef (SortedMap String (String, String)))
locMemo = delay (unsafePerformIO (mkRef 6 empty))

export
lookupLocMemo : String -> Core (Maybe (String, String))
lookupLocMemo k = lookup k <$> coreLift (readIORef (force locMemo))

export
insertLocMemo : String -> (String, String) -> Core ()
insertLocMemo k v = coreLift (modifyIORef (force locMemo) (insert k v))

%noinline
tpMemo : Lazy (IORef (SortedMap String (List Nat)))
tpMemo = delay (unsafePerformIO (mkRef 7 empty))

export
lookupTP : String -> Core (Maybe (List Nat))
lookupTP k = lookup k <$> coreLift (readIORef (force tpMemo))

export
insertTP : String -> List Nat -> Core ()
insertTP k v = coreLift (modifyIORef (force tpMemo) (insert k v))

export
calibrate : Core ()
calibrate = go 20000
  where
    go : Nat -> Core ()
    go Z = pure ()
    go (S k) = do timed "prof.empty" (pure ()); go k

%noinline
ppMemo : Lazy (IORef (SortedMap Name (Maybe (Nat, List Nat))))
ppMemo = delay (unsafePerformIO (mkRef 9 empty))

export
lookupPP : Name -> Core (Maybe (Maybe (Nat, List Nat)))
lookupPP k = lookup k <$> coreLift (readIORef (force ppMemo))

export
insertPP : Name -> Maybe (Nat, List Nat) -> Core ()
insertPP k v = coreLift (modifyIORef (force ppMemo) (insert k v))

%noinline
fixContOn : Lazy Bool
fixContOn = delay (unsafePerformIO (isJust <$> getEnv "IDRIS_MLIR_FIX_CONTINUE"))

export
fixContinue : Bool
fixContinue = force fixContOn
