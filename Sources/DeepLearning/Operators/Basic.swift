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

#if !COMPILING_TENSORFLOW_MODULE
import TensorFlow
#endif

public extension Tensor {
    @inlinable
    @differentiable(wrt: self where Scalar : TensorFlowFloatingPoint)
    func unstack(alongAxis axis: Int = 0) -> [Tensor] {
        return split(numSplits: shape[axis], alongAxis: axis)
    }

    @inlinable
    @differentiable(
        vjp: _vjpSplit(numSplits:alongAxis:) where Scalar : TensorFlowFloatingPoint)
    func split(numSplits: Int, alongAxis axis: Int = 0) -> [Tensor] {
        return Raw.split(
            splitDim: Tensor<Int32>(Int32(axis)), value: self, numSplit: Int64(numSplits))
    }

    @inlinable
    @differentiable(
        wrt: self,
        vjp: _vjpSplit(splitSizes:alongAxis:) where Scalar : TensorFlowFloatingPoint)
    func split(splitSizes: Tensor<Int32>, alongAxis axis: Int = 0) -> [Tensor] {
        return Raw.splitV(
            value: self,
            sizeSplits: splitSizes,
            splitDim: Tensor<Int32>(Int32(axis)),
            numSplit: Int64(splitSizes.shape[0]))
    }

    /// Gathers slices of this tensor at `indices` along the `axis` dimension.
    ///
    /// For 0-D (scalar) `indices`:
    /// ```
    /// result[p_0,          ..., p_{axis-1},
    ///        p_{axis + 1}, ..., p_{N-1}] = 
    /// self[p_0,          ..., p_{axis-1},
    ///      indices,
    ///      p_{axis + 1}, ..., p_{N-1}]
    /// ```
    /// 
    /// For 1-D (vector) `indices`:
    /// ```
    /// result[p_0,          ..., p_{axis-1},
    ///        i,
    ///        p_{axis + 1}, ..., p_{N-1}] = 
    /// self[p_0,          ..., p_{axis-1},
    ///      indices[i],
    ///      p_{axis + 1}, ..., p_{N-1}]
    /// ```
    /// 
    /// In the general case, produces a resulting tensor where:
    /// ```
    /// result[p_0,             ..., p_{axis-1},
    ///        i_{batch\_dims}, ..., i_{M-1},
    ///        p_{axis + 1},    ..., p_{N-1}] = 
    /// self[p_0,             ..., p_{axis-1},
    ///      indices[i_0,     ..., i_{M-1}],
    ///      p_{axis + 1},    ..., p_{N-1}]
    /// ```
    /// where `N = self.rank` and `M = indices.rank`.
    ///
    /// The shape of the resulting tensor is:
    /// `self.shape[..<axis] + indices.shape + self.shape[(axis + 1)...]`.
    /// 
    /// - Note: On CPU, if an out-of-range index is found, an error is thrown. On GPU, if an 
    /// out-of-range index is found, a 0 is stored in the corresponding output values.
    ///
    /// - Parameters:
    ///   - indices: Contains the indices to gather.
    ///   - axis: Dimension along which to gather. Negative values wrap around.
    /// 
    /// - Precondition: `axis` must be in the range `[-rank, rank)`.
    /// 
    /// - Returns: The gathered tensor.
    @inlinable
    // @differentiable(vjp: _vjpGathering where Scalar: TensorFlowFloatingPoint)
    func gathering(
        atIndices indices: Tensor<Int32>, 
        alongAxis axis: Int = 0
    ) -> Tensor {
        return Raw.gatherV2(params: self, indices: indices, axis: Tensor<Int32>(Int32(axis)))
    }

