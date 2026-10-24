"""
    Gathered(items) <: AbstractArtifact

An ordered collection of artifacts that is passed to a step body as one ordinary `Vector`.
"""
struct Gathered <: AbstractArtifact
    items::Vector{AbstractArtifact}
end

payload(gathered::Gathered) = map(payload, gathered.items)
paramsof(::Gathered) = NamedTuple()

function digest(gathered::Gathered)
    parts = Digest[digest("gathered-v1")]
    append!(parts, digest(item) for item in gathered.items)
    return digest(parts...)
end

"""
    gather(items) -> Gathered

Collect a fan-out into one graph input. A step consuming this value receives a `Vector` of
ordinary payloads.
"""
gather(items) = Gathered(collect(AbstractArtifact, items))

"""
    confluence(f, nodes; params...) -> StepInstance

Convenience for applying an ordinary aggregation function to [`gather`](@ref)`(nodes)`.
"""
function confluence(f, nodes; params...)
    return Step(f, nameof(f))(gather(nodes); params...)
end
