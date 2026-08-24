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

# Cache-hit path: rebuild the produced artifact from what's already committed, without
# re-running the step. Only handles the single-file-output case this pass's Steps actually
# produce (`outputs=[required(name)]`, one `output_path` write) — a committed dir with more
# than one file would need a persisted manifest to reconstruct correctly, not implemented
# yet, so it errors clearly rather than guessing.
function reconstruct(si::StepInstance, h::Digest)
    dir = path(h)
    files = readdir(dir)
    length(files) == 1 || error(
        "cache-hit reconstruction for a multi-file output isn't implemented yet " *
            "(committed dir for :$(si.step.name) at $h has $(length(files)) files)"
    )
    return FileArtifact(Path(joinpath(dir, only(files))), h, si.params)
end

"""
    run(target::StepInstance; backend::ExecutionBackend=Local())
    run(targets::AbstractVector{<:StepInstance}; backend::ExecutionBackend=Local())

Execute the graph reachable from `target(s)` (push model, I7 — no backward target
resolution, just the wired graph) and return the produced artifact(s), in the same
shape as the input (one artifact, or a vector). A `StepInstance` already recorded in the
ledger with `status="done"` is a cache hit and is not re-run. `:fail` (abort on error,
the default `Base` behaviour of letting the exception propagate) is the only implemented
`on_upstream_failure` policy; `:skip`/`:placeholder` aren't wired up yet.
"""
Base.run(target::StepInstance; backend::ExecutionBackend = Local()) = only(run([target]; backend))

function Base.run(targets::AbstractVector{<:StepInstance}; backend::ExecutionBackend = Local())
    backend isa Local || error("only the Local backend is implemented today")
    p = plan(targets)
    db = ledger()
    produced = Dict{StepInstance, AbstractArtifact}()
    for si in p.order
        h = digest(si)
        rec = row(db, h)
        if rec !== nothing && rec.status == "done"
            produced[si] = reconstruct(si, h)
            continue
        end
        resolved = [x isa StepInstance ? produced[x] : x for x in si.inputs]
        scratch = scratchdir()
        result = with(CURRENT_SCRATCH => scratch) do
            si.step.f(payload.(resolved)...; si.params...)
        end
        dir = commit!(scratch, h)
        finalized = relocate(artifact(result, si.params), dir, h)
        record!(db, h, si; status = "done")
        record!(db, h, only(si.step.outputs).name, :present; output_hash = h)
        produced[si] = finalized
    end
    return [produced[t] for t in targets]
end
