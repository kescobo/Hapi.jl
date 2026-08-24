@testitem "targets walks nested Tuple/NamedTuple/AbstractArray structures" tags = [:fast] begin
    using Hapi

    f(x) = x
    s = Step(f, :leaf)
    a = s()
    b = s()
    c = s()

    @test Hapi.targets(a) == [a]
    @test Set(Hapi.targets([a, b])) == Set([a, b])

    nested = (; qc = a, results = [(; x = b, y = c), (; x = a, y = b)])
    @test Set(Hapi.targets(nested)) == Set([a, b, c])

    # non-artifact values mixed in are ignored, not errors
    mixed = (a, "hello", 42, [b, nothing, c])
    @test Set(Hapi.targets(mixed)) == Set([a, b, c])
end

@testitem "run accepts the same nested shapes as targets, mirroring the shape back" tags = [:slow] begin
    using Hapi

    @step function idfn(p::AbstractPath; sample)::AbstractPath
        out = output_path(p; suffix = "_copy")
        write(string(out), read(p, String))
        return out
    end

    dir = mktempdir()
    p1 = joinpath(dir, "a.txt")
    p2 = joinpath(dir, "b.txt")
    write(p1, "1")
    write(p2, "2")

    a = idfn(FileArtifact(p1; sample = "A"))
    b = idfn(FileArtifact(p2; sample = "B"))

    cd(dir) do
        result = run((; first = a, rest = [b]))
        @test result.first isa FileArtifact
        @test result.rest isa Vector
        @test result.rest[1] isa FileArtifact
        @test read(string(result.first.path), String) == "1"
        @test read(string(result.rest[1].path), String) == "2"
    end
end
