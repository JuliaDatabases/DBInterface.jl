using Documenter, DBInterface

makedocs(;
    modules=[DBInterface],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/JuliaDatabases/DBInterface.jl/blob/{commit}{path}#L{line}",
    sitename="DBInterface.jl",
    authors="Jacob Quinn",
    assets=String[],
)

deploydocs(;
    repo="github.com/JuliaDatabases/DBInterface.jl",
)
