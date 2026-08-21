# Content-addressed store layout (plan §5): .hapi/store/objects/<hash[0:2]>/<hash>
store_path(digest::Digest; root::AbstractString = ".hapi") =
    joinpath(root, "store", "objects", string(digest)[1:2], string(digest))

"""
    tmp_dir(; root=".hapi") -> String

A fresh scratch directory on the same filesystem as the store, so `commit!` can move into
it atomically. A StepInstance computes its outputs here; nothing under this path is ever
visible under `objects/` unless `commit!` succeeds (I8).
"""
function tmp_dir(; root::AbstractString = ".hapi")
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
function commit!(tmpdir::AbstractString, digest::Digest; root::AbstractString = ".hapi")
    target = store_path(digest; root)
    isdir(target) && return target   # already committed under this content hash
    mkpath(dirname(target))
    mv(tmpdir, target)
    return target
end
