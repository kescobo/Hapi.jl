"""
    confluence(f, nodes; on_upstream_failure=:fail, params...) -> StepInstance

Collapse a *collection* of upstream nodes — built after fan-out has already happened, e.g.
every sample's output from a `map` — into one join node, such as running `multiqc` over
every sample's trim report. `f` is an ordinary function (not [`@step`](@ref)-decorated);
`confluence` builds its [`Step`](@ref) directly. Unlike an ordinary multi-input step, `f`
receives the *whole* collection as a single argument (e.g. `f(reports::Vector{...})`,
already unwrapped via [`payload`](@ref)) rather than splatted across positional arguments.

`f`'s return value determines its outputs, the same as any other step (see [`@step`](@ref)).
`params` default to empty, since a confluence node aggregates across inputs rather than
belonging to any one of them — pass explicit `params` if the aggregate result should carry
its own tag.

Only `on_upstream_failure = :fail` (the default) is implemented; passing `:skip` or
`:placeholder` raises an error rather than silently behaving like `:fail`.
"""
function confluence(f, nodes; on_upstream_failure::Symbol = :fail, params...)
    on_upstream_failure === :fail ||
        error(
        "confluence: on_upstream_failure=:$on_upstream_failure isn't implemented yet " *
            "— only :fail works today."
    )
    # `collapse = true` is what makes `f` receive the whole collection as one argument
    # rather than splatted — not an adapter closure that collects args before forwarding
    # to `f`, which would capture `f` as local state and fail `assert_no_captures`.
    step = Step(f, nameof(f); collapse = true)
    return StepInstance(
        step, digest(step), collect(AbstractArtifact, nodes),
        NamedTuple(params), :cached, :native, Resources()
    )
end
