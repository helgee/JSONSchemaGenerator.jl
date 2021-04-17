module JSONSchemaGenerator

using JSON3
using OrderedCollections: OrderedDict
using StructTypes

export SchemaGenerator
export generate

const SCHEMA_VERSION = "http://json-schema.org/draft-07/schema#"

abstract type Schema end

StructTypes.StructType(::Type{Schema}) = StructTypes.AbstractType()
StructTypes.StructType(::Type{<:Schema}) = StructTypes.OrderedStruct()
StructTypes.omitempties(::Type{<:Schema}) = true
write(io::IO, schema::Schema) = JSON3.write(io, schema)
write(schema::Schema) = write(stdout, schema)

Base.show(io::IO, schema::Schema) = write(io, schema)
Base.:(==)(a::Schema, b::Schema) = string(a) == string(b)

struct JSONString <: Schema
    type::Symbol
    format::String
    JSONString(format="") = new(:string, format)
end

Schema(::Type{<:AbstractString}) = JSONString()

struct JSONNumber <: Schema
    type::Symbol
    JSONNumber(type=:number) = new(type)
end
const JSONInt() = JSONNumber(:integer)

Schema(::Type{<:Integer}) = JSONNumber(:integer)
Schema(::Type{<:Number}) = JSONNumber(:number)

struct JSONBool <: Schema
    type::Symbol
    JSONBool() = new(:boolean)
end

Schema(::Type{Bool}) = JSONBool()

abstract type JSONArray <: Schema end

StructTypes.StructType(::Type{JSONArray}) = StructTypes.AbstractType()
StructTypes.isempty(::Type{JSONArray}, val::Int) = iszero(val)

struct JSONList <: JSONArray
    type::Symbol
    items::Schema
    minItems::Int
    maxItems::Int
    function JSONList(items, length=0)
        return new(:array, items, length, length)
    end
end

Schema(arr::Type{<:AbstractArray}) = JSONList(Schema(eltype(arr)))
Schema(::Type{NTuple{N, T}}) where {N, T} = JSONList(Schema(T), N)

struct JSONTuple <: JSONArray
    type::Symbol
    items::Vector{Schema}
    minItems::Int
    maxItems::Int
    function JSONTuple(items, length=0)
        return new(:array, items, length, length)
    end
end

function Schema(tup::Type{<:Tuple})
    types = fieldtypes(tup)
    return JSONTuple(collect(Schema.(types)), length(types))
end

isrequired(type) = !(type isa Union && type >: Nothing)

struct JSONObject <: Schema
    type::Symbol
    juliatype::Symbol
    properties::OrderedDict{Symbol, Schema}
    required::Vector{Symbol}
    JSONObject(type, properties, required) = new(:object, type, properties, required)
end
StructTypes.excludes(::Type{JSONObject}) = (:juliatype,)

struct JSONOneOf <: Schema
    oneOf::Vector{Schema}
end

function subschemas end

function Schema(::Type{T}) where T
    isabstracttype(T) && return JSONOneOf(collect(Schema.(subschemas(T))))

    properties = OrderedDict{Symbol, Schema}()
    required = Symbol[]
    for (name, type) in zip(fieldnames(T), fieldtypes(T))
        isrequired(type) && push!(required, name)
        push!(properties, name=>Schema(type))
    end
    return JSONObject(nameof(T), properties, required)
end
Schema(::Type{Union{T, Nothing}}) where {T} = Schema(T)

function Schema(::Type{<:AbstractDict})
    properties = OrderedDict{Symbol, Schema}()
end

struct JSONRef <: Schema
    name::String
    ref::String
    JSONRef(name) = new(name, "#/definitions/$name")
end
StructTypes.excludes(::Type{JSONRef}) = (:name,)
StructTypes.names(::Type{JSONRef}) = ((:ref, Symbol("\$ref")),)

struct SchemaGenerator
    schema::String
    definitions::OrderedDict{String, Schema}
    type::Symbol
    format::String
    array_items::Union{Nothing, Schema}
    tuple_items::Vector{Schema}
    minItems::Int
    maxItems::Int
    properties::OrderedDict{Symbol, Schema}
    required::Vector{Symbol}
    root::Schema
end
StructTypes.StructType(::Type{SchemaGenerator}) = StructTypes.OrderedStruct()
function StructTypes.names(::Type{SchemaGenerator})
    return ((:schema, Symbol("\$schema")), (:array_items, :items), (:tuple_items, :items))
end
StructTypes.excludes(::Type{SchemaGenerator}) = (:root,)
StructTypes.omitempties(::Type{SchemaGenerator}) = true
StructTypes.isempty(::Type{SchemaGenerator}, val::Int) = iszero(val)
function StructTypes.isempty(::Type{SchemaGenerator}, val::Union{Nothing, Schema})
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
hoist_definitions!(definitions, ::Schema) = nothing

function SchemaGenerator(model)
    root = Schema(model)
    definitions = OrderedDict{String, JSONObject}()
    hoist_definitions!(definitions, root)

    type = root.type
    if hasfield(typeof(root), :format)
        format = getfield(root, :format)
    else
        format = ""
    end
    if hasfield(typeof(root), :items) && fieldtype(typeof(root), :items) <: Schema
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

