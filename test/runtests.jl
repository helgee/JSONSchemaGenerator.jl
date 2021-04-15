using JSONSchemaGenerator
using OrderedCollections
using Test

const INT_EXAMPLE = """
{
  "\$schema": "http://json-schema.org/draft-07/schema#",

  "type": "integer"
}
"""

# TODO: Test other types

struct Address
    street_address::String
    city::String
    state::String
end

struct Model
    billing_address::Address
    shipping_address::Address
end

const MODEL_EXAMPLE = """
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
  },

  "required": ["billing_address", "shipping_address"]
}
"""

abstract type AbstractFoo end

struct Foo <: AbstractFoo
    val::Int
end

struct Bar <: AbstractFoo
    val::Float64
end

JSONSchemaGenerator.subschemas(::Type{AbstractFoo}) = (Foo, Bar)

struct Option
    val::Union{Nothing, Int}
end

struct Inner
    val::Float64
end

struct Middle
    val::Inner
end

struct Outer
    val::Middle
end

const NESTED_EXAMPLE = """
{
  "\$schema": "http://json-schema.org/draft-07/schema#",

  "definitions": {
    "middle": {
      "type": "object",
      "properties": {
        "val": { "\$ref": "#/definitions/inner" }
      },
      "required": ["val"]
    },
    "inner": {
      "type": "object",
      "properties": {
        "val": { "type": "number" }
      },
      "required": ["val"]
    }
  },

  "type": "object",

  "properties": {
    "val": { "\$ref": "#/definitions/middle" }
  },

  "required": ["val"]
}
"""

stripws(str) = replace(str, r"\s"=>"")

@testset "JSONSchemaGenerator.jl" begin
    @test JSONSchemaGenerator.isrequired(Address)
    @test !JSONSchemaGenerator.isrequired(Union{Nothing, Address})
    @test JSONSchema(String) == JSONString()
    @test JSONSchema(Int) == JSONInt()
    @test JSONSchema(Float64) == JSONNumber()
    @test JSONSchema(Bool) == JSONBool()
    @test JSONSchema(Vector{Float64}) == JSONList(JSONNumber())
    @test JSONSchema(typeof((1, 2, 3, 4))) == JSONList(JSONInt(), 4)
    @test JSONSchema(typeof(("tuple", 1))) == JSONTuple([JSONString(), JSONInt()], 2)
    @test JSONSchema(Address) == JSONObject(:Address, OrderedDict(:street_address=>JSONString(), :city=>JSONString(), :state=>JSONString()), [:street_address, :city, :state])
    @test JSONSchema(AbstractFoo) == JSONOneOf([JSONSchema(Foo), JSONSchema(Bar)])
    @test JSONSchema(Option) == JSONObject(:Option, OrderedDict(:val=>JSONInt()), [])
    @test string(JSONRef("blob")) == "{\"\$ref\":\"#/definitions/blob\"}"
    @test generate(SchemaGenerator(Int)) == stripws(INT_EXAMPLE)
    @test generate(SchemaGenerator(Model)) == stripws(MODEL_EXAMPLE)
    @test generate(SchemaGenerator(Outer)) == stripws(NESTED_EXAMPLE)
end

