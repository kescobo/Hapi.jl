# Execution backends (plan §7). SLURM/AWS still to come. Nothing above `run` may know
# which of these is in use (I1).
abstract type ExecutionBackend end

"""
    Local()

Runs each StepInstance in-process, sequentially. `Distributed` process isolation (the
plan's actual Local backend — "one process per task keeps semantics uniform with cluster
backends") is a near-term follow-up, not dropped: the plan frames the warm worker *pool* as
an optimization over that baseline, not a prerequisite, and this pass is about proving the
execution/commit/cache-hit loop correct before adding process isolation on top of it.
"""
struct Local <: ExecutionBackend end

# The current task's scratch dir, bound around each step body's execution — the same
# ambient-context technique plan §6.3 proposes for env, applied here to "where do I
# write." Defaults to "." (the caller's working directory) so a step's concrete method
# stays directly callable outside `run` — e.g. from a unit test — without needing to fake
# up a `run` context (I2: the body must stay testable on real values).
const CURRENT_SCRATCH = ScopedValue{String}(".")

"""
    output_path(p::AbstractPath; suffix="", ext=nothing) -> AbstractPath
    output_path(ps::NamedTuple; suffix="", ext=nothing) -> NamedTuple

Where a step body should write a new output: alongside `p`'s basename (with `suffix`
appended and `ext` swapped in if given), inside the *current* task's scratch dir. The
`NamedTuple` method applies the same to each path, for a grouped input.
"""
function output_path(p::AbstractPath; suffix::AbstractString = "", ext::Union{Nothing, AbstractString} = nothing)
    base, oldext = splitext(basename(string(p)))
    newext = ext === nothing ? oldext : (startswith(ext, ".") ? ext : "." * ext)
    return Path(joinpath(CURRENT_SCRATCH[], base * suffix * newext))
end
output_path(ps::NamedTuple; kwargs...) = map(p -> output_path(p; kwargs...), ps)

# Rewrite a body's returned artifact (paths still inside the now-moved scratch dir) to
# point at its committed location in the store, with `.hash` set to the StepInstance's own
# digest (re-running an identical StepInstance is guaranteed byte-identical, so a separate
# content re-hash of the output is redundant — see digest(::FileArtifact)).
relocate(fa::FileArtifact, dir::AbstractString, h::Digest) =
    FileArtifact(Path(joinpath(dir, basename(string(fa.path)))), h, fa.params)
relocate(fg::FileGroupArtifact, dir::AbstractString, h::Digest) =
    FileGroupArtifact(map(fa -> relocate(fa, dir, h), fg.files), h, fg.params)

# A step's raw return value determines its outputs (I10 extension, `@step` docs): a bare
# NamedTuple is several independent outputs, each lifted/relocated on its own; anything
# else (a plain value, or an explicitly-constructed artifact — including a FileGroupArtifact,
# which stays ONE grouped output, not several) is the step's one output, named after the
# step itself.
finalizeoutputs(result::NamedTuple, si::StepInstance, dir::AbstractString, h::Digest) =
    NamedTuple(name => relocate(artifact(v, si.params), dir, h) for (name, v) in pairs(result))
finalizeoutputs(result, si::StepInstance, dir::AbstractString, h::Digest) =
    relocate(artifact(result, si.params), dir, h)

relpathof(a::FileArtifact) = basename(string(a.path))

function recordoutputs!(db::SQLite.DB, h::Digest, si::StepInstance, finalized::NamedTuple, policy)
    for (name, art) in pairs(finalized)
        record!(
            db, h, name, :present; output_hash = h, relpath = relpathof(art),
            retention = retentionfor(policy, si.step.name, name)
        )
    end
    return nothing
end
function recordoutputs!(db::SQLite.DB, h::Digest, si::StepInstance, finalized, policy)
    name = si.step.name
    record!(
        db, h, name, :present; output_hash = h, relpath = relpathof(finalized),
        retention = retentionfor(policy, si.step.name, name)
    )
    return nothing
end

"""
    reconstruct(db, si, h) -> AbstractArtifact or NamedTuple

Cache-hit path: rebuild the produced output(s) from the ledger + committed store, without
re-running the step. A single `outputs` row named after the step itself (`finalizeoutputs`'s
convention on the write side) reconstructs as one artifact; anything else — no rows, or
rows under other names — reconstructs as the `NamedTuple` of them. (A step whose one real
output happens to be a 1-field `NamedTuple` named after the step itself is indistinguishable
from a plain single output on reconstruction — a known, narrow ambiguity, not silently
mishandled: it's the same convention on both the write and read side, just not unique.)
"""
function reconstruct(db::SQLite.DB, si::StepInstance, h::Digest)
    orows = outputrows(db, h)
    dir = path(h)
    if length(orows) == 1 && orows[1].name == si.step.name
        r = only(orows)
        return FileArtifact(Path(joinpath(dir, r.relpath)), h, si.params)
    end
    return NamedTuple(r.name => FileArtifact(Path(joinpath(dir, r.relpath)), h, si.params) for r in orows)
end

# The inverse of `targets` (plan.jl): mirror any nested Tuple/NamedTuple/AbstractArray,
# replacing each StepInstance/Output leaf with its produced value and leaving everything
# else untouched. Used both to resolve a StepInstance's own `.inputs` during execution and
# to shape `run`'s return value to match whatever was passed in — one mechanism for both.
resolve(si::StepInstance, produced) = produced[si]
resolve(o::Output, produced) = produced[o.si][o.name]
resolve(x::Tuple, produced) = map(v -> resolve(v, produced), x)
resolve(x::NamedTuple, produced) = map(v -> resolve(v, produced), x)
resolve(x::AbstractArray, produced) = map(v -> resolve(v, produced), x)
resolve(x, produced) = x

"""
    run(x; backend::ExecutionBackend=Local(), retention::Union{Nothing,RetentionPolicy}=nothing)

Execute the graph `targets(x)` finds (push model, I7 — no backward target resolution, just
the wired graph) and return the produced result in the *same shape* as `x` — a single
node, a `Vector`, an arbitrary nested `(; qc, results)`, whatever `x` was. A `StepInstance`
already recorded in the ledger with `status="done"` is a cache hit and is not re-run.
`retention` is a `RetentionPolicy` (see `retention.jl`) consulted when recording each
output's ledger row; omitted, every output records as `:cached`. `:fail` (abort on error,
the default `Base` behaviour of letting the exception propagate) is the only implemented
`on_upstream_failure` policy; `:skip`/`:placeholder` aren't wired up yet.
"""
function Base.run(
        x; backend::ExecutionBackend = Local(),
        retention::Union{Nothing, RetentionPolicy} = nothing
    )
    backend isa Local || error("only the Local backend is implemented today")
    p = plan(x)
    db = ledger()
    produced = Dict{StepInstance, Any}()
    for si in p.order
        h = digest(si)
        rec = row(db, h)
        if rec !== nothing && rec.status == "done"
            produced[si] = reconstruct(db, si, h)
            continue
        end
        resolved = [resolve(inp, produced) for inp in si.inputs]
        scratch = scratchdir()
        result = with(CURRENT_SCRATCH => scratch) do
            si.step.collapse ? si.step.f(payload.(resolved); si.params...) :
                si.step.f(payload.(resolved)...; si.params...)
        end
        dir = commit!(scratch, h)
        finalized = finalizeoutputs(result, si, dir, h)
        record!(db, h, si; status = "done")
        recordoutputs!(db, h, si, finalized, retention)
        produced[si] = finalized
    end
    return resolve(x, produced)
end
