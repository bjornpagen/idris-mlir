/// Leaky ReLU operator
class LeakyReluOp : Op<LeakyReluOp, NoSideEffect> {
public:
  // Static construction function. The type of the result is
  // inferred given the ODS trait.
  static void build(/*...*/, Value *tensor, FloatAttr alpha);

  // Named accessors.
  Value *tensor();
  float alpha();
  Value *output();

  // Parts of the verification are generated from ODS.
  LogicalResult verify() {
    return success(
	isa<TensorType>(tensor()->getType()) &&
        isa<FloatAttr>(getAttr("alpha")) &&
	isa<TensorType>(output()->getType()));
  }
};
