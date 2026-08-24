@testitem "@step never rewrites the body (I2)" tags = [:invariant] begin
    using Hapi

    @step function double_path_len(p::AbstractPath; sample)::Int
        return length(string(p))
    end

    p = Path("some/file.txt")
    # direct call still runs the body exactly, untouched — same result as calling by hand
    @test double_path_len(p; sample = "x") == length(string(p))

    # the hashed source is exactly the authored method, nothing injected
    ms = Hapi.concretemethods(double_path_len)
    @test length(ms) == 1
    src = Hapi.sourcetext(only(ms))
    @test occursin("length(string(p))", src)
    @test !occursin("AbstractArtifact", src)   # generated dispatcher's source isn't mixed in
end
