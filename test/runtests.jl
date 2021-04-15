using JSONSchemaGenerator
using Test

struct Address
    street_address::String
    city::String
    state::String
end

struct Model
    billing_address::Address
    shipping_address::Address
end

const ADDRESS_EXAMPLE = """
{
  "\$schema": "http://json-schema.org/draft-07/schema#",

  "definitions": {
    "address": {
      "type": "object",
      "properties": {
        "street_address": { "type": "string" },
        "city":           { "type": "string" },
        "state":          { "type": "string" }
      },
      "required": ["street_address", "city", "state"]
    }
  },

  "type": "object",

  "properties": {
    "billing_address": { "\$ref": "#/definitions/address" },
    "shipping_address": { "\$ref": "#/definitions/address" }
  }
}
"""

@testset "JSONSchemaGenerator.jl" begin
    @test jsontype(Int) == "integer"
    @test jsontype(String) == "string"
    @test jsontype(Float64) == "number"
    @test jsontype(Address) == "object"
    @test isstruct(Address)
    @test isstruct(Union{Nothing, Address})
    @test structtype(Address) == Address
    @test structtype(Union{Nothing, Address}) == Address
    @test isrequired(Address)
    @test !isrequired(Union{Nothing, Address})
    schema = Schema(Model)
    @test generate(schema) == replace(ADDRESS_EXAMPLE, r"\s"=>"")
end
