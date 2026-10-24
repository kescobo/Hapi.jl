@testitem "gather passes fan-out to an ordinary aggregation function" tags = [:slow] begin
    using Hapi

    @step function copy_for_gather(path::AbstractPath; sample)
        output = Path("$(sample).txt")
        write(string(output), read(path, String))
        return output
    end

    function combine_for_gather(paths::Vector{<:AbstractPath})
        output = Path("combined.txt")
        write(string(output), join(read.(paths, String), ","))
        return output
    end

    root = mktempdir()
    first_path = joinpath(root, "first")
    second_path = joinpath(root, "second")
    write(first_path, "a")
    write(second_path, "b")

    cd(root) do
        nodes = [
            copy_for_gather(FileArtifact(first_path; sample = "A")),
            copy_for_gather(FileArtifact(second_path; sample = "B")),
        ]
        aggregate = confluence(combine_for_gather, nodes)
        @test read(run(aggregate), String) == "a,b"
        @test plan(aggregate).order == [nodes..., aggregate]
    end
end
