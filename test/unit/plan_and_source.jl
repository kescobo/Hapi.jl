@testitem "plan walks selected outputs, gathered inputs, and nested target shapes" tags = [:fast] begin
    using Hapi

    f(path) = path
    root = mktempdir()
    input = joinpath(root, "input")
    write(input, "x")
    step = Step(f, :f)
    first_node = step(FileArtifact(input))
    second_node = step(first_node[:result])
    aggregate(items) = items
    third_node = Step(aggregate, :aggregate)(gather([first_node, second_node]))

    graph = (; selected = second_node[:x], nested = [third_node])
    @test plan(graph).order == [first_node, second_node, third_node]
    @test Set(targets(graph)) == Set([second_node, third_node])
end

@testitem "glob_table parses filename wildcards" tags = [:fast] begin
    using Hapi

    root = mktempdir()
    write(joinpath(root, "sample_A.txt"), "a")
    write(joinpath(root, "sample_B.txt"), "b")
    write(joinpath(root, "other.txt"), "x")
    table = glob_table(joinpath(root, "sample_{sample}.txt"))
    @test Set(row.sample for row in table) == Set(["A", "B"])
    @test all(row -> row.path isa AbstractPath, table)
end
