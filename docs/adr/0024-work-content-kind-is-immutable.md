# Work content kind is immutable

A Work chooses `novel` or `screenplay` when it is created, and that content kind cannot be changed later even when the Work appears empty. The two kinds initialize different content roots, default structures, editor routes, and AI namespaces; requiring a new Work when the user chose the wrong kind avoids an ambiguous emptiness test and a destructive cross-model cleanup or conversion protocol.
