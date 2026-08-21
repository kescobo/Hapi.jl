@testitem "graph construction is pure: no I/O, no backend (I1)" tags = [:invariant] begin
    using Hapi

    before = readdir(pwd())
    f(x) = x
    s = Step(f, :noop)
    leaf = s()
    mid = s(leaf)
    plan(mid)
    after = readdir(pwd())

    @test before == after
end

@testitem "no @workflow macro exists (I3)" tags = [:invariant] begin
    using Hapi

    @test !isdefined(Hapi, Symbol("@workflow"))
end
