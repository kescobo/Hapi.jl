# The definition side (plan.md §3): a pure, testable callable plus its policies. Carries
# NOTHING execution-related (I6) — env/resources are instance-level, attached below.
struct OutputDecl
    name::Symbol
    optional::Bool
end
required(name::Symbol) = OutputDecl(name, false)
optional(name::Symbol) = OutputDecl(name, true)

struct Step
    f::Function
    name::Symbol
    outputs::Vector{OutputDecl}
    depends_on::Vector{Function}   # explicit code deps folded into digest(::Step) (I9)
    stale_policy::Symbol           # :hash (default) | :exists
    on_upstream_failure::Symbol    # :fail (default) | :skip | :placeholder
end

function Step(
        f::Function, name::Symbol; outputs = OutputDecl[], depends_on = Function[],
        stale_policy::Symbol = :hash, on_upstream_failure::Symbol = :fail
    )
    stale_policy in (:hash, :exists) ||
        error("stale_policy must be :hash or :exists, got :$stale_policy")
    on_upstream_failure in (:fail, :skip, :placeholder) ||
        error("on_upstream_failure must be :fail, :skip, or :placeholder, got :$on_upstream_failure")
    return Step(
        f, name, collect(OutputDecl, outputs), collect(Function, depends_on),
        stale_policy, on_upstream_failure
    )
end

# Calling a Step returns this — a lazy graph node, NOT a computed result (I3). `inputs`
# holds concrete AbstractArtifacts and/or upstream StepInstances, which is what lets calls
# nest and any composition syntax (`|>`, `@chain`, plain nesting) build the graph for free.
struct StepInstance <: AbstractArtifact
    step::Step
    code_hash::Digest
    inputs::Vector{AbstractArtifact}
    params::NamedTuple
    retention::Symbol   # :temp | :cached (default) | :published
    env::EnvName
    resources::Resources
end

# Sample identity propagates through the graph: an input's own `params` (if it has any)
# folds in automatically, then explicit keywords apply on top.
function merge_params(inputs, kwparams::NamedTuple)
    merged = NamedTuple()
    for x in inputs
        hasfield(typeof(x), :params) && (merged = merge(merged, x.params))
    end
    return merge(merged, kwparams)
end

# Application builds the graph; it never runs `f` (I3). Env/resources default to native/
# unset and are overridden later by env!/resources!, never at definition (I6).
function (s::Step)(inputs::AbstractArtifact...; params...)
    return StepInstance(
        s, digest(s), collect(AbstractArtifact, inputs),
        merge_params(inputs, NamedTuple(params)), :cached, :native, Resources()
    )
end

# A node's payload is its eventual output's payload, available only once the graph has
# actually been run and committed to the store — execution isn't implemented yet.
payload(si::StepInstance) = error(
    "StepInstance for step :$(si.step.name) has not been produced yet — run the graph first."
)

"""
    digest(step::Step) -> Digest

Shallow source-text hash (I9): the source of every method of `step.f`, plus every
function in `step.depends_on`, concatenated in a deterministic order and hashed. No
automatic transitive callee hashing — that's what `depends_on` is for.
"""
function digest(step::Step)
    assert_no_captures(step.f)
    srcs = String[sourcetext(m) for m in methods(step.f)]
    for dep in step.depends_on
        assert_no_captures(dep)
        append!(srcs, sourcetext(m) for m in methods(dep))
    end
    sort!(srcs)
    return digest(join(srcs, "\0"))
end

sourcetext(m::Method) = string(CodeTracking.definition(String, m))

# Only the `:native` env resolves today; naming any other env is a loud error rather than
# a silently-wrong hash, since real resolution (JLL/conda/container identity) isn't
# implemented yet (I5). Not a `digest` method: EnvName is a bare `Symbol` alias, not a
# distinct type, so dispatching on it would mean dispatching on *any* Symbol.
envdigest(env::EnvName) =
    env === :native ? digest("tool-identity:native") :
    error("env resolution for :$env is not implemented — only :native works today.")

"""
    digest(x::AbstractArtifact) -> Digest
    digest(si::StepInstance) -> Digest

An artifact's content digest — its `.hash` field once produced, or (for a `StepInstance`,
which is more specific and so takes precedence) its task identity (plan §4): code hash +
params + resolved env tool-identity + each input's digest, recursing into upstream
StepInstances. `resources` never enters this (I4).
"""
digest(x::AbstractArtifact) =
    hasfield(typeof(x), :hash) && x.hash !== nothing ? x.hash::Digest : digest(repr(x))

function digest(si::StepInstance)
    return digest(
        si.code_hash, digest(repr(si.params)), envdigest(si.env),
        (digest(x) for x in si.inputs)...
    )
end
