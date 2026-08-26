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
    collapse::Bool                 # true only for confluence(f, nodes) — see confluence.jl.
    # Changes the calling convention, not code identity, so — like stale_policy/
    # on_upstream_failure — it's un-hashed Step metadata (see digest(::Step)).
end

function Step(
        f::Function, name::Symbol; outputs = OutputDecl[], depends_on = Function[],
        stale_policy::Symbol = :hash, on_upstream_failure::Symbol = :fail, collapse::Bool = false
    )
    stale_policy in (:hash, :exists) ||
        error("stale_policy must be :hash or :exists, got :$stale_policy")
    on_upstream_failure in (:fail, :skip, :placeholder) ||
        error("on_upstream_failure must be :fail, :skip, or :placeholder, got :$on_upstream_failure")
    return Step(
        f, name, collect(OutputDecl, outputs), collect(Function, depends_on),
        stale_policy, on_upstream_failure, collapse
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

# Sample identity propagates through the graph: an input's own `params` folds in
# automatically, then explicit keywords apply on top. Every element of `inputs` is an
# AbstractArtifact (the Step callable's signature guarantees it); `Output` is the one
# subtype without a `.params` field of its own, so it gets a more specific override below.
paramsof(x::AbstractArtifact) = x.params

function merge_params(inputs, kwparams::NamedTuple)
    merged = NamedTuple()
    for x in inputs
        merged = merge(merged, paramsof(x))
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

# A reference to one specific named output of a multi-output StepInstance (I10 extension:
# a step's return value determines its outputs — a NamedTuple return is N named outputs,
# keyed by its field names; a single value is one, named after the step). `si[:profile]`
# wires that one output into a downstream call exactly like any other artifact.
struct Output <: AbstractArtifact
    si::StepInstance
    name::Symbol
end
Base.getindex(si::StepInstance, name::Symbol) = Output(si, name)
Base.getindex(si::StepInstance, names::Tuple{Vararg{Symbol}}) = map(n -> Output(si, n), names)
paramsof(o::Output) = o.si.params

payload(o::Output) = error(
    "Output :$(o.name) of step :$(o.si.step.name) has not been produced yet — run the graph first."
)

# Combines the parent StepInstance's digest with the output name — not just the parent's
# digest alone, or two different outputs of the same instance (e.g. metaphlan's :sam vs
# :profile) would hash identically as a downstream consumer's input, silently masking a
# wiring mistake.
digest(o::Output) = digest(digest(o.si), digest(string(o.name)))

"""
    concretemethods(f) -> Vector{Method}

`f`'s methods whose signature does *not* mention `AbstractArtifact` — i.e. the user's own
concrete-typed method(s), excluding the `AbstractArtifact...`-dispatching sibling `@step`
generates under the same name. `digest(::Step)` and `assert_no_captures` both use this so
generated graph-building plumbing never leaks into the code hash or the purity check.
"""
concretemethods(f) = [m for m in methods(f) if !isgraphmethod(m)]
isgraphmethod(m::Method) = any(mentions_abstractartifact, Base.unwrap_unionall(m.sig).parameters[2:end])
mentions_abstractartifact(t::Core.TypeofVararg) = isdefined(t, :T) && mentions_abstractartifact(t.T)
mentions_abstractartifact(t::Type) = t <: AbstractArtifact
mentions_abstractartifact(t) = false

"""
    digest(step::Step) -> Digest

Shallow source-text hash (I9): the source of every *concrete-typed* method of `step.f`
(`concretemethods` — excludes any `@step`-generated `AbstractArtifact`-dispatching
sibling), plus every function in `step.depends_on`, concatenated in a deterministic order
and hashed. No automatic transitive callee hashing — that's what `depends_on` is for.
"""
function digest(step::Step)
    ms = concretemethods(step.f)
    assert_no_captures(step.f, ms)
    srcs = String[sourcetext(m) for m in ms]
    for dep in step.depends_on
        assert_no_captures(dep)
        append!(srcs, sourcetext(m) for m in methods(dep))
    end
    sort!(srcs)
    return digest(join(srcs, "\0"))
end

sourcetext(m::Method) = string(CodeTracking.definition(String, m))

"""
    @step function foo(p::AbstractPath; sample)::AbstractPath
        ...
    end

Lift a function authored against **plain values** into a graph citizen (I2, I9): the
original method is left completely untouched (still directly callable/testable on real
values — `foo(a_real_path; sample="x")` runs the body exactly as written, no Hapi types
involved). `@step` adds ONE sibling method under the *same name* that accepts
artifacts/`StepInstance`s and builds a lazy graph node via `Step`'s existing callable —
ordinary multiple dispatch, not the macro, decides which method runs for a given call.

The body stays "normal" on *both* ends: `run` unwraps each input via `payload` before
calling it, and wraps whatever it returns via `artifact`. What a body returns determines
its outputs — not a macro option, decided fresh from the return value each run: a single
value (an `AbstractPath`, say) is one output, named after the step; a `NamedTuple` return
is N named outputs, one per field, each independently committed/hashed/retained — see
`si[:name]`/`Output` for wiring a specific one downstream. Returning an `AbstractArtifact`
directly always passes through `artifact` unchanged (full control — a custom hash, etc.);
that also means an explicitly-constructed `FileGroupArtifact` return is one grouped output,
not several — only a *bare* `NamedTuple` of un-wrapped values means "N separate outputs."

Limitation, disclosed rather than silently mishandled: decorating a *second* concrete-typed
overload of the same name still works for hashing (both methods are concrete, so
`concretemethods`/`digest` see both) but its output declaration/policies replace the
first `@step`'s `Step` — full per-overload metadata merging isn't implemented yet.
"""
macro step(expr)
    def = splitdef(expr)
    name = def[:name]
    name isa Symbol || error("@step requires a plain function name, got $(name)")
    stepvar = gensym(name)
    return quote
        $(esc(combinedef(def)))
        const $(esc(stepvar)) = Step($(esc(name)), $(QuoteNode(name)); outputs = [required($(QuoteNode(name)))])
        $(esc(name))(inputs::AbstractArtifact...; params...) = $(esc(stepvar))(inputs...; params...)
    end
end

# Only the `:native` env resolves today; naming any other env is a loud error rather than
# a silently-wrong hash, since real resolution (JLL/conda/container identity) isn't
# implemented yet (I5). EnvName is a bare `Symbol` alias, not a distinct type, so this
# can't be a `digest` method (dispatching on it would mean dispatching on *any* Symbol) —
# but *within* this function, dispatching on `Val(env)` (rather than branching on `env ===
# :native`) is the ordinary Julia way to switch on a symbol's value.
envdigest(env::EnvName) = envdigest(Val(env))
envdigest(::Val{:native}) = digest("tool-identity:native")
envdigest(::Val{E}) where {E} = error("env resolution for :$E is not implemented — only :native works today.")

"""
    digest(si::StepInstance) -> Digest

A StepInstance's task identity (plan §4): code hash + params + resolved env tool-identity
+ each input's digest, recursing into upstream StepInstances. `resources` never enters
this (I4).
"""
function digest(si::StepInstance)
    return digest(
        si.code_hash, digest(repr(si.params)), envdigest(si.env),
        (digest(x) for x in si.inputs)...
    )
end
