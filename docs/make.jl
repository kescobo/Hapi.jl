using Hapi
using Documenter

makedocs(;
    modules=[Hapi],
    checkdocs=:exports,
    authors="Kevin Bonham <kevbonham@gmail.com>",
    repo="https://github.com/kescobo/Hapi.jl/blob/{commit}{path}#L{line}",
    sitename="Hapi.jl",
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
