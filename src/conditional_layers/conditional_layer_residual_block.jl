# Residual block from Putzky and Welling (2019): https://arxiv.org/abs/1911.10914
# Author: Philipp Witte, pwitte3@gatech.edu
# Date: January 2020

export ConditionalResidualBlock

"""
    RB = ConditionalResidualBlock(nx, ny, n_in, n_hidden, batchsize; k1=4, k2=3, p1=0, p2=1, fan=false)

 Create a (non-invertible) residual block, consisting of three convolutional layers and activation functions.
 The first convolution is a downsampling operation with a stride equal to the kernel dimension. The last
 convolution is the corresponding transpose operation and upsamples the data to either its original dimensions
 or to twice the number of input channels (for `fan=true`). The first and second layer contain a bias term.

 *Input*: 

 - `nx, ny`: spatial dimensions of input
 
 - `n_in`, `n_hidden`: number of input and hidden channels

 - `k1`, `k2`: kernel size of convolutions in residual block. `k1` is the kernel of the first and third 
    operator, `k2` is the kernel size of the second operator.

 - `p1`, `p2`: padding for the first and third convolution (`p1`) and the second convolution (`p2`)

 - `fan`: bool to indicate whether the ouput has twice the number of input channels. For `fan=false`, the last
    activation function is a gated linear unit (thereby bringing the output back to the original dimensions).
    For `fan=true`, the last activation is a ReLU, in which case the output has twice the number of channels
    as the input.

or

 - `W1`, `W2`, `W3`: 4D tensors of convolutional weights

 - `b1`, `b2`: bias terms

 - `nx`, `ny`: spatial dimensions of input image

 *Output*:
 
 - `RB`: residual block layer

 *Usage:*

 - Forward mode: `Y = RB.forward(X)`

 - Backward mode: `ΔX = RB.backward(ΔY, X)`

 *Trainable parameters:*

 - Convolutional kernel weights `RB.W1`, `RB.W2` and `RB.W3`

 - Bias terms `RB.b1` and `RB.b2`

 See also: [`get_params`](@ref), [`clear_grad!`](@ref)
"""
struct ConditionalResidualBlock <: NeuralNetLayer
    W0::Parameter
    W1::Parameter
    W2::Parameter
    W3::Parameter
    b0::Parameter
    b1::Parameter
    b2::Parameter
    cdims1::DenseConvDims
    cdims2::DenseConvDims
    cdims3::DenseConvDims
    forward::Function
    backward::Function
end

# Constructor
function ConditionalResidualBlock(nx1, nx2, nx_in, ny1, ny2, ny_in, n_hidden, batchsize; k1=3, k2=3, p1=1, p2=1, s1=1, s2=1)

    # Initialize weights
    W0 = Parameter(glorot_uniform(nx1*nx2*nx_in, ny1*ny2*ny_in))  # Dense layer for data D
    W1 = Parameter(glorot_uniform(k1, k1, 2*nx_in, n_hidden))
    W2 = Parameter(glorot_uniform(k2, k2, n_hidden, n_hidden))
    W3 = Parameter(glorot_uniform(k1, k1, nx_in, n_hidden))
    b0 = Parameter(zeros(Float32, nx1*nx2*nx_in))
    b1 = Parameter(zeros(Float32, n_hidden))
    b2 = Parameter(zeros(Float32, n_hidden))

    # Dimensions for convolutions
    cdims1 = DenseConvDims((nx1, nx2, 2*nx_in, batchsize), (k1, k1, 2*nx_in, n_hidden); 
        stride=(s1,s1), padding=(p1,p1))
    cdims2 = DenseConvDims((Int(nx1/s1), Int(nx2/s1), n_hidden, batchsize), 
        (k2, k2, n_hidden, n_hidden); stride=(s2,s2), padding=(p2,p2))
    cdims3 = DenseConvDims((nx1, nx2, nx_in, batchsize), (k1, k1, nx_in, n_hidden); 
        stride=(s1,s1), padding=(p1,p1))

    return ConditionalResidualBlock(W0, W1, W2, W3, b0, b1, b2, cdims1, cdims2, cdims3,
                                    (X, D) -> residual_forward(X, D, W0, W1, W2, W3, b0, b1, b2, cdims1, cdims2, cdims3),
                                    (ΔY, ΔD, X, D) -> residual_backward(ΔY, ΔD, X, D, W0, W1, W2, W3, b0, b1, b2, cdims1, cdims2, cdims3)
                                    )
