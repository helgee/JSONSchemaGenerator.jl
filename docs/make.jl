using JSONSchemaGenerator
using Documenter

DocMeta.setdocmeta!(JSONSchemaGenerator, :DocTestSetup, :(using JSONSchemaGenerator); recursive=true)

makedocs(;
    modules=[JSONSchemaGenerator],
    authors="Helge Eichhorn <git@helgeeichhorn.de> and contributors",
    repo="https://github.com/helgee/JSONSchemaGenerator.jl/blob/{commit}{path}#{line}",
    sitename="JSONSchemaGenerator.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://helgee.github.io/JSONSchemaGenerator.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/helgee/JSONSchemaGenerator.jl",
)
