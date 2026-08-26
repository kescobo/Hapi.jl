# The trait every input type implements (plan.md §3, I10). Concrete subtypes
# (FileArtifact, ObjectArtifact, FileGroupArtifact, StoredRef, Reference) don't exist yet —
# they're built on top of this once real artifacts start flowing through steps.
abstract type AbstractArtifact end

"""
    payload(artifact::AbstractArtifact)

Unwrap `artifact` to the concrete value(s) a step body operates on — a scalar or a
`NamedTuple`, whatever shape the consuming step body wants. This is the entire
extension contract: a type flows through steps by implementing this one method.
"""
function payload end

# A file (or directory) on disk, tracked by content hash (plan §3).
struct FileArtifact <: AbstractArtifact
    path::AbstractPath
    hash::Union{Nothing, Digest}
    params::NamedTuple
end
function FileArtifact(path; hash::Union{Nothing, Digest} = nothing, params...)
    # Absolute, regardless of what's given: `run` (backends.jl) `cd`s into a step's
    # scratch dir while it executes, so a relative path would silently break once the
    # working directory changes underneath it.
    p = Path(abspath(string(path)))
    return FileArtifact(p, hash, NamedTuple(params))
end
payload(fa::FileArtifact) = fa.path

# A labelled bundle of related files that flow — and hash — as one unit (paired-end
# reads, a BAM+index): members are addressed by ROLE, in `files`, not by position.
struct FileGroupArtifact <: AbstractArtifact
    files::NamedTuple
    hash::Union{Nothing, Digest}
    params::NamedTuple
end
function FileGroupArtifact(files::NamedTuple; hash::Union{Nothing, Digest} = nothing, params...)
    return FileGroupArtifact(files, hash, NamedTuple(params))
end
payload(fg::FileGroupArtifact) = map(payload, fg.files)

"""
    fg[name::Symbol] -> FileArtifact
    fg[names::Tuple{Vararg{Symbol}}] -> FileGroupArtifact

Pull one member out (e.g. `reads[:R1]`, to pass it as a separate positional argument to a
step that wants R1/R2 apart rather than as one grouped `NamedTuple` input) or a sub-group
over several (mirrors `NamedTuple`'s own indexing: one key unwraps to the scalar, a tuple
of keys gives back the same container type, not a bare collection). The group's `params`
merge into a single extracted member — members carry none of their own, so indexing them
out raw would silently drop `sample`; a member's own params, if it ever has any, win on
conflict. A sub-group's `.hash` resets to `nothing` rather than inheriting the parent's —
the subset isn't byte-identical to the whole group — but `digest` on it still doesn't
re-read any files, since each member already carries its own `.hash`.
"""
function Base.getindex(fg::FileGroupArtifact, name::Symbol)
    fa = fg.files[name]
    return FileArtifact(fa.path, fa.hash, merge(fg.params, fa.params))
end
function Base.getindex(fg::FileGroupArtifact, names::Tuple{Vararg{Symbol}})
    return FileGroupArtifact(fg.files[names], nothing, fg.params)
end

"""
    digest(p::AbstractPath) -> Digest

The content digest of the file at `p` — reads the whole file into memory and hashes it
(streaming is a later optimization, not needed for this size of workload yet).
"""
digest(p::AbstractPath) = digest(read(string(p)))

# Dispatches on the *extracted* `.hash` field's type instead of branching on `!== nothing`
# — `fallback` is a thunk so the (potentially expensive: reads a whole file) un-produced
# case is never evaluated when a hash is already there.
resolvedhash(h::Digest, fallback) = h
resolvedhash(::Nothing, fallback) = fallback()

"""
    digest(x::FileArtifact) -> Digest
    digest(x::FileGroupArtifact) -> Digest

An already-produced artifact's `.hash` (set to the producing StepInstance's own digest —
re-running an identical StepInstance is guaranteed byte-identical by the hash contract, so
a separate content re-hash is redundant); otherwise (a `source` input Hapi never produced)
the real content hash of the file(s) on disk, so a source file changing on disk is
correctly seen as a different input.
"""
digest(fa::FileArtifact) = resolvedhash(fa.hash, () -> digest(fa.path))
digest(fg::FileGroupArtifact) = resolvedhash(fg.hash, () -> digest((digest(f) for f in fg.files)...))

"""
    artifact(x, params::NamedTuple) -> AbstractArtifact

The inverse of `payload`: lift one raw value a step body returned into an artifact, so a
body can return *plain* values (`AbstractPath`) and stay an ordinary, non-Hapi function —
`run` calls this on the body's return value, or on each field of it when a `NamedTuple`
return means several independent outputs (`@step`/multi-output, `backends.jl`) rather than
one grouped artifact. An `AbstractPath` becomes a `FileArtifact`. A body that already
returns an `AbstractArtifact` — for full control over an explicit hash, etc., or to return
one *grouped* output (`FileGroupArtifact((R1=.., R2=..); sample)` stays one output, not
two) — passes through unchanged; `params` is ignored in that case, since the body set its
own.
"""
artifact(x::AbstractArtifact, params::NamedTuple) = x
artifact(p::AbstractPath, params::NamedTuple) = FileArtifact(p, nothing, params)
