# What a named environment can resolve to (plan.md §3/§6.3). No mechanism is imposed a
# priority over another; the hash contract cares only about resolved tool identity (I5),
# not which of these delivered it.
abstract type EnvSpec end

struct Native <: EnvSpec end

struct JLLEnv <: EnvSpec
    pkgs::Vector{String}   # e.g. ["Samtools_jll@1.17"]
end

# Phase 2: `spec` will be `CondaPkg.PkgSpec` once CondaPkg.jl is a dependency. Kept
# structurally present now (plan §3) without pulling in an unused Phase-2 dependency.
struct CondaEnv <: EnvSpec
    spec::Any
end

# Phase 2: container execution (apptainer preferred; podman/docker; user-provided images
# only). `binds` will use FilePaths' `AbstractPath` once concrete artifacts land.
struct Container <: EnvSpec
    image::String
    runtime::Symbol   # :apptainer (default) | :podman | :docker
    binds::Vector{Pair{Any, Any}}
end

# A StepInstance names its env by this; HapiEnv.toml resolves the name to an EnvSpec.
const EnvName = Symbol

# The execution envelope. NEVER enters the hash contract (I4) — bumping walltime and
# resubmitting must be cache-valid.
struct Resources
    cpus::Int
    mem::Union{Nothing, Int}         # bytes
    walltime::Union{Nothing, Period}
    gpus::Int
    extra::Dict{Symbol, Any}         # backend-specific (SLURM --partition, etc.)
end

Resources() = Resources(1, nothing, nothing, 0, Dict{Symbol, Any}())
