module Main

import IdrisMLIR.IO

-- rule: SEM-STR-2
main : IO ()
main = do
  putStrLn (prim__cast_IntString (prim__sub_Int 0 9223372036854775807))
  putStrLn (prim__cast_Int8String (prim__cast_IntInt8 200))
  putStrLn (prim__cast_Bits64String (prim__cast_IntBits64 (-1)))
  putStrLn (prim__cast_Int32String (prim__cast_IntInt32 0))
  loop 3
  where
    loop : Int -> IO ()
    loop 0 = putStrLn "done"
    loop n = do
      putStrLn (prim__strAppend "n=" (prim__cast_IntString (prim__mul_Int n 1000)))
      loop (prim__sub_Int n 1)
