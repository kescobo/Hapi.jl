@testitem "execution stores content objects and transactionally records the result" tags = [:slow] begin
    using Hapi

    @step function copy_file(path::AbstractPath; sample)
        output = Path("copy.txt")
        write(string(output), read(path, String))
        return output
    end

    root = mktempdir()
    input = joinpath(root, "input.txt")
    write(input, "hello")

    cd(root) do
        node = copy_file(FileArtifact(input; sample = "S"))
        result = run(node)
        @test result isa AbstractPath
        @test read(result, String) == "hello"

        database = ledger()
        task_row = row(database, digest(node))
        nodes = resultrows(database, digest(node))
        close(database)
        @test task_row.status == "done"
        @test length(nodes) == 1
        @test only(nodes).kind == :file
        @test only(nodes).object_hash == digest(result)
        @test only(nodes).object_hash != digest(node)

        started_at = task_row.started_at
        @test run(node) == result
        database = ledger()
        @test row(database, digest(node)).started_at == started_at
        close(database)
    end
end


@testitem "step bodies can shell out and remain cacheable" tags = [:slow] begin
    using Hapi

    @step function external_copy(path::AbstractPath; sample)
        output = Path("external-copy.txt")
        program = "write(ARGS[2], read(ARGS[1], String) * \" via subprocess\")"
        Base.run(
            `$(Base.julia_cmd()) --startup-file=no -e $program $(string(path)) $(string(output))`
        )
        return output
    end

    root = mktempdir()
    input = joinpath(root, "input.txt")
    write(input, "hello")

    cd(root) do
        node = external_copy(FileArtifact(input; sample = "S"))
        first_result = run(node)
        @test read(first_result, String) == "hello via subprocess"
        @test run(node) == first_result
    end
end

@testitem "missing and escaping outputs fail without a successful manifest" tags = [:slow] begin
    using Hapi

    @step missing(path::AbstractPath; sample) = Path("missing.txt")
    @step escaping(path::AbstractPath; sample) = Path(joinpath("..", "outside.txt"))

    root = mktempdir()
    input = joinpath(root, "input.txt")
    write(input, "x")
    write(joinpath(root, "outside.txt"), "outside")

    cd(root) do
        for step_function in (missing, escaping)
            node = step_function(FileArtifact(input; sample = "S"))
            @test_throws ErrorException run(node)
            database = ledger()
            @test row(database, digest(node)).status == "failed"
            @test isempty(resultrows(database, digest(node)))
            close(database)
            @test isempty(readdir(joinpath(root, ".hapi", "tmp")))
        end
    end
end

@testitem "body failure records failure and removes partial scratch state" tags = [:slow] begin
    using Hapi

    @step function explode(path::AbstractPath; sample)
        write("partial.txt", "partial")
        error("boom")
    end

    root = mktempdir()
    input = joinpath(root, "input.txt")
    write(input, "x")

    cd(root) do
        node = explode(FileArtifact(input; sample = "S"))
        @test_throws ErrorException run(node)
        database = ledger()
        @test row(database, digest(node)).status == "failed"
        @test isempty(resultrows(database, digest(node)))
        close(database)
        @test isempty(readdir(joinpath(root, ".hapi", "tmp")))
    end
end

@testitem "corrupt content objects are detected and replaced" tags = [:slow] begin
    using Hapi

    @step function reproduce(path::AbstractPath; sample)
        output = Path("result.txt")
        write(string(output), read(path, String) * "-result")
        return output
    end

    root = mktempdir()
    input = joinpath(root, "input.txt")
    write(input, "source")

    cd(root) do
        node = reproduce(FileArtifact(input; sample = "S"))
        result = run(node)
        write(string(result), "corrupt")
        repaired = run(node)
        @test read(repaired, String) == "source-result"
        database = ledger()
        @test digest(repaired) == only(resultrows(database, digest(node))).object_hash
        close(database)
    end
end

@testitem "a done row without a result manifest is not a cache hit" tags = [:slow] begin
    using Hapi

    @step function recover_manifest(path::AbstractPath; sample)
        output = Path("recovered.txt")
        write(string(output), read(path, String))
        return output
    end

    root = mktempdir()
    input = joinpath(root, "input.txt")
    write(input, "source")

    cd(root) do
        node = recover_manifest(FileArtifact(input; sample = "S"))
        database = ledger()
        record!(database, digest(node), node; status = "done")
        close(database)

        result = run(node)
        @test read(result, String) == "source"
        database = ledger()
        @test row(database, digest(node)).status == "done"
        @test length(resultrows(database, digest(node))) == 1
        close(database)
    end
end
