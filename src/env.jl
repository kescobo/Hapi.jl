"""
    EnvSpec

Abstract supertype for the ways a [`StepInstance`](@ref) can resolve the tools it needs:
[`Native`](@ref) (whatever's already on `PATH`), [`JLLEnv`](@ref) (Julia JLL packages),
`CondaEnv`, or `Container`. What matters for caching is the resolved tool *identity* (name
+ version), not which of these delivered it.
"""
abstract type EnvSpec end

"""
    Native()

An [`EnvSpec`](@ref) that uses whatever tools are already available on `PATH`, with no
environment management.
"""
struct Native <: EnvSpec end

"""
    JLLEnv(pkgs::Vector{String})

An [`EnvSpec`](@ref) that resolves tools from Julia JLL packages, e.g.
`JLLEnv(["Samtools_jll@1.17"])`.
"""
struct JLLEnv <: EnvSpec
    pkgs::Vector{String}   # e.g. ["Samtools_jll@1.17"]
end

# Conda env delivery isn't implemented yet. `spec` will be `CondaPkg.PkgSpec` once
# CondaPkg.jl is a dependency — kept structurally present now (plan §3) without pulling in
# a dependency nothing uses yet.
struct CondaEnv <: EnvSpec
    spec::Any
end

# Container execution (apptainer preferred; podman/docker; user-provided images only)
# isn't implemented yet. `binds` will use FilePaths' `AbstractPath` once concrete
# artifacts land.
struct Container <: EnvSpec
    image::String
    runtime::Symbol   # :apptainer (default) | :podman | :docker
    binds::Vector{Pair{Any, Any}}
end

"""
    EnvName

A `Symbol` naming an environment; `HapiEnv.toml` resolves the name to an [`EnvSpec`](@ref).
"""
const EnvName = Symbol

"""
    Resources(cpus=1, mem=nothing, walltime=nothing, gpus=0, extra=Dict{Symbol,Any}())

The compute envelope (CPUs, memory in bytes, walltime, GPUs, and backend-specific extras
such as a SLURM `:partition`) requested for a [`StepInstance`](@ref)'s execution. Purely a
scheduling hint: resources never affect a step's content hash, so bumping walltime and
resubmitting is always cache-valid.
"""
struct Resources
    cpus::Int
    mem::Union{Nothing, Int}         # bytes
    walltime::Union{Nothing, Period}
    gpus::Int
    extra::Dict{Symbol, Any}         # backend-specific (SLURM --partition, etc.)
end

Resources() = Resources(1, nothing, nothing, 0, Dict{Symbol, Any}())
