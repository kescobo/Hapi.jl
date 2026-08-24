"""
    PlanResult

`order` is the given target(s) and everything upstream of them, in dependency-first
topological order. `frontier` is the I11c forward-compat hook: once dynamic
(unknown-cardinality) outputs land, the execution loop will check it; it is always `false`
today.
"""
struct PlanResult
    order::Vector{StepInstance}
    frontier::Bool
end

"""
    plan(target::StepInstance) -> PlanResult
    plan(targets::AbstractVector{<:StepInstance}) -> PlanResult

Build the execution order for one or several targets and everything they (transitively)
depend on — the vector form is what `Base.map`-based fan-out (plan §6) has to `run`. A
pure graph walk over `.inputs` — no I/O, no backend knowledge (I1); nothing upstream of
`run` may depend on how the graph will eventually be executed.
"""
plan(target::StepInstance)::PlanResult = plan([target])

function plan(targets::AbstractVector{<:StepInstance})::PlanResult
    order = StepInstance[]
    visiting = Set{StepInstance}()
    visited = Set{StepInstance}()
    for target in targets
        visit!(order, visiting, visited, target)
    end
    return PlanResult(order, false)
end

function visit!(order, visiting, visited, node::StepInstance)
    node in visited && return nothing
    node in visiting && error("cycle detected in graph at step :$(node.step.name)")
    push!(visiting, node)
    for input in node.inputs
        input isa StepInstance && visit!(order, visiting, visited, input)
    end
    delete!(visiting, node)
    push!(visited, node)
    push!(order, node)
    return nothing
end
