"""
    AbstractArtifact

Internal representation of a value that can participate in a workflow graph. Step bodies
consume and return ordinary Julia values; Hapi wraps values at graph and execution
boundaries.
"""
abstract type AbstractArtifact end

"""
    payload(artifact::AbstractArtifact)

Recover the ordinary Julia value represented by an artifact.
"""
function payload end

"""
    FileArtifact(path; logical_name=basename(path), hash=nothing, params...)

A file entering or produced by a workflow. Source files are hashed from their contents.
Produced files carry the content hash of the immutable object stored by Hapi. `logical_name`
is the basename exposed to step bodies and participates in task identity independently of
the host or object-store path.
"""
struct FileArtifact <: AbstractArtifact
    path::AbstractPath
    logical_name::String
    hash::Union{Nothing, Digest}
    params::NamedTuple
end

function FileArtifact(
        path;
        logical_name::AbstractString = basename(Path(string(path))),
        hash::Union{Nothing, Digest} = nothing,
        params...,
    )
    validate_logical_name(logical_name)
    return FileArtifact(
        Path(abspath(string(path))),
        String(logical_name),
        hash,
        NamedTuple(params),
    )
end

payload(artifact::FileArtifact) = artifact.path

"""
    logicalname(artifact::FileArtifact) -> String

Return the execution-visible basename associated with a file artifact.
"""
logicalname(artifact::FileArtifact) = artifact.logical_name

function validate_logical_name(name::AbstractString)
    isempty(name) && throw(ArgumentError("a logical filename cannot be empty"))
    name in (".", "..") && throw(ArgumentError("invalid logical filename: $name"))
    occursin('/', name) && throw(ArgumentError("a logical filename cannot contain '/': $name"))
    occursin('\\', name) && throw(ArgumentError("a logical filename cannot contain '\\': $name"))
    occursin('\0', name) && throw(ArgumentError("a logical filename cannot contain NUL"))
    return String(name)
end

"""
    NamedArtifact(values, params)

Internal artifact branch corresponding to an ordinary `NamedTuple`. Keys and nesting are
preserved, so passing the whole branch downstream produces the original `NamedTuple`, while
indexing selects one branch or leaf.
"""
struct NamedArtifact{T <: NamedTuple} <: AbstractArtifact
    values::T
    params::NamedTuple
end

payload(artifact::NamedArtifact) = map(payload, artifact.values)
function Base.getindex(artifact::NamedArtifact, name::Symbol)
    child = artifact.values[name]
    return withparams(child, merge(artifact.params, paramsof(child)))
end

"""
    AbsentArtifact

An intentionally absent named result, represented by `nothing` in an ordinary step return
value.
"""
struct AbsentArtifact <: AbstractArtifact end

payload(::AbsentArtifact) = nothing

"""
    artifact(value, params=NamedTuple()) -> AbstractArtifact

Lift an ordinary Julia result into Hapi's internal artifact representation. Paths become
file leaves, `NamedTuple`s become recursively structured branches, and `nothing` marks an
intentionally absent result.
"""
artifact(path::AbstractPath, params::NamedTuple = NamedTuple()) =
    FileArtifact(path; params...)

function artifact(values::NamedTuple, params::NamedTuple = NamedTuple())
    children = map(value -> artifact(value, NamedTuple()), values)
    return NamedArtifact(children, params)
end

artifact(::Nothing, params::NamedTuple = NamedTuple()) = AbsentArtifact()
artifact(value::AbstractArtifact, params::NamedTuple = NamedTuple()) =
    withparams(value, merge(paramsof(value), params))

digest(path::AbstractPath) = digest(read(string(path)))
contentdigest(artifact::FileArtifact) =
    resolvedhash(artifact.hash, () -> digest(artifact.path))
digest(artifact::FileArtifact) =
    digest(digest("file-artifact-v2"), contentdigest(artifact), digest(artifact.logical_name))
digest(::AbsentArtifact) = digest("absent")

function digest(artifact::NamedArtifact)
    parts = Digest[digest("named-result-v1")]
    for (name, value) in pairs(artifact.values)
        push!(parts, digest(string(name)))
        push!(parts, digest(value))
    end
    return digest(parts...)
end

resolvedhash(hash::Digest, fallback) = hash
resolvedhash(::Nothing, fallback) = fallback()

paramsof(artifact::FileArtifact) = artifact.params
paramsof(artifact::NamedArtifact) = artifact.params
paramsof(::AbsentArtifact) = NamedTuple()

withparams(file::FileArtifact, params::NamedTuple) =
    FileArtifact(file.path, file.logical_name, file.hash, params)
withparams(branch::NamedArtifact, params::NamedTuple) = NamedArtifact(branch.values, params)
withparams(absent::AbsentArtifact, params::NamedTuple) = absent
