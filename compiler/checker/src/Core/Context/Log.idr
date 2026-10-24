-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Context.Log

import public Core.Context
import Core.Options

import Data.String
import Libraries.Data.StringMap

import System.Clock

%default covering

-- if this function is called, then logging must be enabled.
%inline
export
logString : String -> Nat -> String -> Core ()
logString "" n msg = coreLift $ putStrLn
    $ "LOG " ++ show n ++ ": " ++ msg
logString str n msg = coreLift $ putStrLn
    $ "LOG " ++ str ++ ":" ++ show n ++ ": " ++ msg

export
unverifiedLogging : {auto c : Ref Ctxt Defs} ->
                    String -> Nat -> Core Bool
unverifiedLogging str Z = pure True
unverifiedLogging str n = do
    opts <- getSession
    pure $ logEnabled opts && keepLog (mkUnverifiedLogLevel str n) (logLevel opts)

%inline
export
logging : {auto c : Ref Ctxt Defs} ->
          LogTopic -> Nat -> Core Bool
logging s n = unverifiedLogging s.topic n

||| Log message with a term, translating back to human readable names first.
export
logTerm : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          LogTopic -> Nat -> Lazy String -> Term vars -> Core ()
logTerm s n msg tm
    = when !(logging s n)
        $ do tm' <- toFullNames tm
             logString s.topic n $ msg ++ ": " ++ show tm'

||| Log a message with the given log level. Use increasingly
||| high log level numbers for more granular logging.
|||
||| If you want to use some `Core` computation to produce a message string, use `logC`.
||| I.e. instead of `log "topic" 10 "message \{show !(toFullNames fn)}"` use
||| `logC "topic" 10 $ do pure ""message \{show !(toFullNames fn)}""`.
||| This will enfore that additional computation happends only when needed.
||| `do` before `pure` in this case ensures the correct bounds.
export
log : {auto c : Ref Ctxt Defs} ->
      LogTopic -> Nat -> Lazy String -> Core ()
log s n msg
    = when !(logging s n)
        $ logString s.topic n msg

export
unverifiedLogC : {auto c : Ref Ctxt Defs} ->
                 String -> Nat -> Core String -> Core ()
unverifiedLogC str n cmsg
    = when !(unverifiedLogging str n)
        $ do msg <- cmsg
             logString str n msg

%inline
export
logC : {auto c : Ref Ctxt Defs} ->
       LogTopic -> Nat -> Core String -> Core ()
logC s = unverifiedLogC s.topic

nano : Integer
nano = 1000000000

micro : Integer
micro = 1000000

-- A time in nanoseconds, shown in seconds to the millisecond. Both
-- divisors are the constants above, so no division meets zero.
showSeconds : Integer -> String
showSeconds time
    = show (time `div` nano) ++ "." ++
      addZeros (unpack (show ((time `mod` nano) `div` micro))) ++ "s"
  where
    addZeros : List Char -> String
    addZeros [] = "000"
    addZeros [x] = "00" ++ cast x
    addZeros [x,y] = "0" ++ cast x ++ cast y
    addZeros str = pack str

export
logTimeWhen : {auto c : Ref Ctxt Defs} ->
              Bool -> Nat -> Lazy String -> Core a -> Core a
logTimeWhen p lvl str act
    = if p
         then do clock <- coreLift (clockTime Process)
                 let t = seconds clock * nano + nanoseconds clock
                 res <- act
                 clock <- coreLift (clockTime Process)
                 let t' = seconds clock * nano + nanoseconds clock
                 let time = t' - t
                 coreLift $ do
                   let header = "TIMING " ++ replicate lvl '+' ++ ifThenElse (0 < lvl) " " ""
                   putStrLn $ header ++ str ++ ": " ++ showSeconds time
                 pure res
         else act

export
logTime : {auto c : Ref Ctxt Defs} ->
          Nat -> Lazy String -> Core a -> Core a
logTime lvl str act
    = do opts <- getSession
         logTimeWhen (maybe False (lvl <=) (logTimings opts)) lvl str act
