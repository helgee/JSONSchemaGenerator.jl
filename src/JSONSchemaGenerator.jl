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
function StructTypes.isempty(::Type{<:Schema}, val::Union{Nothing, Schema})
    return isnothing(val)
end
write(io::IO, schema::Schema) = JSON3.write(io, schema)
write(schema::Schema) = write(stdout, schema)

Base.show(io::IO, schema::Schema) = write(io, schema)
Base.:(==)(a::Schema, b::Schema) = string(a) == string(b)

Schema(::Type{Any}) = nothing
Schema(::Type{T}) where T = Schema(StructTypes.StructType(T), T)
Schema(::Type{Union{T, Nothing}}) where {T} = Schema(T)

struct JSONNull <: Schema
    type::Nothing
    JSONNull() = new(nothing)
end

struct JSONString <: Schema
    type::Symbol
    format::String
    JSONString(format="") = new(:string, format)
end

Schema(::StructTypes.StringType, ::Type{T}) where T = JSONString()

struct JSONNumber <: Schema
    type::Symbol
    JSONNumber(type=:number) = new(type)
end
const JSONInt() = JSONNumber(:integer)

Schema(::StructTypes.NumberType, ::Type{<:Integer}) = JSONNumber(:integer)
Schema(::StructTypes.NumberType, ::Type{<:Number}) = JSONNumber(:number)

struct JSONBool <: Schema
    type::Symbol
    JSONBool() = new(:boolean)
end

Schema(::StructTypes.BoolType, ::Type{Bool}) = JSONBool()

abstract type JSONArray <: Schema end

StructTypes.StructType(::Type{JSONArray}) = StructTypes.AbstractType()
StructTypes.isempty(::Type{JSONArray}, val::Int) = iszero(val)

mutable struct JSONList <: JSONArray
    type::Symbol
    items::Union{Nothing, Schema}
    minItems::Int
    maxItems::Int
    function JSONList(items, length=0)
        return new(:array, items, length, length)
    end
end

Schema(::StructTypes.ArrayType, arr::Type{<:AbstractArray}) = JSONList(Schema(eltype(arr)))
Schema(::StructTypes.ArrayType, set::Type{<:AbstractSet}) = JSONList(Schema(eltype(set)))
Schema(::StructTypes.ArrayType, ::Type{NTuple{N, T}}) where {N, T} = JSONList(Schema(T), N)

struct JSONTuple <: JSONArray
    type::Symbol
    items::Vector{Schema}
    minItems::Int
    maxItems::Int
    function JSONTuple(items, length=0)
        return new(:array, items, length, length)
    end
end

function Schema(::StructTypes.ArrayType, tup::Type{<:Tuple})
    types = fieldtypes(tup)
    return JSONTuple(collect(Schema.(types)), length(types))
end

isrequired(type) = !(type isa Union && type >: Nothing)

struct JSONObject <: Schema
    type::Symbol
    title::Union{Symbol, Nothing}
    properties::OrderedDict{Symbol, Schema}
    required::Vector{Symbol}
    additionalProperties::Union{Bool, Schema}
    function JSONObject(type, properties, required, additionalProperties=false)
        return new(:object, type, properties, required, additionalProperties)
    end
end
# StructTypes.excludes(::Type{JSONObject}) = (:juliatype,)

function Schema(::StructTypes.DataType, ::Type{T}) where T
    properties = OrderedDict{Symbol, Schema}()
    required = Symbol[]
    for (name, type) in zip(fieldnames(T), fieldtypes(T))
        isrequired(type) && push!(required, name)
        push!(properties, name=>Schema(type))
    end
    return JSONObject(nameof(T), properties, required)
end

function Schema(::StructTypes.DictType, ::Type{<:AbstractDict{K, V}}) where {K, V}
    schema = Schema(V)
    isnothing(schema) && return JSONObject(nothing, Dict(), [], true)
    return JSONObject(nothing, Dict(), [], schema)
end
Schema(::StructTypes.DictType, ::Type{<:AbstractDict}) = Schema(Dict{Any, Any})

struct JSONAnyOf <: Schema
    anyOf::Vector{Schema}
end

function Schema(u::Union)
    v = Schema[]
    schema!(v, u)
    length(unique(v)) == 1 && return v[1]
    return JSONAnyOf(v)
end

function schema!(v::Vector{Schema}, u::Union)
    push!(v, Schema(u.a))
    return schema!(v, u.b)
end

function schema!(v::Vector{Schema}, ::Type{T}) where T
    push!(v, Schema(T))
    return v
end

struct JSONOneOf <: Schema
    oneOf::Vector{Schema}
end

function Schema(::StructTypes.AbstractType, ::Type{T}) where T
    v = Schema[]
    for type in values(StructTypes.subtypes(T))
        push!(v, Schema(type))
    end
    length(unique(v)) == 1 && return v[1]
    return JSONOneOf(v)
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
    additionalProperties::Union{Nothing, Bool, Schema}
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
function StructTypes.isempty(::Type{SchemaGenerator}, val::Union{Nothing, Bool, Schema})
    return isnothing(val)
end

function hoist_definitions!(definitions, schema::JSONList; kwargs...)
    ref = hoist_definitions!(definitions, schema.items)
    if !isnothing(ref)
        schema.items = ref
    end
    return nothing
end

function hoist_definitions!(definitions, schema::JSONTuple; kwargs...)
    for (i, item) in enumerate(schema.items)
        ref = hoist_definitions!(definitions, item)
        if !isnothing(ref)
            schema.items[i] = ref
        end
    end
    return nothing
end

function hoist_definitions!(definitions, schema::JSONOneOf; kwargs...)
    for (i, item) in enumerate(schema.oneOf)
        ref = hoist_definitions!(definitions, item)
        if !isnothing(ref)
            schema.oneOf[i] = ref
        end
    end
    return nothing
end

function hoist_definitions!(definitions, schema::JSONAnyOf; kwargs...)
    for (i, item) in enumerate(schema.anyOf)
        ref = hoist_definitions!(definitions, item)
        if !isnothing(ref)
            schema.anyOf[i] = ref
        end
    end
    return nothing
end

function hoist_definitions!(definitions, schema::JSONObject; isroot=false)
    for (key, prop) in schema.properties
        ref = hoist_definitions!(definitions, prop)
        isnothing(ref) && continue
        schema.properties[key] = ref
    end

    (isroot || isnothing(schema.title)) && return nothing
    name = lowercase(string(schema.title))
    if !(name in keys(definitions))
        push!(definitions, name=>schema)
    end
    return JSONRef(name)
end

hoist_definitions!(definitions, ::Schema; kwargs...) = nothing

function hoist_definitions(schema)
    definitions = OrderedDict{String, JSONObject}()
    hoist_definitions!(definitions, schema, isroot=true)
    return definitions
end

function SchemaGenerator(model)
    root = Schema(model)
    definitions = hoist_definitions(root)

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
    if hasfield(typeof(root), :additionalProperties)
        additionalProperties = getfield(root, :additionalProperties)
    else
        additionalProperties = nothing
    end
    return SchemaGenerator(SCHEMA_VERSION, definitions, type, format, array_items, tuple_items, minItems, maxItems, properties, required, additionalProperties, root)
end

function generate(generator::SchemaGenerator; pretty=false)
    json = JSON3.write(generator)
    pretty && return JSON3.pretty(json)
    return json
end

end

