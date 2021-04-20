using JSONSchemaGenerator

using JSON3
using JSONSchema
using OrderedCollections
using Test
using StructTypes

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
StructTypes.StructType(::Type{Address}) = StructTypes.Struct()

struct Model
    billing_address::Address
    shipping_address::Address
end
StructTypes.StructType(::Type{Model}) = StructTypes.Struct()

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
      "required": ["street_address", "city", "state"],
      "additionalProperties": false
    }
  },

  "type": "object",

  "properties": {
    "billing_address": { "\$ref": "#/definitions/address" },
    "shipping_address": { "\$ref": "#/definitions/address" }
  },

  "required": ["billing_address", "shipping_address"],
  "additionalProperties": false
}
"""

abstract type AbstractFoo end
StructTypes.StructType(::Type{AbstractFoo}) = StructTypes.AbstractType()
StructTypes.subtypes(::Type{AbstractFoo}) = (foo=Foo, bar=Bar)

struct Foo <: AbstractFoo
    val::Int
end
StructTypes.StructType(::Type{Foo}) = StructTypes.Struct()

struct Bar <: AbstractFoo
    val::Float64
end
StructTypes.StructType(::Type{Bar}) = StructTypes.Struct()

struct Option
    val::Union{Nothing,Int}
end
StructTypes.StructType(::Type{Option}) = StructTypes.Struct()

struct Inner
    val::Float64
end
StructTypes.StructType(::Type{Inner}) = StructTypes.Struct()

struct Middle
    val::Inner
end
StructTypes.StructType(::Type{Middle}) = StructTypes.Struct()

struct Outer
    val::Middle
end
StructTypes.StructType(::Type{Outer}) = StructTypes.Struct()

const NESTED_EXAMPLE = """
{
  "\$schema": "http://json-schema.org/draft-07/schema#",

  "definitions": {
    "inner": {
      "type": "object",
      "properties": {
        "val": { "type": "number" }
      },
      "required": ["val"],
      "additionalProperties": false
    },
    "middle": {
      "type": "object",
      "properties": {
        "val": { "\$ref": "#/definitions/inner" }
      },
      "required": ["val"],
      "additionalProperties": false
    }
  },

  "type": "object",

  "properties": {
    "val": { "\$ref": "#/definitions/middle" }
  },

  "required": ["val"],
  "additionalProperties": false
}
"""

stripws(str) = replace(str, r"\s" => "")

@testset "JSONSchemaGenerator.jl" begin
    @testset "Schema" begin
        @test JSONSchemaGenerator.isrequired(Address)
        @test !JSONSchemaGenerator.isrequired(Union{Nothing,Address})
        @test JSONSchemaGenerator.Schema(String) == JSONSchemaGenerator.JSONString()
        @test JSONSchemaGenerator.Schema(Int) == JSONSchemaGenerator.JSONInt()
        @test JSONSchemaGenerator.Schema(Float64) == JSONSchemaGenerator.JSONNumber()
        @test JSONSchemaGenerator.Schema(Bool) == JSONSchemaGenerator.JSONBool()
        @test JSONSchemaGenerator.Schema(Vector{Float64}) ==
              JSONSchemaGenerator.JSONList(JSONSchemaGenerator.JSONNumber())
        @test JSONSchemaGenerator.Schema(typeof((1, 2, 3, 4))) ==
              JSONSchemaGenerator.JSONList(JSONSchemaGenerator.JSONInt(), 4)
        @test JSONSchemaGenerator.Schema(typeof(("tuple", 1))) == JSONSchemaGenerator.JSONTuple(
            [JSONSchemaGenerator.JSONString(), JSONSchemaGenerator.JSONInt()], 2
        )
        @test JSONSchemaGenerator.Schema(Address) == JSONSchemaGenerator.JSONObject(
            :Address,
            OrderedDict(
                :street_address => JSONSchemaGenerator.JSONString(),
                :city => JSONSchemaGenerator.JSONString(),
                :state => JSONSchemaGenerator.JSONString(),
            ),
            [:street_address, :city, :state],
        )
        @test JSONSchemaGenerator.Schema(AbstractFoo) == JSONSchemaGenerator.JSONOneOf([
            JSONSchemaGenerator.Schema(Foo), JSONSchemaGenerator.Schema(Bar)
        ])
        @test JSONSchemaGenerator.Schema(Option) == JSONSchemaGenerator.JSONObject(
            :Option, OrderedDict(:val => JSONSchemaGenerator.JSONInt()), []
        )
        @test string(JSONSchemaGenerator.JSONRef("blob")) ==
              "{\"\$ref\":\"#/definitions/blob\"}"
        @test generate(SchemaGenerator(Int)) == stripws(INT_EXAMPLE)
        @test generate(SchemaGenerator(Model)) == stripws(MODEL_EXAMPLE)
        @test generate(SchemaGenerator(Outer)) == stripws(NESTED_EXAMPLE)
    end
    @testset "Round Trip" begin
        schema_file = tempname()
        json_file = tempname()
        open(schema_file, "w") do f
            write(f, generate(SchemaGenerator(Model)))
        end
        model = Model(
            Address("1600 Pennsylvania Avenue NW", "Washington", "DC"),
            Address("1st Street SE", "Washington", "DC"),
        )
        open(json_file, "w") do f
            JSON3.write(f, model)
        end
        schema = Schema(read(schema_file, String))
        @test isvalid(JSON3.read(read(json_file, String), Dict), schema)
    end
end

