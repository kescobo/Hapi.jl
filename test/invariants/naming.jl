@testitem "naming: Step/StepInstance, no Task/Process/Rule/Node/Job (I12)" tags = [:invariant] begin
    using Hapi

    @test isdefined(Hapi, :Step)
    @test isdefined(Hapi, :StepInstance)

    # Task resolves via Base regardless (every module sees Base's exports) — the actual
    # invariant is that Hapi doesn't shadow it with its own type of the same name.
    @test Hapi.Task === Base.Task
    for bad in (:Process, :Rule, :Node, :Job)
        @test !isdefined(Hapi, bad)
    end

    # Constructor verb must not shadow Base.step (the step of a range): Hapi doesn't
    # redefine `step`, and no `step(::Step)` method exists.
    @test Hapi.step === Base.step
    @test !hasmethod(step, Tuple{Step})
end
