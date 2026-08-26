"""
    PlanResult

`order` is the given target(s) and everything upstream of them, in dependency-first
topological order. `frontier` is a forward-compat hook for dynamic (unknown-cardinality)
outputs, a feature that doesn't exist yet — it is always `false` today.
"""
struct PlanResult
    order::Vector{StepInstance}
    frontier::Bool
end

"""
    targets(x) -> Vector{StepInstance}

Every `StepInstance` reachable from `x` by walking `Tuple`/`NamedTuple`/`AbstractArray`
nesting — a `StepInstance` (or `Output`, resolved to its parent) is a leaf; anything else
is ignored. This is what lets `plan`/`run`/`retention` take whatever ordinary Julia value
a pipeline function returns (a single node, a `Vector`, `(; qc, results)`, ...) instead of
requiring it pre-flattened.
"""
targets(x) = targets!(StepInstance[], x)
targets!(acc::Vector{StepInstance}, si::StepInstance) = push!(acc, si)
targets!(acc::Vector{StepInstance}, o::Output) = targets!(acc, o.si)
function targets!(acc::Vector{StepInstance}, x::Union{Tuple, NamedTuple, AbstractArray})
    for v in x
        targets!(acc, v)
    end
    return acc
end
targets!(acc::Vector{StepInstance}, x) = acc

"""
    plan(x) -> PlanResult

Build the execution order for every `StepInstance` [`targets`](@ref)`(x)` finds, and
everything they (transitively) depend on. A pure graph walk over `.inputs` — no I/O, no
backend knowledge; nothing about how the graph will eventually be executed is decided here.
"""
function plan(x)::PlanResult
    order = StepInstance[]
    visiting = Set{StepInstance}()
    visited = Set{StepInstance}()
    for target in targets(x)
        visit!(order, visiting, visited, target)
    end
    return PlanResult(order, false)
end

function visit!(order, visiting, visited, node::StepInstance)
    node in visited && return nothing
    node in visiting && error("cycle detected in graph at step :$(node.step.name)")
    push!(visiting, node)
    for input in node.inputs
        visitinput!(order, visiting, visited, input)
    end
    delete!(visiting, node)
    push!(visited, node)
    push!(order, node)
    return nothing
end

visitinput!(order, visiting, visited, input::StepInstance) = visit!(order, visiting, visited, input)
visitinput!(order, visiting, visited, input::Output) = visit!(order, visiting, visited, input.si)
visitinput!(order, visiting, visited, input) = nothing
