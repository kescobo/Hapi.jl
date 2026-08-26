using Hapi
using Documenter

makedocs(;
    modules=[Hapi],
    authors="Kevin Bonham <kevbonham@gmail.com>",
    repo="https://github.com/kescobo/Hapi.jl/blob/{commit}{path}#L{line}",
    sitename="Hapi.jl",
    # CondaEnv/Container are intentional stubs with no docstring yet; warn rather than
    # fail the build until they (or their docs) land.
    warnonly=[:missing_docs, :cross_references],
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        edit_link="main",
        canonical="https://kescobo.github.io/Hapi.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/kescobo/Hapi.jl",
    push_preview=true,
    devbranch="main"
)
