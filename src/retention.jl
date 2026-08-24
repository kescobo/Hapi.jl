"""
    RetentionPolicy

A pipeline-level overlay of retention classes, keyed by step name (applies to all of that
step's outputs) or by step name + output name (applies to just that one). Retention is
pipeline policy, not step definition (I6's env/resources layering applied to retention
too) — `@step` never declares it; `retention(...)` builds this immutably and `run(...;
retention=...)` is the only place it's consulted.
"""
struct RetentionPolicy
    whole_step::Dict{Symbol, Symbol}
    per_output::Dict{Symbol, Dict{Symbol, Symbol}}
end

"""
    retention(x, pairs::Pair...) -> RetentionPolicy

Build a retention overlay for the graph reachable from `x` — the full transitive ancestry
(`plan(x).order`), not just `x`'s own top-level shape, since a step like `:concatenate` is
typically an upstream *ancestor* of whatever `x` holds directly, not something `x` names.
Each pair is `step_name => retention` (applies to every output of that step) or
`step_name => (output_name = retention, ...)` (applies to just those named outputs, e.g.
`:metaphlan => (bowtie2 = :published,)`). Validated against the graph's actual step names —
an unknown step name errors here rather than silently doing nothing at run time. Output
names can't be validated the same way (they're only known once a multi-output step has
actually run), so an output name that never exists is silently inert, not an error.
"""
function retention(x, pairs::Pair...)
    known = Set(si.step.name for si in plan(x).order)
    whole_step = Dict{Symbol, Symbol}()
    per_output = Dict{Symbol, Dict{Symbol, Symbol}}()
    for (step_name, spec) in pairs
        step_name isa Symbol || error("retention: step name must be a Symbol, got $(typeof(step_name))")
        step_name in known ||
            error("retention: no step named :$step_name found in the given graph")
        if spec isa Symbol
            spec in (:temp, :cached, :published) ||
                error("retention: value for :$step_name must be :temp, :cached, or :published, got :$spec")
            whole_step[step_name] = spec
        elseif spec isa NamedTuple
            entry = get!(per_output, step_name, Dict{Symbol, Symbol}())
            for name in propertynames(spec)
                merge!(entry, Dict(name => spec[name]))
            end
        else
            error(
                "retention: value for :$step_name must be a Symbol (whole step) or a " *
                    "NamedTuple (per output), got $(typeof(spec))"
            )
        end
    end
    return RetentionPolicy(whole_step, per_output)
end

"""
    retentionfor(policy, step_name, output_name) -> Symbol

The effective retention for one output under `policy` — per-output override, then
whole-step override, then `:cached`. `policy === nothing` (no overlay given to `run`)
always yields `:cached`.
"""
function retentionfor(policy::Union{Nothing, RetentionPolicy}, step_name::Symbol, output_name::Symbol)
    policy === nothing && return :cached
    haskey(policy.per_output, step_name) && haskey(policy.per_output[step_name], output_name) &&
        return policy.per_output[step_name][output_name]
    haskey(policy.whole_step, step_name) && return policy.whole_step[step_name]
    return :cached
end
