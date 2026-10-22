module Bug
import Data.IOArray.Prims

data Arr : Type where
  MkArr : ArrayData Int -> Arr

new : Int -> Arr
new n = MkArr (unsafePerformIO (fromPrim (prim__newArray n 0)))

get : Arr -> Int -> Int
get (MkArr d) i = unsafePerformIO (fromPrim (prim__arrayGet d i))

||| Writes, and gives the array back.
set : Arr -> Int -> Int -> Arr
set (MkArr d) i x = let () = unsafePerformIO (fromPrim (prim__arraySet d i x)) in MkArr d

main : IO ()
main = let a = set (new 4) 2 7 in printLn (get a 2)
