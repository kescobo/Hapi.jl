```@meta
CurrentModule = Hapi
```

# Hapi

```@docs
Hapi
```

Hapi makes ordinary Julia functions reproducible workflow steps. `@step` preserves the
authored method and adds graph-building behavior for artifact inputs.

## Define a step

```julia
@step function copy_input(input::AbstractPath; sample)
    output = Path("$(sample)_copy.txt")
    write(string(output), read(input, String))
    return output
end
```

Calling `copy_input` with a path executes it normally. Calling it with a value from `source`
or another step returns a lazy `StepInstance`.

## Build and run a workflow

```julia
rows = [(sample="A", path="A.txt"), (sample="B", path="B.txt")]

inputs = source(rows; params=row -> (; sample=row.sample)) do row
    Path(row.path)
end

graph = map(copy_input, inputs)
results = run(graph)
```

The returned `results` are ordinary paths with their logical filenames, backed by Hapi's
content-addressed store.

## Logical filenames

Hapi preserves the basename exposed to step bodies and understands common compound
bioinformatics extensions:

```julia
splitname(p"sample_R1.fastq.gz")
# ("sample_R1", ".fastq.gz")

with_stem_suffix(p"sample_R1.fastq.gz", "_trimmed")
# p"sample_R1_trimmed.fastq.gz"
```

Extension policies are immutable and locally extensible:

```julia
policy = addsuffixes(DEFAULT_EXTENSION_POLICY, ".loom.gz")
splitname(p"matrix.loom.gz", policy)
# ("matrix", ".loom.gz")
```

The byte hash remains the content-object key. The logical name separately participates in
downstream task identity because command-line tools may infer formats from filenames.

## Structured values

A named tuple is preserved as a structured result:

```julia
@step function pair(input::AbstractPath; sample)
    left = Path("left.txt")
    right = Path("right.txt")
    # write left and right...
    return (; left, right)
end

result = pair(input)
left_only = result[:left]
```

Passing `result` to another step supplies the entire named tuple. Passing `left_only`
supplies one path. Nested named tuples and intentional absence (`nothing`) follow the same
rule.

## Fan-in

Use `gather` when an aggregation step consumes a fan-out as one vector:

```julia
summary = summarize(gather(per_sample_results))
```

`confluence(f, nodes)` wraps an ordinary aggregation function as a convenience.

## API

```@docs
@step
Step
StepInstance
Output
source
glob_table
gather
confluence
run
plan
PlanResult
targets
FileArtifact
AbstractArtifact
payload
logicalname
ExtensionPolicy
DEFAULT_EXTENSION_POLICY
addsuffixes
splitname
with_stem_suffix
ExecutionBackend
Local
EnvName
Resources
Digest
digest
path
scratchdir
commit!
ledger
record!
row
resultrows
```
