# 65537 functions @f<i>, and a chain of @g<i> that makes the closure of
# @f<n> for n = i and asks the next one otherwise: every closure is made by
# the evaluated call, so the labels are numbered 0 to 65536 in order.
BEGIN {
  n = 65536
  fn = "!idr.fn<(i64) -> (i64)>"
  attrs = "attributes {idr.total, idr.effects = #idr.effects<none>}"
  print "module {"
  for (i = 0; i <= n; i++) {
    print "  func.func private @f" i "(%c: i64, %x: i64) -> i64 " attrs " {"
    print "    return %x : i64"
    print "  }"
    print "  func.func private @g" i "(%n: i64) -> " fn " " attrs " {"
    if (i == n) {
      print "    %c = idr.closure @f" i "(%n) : (i64) -> " fn
      print "    return %c : " fn
    } else {
      print "    %r = idr.match_lit %n : i64 -> (" fn ") {"
      print "    case " i " {"
      print "      %c = idr.closure @f" i "(%n) : (i64) -> " fn
      print "      idr.yield %c : " fn
      print "    }"
      print "    default {"
      print "      %c = func.call @g" (i + 1) "(%n) : (i64) -> " fn
      print "      idr.yield %c : " fn
      print "    }"
      print "    }"
      print "    return %r : " fn
    }
    print "  }"
  }
  print "  func.func @Prog.main() -> " fn " {"
  print "    %n = arith.constant " n " : i64"
  print "    %c = func.call @g0(%n) : (i64) -> " fn
  print "    return %c : " fn
  print "  }"
  print "}"
}
