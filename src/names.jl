"""
    ExtensionPolicy(suffixes...)

An immutable collection of recognized filename suffixes. [`splitname`](@ref) chooses the
longest matching suffix, allowing compound bioinformatics suffixes such as `.fastq.gz`.
Use [`addsuffixes`](@ref) to derive a policy with additional suffixes.
"""
struct ExtensionPolicy{S <: Tuple}
    suffixes::S
end

function ExtensionPolicy(suffixes::AbstractString...)
    normalized = String[]
    for suffix in suffixes
        startswith(suffix, ".") || throw(ArgumentError("an extension must start with '.': $suffix"))
        length(suffix) > 1 || throw(ArgumentError("an extension cannot be only '.'"))
        suffix in normalized || push!(normalized, String(suffix))
    end
    return ExtensionPolicy(Tuple(normalized))
end

"""
    DEFAULT_EXTENSION_POLICY

The built-in immutable extension policy for common bioinformatics and compression formats.
"""
const DEFAULT_EXTENSION_POLICY = ExtensionPolicy(
    ".fastq.gz",
    ".fastq.bz2",
    ".fastq.xz",
    ".fq.gz",
    ".fq.bz2",
    ".fq.xz",
    ".fasta.gz",
    ".fasta.bz2",
    ".fa.gz",
    ".fa.bz2",
    ".fna.gz",
    ".sam.gz",
    ".vcf.gz",
    ".bed.gz",
    ".gff.gz",
    ".gff3.gz",
    ".gtf.gz",
    ".fastq",
    ".fasta",
    ".cram",
    ".bam",
    ".sam",
    ".bcf",
    ".vcf",
    ".bed",
    ".gff3",
    ".gff",
    ".gtf",
    ".fna",
    ".fq",
    ".fa",
    ".bz2",
    ".gz",
    ".xz",
    ".zst",
)

"""
    addsuffixes(policy, suffixes...) -> ExtensionPolicy

Return a new extension policy containing `policy`'s suffixes and the additional suffixes.
The original policy is unchanged.
"""
addsuffixes(policy::ExtensionPolicy, suffixes::AbstractString...) =
    ExtensionPolicy(policy.suffixes..., suffixes...)

"""
    splitname(path, policy=DEFAULT_EXTENSION_POLICY) -> (stem, suffix)

Split a path's basename using the longest suffix recognized by `policy`. The returned suffix
preserves the spelling and case from the basename. When no registered suffix matches, fall
back to `splitext`, so ordinary single extensions continue to work.
"""
function splitname(path::AbstractPath, policy::ExtensionPolicy = DEFAULT_EXTENSION_POLICY)
    name = basename(path)
    folded_name = lowercase(name)
    matched = ""
    for suffix in policy.suffixes
        length(name) > length(suffix) || continue
        length(suffix) > length(matched) || continue
        endswith(folded_name, lowercase(suffix)) || continue
        matched = last(name, length(suffix))
    end
    if isempty(matched)
        return splitext(name)
    end
    return (chop(name; tail = length(matched)), matched)
end

"""
    with_stem_suffix(path, addition; policy=DEFAULT_EXTENSION_POLICY) -> AbstractPath

Insert `addition` between a path's basename stem and its recognized extension, preserving
the parent directory and compound extensions.
"""
function with_stem_suffix(
        path::AbstractPath,
        addition::AbstractString;
        policy = DEFAULT_EXTENSION_POLICY,
    )
    stem, suffix = splitname(path, policy)
    name = string(stem, addition, suffix)
    return hasparent(path) ? Path(joinpath(string(parent(path)), name)) : Path(name)
end

function paramdigest(policy::ExtensionPolicy)
    parts = Digest[digest("param:extension-policy-v1")]
    append!(parts, digest(suffix) for suffix in policy.suffixes)
    return digest(parts...)
end
