"""
    AbstractArtifact

Supertype for everything that can flow into or out of a [`Step`](@ref): [`FileArtifact`](@ref)
(a single file), [`FileGroupArtifact`](@ref) (a named bundle of files), and
[`StepInstance`](@ref)/[`Output`](@ref) (references to a graph node's eventual result). A
serialized-object counterpart for non-path values (`ObjectArtifact`) is planned but not
built yet.

The extension contract for a new artifact type is exactly two methods:
[`payload`](@ref) (unwrap, for step bodies to consume) and [`artifact`](@ref) (wrap, the
inverse, for step bodies to produce).
"""
abstract type AbstractArtifact end

"""
    payload(artifact::AbstractArtifact)

Unwrap `artifact` to the concrete value(s) a step body operates on — a scalar or a
`NamedTuple`, whatever shape the consuming step body wants. This is one half of the
extension contract; see also [`artifact`](@ref), its inverse.
"""
function payload end

"""
    FileArtifact(path; hash=nothing, params...)

A single file (or directory) on disk, tracked by content hash. `params` carries arbitrary
metadata that travels with the file through the graph (e.g. `sample = "S1"`), so a
downstream output can still be traced back to the sample/run that produced it.
"""
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

"""
    FileGroupArtifact(files::NamedTuple; hash=nothing, params...)

A labelled bundle of related files that flow — and hash — as one unit, e.g. paired-end
reads (`(R1=.., R2=..)`) or a BAM plus its index. Members are addressed by role, via
`files`, not by position. Index a `FileGroupArtifact` (`fg[:R1]`, `fg[(:R1, :R2)]`) to pull
one or more members back out as a [`FileArtifact`](@ref)/`FileGroupArtifact` — see the
`getindex` docstring below.
"""
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
merge into a single extracted member — members typically carry none of their own, so
indexing them out raw would silently drop `sample` — but a member's own params, if it ever
has any, win on conflict. A sub-group's `.hash` resets to `nothing` rather than inheriting
the parent's — the subset isn't byte-identical to the whole group — but `digest` on it
still doesn't re-read any files, since each member already carries its own `.hash`.
"""
function Base.getindex(fg::FileGroupArtifact, name::Symbol)
    fa = fg.files[name]::FileArtifact
    return FileArtifact(fa.path, fa.hash, merge(fg.params, fa.params))
end
function Base.getindex(fg::FileGroupArtifact, names::Tuple{Vararg{Symbol}})
    return FileGroupArtifact(fg.files[names], nothing, fg.params)
end

"""
    digest(p::AbstractPath) -> Digest

The content digest of the file at `p` — reads the whole file into memory and hashes it.
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

`x`'s already-recorded `.hash` if it has one (a produced output); otherwise the real
content hash of the underlying file(s) on disk — so a [`source`](@ref) input that Hapi
never produced is correctly seen as a different input if the file on disk changes.
"""
digest(fa::FileArtifact) = resolvedhash(fa.hash, () -> digest(fa.path))
digest(fg::FileGroupArtifact) = resolvedhash(fg.hash, () -> digest((digest(f) for f in fg.files)...))

"""
    artifact(x, params::NamedTuple) -> AbstractArtifact

The inverse of [`payload`](@ref): lift a raw value a step body returned into an artifact,
so the body itself can stay an ordinary function returning plain values (an `AbstractPath`
becomes a [`FileArtifact`](@ref)). A value that's already an `AbstractArtifact` — for full
control over the result, e.g. an explicit hash, or to return a
[`FileGroupArtifact`](@ref) as one grouped output — passes through unchanged, and `params`
is ignored since the body already set its own.
"""
artifact(x::AbstractArtifact, params::NamedTuple) = x
artifact(p::AbstractPath, params::NamedTuple) = FileArtifact(p, nothing, params)
