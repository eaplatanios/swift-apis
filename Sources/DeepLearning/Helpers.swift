// Copyright 2018 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@_exported import TensorFlowCore

/// Returns a tensor with the same shape and scalars as the specified tensor.
@inlinable
@differentiable
public func identity<Scalar>(_ x: Tensor<Scalar>) -> Tensor<Scalar> {
    return x
}

// `pow` is defined in Darwin/Glibc on `Float` and `Double`, but there doesn't exist a generic
// version for `FloatingPoint`.
// This is a manual definition.
@inlinable
func pow<T: BinaryFloatingPoint>(_ x: T, _ y: T) -> T {
    return T(pow(Double(x), Double(y)))
}
