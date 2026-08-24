"""
    confluence(f, nodes; params...) -> StepInstance

Collapse a *collection* of upstream nodes into ONE join node — the only Hapi verb that
does (O11). `nodes` is a runtime-sized collection built after fan-out already happened
(e.g. every sample's trim output, across all samples) — categorically different from an
ordinary multi-input `@step` call, which takes a small, fixed number of distinctly-sourced
inputs *within* one pipeline. `f` receives the whole collection as one argument
(`f(reports::Vector{...})`, unwrapped via `payload`), not splatted — this is what the
`collapse` flag on `Step` is for (see `steps.jl`): an adapter closure that collected args
before forwarding to `f` would capture `f` as local state and fail `assert_no_captures`
(I9), so the calling convention is a `Step`-level flag instead, changing nothing about how
`f` itself is hashed.

`f` is an ordinary function, not `@step`-decorated — `confluence` builds the `Step` from
it directly. Output naming/wrapping follows the same rule as any other step: `f`'s return
value determines its outputs. `params` default to empty (a confluence node aggregates
*across* samples, so auto-folding each input's own `params` wouldn't be meaningful — state
explicit `params` if the aggregate result should be tagged with anything).

`on_upstream_failure` stays `:fail`-only, consistent with the rest of the engine — nothing
implements `:skip`/`:placeholder` propagation anywhere yet, so requesting one here errors
clearly rather than silently behaving like `:fail` anyway.
"""
function confluence(f, nodes; on_upstream_failure::Symbol = :fail, params...)
    on_upstream_failure === :fail ||
        error(
        "confluence: on_upstream_failure=:$on_upstream_failure isn't implemented yet " *
            "— only :fail works today."
    )
    step = Step(f, nameof(f); collapse = true)
    return StepInstance(
        step, digest(step), collect(AbstractArtifact, nodes),
        NamedTuple(params), :cached, :native, Resources()
    )
end
