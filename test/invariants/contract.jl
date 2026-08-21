@testitem "payload is the whole extension contract (I10)" tags = [:invariant] begin
    using Hapi

    @test_throws MethodError payload(42)

    f(x) = x
    si = Step(f, :noop)()
    @test_throws ErrorException payload(si)   # not produced yet — execution isn't implemented
end