end

function residual_forward(X0, D, W0, W1, W2, W3, b0, b1, b2, cdims1, cdims2, cdims3; save=false)

    # Dimensions of input image X
    nx1, nx2, nx_in, batchsize = size(X0)
    
    Y0 = W0.data*reshape(D, :, batchsize) .+ b0.data
    X0_ = ReLU(reshape(Y0, nx1, nx2, nx_in, batchsize))
    X1 = tensor_cat(X0, X0_)

    Y1 = conv(X1, W1.data, cdims1) .+ reshape(b1.data, 1, 1, :, 1)
    X2 = ReLU(Y1)

    Y2 = X2 + conv(X2, W2.data, cdims2) .+ reshape(b2.data, 1, 1, :, 1)
    X3 = ReLU(Y2)
    
    Y3 = ∇conv_data(X3, W3.data, cdims3)
    X4 = ReLU(Y3)

    if save == false
        return X4, D
    else
        return Y0, Y1, Y2, Y3, X1, X2, X3
    end
end


function residual_backward(ΔX4, ΔD, X0, D, W0, W1, W2, W3, b0, b1, b2, cdims1, cdims2, cdims3)

    # Recompute forward states from input X
    Y0, Y1, Y2, Y3, X1, X2, X3 = residual_forward(X0, D, W0, W1, W2, W3, b0, b1, b2, cdims1, cdims2, cdims3; save=true)
    nx1, nx2, nx_in, batchsize = size(X0)

    # Backpropagate residual ΔX4 and compute gradients
    ΔY3 = ReLUgrad(ΔX4, Y3)
    ΔX3 = conv(ΔY3, W3.data, cdims3)
    ΔW3 = ∇conv_filter(ΔY3, X3, cdims3)

    ΔY2 = ReLUgrad(ΔX3, Y2)
    ΔX2 = ∇conv_data(ΔY2, W2.data, cdims2) + ΔY2
    ΔW2 = ∇conv_filter(X2, ΔY2, cdims2)
    Δb2 = sum(ΔY2, dims=(1,2,4))[1,1,:,1]

    ΔY1 = ReLUgrad(ΔX2, Y1)
    ΔX1 = ∇conv_data(ΔY1, W1.data, cdims1)
    ΔW1 = ∇conv_filter(X1, ΔY1, cdims1)
    Δb1 = sum(ΔY1, dims=(1,2,4))[1,1,:,1]

    ΔX0, ΔX0_ = tensor_split(ΔX1)
    ΔY0 = ReLUgrad(ΔX0_, reshape(Y0, nx1, nx2, nx_in, batchsize))
    ΔD = reshape(transpose(W0.data)*reshape(ΔY0, :, batchsize), size(D))
    ΔW0 = reshape(D, :, batchsize)*transpose(reshape(ΔY0, :, batchsize))
    Δb0 = vec(sum(ΔY0, dims=4))
    
    # Set gradients
    W0.grad = ΔW0
    W1.grad = ΔW1
    W2.grad = ΔW2
    W3.grad = ΔW3
    b0.grad = Δb0
    b1.grad = Δb1
    b2.grad = Δb2

    return ΔX0, ΔD
end

# Clear gradients
function clear_grad!(RB::ConditionalResidualBlock)
    RB.W0.grad = nothing
    RB.W1.grad = nothing
    RB.W2.grad = nothing
    RB.W3.grad = nothing
    RB.b0.grad = nothing
    RB.b1.grad = nothing
    RB.b2.grad = nothing
end

"""
    P = get_params(NL::NeuralNetLayer)

 Returns a cell array of all parameters in the network layer. Each cell
 entry contains a reference to the original parameter; i.e. modifying
 the paramters in `P`, modifies the parameters in `NL`.
"""
get_params(RB::ConditionalResidualBlock) = [RB.W0, RB.W1, RB.W2, RB.W3, RB.b0, RB.b1, RB.b2]