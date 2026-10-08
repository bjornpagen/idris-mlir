backport, retest on trunk

Do not send. The shift is a backport of 44a4dbf32 (#218495). The remainder cases (`remsi` of INT_MIN % -1, `remui` of a possibly negative word) must be rerun on trunk before anyone decides to file. Nothing to send until that retest.

Author: Bjorn, individual, outside any employer. Not Bugzilla.
