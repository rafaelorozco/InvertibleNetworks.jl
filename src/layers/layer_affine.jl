# Affine scaling layer
# Author: Philipp Witte, pwitte3@gatech.edu
# Date: January 2020
#

export AffineLayer

"""
    AL = AffineLayer(nx, ny, nc; logdet=false)

 Create a layer for an affine transformation.

 *Input*: 
 
 - `nx`, `ny, `nc`: input dimensions and number of channels 
 
 - `logdet`: bool to indicate whether to compute the logdet

 *Output*:
 
 - `AL`: Network layer for affine transformation.

 *Usage:*

 - Forward mode: `Y, logdet = AL.forward(X)`

 - Inverse mode: `X = AL.inverse(Y)`

 - Backward mode: `ΔX, X = AL.backward(ΔY, Y)`

 *Trainable parameters:*

 - Scaling factor `AL.s`

 - Bias `AL.b`

 See also: [`get_params`](@ref), [`clear_grad!`](@ref)
"""
struct AffineLayer <: NeuralNetLayer
    s::Parameter
    b::Parameter
    logdet::Bool
end

@Flux.functor AffineLayer

# Constructor: Initialize with nothing
function AffineLayer(nx::Int64, ny::Int64, nc::Int64; logdet=false)
    s = Parameter(glorot_uniform(nx, ny, nc))
    b = Parameter(zeros(Float32, nx, ny, nc))
    return AffineLayer(s, b, logdet)
end

# Foward pass: Input X, Output Y
function affine_forward(X, AL::AffineLayer)

    Y = X .* AL.s.data .+ AL.b.data
    
    # If logdet true, return as second ouput argument
    AL.logdet == true ? (return Y, logdet_forward(s)) : (return Y)
end

# Inverse pass: Input Y, Output X
function affine_inverse(Y, AL::AffineLayer)
    X = (Y .- AL.b.data) ./ (AL.s.data + randn(Float32, size(AL.s.data)) .* eps(1f0))   # avoid division by 0
    return X
end

# Backward pass: Input (ΔY, Y), Output (ΔY, Y)
function affine_backward(ΔY, Y, AL::AffineLayer)
    nx, ny, n_in, batchsize = size(Y)
    X = inverse(Y, AL)
    ΔX = ΔY .* AL.s.data
    Δs = sum(ΔY .* X, dims=4)[:,:,:,1]
    AL.logdet == true && (Δs -= logdet_backward(s))
    Δb = sum(ΔY, dims=4)[:,:,:,1]
    AL.s.grad = Δs
    AL.b.grad = Δb
    return ΔX, X
end

# Clear gradients
function clear_grad!(AL::AffineLayer)
    AL.s.grad = nothing
    AL.b.grad = nothing
end

# Get parameters
get_params(AL::AffineLayer) = [AL.s, AL.b]

# Logdet
logdet_forward(s) = sum(log.(abs.(s.data))) 
logdet_backward(s) = 1f0 ./ s.data
