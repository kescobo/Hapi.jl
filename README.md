# Hapi.jl

Hapi turns ordinary Julia functions into content-addressed workflows with minimal
workflow-specific syntax.

```julia
using Hapi

@step function wordcount(input::AbstractPath; sample)
    output = Path("$(sample)_count.txt")
    write(string(output), string(length(split(read(input, String)))))
    return output
end

inputs = source([(sample="A", path="A.txt"), (sample="B", path="B.txt")];
                params=row -> (; sample=row.sample)) do row
    Path(row.path)
end

results = run(map(wordcount, inputs))
```

`wordcount` remains an ordinary function when called with an ordinary path. When called on a
value from `source` or another step, it builds a lazy graph node instead. `run` validates
outputs, stores files by content hash, and reuses complete cached results.

Logical filenames survive storage and cache hits. Compound bioinformatics extensions are
handled as a unit:

```julia
with_stem_suffix(p"sample_R1.fastq.gz", "_trimmed")
# p"sample_R1_trimmed.fastq.gz"
```

The default immutable policy recognizes common FASTQ/FASTA, SAM/BAM/CRAM, VCF/BCF,
BED/GFF/GTF, and compression suffixes. Derive a policy for another compound extension
without changing global state:

```julia
policy = addsuffixes(DEFAULT_EXTENSION_POLICY, ".loom.gz")
splitname(p"matrix.loom.gz", policy)  # ("matrix", ".loom.gz")
```

Structured ordinary values are preserved:

```julia
@step function trim(reads::NamedTuple; sample)
    (; R1, R2) = reads
    # write outputs...
    return (; R1=trimmed_R1, R2=trimmed_R2)
end
```

Passing the whole result downstream reconstructs the `NamedTuple`; indexing, such as
`trimmed[:R1]`, selects one leaf.

Hapi is under active development. The current design contract is documented in the outer
development workspace's `hapi-plan.md`.
