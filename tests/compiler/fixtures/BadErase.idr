module BadErase

data Count = Zero | Next Count

bad : (0 witness : Count) -> Count
bad witness = witness
