"""
    Digest

A content hash — wraps a raw SHA-256 digest so callers get hex `show`/`string` for free
instead of handling raw bytes directly (store paths, ledger rows, ...). Construct one with
[`digest`](@ref), not the `Digest` constructor directly.
"""
struct Digest
    bytes::NTuple{32, UInt8}
end

"""
    digest(x) -> Digest

The content digest of `x`. Dispatches over what `x` is: raw bytes or a string hash
directly; several `Digest`s combine (order-sensitively) into one, e.g. to fold a
[`StepInstance`](@ref)'s code hash, params, environment identity, and each input's digest
into a single task-identity hash; a [`Step`](@ref) hashes its source code; an
`AbstractArtifact` or `StepInstance` hashes its task identity.
"""
digest(data::AbstractVector{UInt8}) = Digest(NTuple{32, UInt8}(sha256(data)))
digest(s::AbstractString) = digest(Vector{UInt8}(codeunits(s)))
digest(parts::Digest...) = digest(reduce(vcat, (collect(p.bytes) for p in parts); init = UInt8[]))

Base.string(d::Digest) = bytes2hex(collect(d.bytes))
Base.show(io::IO, d::Digest) = print(io, "Digest(", string(d)[1:12], "…)")
Base.:(==)(a::Digest, b::Digest) = a.bytes == b.bytes
Base.hash(d::Digest, h::UInt) = hash(d.bytes, h)

"""
    assert_no_captures(f, ms = methods(f))

I9's "captured non-const globals are a hard error" — two distinct Julia mechanisms, both
checked: (1) a closure over a *local* variable stores that state as a field on its
synthesized callable type, so any such closure (`nfields(f) != 0`) is rejected outright;
(2) a plain top-level function referencing a *global* doesn't capture anything structurally
— it resolves the global at call time — so each method in `ms`'s lowered code is scanned
for `GlobalRef`s and any pointing at a non-`const` binding is rejected. Referencing other
functions/types (ordinary `const` bindings) is unaffected. `ms` defaults to all of `f`'s
methods; `digest(::Step)` passes a filtered subset (only the user's concrete-typed
methods — see `concretemethods` in steps.jl) so `@step`-generated dispatch plumbing isn't
checked or hashed as if it were user code.
"""
function assert_no_captures(f, ms = methods(f))
    nfields(f) == 0 || error(
        "$(nameof(typeof(f))) captures local state (has $(nfields(f)) field(s)) — task " *
            "functions must be pure and top-level; use explicit `depends_on` for callee " *
            "dependencies instead."
    )
    for m in ms
        for gr in globalrefs(Base.uncompressed_ast(m))
            isconst(gr.mod, gr.name) || error(
                "$(m.name) references non-const global $(gr.mod).$(gr.name) — task " *
                    "functions must be pure and top-level; make it `const` or pass it as an argument."
            )
        end
    end
    return nothing
end

function globalrefs(ci::Core.CodeInfo)
    refs = GlobalRef[]
    for stmt in ci.code
        globalrefs!(refs, stmt)
    end
    return refs
end

globalrefs!(acc::Vector{GlobalRef}, x::GlobalRef) = push!(acc, x)
function globalrefs!(acc::Vector{GlobalRef}, x::Expr)
    for a in x.args
        globalrefs!(acc, a)
    end
    return acc
end
globalrefs!(acc::Vector{GlobalRef}, x) = acc
