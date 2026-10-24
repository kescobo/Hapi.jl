@testitem "ordinary functions become lazy steps without changing their bodies" tags = [:fast, :invariant] begin
    using Hapi

    @step function paired(path::AbstractPath; sample)
        return (; R1 = path, R2 = path, sample)
    end

    path = Path("input.txt")
    direct = paired(path; sample = "S")
    @test direct == (; R1 = path, R2 = path, sample = "S")

    root = mktempdir()
    input = joinpath(root, "input.txt")
    write(input, "x")
    node = paired(FileArtifact(input; sample = "S"))
    @test node isa StepInstance
    @test node[:R1] isa Output
    @test node[:R1].selector == (:R1,)

    source_text = Hapi.sourcetext(only(Hapi.concretemethods(paired)))
    @test !occursin("AbstractArtifact", source_text)

    captured_source = Hapi.sourcetext(nothing, only(Hapi.concretemethods(paired)))
    @test occursin("function paired", captured_source)
    @test !occursin("AbstractArtifact", captured_source)
end


@testitem "REPL-authored steps retain hashable source without standard REPL history" tags = [:fast, :invariant] begin
    using Hapi

    definition = Meta.parse(
        "@step function repl_identity(path::AbstractPath)\n" *
            "    return path\n" *
            "end";
        filename = "REPL[87654321]",
    )
    Core.eval(@__MODULE__, definition)

    method = only(Hapi.concretemethods(repl_identity))
    @test occursin("function repl_identity", Hapi.sourcetext(method))
    @test repl_identity(FileArtifact(@__FILE__)) isa StepInstance
end


@testitem "parameter hashing is structural and type-sensitive" tags = [:fast, :invariant] begin
    using Hapi

    f(path; count = 1) = path
    step = Step(f, :f)
    input = FileArtifact(@__FILE__)

    @test digest(step(input; count = Int32(1))) != digest(step(input; count = Int64(1)))
    @test digest(step(input; outer = (; x = 1))) != digest(step(input; outer = (; y = 1)))
end

@testitem "core graph types contain no lifecycle or backend policy" tags = [:fast, :invariant] begin
    using Hapi

    @test fieldnames(Step) == (:f, :name, :depends_on)
    @test :resources in fieldnames(StepInstance)
    @test :env in fieldnames(StepInstance)
    @test :retention ∉ fieldnames(StepInstance)
    @test !isdefined(Hapi, :FileGroupArtifact)
    @test !isdefined(Hapi, :OutputDecl)
    @test !isdefined(Hapi, :delta)
    @test !isdefined(Hapi, Symbol("@workflow"))
end

@testitem "resources never affect task identity" tags = [:fast, :invariant] begin
    using Hapi

    identity_function(path) = path
    root = mktempdir()
    input = joinpath(root, "input.txt")
    write(input, "x")
    original = Step(identity_function, :identity)(FileArtifact(input))
    changed = StepInstance(
        original.step,
        original.code_hash,
        original.inputs,
        original.params,
        original.env,
        Resources(32, 2^30, nothing, 1, Dict{Symbol, Any}(:queue => "large")),
    )
    @test digest(original) == digest(changed)
end

@testitem "structured names participate in artifact identity" tags = [:fast, :invariant] begin
    using Hapi

    root = mktempdir()
    first_path = joinpath(root, "first.txt")
    second_path = joinpath(root, "second.txt")
    write(first_path, "first")
    write(second_path, "second")

    reads = Hapi.artifact((; R1 = Path(first_path), R2 = Path(second_path)))
    renamed = Hapi.artifact((; left = Path(first_path), right = Path(second_path)))
    @test digest(reads) != digest(renamed)
end
