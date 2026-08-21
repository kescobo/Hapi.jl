"""
    PlanResult

`order` is `target` and its upstream StepInstances in dependency-first topological order.
`frontier` is the I11c forward-compat hook: once dynamic (unknown-cardinality) outputs
land, the execution loop will check it; it is always `false` today.
"""
struct PlanResult
    order::Vector{StepInstance}
    frontier::Bool
end

"""
    plan(target::StepInstance) -> PlanResult

Build the execution order for `target` and everything it (transitively) depends on. A
pure graph walk over `.inputs` — no I/O, no backend knowledge (I1); nothing upstream of
`run` may depend on how the graph will eventually be executed.
"""
function plan(target::StepInstance)::PlanResult
    order = StepInstance[]
    visiting = Set{StepInstance}()
    visited = Set{StepInstance}()
    visit(node::StepInstance) = begin
        node in visited && return nothing
        node in visiting && error("cycle detected in graph at step :$(node.step.name)")
        push!(visiting, node)
        for input in node.inputs
            input isa StepInstance && visit(input)
        end
        delete!(visiting, node)
        push!(visited, node)
        push!(order, node)
        return nothing
    end
    visit(target)
    return PlanResult(order, false)
end
