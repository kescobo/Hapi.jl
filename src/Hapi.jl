"""
    Hapi

A workflow engine for content-addressed, cacheable data-processing pipelines.

Pipelines are built by applying [`Step`](@ref)s (wrapped with [`@step`](@ref)) to
[`AbstractArtifact`](@ref)s — typically [`FileArtifact`](@ref)/[`FileGroupArtifact`](@ref)
produced by [`source`](@ref) — which lazily builds a graph of [`StepInstance`](@ref)s.
Call [`run`](@ref) on the result (or any nested collection of results) to execute the
graph: each step's inputs and code are content-hashed, outputs are committed to a
content-addressed store, and a step whose hash is already recorded is skipped rather than
re-run. [`retention`](@ref) attaches a publish/cache/temp policy to specific outputs.
"""
module Hapi

export AbstractArtifact, payload, artifact, FileArtifact, FileGroupArtifact,
    EnvSpec, Native, JLLEnv, CondaEnv, Container, EnvName, Resources,
    Digest, digest,
    OutputDecl, required, optional, Step, StepInstance, Output, @step,
    path, scratchdir, commit!,
    ledger, record!, row, outputrows,
    PlanResult, plan, targets,
    ExecutionBackend, Local,
    source, glob_table,
    confluence,
    RetentionPolicy, retention, retentionfor,
    AbstractPath, Path

using Dates: Period
using SHA: sha256
using CodeTracking
using SQLite
using DBInterface
using FilePathsBase: AbstractPath, Path
using MacroTools: splitdef, combinedef
using Tables

include("hashing.jl")
include("artifacts.jl")
include("env.jl")
include("steps.jl")
include("store.jl")
include("ledger.jl")
include("plan.jl")
include("source.jl")
include("retention.jl")
include("confluence.jl")
include("backends.jl")

end # module