    /// Gathers slices of this tensor at `indices` along the `axis` dimension, while ignoring the 
    /// first `batchDims` dimensions that correspond to batch dimensions.
    /// 
    /// Performs similar functionality to `gathering`, except that the resulting tensor shape is now:
    /// `self.shape[..<axis] + indices.shape[batchDims...] + self.shape[(axis + 1)...]`.
    ///
    /// - Parameters:
    ///   - indices: Contains the indices to gather.
    ///   - axis: Dimension along which to gather. Negative values wrap around.
    ///   - batchDims: Number of leading batch dimensions to ignore.
    /// 
    /// - Precondition: `axis` must be in the range `[-rank, rank)`, while also being greater than 
    ///     or equal to `batchDims`.
    /// - Precondition: `batchDims` must be less than `indices.rank`.
    /// 
    /// - Returns: The gathered tensor.
    @inlinable
    func batchGathering(
        atIndices indices: Tensor<Int32>,
        alongAxis axis: Int,
        numBatchDims batchDims: Int
    ) -> Tensor {
        precondition(batchDims >= 0 && batchDims < indices.rank,
                     "'numBatchDims' must be non-negative and less than 'indices.rank'.")
        precondition(batchDims < rank, "'numBatchDims' must be less than the tensor's rank.")

        // Handle the axis argument by transposing the axis dimension so that it is the first
        // non-batch dimension, recursively calling `batchGathering` with `axis = 0`, and then
        // transposing the result to put the pre-axis dimensions before the indices dimensions.
        if axis != batchDims {
            // Adjust axis to be positive.
            let posAxis = axis < 0 ? axis + rank : axis

            precondition(posAxis >= 0 && posAxis < rank, "'axis' is out of range.")
            precondition(batchDims <= posAxis, "'batchDims' must be less than or equal to 'axis'.")

            // Move self[axis] up to self[batchDims].
            let permutation = Tensor<Int32>(concatenating: [
                Tensor<Int32>(0 ..< Int32(batchDims)),
                Tensor<Int32>(Int32(axis)).rankLifted(),
                Tensor<Int32>(rangeFrom: Int32(batchDims), to: Int32(posAxis), stride: 1),
                Tensor<Int32>(rangeFrom: Int32(axis) + 1, to: Int32(rank), stride: 1)])
            let tensor = transposed(withPermutations: permutation)
            let result = tensor.batchGathering(
                atIndices: indices, alongAxis: batchDims, numBatchDims: batchDims)

            // Move the result dimensions corresponding to self[batchDims ..< axis] to just before
            // the dimensions corresponding to indices[batchDims ...].
            let start = indices.rank + posAxis - batchDims
            let resultPermutation = Tensor<Int32>(concatenating: [
                Tensor<Int32>(0 ..< Int32(batchDims)),
                Tensor<Int32>(rangeFrom: Int32(indices.rank), to: Int32(start), stride: 1),
                Tensor<Int32>(Int32(batchDims) ..< Int32(indices.rank)),
                Tensor<Int32>(rangeFrom: Int32(start), to: Int32(result.rank), stride: 1)])
            return result.transposed(withPermutations: resultPermutation)
        }

        let castedShape = Tensor<Int32>(shapeTensor)
        var batchIndices = indices
        var accumulated = Tensor<Int32>(ones: [])
        for d in (1...batchDims).reversed() {
            accumulated *= castedShape[d]
            let dValue = castedShape[d - 1]
            let dIndices = Tensor<Int32>(
                rangeFrom: Tensor<Int32>(zeros: []),
                to: dValue,
                stride: Tensor<Int32>(ones: [])
            ) * accumulated
            let dShape = Tensor<Int32>(concatenating: [
                Tensor<Int32>([Int32](repeating: 1, count: Int(d - 1))),
                Tensor<Int32>([dValue]),
                Tensor<Int32>([Int32](repeating: 1, count: Int(indices.rank - 1)))])
            batchIndices += dIndices.reshaped(toShape: dShape)
        }

        let flatIndices = batchIndices.flattened()
        let outerShape = shapeTensor[Int(batchDims + 1)...]
        let innerShape = shapeTensor[..<Int(batchDims + 1)].product(squeezingAxes: [0])
        let flatTensor = reshaped(toShape: innerShape.rankLifted().concatenated(with: outerShape))
        let flatResult = flatTensor.gathering(atIndices: flatIndices)
        return flatResult.reshaped(toShape: indices.shapeTensor.concatenated(with: outerShape))
    }

