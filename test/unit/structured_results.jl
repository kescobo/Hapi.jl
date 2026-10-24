@testitem "source and step results preserve ordinary NamedTuple structure" tags = [:slow] begin
    using Hapi

    @step function split_reads(reads::NamedTuple; sample)
        r1 = Path("trimmed_R1.txt")
        r2 = Path("trimmed_R2.txt")
        write(string(r1), read(reads.R1, String) * "1")
        write(string(r2), read(reads.R2, String) * "2")
        return (; reads = (; R1 = r1, R2 = r2), report = nothing)
    end

    root = mktempdir()
    input1 = joinpath(root, "R1.txt")
    input2 = joinpath(root, "R2.txt")
    write(input1, "a")
    write(input2, "b")
    table = [(; R1 = Path(input1), R2 = Path(input2), sample = "S")]

    cd(root) do
        inputs = source(table; params = row -> (; sample = row.sample)) do row
            (; R1 = row.R1, R2 = row.R2)
        end
        @test only(inputs)[:R1].params == (; sample = "S")
        node = split_reads(only(inputs))
        result = run(node)
        @test propertynames(result) == (:reads, :report)
        @test propertynames(result.reads) == (:R1, :R2)
        @test read(result.reads.R1, String) == "a1"
        @test read(result.reads.R2, String) == "b2"
        @test result.report === nothing

        selected = run(node[:reads][:R2])
        @test selected == result.reads.R2
    end
end

@testitem "a selected branch hashes by its complete selector" tags = [:fast] begin
    using Hapi

    f(path) = path
    root = mktempdir()
    input = joinpath(root, "input")
    write(input, "x")
    node = Step(f, :f)(FileArtifact(input))
    @test digest(node[:reads][:R1]) != digest(node[:reads][:R2])
    @test digest(node[:reads][:R1]) != digest(node[:R1])
end
