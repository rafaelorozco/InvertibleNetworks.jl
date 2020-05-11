# Activation normalization layer
# Adapted from Kingma and Dhariwal (2018): https://arxiv.org/abs/1807.03039
# Author: Philipp Witte, pwitte3@gatech.edu
# Date: January 2020
#

export ActNorm, reset!

"""
    AN = ActNorm(k; logdet=false)

 Create activation normalization layer. The parameters are initialized during
 the first use, such that the output has zero mean and unit variance along
 channels for the current mini-batch size.

 *Input*:

 - `k`: number of channels

 - `logdet`: bool to indicate whether to compute the logdet

 *Output*:

 - `AN`: Network layer for activation normalization.

 *Usage:*

 - Forward mode: `Y, logdet = AN.forward(X)`

 - Inverse mode: `X = AN.inverse(Y)`

 - Backward mode: `ΔX, X = AN.backward(ΔY, Y)`

 *Trainable parameters:*

 - Scaling factor `AN.s`

 - Bias `AN.b`

 See also: [`get_params`](@ref), [`clear_grad!`](@ref)
"""
struct ActNorm <: NeuralNetLayer
    k::Integer
    s::Parameter
    b::Parameter
    logdet::Bool
end

@Flux.functor ActNorm

# Constructor: Initialize with nothing
function ActNorm(k; logdet=false)
    s = Parameter(nothing)
    b = Parameter(nothing)
    return ActNorm(k, s, b, logdet)
end

# 2D Foward pass: Input X, Output Y
function forward(X::AbstractArray{Float32, 4}, AN::ActNorm)
    nx, ny, n_in, batchsize = size(X)

    # Initialize during first pass such that
    # output has zero mean and unit variance
    if AN.s.data == nothing
        μ = mean(X; dims=(1,2,4))[1,1,:,1]
        σ_sqr = var(X; dims=(1,2,4))[1,1,:,1]
        AN.s.data = 1f0 ./ sqrt.(σ_sqr)
        AN.b.data = -μ ./ sqrt.(σ_sqr)
    end
    Y = X .* reshape(AN.s.data, 1, 1, :, 1) .+ reshape(AN.b.data, 1, 1, :, 1)

    # If logdet true, return as second ouput argument
    AN.logdet == true ? (return Y, logdet_forward(nx, ny, AN.s)) : (return Y)
end

# 3D Foward pass: Input X, Output Y
function forward(X::AbstractArray{Float32, 5}, AN::ActNorm)
    nx, ny, nz, n_in, batchsize = size(X)

    # Initialize during first pass such that
    # output has zero mean and unit variance
    if AN.s.data == nothing
        μ = mean(X; dims=(1,2,3,5))[1,1,1,:,1]
        σ_sqr = var(X; dims=(1,2,3,5))[1,1,1,:,1]
        s.data = 1f0 ./ sqrt.(σ_sqr)
        b.data = -μ ./ sqrt.(σ_sqr)
    end
    Y = X .* reshape(AN.s.data, 1, 1, 1, :, 1) .+ reshape(AN.b.data, 1, 1, 1, :, 1)

    # If logdet true, return as second ouput argument
    AN.logdet == true ? (return Y, logdet_forward(nx, ny, AN.s)) : (return Y)
end

# 2D Inverse pass: Input Y, Output X
function inverse(Y::AbstractArray{Float32, 4}, AN::ActNorm)
    X = (Y .- reshape(AN.b.data, 1, 1, :, 1)) ./ reshape(AN.s.data, 1, 1, :, 1)
    return X
end

# 3D Inverse pass: Input Y, Output X
function inverse(Y::AbstractArray{Float32, 5}, AN::ActNorm)
    X = (Y .- reshape(AN.b.data, 1, 1, 1, :, 1)) ./ reshape(AN.s.data, 1, 1, 1, :, 1)
    return X
end

# 2D Backward pass: Input (ΔY, Y), Output (ΔY, Y)
function backward(ΔY::AbstractArray{Float32, 4}, Y::AbstractArray{Float32, 4}, AN::ActNorm)
    nx, ny, n_in, batchsize = size(Y)
    X = inverse(Y, AN)
    ΔX = ΔY .* reshape(AN.s.data, 1, 1, :, 1)
    Δs = sum(ΔY .* X, dims=(1,2,4))[1, 1, :, 1]
    AN.logdet == true && (Δs -= logdet_backward(nx, ny, AN.s))
    Δb = sum(ΔY, dims=(1,2,4))[1, 1, :, 1]
    AN.s.grad = Δs
    AN.b.grad = Δb
    return ΔX, X
end

# 3D Backward pass: Input (ΔY, Y), Output (ΔY, Y)
function backward(ΔY::AbstractArray{Float32, 5}, Y::AbstractArray{Float32, 5}, AN::ActNorm)
    nx, ny, nz, n_in, batchsize = size(Y)
    X = inverse(Y, AN)
    ΔX = ΔY .* reshape(AN.s.data, 1, 1, 1, :, 1)
    Δs = sum(ΔY .* X, dims=(1,2,3,5))[1, 1, 1, :, 1]
    AN.logdet == true && (Δs -= logdet_backward(nx, ny, nz, AN.s))
    Δb = sum(ΔY, dims=(1,2,3,5))[1, 1, 1, :, 1]
    AN.s.grad = Δs
    AN.b.grad = Δb
    return ΔX, X
end

# Clear gradients
function clear_grad!(AN::ActNorm)
    AN.s.grad = nothing
    AN.b.grad = nothing
end

# Reset actnorm layers
function reset!(AN::ActNorm)
    AN.s.data = nothing
    AN.b.data = nothing
end

function reset!(AN::AbstractArray{ActNorm, 1})
    for j=1:length(AN)
        AN[j].s.data = nothing
        AN[j].b.data = nothing
    end
end

# Get parameters
get_params(AN::ActNorm) = [AN.s, AN.b]

# 2D Logdet
logdet_forward(nx, ny, s) = nx*ny*sum(log.(abs.(s.data)))
logdet_backward(nx, ny, s) = nx*ny ./ s.data

# 3D Logdet
logdet_forward(nx, ny, nz, s) = nx*ny*nz*sum(log.(abs.(s.data)))
logdet_backward(nx, ny, nz, s) = nx*ny*nz ./ s.data
