@testitem "compound extensions use an immutable extensible policy" tags = [:fast] begin
    using Hapi

    @test splitname(p"some.sample_R1.fastq.gz") == ("some.sample_R1", ".fastq.gz")
    @test splitname(p"alignment.bam") == ("alignment", ".bam")
    @test splitname(p"reads.FASTQ.GZ") == ("reads", ".FASTQ.GZ")
    @test splitname(p"notes.txt") == ("notes", ".txt")
    @test with_stem_suffix(p"some.sample_R1.fastq.gz", "_trimmed") ==
        p"some.sample_R1_trimmed.fastq.gz"

    custom = addsuffixes(DEFAULT_EXTENSION_POLICY, ".loom.gz")
    @test splitname(p"matrix.loom.gz") == ("matrix.loom", ".gz")
    @test splitname(p"matrix.loom.gz", custom) == ("matrix", ".loom.gz")
    @test ".loom.gz" ∉ DEFAULT_EXTENSION_POLICY.suffixes
    @test_throws ArgumentError ExtensionPolicy("fastq.gz")

    struct ProjectPolicy end
    Hapi.splitname(path::AbstractPath, ::ProjectPolicy) = ("project", ".data.gz")
    @test with_stem_suffix(p"input.data.gz", "_ready"; policy = ProjectPolicy()) ==
        p"project_ready.data.gz"
end

@testitem "logical names affect tasks but not byte identity" tags = [:fast, :invariant] begin
    using Hapi

    passthrough(path) = path
    root = mktempdir()
    input = joinpath(root, "same-bytes")
    write(input, "content")
    sam = FileArtifact(input; logical_name = "sample.sam")
    bam = FileArtifact(input; logical_name = "sample.bam")

    @test digest(sam.path) == digest(bam.path)
    @test digest(sam) != digest(bam)
    @test digest(Step(passthrough, :passthrough)(sam)) !=
        digest(Step(passthrough, :passthrough)(bam))
end

@testitem "logical names survive execution, staging, manifests, and cache hits" tags = [:slow] begin
    using Hapi

    @step function trim_named_fastq(path::AbstractPath; sample)
        output = with_stem_suffix(Path(basename(path)), "_trimmed")
        write(output, read(path, String))
        return output
    end

    @step function observe_staged_name(path::AbstractPath; sample)
        output = Path("observed-name.txt")
        write(output, basename(path))
        return output
    end

    root = mktempdir()
    input = joinpath(root, "some_sample_R1.fastq.gz")
    write(input, "reads")

    cd(root) do
        trimmed = trim_named_fastq(FileArtifact(input; sample = "S"))
        observed = observe_staged_name(trimmed)
        first_result = run((; trimmed, observed))

        @test basename(first_result.trimmed) == "some_sample_R1_trimmed.fastq.gz"
        @test read(first_result.trimmed, String) == "reads"
        @test read(first_result.observed, String) == "some_sample_R1_trimmed.fastq.gz"

        database = ledger()
        rows = resultrows(database, digest(trimmed))
        close(database)
        @test only(rows).logical_name == "some_sample_R1_trimmed.fastq.gz"

        second_result = run((; trimmed, observed))
        @test second_result == first_result
        @test basename(second_result.trimmed) == "some_sample_R1_trimmed.fastq.gz"
    end
end

@testitem "staging isolates inputs with identical logical names" tags = [:slow] begin
    using Hapi

    @step function combine_same_names(left::AbstractPath, right::AbstractPath)
        output = Path("combined.txt")
        write(output, read(left, String) * read(right, String))
        return output
    end

    root = mktempdir()
    first_dir = joinpath(root, "first")
    second_dir = joinpath(root, "second")
    mkpath(first_dir)
    mkpath(second_dir)
    first_path = joinpath(first_dir, "reads.fastq.gz")
    second_path = joinpath(second_dir, "reads.fastq.gz")
    write(first_path, "first")
    write(second_path, "second")

    cd(root) do
        node = combine_same_names(FileArtifact(first_path), FileArtifact(second_path))
        @test read(run(node), String) == "firstsecond"
    end
end

@testitem "ledger upgrades result manifests with logical names" tags = [:fast] begin
    using Hapi

    root = mktempdir()
    database_path = joinpath(root, "old.sqlite")
    database = Hapi.SQLite.DB(database_path)
    Hapi.DBInterface.execute(
        database,
        """
        CREATE TABLE result_nodes (
            step_hash TEXT NOT NULL,
            node_id INTEGER NOT NULL,
            parent_id INTEGER,
            name TEXT,
            position INTEGER NOT NULL,
            kind TEXT NOT NULL,
            object_hash TEXT,
            PRIMARY KEY (step_hash, node_id)
        )
        """,
    )
    close(database)

    database = ledger(database_path)
    columns = [String(row.name) for row in Hapi.DBInterface.execute(database, "PRAGMA table_info(result_nodes)")]
    close(database)
    @test "logical_name" in columns
end
