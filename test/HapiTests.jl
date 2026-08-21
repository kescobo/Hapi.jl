module HapiTests

using Hapi
using ReTest

@testset "Hapi.jl" begin
    f(x) = x
    s = Step(f, :noop)
    si = s()
    @test si isa StepInstance
    @test si isa AbstractArtifact
end

end # module
