// A rewrite pattern declaring an equivalence between a source and target DAG.
def : Pattern<
    // The first parameter is the source DAG with nodes corresponding to Ops in
    // ODS followed by a list of named arguments, potentially with more type
    // constraints.
    (LeakyReluOp $arg, F32Attr:$alpha),

    // The second parameter is a list of DAGs that is used to replace matched
    // source DAG. DRR supports multiple result patterns as well as auxiliary
    // Ops, which are used for building the replacement ops but are not
    // directly used for replacements. The DAGs may refer to matched values in
    // the source DAG or those created in target.
    [(SelectOp (CmpFOp CMPF_P_ODT
      // A referenced argument bound in the source DAG.
        $arg
      // Nested DAG construct Ops that produce value from attribute created in
      // pattern.
        (ConstantOp ConstantAttr<F32Attr, "0.">))
      // And the two final, required arguments of SelectOp.
        $arg,  (ConstantOp $alpha))]>;
