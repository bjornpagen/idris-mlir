module attributes {gpu.container_module} {
  gpu.module @kernels {
    func.func private @fill(%t: tensor<4xf32>) -> tensor<4xf32> {
      %f = arith.constant 1.0 : f32
      %0 = linalg.fill ins(%f : f32) outs(%t : tensor<4xf32>) -> tensor<4xf32>
      return %0 : tensor<4xf32>
    }

    func.func @caller(%t: tensor<10xf32>) -> tensor<10xf32> {
      %e = tensor.empty() : tensor<4xf32>
      %0 = func.call @fill(%e) : (tensor<4xf32>) -> tensor<4xf32>
      %1 = tensor.insert_slice %0 into %t[0] [4] [1] : tensor<4xf32> into tensor<10xf32>
      return %1 : tensor<10xf32>
    }
  }
}
