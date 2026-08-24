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
    p = path isa AbstractPath ? path : Path(String(path))
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
    digest(p::AbstractPath) -> Digest

The content digest of the file at `p` — reads the whole file into memory and hashes it
(streaming is a later optimization, not needed for this size of workload yet).
"""
digest(p::AbstractPath) = digest(read(string(p)))

"""
    digest(x::FileArtifact) -> Digest
    digest(x::FileGroupArtifact) -> Digest

An already-produced artifact's `.hash` (set to the producing StepInstance's own digest —
re-running an identical StepInstance is guaranteed byte-identical by the hash contract, so
a separate content re-hash is redundant); otherwise (a `source` input Hapi never produced)
the real content hash of the file(s) on disk, so a source file changing on disk is
correctly seen as a different input.
"""
digest(fa::FileArtifact) = fa.hash !== nothing ? fa.hash : digest(fa.path)
digest(fg::FileGroupArtifact) = fg.hash !== nothing ? fg.hash : digest((digest(f) for f in fg.files)...)

"""
    artifact(x, params::NamedTuple) -> AbstractArtifact

The inverse of `payload`: lift a step body's raw return value into an artifact, so an
authored function can take and return *plain* values (`AbstractPath`, a `NamedTuple` of
paths) and stay an ordinary, non-Hapi function — `run` calls this after the body returns.
Dispatches on what came back: an `AbstractPath` becomes a `FileArtifact`; a `NamedTuple` of
paths becomes a `FileGroupArtifact` (each member lifted the same way, with no params of its
own — the group carries the shared `params`, matching plan §3's own construction pattern).
A body that already returns an `AbstractArtifact` — for full control over retention, a
custom hash, etc. — passes through unchanged; `params` is ignored in that case, since the
body set its own.
"""
artifact(x::AbstractArtifact, params::NamedTuple) = x
artifact(p::AbstractPath, params::NamedTuple) = FileArtifact(p, nothing, params)
artifact(ps::NamedTuple, params::NamedTuple) = FileGroupArtifact(map(p -> artifact(p, NamedTuple()), ps), nothing, params)
