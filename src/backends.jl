"""
    ExecutionBackend

Supertype for where/how [`run`](@ref) actually executes a graph's [`StepInstance`](@ref)s.
[`Local`](@ref) is the only backend implemented today; SLURM/AWS backends are planned.
Nothing above `run` needs to know which backend is in use.
"""
abstract type ExecutionBackend end

"""
    Local()

An [`ExecutionBackend`](@ref) that runs each [`StepInstance`](@ref) in-process,
sequentially, with no process isolation between steps.
"""
struct Local <: ExecutionBackend end

# `collapse` (confluence.jl) selects a calling convention, not a value — dispatch on
# `Val(step.collapse)` rather than branching on the Bool directly.
callstep(step::Step, args, params) = callstep(Val(step.collapse), step, args, params)
callstep(::Val{true}, step::Step, args, params) = step.f(args; params...)
callstep(::Val{false}, step::Step, args, params) = step.f(args...; params...)

# Rewrite a body's returned artifact — written to a path *relative to the scratch dir
# it ran in* (see `run`'s `cd(scratch) do ... end` below) — to its committed absolute
# location, preserving any subdirectory structure the body created (`mkpath("logs");
# write("logs/x.txt", ...)` commits to `$dir/logs/x.txt`, not just `$dir/x.txt`), with
# `.hash` set to the StepInstance's own digest (re-running an identical StepInstance is
# guaranteed byte-identical, so a separate content re-hash of the output is redundant —
# see digest(::FileArtifact)).
relocate(fa::FileArtifact, dir::AbstractString, h::Digest) =
    FileArtifact(Path(joinpath(dir, string(fa.path))), h, fa.params)
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

# The committed file's path, relative to its StepInstance's store dir — recorded in the
# ledger so a cache hit (`reconstruct`) can rebuild the artifact without re-running.
relpathof(a::FileArtifact, dir::AbstractString) = relpath(string(a.path), dir)

function recordoutputs!(db::SQLite.DB, h::Digest, si::StepInstance, finalized::NamedTuple, dir::AbstractString, policy)
    for (name, art) in pairs(finalized)
        record!(
            db, h, name, :present; output_hash = h, relpath = relpathof(art, dir),
            retention = retentionfor(policy, si.step.name, name)
        )
    end
    return nothing
end
function recordoutputs!(db::SQLite.DB, h::Digest, si::StepInstance, finalized, dir::AbstractString, policy)
    name = si.step.name
    record!(
        db, h, name, :present; output_hash = h, relpath = relpathof(finalized, dir),
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

Execute the graph reachable from `x` — a [`StepInstance`](@ref), or any nested
`Tuple`/`NamedTuple`/`Vector` of them — and return the produced result in the same shape
as `x` was given. A `StepInstance` already recorded as done is a cache hit and is not
re-run. `retention` is a [`RetentionPolicy`](@ref) consulted when recording each output;
if omitted, every output records as `:cached`. `:fail` (the default — let the exception
propagate) is the only implemented `on_upstream_failure` policy today.

Each step runs with the working directory `cd`'d into a fresh scratch directory, so a step
body can write outputs at plain, ordinary relative paths (`"trimmed.txt"`,
`"logs/run.log"`, ...) with no Hapi-specific call involved; `run` is what commits whatever
the body wrote into the content-addressed store. Because of this, the identical function
used inside `run` is also directly callable outside it (from a REPL, a unit test, ...) — it
just writes relative to the caller's own working directory, like any ordinary function.
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
        if !isnothing(rec) && rec.status == "done"
            produced[si] = reconstruct(db, si, h)
            continue
        end
        resolved = [resolve(inp, produced) for inp in si.inputs]
        scratch = scratchdir()
        result = cd(scratch) do
            callstep(si.step, payload.(resolved), si.params)
        end
        dir = commit!(scratch, h)
        finalized = finalizeoutputs(result, si, dir, h)
        record!(db, h, si; status = "done")
        recordoutputs!(db, h, si, finalized, dir, retention)
        produced[si] = finalized
    end
    return resolve(x, produced)
end
