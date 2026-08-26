"""
    path(d::Digest; root=".hapi") -> String

The content-addressed store path for `d`: `\$root/store/objects/<hash[0:2]>/<hash>`.
`root` defaults to an absolute path (not the literal `".hapi"`) so it still resolves
correctly from inside a step's scratch directory, which [`run`](@ref) `cd`s into while
executing.
"""
path(d::Digest; root::AbstractString = abspath(".hapi")) =
    joinpath(root, "store", "objects", string(d)[1:2], string(d))

"""
    scratchdir(; root=".hapi") -> String

A fresh directory to compute a `StepInstance`'s outputs into, on the same filesystem as the
store so [`commit!`](@ref) can move it in atomically — not `mktempdir()`, since that
defaults to the system temp dir, which is often a different filesystem/mount than `root`
(which would silently downgrade `commit!`'s move from an atomic rename to a copy+delete).
"""
function scratchdir(; root::AbstractString = abspath(".hapi"))
    dir = joinpath(root, "tmp")
    mkpath(dir)
    return mktempdir(dir)
end

"""
    commit!(tmpdir, digest; root=".hapi") -> String

Atomically move a completed temp dir into the content-addressed store under `digest`. Only
called after a `StepInstance`'s outputs are fully written — a failed or interrupted run
simply never calls this, so partial outputs never enter the store.
"""
function commit!(tmpdir::AbstractString, d::Digest; root::AbstractString = abspath(".hapi"))
    target = path(d; root)
    isdir(target) && return target   # already committed under this content hash
    mkpath(dirname(target))
    mv(tmpdir, target)
    return target
end
