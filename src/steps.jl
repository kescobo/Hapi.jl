"""
    OutputDecl(name::Symbol, optional::Bool)

Declares one of a [`Step`](@ref)'s named outputs. Build one with [`required`](@ref) or
[`optional`](@ref) rather than calling `OutputDecl` directly.
"""
struct OutputDecl
    name::Symbol
    optional::Bool
end

"""
    required(name::Symbol) -> OutputDecl

An [`OutputDecl`](@ref) for an output that must be present.
"""
required(name::Symbol) = OutputDecl(name, false)

"""
    optional(name::Symbol) -> OutputDecl

An [`OutputDecl`](@ref) for an output that may be legitimately absent.
"""
optional(name::Symbol) = OutputDecl(name, true)

"""
    Step(f::Function, name::Symbol; outputs=OutputDecl[], depends_on=Function[],
         stale_policy=:hash, on_upstream_failure=:fail, collapse=false)

A pipeline step definition: a pure, testable callable `f` plus its policies. A `Step`
carries no execution state — no environment, no resources — those are bound per call, on
the [`StepInstance`](@ref) it produces when applied to inputs.

`depends_on` lists helper functions whose source should be folded into this step's code
hash (`f`'s own body is hashed automatically; it does not transitively hash callees).
`stale_policy` is `:hash` (content-hash based staleness, the default) or `:exists`.
`on_upstream_failure` is `:fail` (the default; only value implemented today), `:skip`, or
`:placeholder`. `collapse` is set by [`confluence`](@ref) and should not be passed
directly — it changes the calling convention (the whole input collection passed as one
argument, rather than splatted) without affecting code identity.

Most steps are defined via [`@step`](@ref) rather than by calling `Step` directly.
"""
struct Step
    f::Function
    name::Symbol
    outputs::Vector{OutputDecl}
    depends_on::Vector{Function}
    stale_policy::Symbol           # :hash (default) | :exists
    on_upstream_failure::Symbol    # :fail (default) | :skip | :placeholder
    collapse::Bool                 # true only for confluence(f, nodes) — see confluence.jl
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

"""
    StepInstance <: AbstractArtifact

A lazy graph node produced by calling a [`Step`](@ref) on its inputs — **not** a computed
result. `inputs` holds concrete artifacts and/or upstream `StepInstance`s, which is what
lets calls nest (and ordinary composition — `|>`, `@chain`, plain nesting) build the graph
for free, with no separate composition syntax needed. Call [`run`](@ref) on a
`StepInstance` (or a collection containing one) to actually execute it.
"""
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

# Application builds the graph; it never runs `f`. Env/resources default to native/unset
# and are overridden later by env!/resources!, never at definition.
function (s::Step)(inputs::AbstractArtifact...; params...)
    return StepInstance(
        s, digest(s), collect(AbstractArtifact, inputs),
        merge_params(inputs, NamedTuple(params)), :cached, :native, Resources()
    )
end

# A node's payload is its eventual output's payload, available only once `run` has actually
# executed and committed it — calling `payload` on a StepInstance before that is a mistake.
payload(si::StepInstance) = error(
    "StepInstance for step :$(si.step.name) has not been produced yet — run the graph first."
)

"""
    Output <: AbstractArtifact

A reference to one specific named output of a multi-output [`StepInstance`](@ref) —
returned by indexing the instance, `si[:profile]` or `si[(:profile, :bowtie2)]`
(see [`StepInstance`](@ref)'s `getindex` methods) — and usable anywhere a downstream step
expects an artifact input.
"""
struct Output <: AbstractArtifact
    si::StepInstance
    name::Symbol
end

"""
    si[name::Symbol] -> Output
    si[names::Tuple{Vararg{Symbol}}] -> Vector{Output}

Reference one (or several) of a multi-output [`StepInstance`](@ref)'s named outputs, e.g.
`metaphlan_result[:profile]` to pass just that output downstream. `si.step`'s output names
come from the return value of the step's body at run time (see [`@step`](@ref)).
"""
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

A shallow source-text hash of `step`'s code: the source of every *concrete-typed* method of
`step.f` (excluding any `@step`-generated `AbstractArtifact`-dispatching sibling), plus
every function in `step.depends_on`, concatenated in a deterministic order and hashed. This
does not transitively hash callees — list any helper function whose changes should
invalidate the cache in `depends_on`.
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

Lift a function authored against **plain values** into a pipeline step. The original
method is left completely untouched — it stays directly callable/testable on real values
(`foo(a_real_path; sample="x")` runs the body exactly as written, no Hapi types involved).
`@step` adds one sibling method under the *same name* that accepts artifacts/
[`StepInstance`](@ref)s instead and builds a lazy graph node; ordinary multiple dispatch,
not the macro, decides which method runs for a given call.

The body stays a plain function on both ends: [`run`](@ref) unwraps each input via
[`payload`](@ref) before calling it, and wraps whatever it returns via [`artifact`](@ref).
What the body returns determines its outputs, decided fresh from the return value each run:
a single value (an `AbstractPath`, say) is one output, named after the step; a `NamedTuple`
return is N named outputs, one per field, each independently committed/hashed/retained —
see [`Output`](@ref) for wiring one of them downstream via `si[:name]`. Returning an
`AbstractArtifact` directly always passes through [`artifact`](@ref) unchanged (full
control over the result — a custom hash, etc.); this also means an explicitly-constructed
[`FileGroupArtifact`](@ref) return is one grouped output, not several — only a *bare*
`NamedTuple` of un-wrapped values means "N separate outputs."

Current limitation: decorating a *second* concrete-typed overload of the same name still
works for hashing (both methods are concrete, so both are included), but its output
declaration/policies replace the first `@step`'s `Step` rather than merging with it.
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

A `StepInstance`'s task identity: its step's code hash, its `params`, its resolved
environment's tool identity, and each input's digest (recursing into upstream
`StepInstance`s). `si.resources` never enters this — resource changes never invalidate the
cache.
"""
function digest(si::StepInstance)
    return digest(
        si.code_hash, digest(repr(si.params)), envdigest(si.env),
        (digest(x) for x in si.inputs)...
    )
end
