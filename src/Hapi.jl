"""
    Hapi

A workflow engine for content-addressed, cacheable data-processing pipelines.

Ordinary Julia functions become lazy workflow steps by adding [`@step`](@ref). Direct calls
on ordinary values still execute the original body; calls on values produced by [`source`](@ref)
or another step build a graph of [`StepInstance`](@ref)s. [`run`](@ref) executes that graph,
validates returned paths, stores files by content hash, and records a transactional result
manifest for reproducible cache hits.
"""
module Hapi

export AbstractArtifact, payload, FileArtifact, logicalname,
    ExtensionPolicy, DEFAULT_EXTENSION_POLICY, addsuffixes, splitname, with_stem_suffix,
    EnvName, Resources,
    Digest, digest,
    Step, StepInstance, Output, @step,
    path, scratchdir, commit!,
    ledger, record!, row, resultrows,
    PlanResult, plan, targets,
    ExecutionBackend, Local,
    source, glob_table,
    gather, confluence,
    AbstractPath, Path, @p_str

using Dates: Period, now
using SHA: sha256
using CodeTracking
using SQLite
using DBInterface
using FilePathsBase: AbstractPath, Path, @p_str, hasparent
using MacroTools: splitdef, combinedef, prewalk
using Tables

include("hashing.jl")
include("names.jl")
include("artifacts.jl")
include("env.jl")
include("steps.jl")
include("store.jl")
include("ledger.jl")
include("confluence.jl")
include("plan.jl")
include("source.jl")
include("backends.jl")

end # module
