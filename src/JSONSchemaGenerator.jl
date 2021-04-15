module JSONSchemaGenerator

using JSON3
using OrderedCollections: OrderedDict
using StructTypes

const SCHEMA_VERSION = "http://json-schema.org/draft-07/schema#"

export SchemaGenerator
export JSONSchema, JSONString, JSONNumber, JSONInt, JSONBool, JSONRef
export JSONObject, JSONArray, JSONList, JSONTuple, JSONOneOf
export generate

abstract type JSONSchema end

StructTypes.StructType(::Type{JSONSchema}) = StructTypes.AbstractType()
StructTypes.StructType(::Type{<:JSONSchema}) = StructTypes.OrderedStruct()
StructTypes.omitempties(::Type{<:JSONSchema}) = true
write(io::IO, schema::JSONSchema) = JSON3.write(io, schema)
write(schema::JSONSchema) = write(stdout, schema)

Base.show(io::IO, schema::JSONSchema) = write(io, schema)
Base.:(==)(a::JSONSchema, b::JSONSchema) = string(a) == string(b)

struct JSONString <: JSONSchema
    type::Symbol
    format::String
    JSONString(format="") = new(:string, format)
end

JSONSchema(::Type{<:AbstractString}) = JSONString()

struct JSONNumber <: JSONSchema
    type::Symbol
    JSONNumber(type=:number) = new(type)
end
const JSONInt() = JSONNumber(:integer)

JSONSchema(::Type{<:Integer}) = JSONNumber(:integer)
JSONSchema(::Type{<:Number}) = JSONNumber(:number)

struct JSONBool <: JSONSchema
    type::Symbol
    JSONBool() = new(:boolean)
end

JSONSchema(::Type{Bool}) = JSONBool()

abstract type JSONArray <: JSONSchema end

StructTypes.StructType(::Type{JSONArray}) = StructTypes.AbstractType()
StructTypes.isempty(::Type{JSONArray}, val::Int) = iszero(val)

struct JSONList <: JSONArray
    type::Symbol
    items::JSONSchema
    minItems::Int
    maxItems::Int
    function JSONList(items, length=0)
        return new(:array, items, length, length)
    end
end

JSONSchema(arr::Type{<:AbstractArray}) = JSONList(JSONSchema(eltype(arr)))
JSONSchema(::Type{NTuple{N, T}}) where {N, T} = JSONList(JSONSchema(T), N)

struct JSONTuple <: JSONArray
    type::Symbol
    items::Vector{JSONSchema}
    minItems::Int
    maxItems::Int
    function JSONTuple(items, length=0)
        return new(:array, items, length, length)
    end
end

function JSONSchema(tup::Type{<:Tuple})
    types = fieldtypes(tup)
    return JSONTuple(collect(JSONSchema.(types)), length(types))
end

isrequired(type) = !(type isa Union && type >: Nothing)

struct JSONObject <: JSONSchema
    type::Symbol
    juliatype::Symbol
    properties::OrderedDict{Symbol, JSONSchema}
    required::Vector{Symbol}
    JSONObject(type, properties, required) = new(:object, type, properties, required)
end
StructTypes.excludes(::Type{JSONObject}) = (:juliatype,)

struct JSONOneOf <: JSONSchema
    oneOf::Vector{JSONSchema}
end

function subschemas end

function JSONSchema(::Type{T}) where T
    isabstracttype(T) && return JSONOneOf(collect(JSONSchema.(subschemas(T))))

    properties = OrderedDict{Symbol, JSONSchema}()
    required = Symbol[]
    for (name, type) in zip(fieldnames(T), fieldtypes(T))
        isrequired(type) && push!(required, name)
        push!(properties, name=>JSONSchema(type))
    end
    return JSONObject(nameof(T), properties, required)
end
JSONSchema(::Type{Union{T, Nothing}}) where {T} = JSONSchema(T)

struct JSONRef <: JSONSchema
    name::String
    ref::String
    JSONRef(name) = new(name, "#/definitions/$name")
end
StructTypes.excludes(::Type{JSONRef}) = (:name,)
StructTypes.names(::Type{JSONRef}) = ((:ref, Symbol("\$ref")),)

struct SchemaGenerator
    schema::String
    definitions::OrderedDict{String, JSONSchema}
    type::Symbol
    format::String
    array_items::Union{Nothing, JSONSchema}
    tuple_items::Vector{JSONSchema}
    minItems::Int
    maxItems::Int
    properties::OrderedDict{Symbol, JSONSchema}
    required::Vector{Symbol}
    root::JSONSchema
end
StructTypes.StructType(::Type{SchemaGenerator}) = StructTypes.OrderedStruct()
function StructTypes.names(::Type{SchemaGenerator})
    return ((:schema, Symbol("\$schema")), (:array_items, :items), (:tuple_items, :items))
end
StructTypes.excludes(::Type{SchemaGenerator}) = (:root,)
StructTypes.omitempties(::Type{SchemaGenerator}) = true
StructTypes.isempty(::Type{SchemaGenerator}, val::Int) = iszero(val)
function StructTypes.isempty(::Type{SchemaGenerator}, val::Union{Nothing, JSONSchema})
    return isnothing(val)
end

function hoist_definitions!(definitions, schema::JSONObject)
    for (key, prop) in schema.properties
        prop isa JSONObject || continue
        name = lowercase(string(prop.juliatype))
        if !(name in keys(definitions))
            push!(definitions, name=>prop)
            hoist_definitions!(definitions, prop)
        end
        schema.properties[key] = JSONRef(name)
    end
    return nothing
end
hoist_definitions!(definitions, ::JSONSchema) = nothing

function SchemaGenerator(model)
    root = JSONSchema(model)
    definitions = OrderedDict{String, JSONObject}()
    hoist_definitions!(definitions, root)

    type = root.type
    if hasfield(typeof(root), :format)
        format = getfield(root, :format)
    else
        format = ""
    end
    if hasfield(typeof(root), :items) && fieldtype(typeof(root), :items) <: JSONSchema
        array_items = getfield(root, :items)
    else
        array_items = nothing
    end
    if hasfield(typeof(root), :items) && fieldtype(typeof(root), :items) <: AbstractArray
        tuple_items = getfield(root, :items)
    else
        tuple_items = []
    end
    if hasfield(typeof(root), :minItems)
        minItems = getfield(root, :minItems)
    else
        minItems = 0
    end
    if hasfield(typeof(root), :maxItems)
        maxItems = getfield(root, :maxItems)
    else
        maxItems = 0
    end
    if hasfield(typeof(root), :properties)
        properties = getfield(root, :properties)
    else
        properties = OrderedDict()
    end
    if hasfield(typeof(root), :required)
        required = getfield(root, :required)
    else
        required = []
    end
    return SchemaGenerator(SCHEMA_VERSION, definitions, type, format, array_items, tuple_items, minItems, maxItems, properties, required, root)
end

function generate(generator::SchemaGenerator; pretty=false)
    json = JSON3.write(generator)
    pretty && return JSON3.pretty(json)
    return json
end

end

