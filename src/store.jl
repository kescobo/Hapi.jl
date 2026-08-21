# Content-addressed store layout (plan §5): .hapi/store/objects/<hash[0:2]>/<hash>
# (parameter is `d`, not `digest`, so it doesn't shadow the `digest` function in this scope)
path(d::Digest; root::AbstractString = ".hapi") =
    joinpath(root, "store", "objects", string(d)[1:2], string(d))

"""
    scratchdir(; root=".hapi") -> String

A fresh directory to compute a StepInstance's outputs into, on the same filesystem as the
store so `commit!` can `mv` into it atomically — not just `mktempdir()`, because that
defaults to the system temp dir, which is frequently a different filesystem/mount than
`root`, silently downgrading `commit!`'s `mv` from an atomic rename to a copy+delete (I8).
"""
function scratchdir(; root::AbstractString = ".hapi")
    dir = joinpath(root, "tmp")
    mkpath(dir)
    return mktempdir(dir)
end

"""
    commit!(tmpdir, digest; root=".hapi") -> String

Atomically move a completed temp dir into the content-addressed store under `digest`.
Only called after a StepInstance's outputs are fully written — a failed or interrupted
run simply never calls this, so partial outputs never enter the store (I8).
"""
function commit!(tmpdir::AbstractString, d::Digest; root::AbstractString = ".hapi")
    target = path(d; root)
    isdir(target) && return target   # already committed under this content hash
    mkpath(dirname(target))
    mv(tmpdir, target)
    return target
end
