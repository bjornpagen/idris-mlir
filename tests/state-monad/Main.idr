module Main

import Prelude

State : Type -> Type -> Type
State s a = s -> Pair a s

pureS : a -> State s a
pureS x = \s => MkPair x s

bindS : State s a -> (a -> State s b) -> State s b
bindS m k = \s => case m s of
                    MkPair x s' => k x s'

get : State s s
get = \s => MkPair s s

put : s -> State s ()
put x = \_ => MkPair () x

tick : State Int ()
tick = bindS get (\n => put (prim__add_Int n 1))

run : Int -> State Int ()
run 0 = pureS ()
run k = bindS tick (\_ => run (prim__sub_Int k 1))

-- The state threaded through a thousand ticks from 0, and through none
-- from 7, which it returns unchanged.
report : Int -> Int -> IO ()
report k s = case run k s of
  MkPair _ count => putStrLn (prim__strAppend "count " (prim__cast_IntString count))

main : IO ()
main = do
  report 1000 0
  report 0 7
