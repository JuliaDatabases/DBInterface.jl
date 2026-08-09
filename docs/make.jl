using Documenter, DBInterface

makedocs(;
    modules=[DBInterface],
    format=Documenter.HTML(repolink="https://github.com/JuliaDatabases/DBInterface.jl"),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/JuliaDatabases/DBInterface.jl/blob/{commit}{path}#L{line}",
    sitename="DBInterface.jl",
    authors="Jacob Quinn",
)

deploydocs(;
    repo="github.com/JuliaDatabases/DBInterface.jl",
)
