@testitem "confluence receives the whole collection as one argument, not splatted" tags = [:slow] begin
    using Hapi

    dir = mktempdir()
    write(joinpath(dir, "a.txt"), "1")
    write(joinpath(dir, "b.txt"), "2")

    @step function idfn(p::AbstractPath; sample)::AbstractPath
        return p
    end

    function combine(paths::Vector{<:AbstractPath})
        out = output_path(first(paths); suffix = "_combined")
        write(string(out), string(length(paths)))
        return out
    end

    cd(dir) do
        a = idfn(FileArtifact(joinpath(dir, "a.txt"); sample = "A"))
        b = idfn(FileArtifact(joinpath(dir, "b.txt"); sample = "B"))

        node = confluence(combine, [a, b])
        @test node.step.collapse
        @test length(node.inputs) == 2

        result = run(node)
        @test read(string(result.path), String) == "2"
    end
end

@testitem "confluence: on_upstream_failure other than :fail errors clearly" tags = [:fast] begin
    using Hapi
    f(xs) = xs
    @test_throws ErrorException confluence(f, StepInstance[]; on_upstream_failure = :skip)
end
