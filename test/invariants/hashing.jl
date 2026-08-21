@testitem "resources never enter the hash (I4)" tags = [:invariant] begin
    using Hapi

    f(x) = x
    s = Step(f, :id)
    leaf = s()
    a = s(leaf)
    b = Hapi.StepInstance(
        a.step, a.code_hash, a.inputs, a.params, a.retention, a.env,
        Resources(8, 1024, nothing, 1, Dict{Symbol, Any}(:partition => "big"))
    )

    @test digest(a) == digest(b)
end

@testitem "env/resources are instance bindings, not Step properties (I6)" tags = [:invariant] begin
    using Hapi

    @test :env ∉ fieldnames(Step)
    @test :resources ∉ fieldnames(Step)
    @test :env in fieldnames(StepInstance)
    @test :resources in fieldnames(StepInstance)
end

@testitem "code hash: shallow source hash + capture guard (I9)" tags = [:invariant] begin
    using Hapi

    f1(x) = x + 1
    f2(x) = x + 2
    @test digest(Step(f1, :a)) != digest(Step(f2, :a))
    @test digest(Step(f1, :a)) == digest(Step(f1, :b))

    nonconst_global = 10
    bad(x) = x + nonconst_global
    @test_throws ErrorException digest(Step(bad, :bad))

    function make_local_closure()
        captured = 99
        return x -> x + captured
    end
    @test_throws ErrorException digest(Step(make_local_closure(), :bad2))
end
