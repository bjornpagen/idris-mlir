module Main

import IdrisMLIR.IO

-- countdown returns an action; raised, it takes the world and loops.
countdown : Int -> IO ()
countdown 0 = putStrLn "liftoff"
countdown n = do
  putStrLn (prim__cast_IntString n)
  countdown (prim__sub_Int n 1)

main : IO ()
main = countdown 3
