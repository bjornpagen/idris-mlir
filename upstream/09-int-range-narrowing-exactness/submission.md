not drafted

Not ready to send: the texts are not written. The shift was 44a4dbf32 (#218495), which the pin (llvm main at 7208ba24) has; the patch no longer carries it. Both remainder cases (`remsi` of the narrow minimum rem -1, `remui` of a possibly negative word) still narrow on main at 7208ba24 (README, "Testing on main"), so this becomes an issue and a pull request with `llvm.patch`, in `upstream/README.md`'s order, once its texts are written here.

Author: Bjorn, individual, outside any employer. Not Bugzilla.