    /// Gathers values from this tensor according to the provided boolean mask.
    ///
    /// For example:
    /// ```
    /// // 1-D example
    /// // tensor is [0, 1, 2, 3]
    /// // mask is [true, false, true, false]
    /// tensor.gathering(where: mask) // is [0, 2]
    /// 
    /// // 2-D example
    /// // tensor is [[1, 2], [3, 4], [5, 6]]
    /// // mask is [true, false, true]
    /// tensor.gathering(where: mask) // is [[1, 2], [5, 6]]
    /// ```
    ///
    /// In general, `0 < mask.rank = K <= tensor.rank`, and the `mask`'s shape must match the first 
    /// K dimensions of the `tensor`'s shape. We then have:
    /// `tensor.gathering(where: mask)[i, j1, ..., jd] = tensor[i1, ..., iK, j1, ..., jd]`, where 
    /// `[i1, ..., iK]` is the `i`th `true` entry of `mask` (row-major order).
    /// 
    /// The `axis` could be used with `mask` to indicate the axis to mask from. In that case, 
    /// `axis + mask.rank <= tensor.rank` and the `mask``'s shape must match the first 
    /// `axis + mask.rank` dimensions of the `tensor`'s shape.
    /// 
    /// - Parameters:
    ///   - mask: K-D boolean tensor, where `K <= self.rank`.
    ///   - axis: 0-D integer tensor representing the axis in `self` to mask from, where 
    ///     `K + axis <= self.rank`.
    /// 
    /// - Precondition: The `mask` cannot be a scalar: `mask.rank != 0`.
    /// 
    /// - Returns: `(self.rank - K + 1)`-dimensional tensor populated by entries in this tensor 
    ///   corresponding to `true` values in `mask`.
    @inlinable
    func gathering(where mask: Tensor<Bool>, alongAxis axis: Int = 0) -> Tensor {
        precondition(mask.rank != 0, "The boolean mask cannot be a scalar.")
        let posAxis = axis < 0 ? axis + rank : axis
        let leadingSize = shapeTensor[posAxis ..< posAxis + mask.rank].product().rankLifted()
        let reshapedTensor = reshaped(
            toShape: Tensor<Int32>(concatenating: [
                shapeTensor[..<posAxis], leadingSize, shapeTensor[(posAxis + mask.rank)...]]))
        let indices = Tensor<Int32>(mask.flattened().nonZeroIndices().squeezingShape(at: 1))
        return reshapedTensor.gathering(atIndices: indices, alongAxis: posAxis)
    }
}

public extension Tensor {
    /// Returns the locations of non-zero / true values in this tensor.
    ///
    /// The coordinates are returned in a 2-D tensor where the first dimension (rows) represents the 
    /// number of non-zero elements, and the second dimension (columns) represents the coordinates 
    /// of the non-zero elements. Keep in mind that the shape of the output tensor can vary 
    /// depending on how many true values there are in this tensor. Indices are output in row-major 
    /// order.
    ///
    /// For example:
    /// ```
    /// // 'input' is [[true, false], [true, false]]
    /// // 'input' has 2 true values and so the output has 2 rows.
    /// // 'input' has rank of 2, and so the second dimension of the output has size 2.
    /// input.nonZeroIndices() // is [[0, 0], [1, 0]]
    ///
    /// // 'input' is [[[ true, false], [ true, false]],
    /// //             [[false,  true], [false,  true]],
    /// //             [[false, false], [false,  true]]]
    /// // 'input' has 5 true values and so the output has 5 rows.
    /// // 'input' has rank 3, and so the second dimension of the output has size 3.
    /// input.nonZeroIndices() // is [[0, 0, 0],
    ///                        //     [0, 1, 0],
    ///                        //     [1, 0, 1],
    ///                        //     [1, 1, 1],
    ///                        //     [2, 1, 1]]
    /// ```
    ///
    /// - Returns: A tensor with shape `(num_true, rank(condition))`.
    @inlinable
    func nonZeroIndices() -> Tensor<Int64> {
        return Raw.where_(self)
    }
}

public extension Tensor where Scalar : TensorFlowFloatingPoint {
    @inlinable
    internal func _vjpSplit(
        numSplits: Int,
        alongAxis axis: Int = 0
    ) -> ([Tensor], (Array<Tensor>.DifferentiableView) -> Tensor) {
        let result = split(numSplits: numSplits, alongAxis: axis)
        return (result, { v in Tensor(concatenating: v.base, alongAxis: axis) })
    }

    @inlinable
    internal func _vjpSplit(
        splitSizes: Tensor<Int32>,
        alongAxis axis: Int = 0
    ) -> ([Tensor], (Array<Tensor>.DifferentiableView) -> Tensor) {
        let result = split(splitSizes: splitSizes, alongAxis: axis)
        return (result, { v in Tensor(concatenating: v.base, alongAxis: axis) })
    }
}
