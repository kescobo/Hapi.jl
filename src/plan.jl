"""
    PlanResult

Dependency-first execution order for a concrete workflow graph.
"""
struct PlanResult
    order::Vector{StepInstance}
end

"""
    targets(value) -> Vector{StepInstance}

Find lazy step nodes in nested tuples, named tuples, and arrays.
"""
targets(value) = targets!(StepInstance[], value)
targets!(targets::Vector{StepInstance}, instance::StepInstance) = push!(targets, instance)
targets!(targets::Vector{StepInstance}, output::Output) = targets!(targets, output.instance)

function targets!(targets::Vector{StepInstance}, value::Union{Tuple, NamedTuple, AbstractArray})
    for item in value
        targets!(targets, item)
    end
    return targets
end

targets!(targets::Vector{StepInstance}, value) = targets

"""
    plan(value) -> PlanResult

Build a dependency-first order without executing code or consulting a backend.
"""
function plan(value)
    order = StepInstance[]
    visiting = Set{StepInstance}()
    visited = Set{StepInstance}()
    for target in targets(value)
        visit!(order, visiting, visited, target)
    end
    return PlanResult(order)
end

function visit!(order, visiting, visited, instance::StepInstance)
    instance in visited && return nothing
    instance in visiting && error("cycle detected in graph at step :$(instance.step.name)")
    push!(visiting, instance)
    for input in instance.inputs
        visitinput!(order, visiting, visited, input)
    end
    delete!(visiting, instance)
    push!(visited, instance)
    push!(order, instance)
    return nothing
end

visitinput!(order, visiting, visited, instance::StepInstance) =
    visit!(order, visiting, visited, instance)
visitinput!(order, visiting, visited, output::Output) =
    visit!(order, visiting, visited, output.instance)

function visitinput!(order, visiting, visited, gathered::Gathered)
    for item in gathered.items
        visitinput!(order, visiting, visited, item)
    end
    return nothing
end

visitinput!(order, visiting, visited, input) = nothing
