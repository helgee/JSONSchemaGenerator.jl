module JSONSchemaGenerator

using JSON3
using OrderedCollections: OrderedDict
using StructTypes

export JSONType, JSONArray, Reference, Property, Object, Schema
export generate, isstruct, isrequired, structtype, jsontype

const SCHEMA_VERSION = "http://json-schema.org/draft-07/schema#"

const PropType = OrderedDict{String, OrderedDict{String, String}}

struct Reference
	ref::String
	Reference(name) = new("#/definitions/$name")
end
StructTypes.StructType(::Type{Reference}) = StructTypes.OrderedStruct()
StructTypes.names(::Type{Reference}) = ((:ref, Symbol("\$ref")),)

struct Property
	type::String
	enum::Array{String}
	Property(type, enum=String[]) = new(type, enum)
end
StructTypes.StructType(::Type{Property}) = StructTypes.OrderedStruct()
StructTypes.omitempties(::Type{Property}) = true

struct Object
	type::String
	properties::OrderedDict{String, Union{Property, Reference}}
	required::Array{String}
	Object(properties, required) = new("object", properties, required)
end
StructTypes.StructType(::Type{Object}) = StructTypes.OrderedStruct()
StructTypes.omitempties(::Type{Object}) = true

struct JSONArray
	type::String
	items::Union{OrderedDict{String, String}, Reference}
end

jsonname(type) = lowercase(String(nameof(type)))

isstruct(dt::DataType) = isstructtype(dt)
isstruct(::Type{Union{T, Nothing}}) where {T} = isstructtype(T)
structtype(dt::DataType) = dt
structtype(::Type{Union{T, Nothing}}) where {T} = T
isrequired(dt) = !(dt isa Union && Nothing <: dt)

function define_structs!(definitions, type)
	name = jsonname(type)
	name in keys(definitions) && return

	properties = OrderedDict{String, Union{Property, Reference}}()
	required = String[]
	for (fn, ftype) in zip(fieldnames(type), fieldtypes(type))
		fname = String(fn)
		if isrequired(ftype)
			push!(required, fname)
		end
		if jsontype(ftype) == "object"
			stype = structtype(ftype)
			jtype = jsonname(stype)
			# Recurse into undefined field types
			jtype in keys(definitions) || define_structs!(definitions, ftype)
			push!(properties, fname=>Reference(jtype))
			continue
		end
		push!(properties, fname=>Property(jsontype(ftype)))
	end
	push!(definitions, name=>Object(properties, required))
end

struct Schema
	schema::String
	definitions::OrderedDict{String, Object}
	type::String
	properties::OrderedDict{String, Union{Property, Reference}}
	function Schema(model::DataType)
		definitions = OrderedDict{String, Object}()
		type = "object"
		properties = OrderedDict{String, Union{Property, Reference}}()
		for (fn, ftype) in zip(fieldnames(model), fieldtypes(model))
			fname = String(fn)
			if jsontype(ftype) == "object"
				stype = structtype(ftype)
				jtype = jsonname(stype)
				# Recurse into undefined field types
				jtype in keys(definitions) || define_structs!(definitions, ftype)
				push!(properties, fname=>Reference(jtype))
				continue
			end
			push!(properties, fname=>Property(jsontype(ftype)))
		end
		return new(SCHEMA_VERSION, definitions, type, properties)
	end
end
StructTypes.StructType(::Type{Schema}) = StructTypes.OrderedStruct()
StructTypes.names(::Type{Schema}) = ((:schema, Symbol("\$schema")),)

function generate(schema::Schema; pretty=false)
	json = JSON3.write(schema)
	pretty && return JSON3.pretty(json)
	return json
end

jsontype(::Type{<:AbstractString}) = "string"
jsontype(::Type{<:Integer}) = "integer"
jsontype(::Type{<:AbstractFloat}) = "number"
jsontype(::Type{T}) where {T} = "object"

end
