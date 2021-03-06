local structs = _G.structs or {}

function structs.Register(META)
	local arg_lines = {}
	
	for arg_i, arg in pairs(META.Args) do
		if type(arg) ~= "table" then arg = {arg} end
		
		for i, v in pairs(arg) do
			if arg_i == 1 then
				arg_lines[i] = "\tstruct { " .. META.NumberType .. " "
			end
			
			arg_lines[i] = arg_lines[i] .. v
					
			if arg_i ~= #META.Args then
				arg_lines[i] = arg_lines[i] .. ", "
			else
				arg_lines[i] = arg_lines[i] .. "; };"
			end
		end
	end
	
	table.insert(arg_lines, "\t" .. META.NumberType .. " _[" .. #META.Args .. "];")
	
	META.__index = META
	META.Type = META.ClassName:lower()
	META.TypeX = META.TypeX or META.Type
	
	local obj
	
	if META.StructOverride then
		obj = META.StructOverride()
	else
		local type_name = META.ClassName
		while pcall(ffi.typeof, type_name) do
			type_name = type_name .. "_" 
		end
		ffi.cdef("typedef union " .. type_name .. " {\n" .. table.concat(arg_lines, "\n") .. "\n} " .. type_name .. ";")
		obj = assert(ffi.metatype(type_name, META))
	end
		
	if META.Constructor then
		structs[META.ClassName] = function(...) return obj(META.Constructor(...)) end
	else
		structs[META.ClassName] = obj
 	end
		
	_G[META.ClassName] = structs[META.ClassName]
	
	prototype.Register(META)
end 
 
-- helpers

function structs.AddGetFunc(META, name, name2)
	META["Get"..(name2 or name)] = function(self, ...)
		return self[name](self:Copy(), ...)
	end
end

structs.OperatorTranslate = 
{
	["+"] = "__add",
	["-"] = "__sub",
	["*"] = "__mul",
	["/"] = "__div",
	["^"] = "__pow",
	["%"] = "__mod",
}
 
local function parse_args(META, lua, sep, protect)
	sep = sep or ", "
	
	local str = ""
	
	local count = #META.Args
	
	for _, line in pairs(lua:explode("\n")) do
		if line:find("KEY") or line:find("ARG") then
			local str = ""
			for i, trans in pairs(META.Args) do
				local arg = trans
				
				if type(trans) == "table" then
					arg = trans[1]
				end
								
				if protect and META.ProtectedFields and META.ProtectedFields[arg] then
					str = str .. "PROTECT " .. arg
				elseif line:find("ARG") then
					str = str .. arg
					if i ~= count then
						str = str .. ", "
					end	
				else
					str = str .. line:gsub("KEY", arg)	
				end
				
				if i ~= count and not line:find("ARG") then
					str = str .. sep
				end	
				
				if line:find("KEY") then
					str = str .. "\n"
				end
			end		
			
			if line:find("ARG") then
				str = line:gsub("ARG", str)
			end
			line = str
		end
		str = str .. line .. "\n"
	end
	
	return str
end
 
function structs.AddOperator(META, operator, ...)
	if operator == "tostring" then
		local lua = [==[
		local META, structs = ...
		META["__tostring"] = function(a)
				return 
				string.format(
					"%s(LINE)", 
					META.ClassName, 
					a.KEY
				)
			end
		]==]
		
		local str = ""
		for i in pairs(META.Args) do
			str = str .. "%%s"
			if i ~= #META.Args then
				str = str .. ", "
			end
		end

		lua = lua:gsub("LINE", str)
		
		lua = parse_args(META, lua, ", ")
				
		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	elseif operator == "unpack" then
		local lua = [==[
		local META, structs = ...
		META["Unpack"] = function(a)
				return
				a.KEY
			end
		]==]
		
		lua = parse_args(META, lua, ", ")
		
		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	elseif operator == "==" then
		local lua = [==[
		local META, structs = ...
		META["__eq"] = function(a, b)
				return 
				--a and
				--getmetatable(a) == "ffi" and
				type(a) == "cdata" and
				ffi.istype(a, b) and 
				
				a.KEY == b.KEY
			end
		]==]
				
		lua = parse_args(META, lua, " and ")

		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
		
		local lua = [==[
		local META, structs = ...
		META["IsEqual"] = function(self, ARG)
			return 
				self.KEY == KEY
			end
		]==]
		
		lua = parse_args(META, lua, " and ")

		assert(loadstring(lua, META.ClassName .. " operator IsEqual"))(META, structs)
	elseif operator == "unm" then
		local lua = [==[
		local META, structs = ...
		META["__unm"] = function(a)
				return
				CTOR(
					-a.KEY
				)
			end
		]==]
		
		lua = parse_args(META, lua, ", ", true)
		lua = lua:gsub("PROTECT", "a.")

		
		lua = lua:gsub("CTOR", "structs."..META.ClassName)
		
		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	elseif operator == "zero" then
		local lua = [==[
		local META, structs = ...
		META["Zero"] = function(a)
				a.KEY = 0
				return a
			end
		]==]
		
		lua = parse_args(META, lua, "")
		
		lua = lua:gsub("CTOR", "structs."..META.ClassName)
		
		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	elseif operator == "set" then
		local lua = [==[
		local META, structs = ...
		META["Set"] = function(a, ARG)
				a.KEY = KEY
				return a
			end
		]==]
		
		lua = parse_args(META, lua, "")
		
		lua = lua:gsub("CTOR", "structs."..META.ClassName)
		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	elseif operator == "copy" then
		local lua = [==[
		local META, structs = ...
		META["Copy"] = function(a)
				return
				CTOR(
					a.KEY
				)
			end
		META.__copy = META.Copy
		]==]
		
		lua = parse_args(META, lua, ", ")
		
		lua = lua:gsub("CTOR", "structs."..META.ClassName)
		
		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	elseif operator == "math" then
		local args = {...}
		local func_name = args[1]
		local accessor_name = args[2]
		local accessor_name_get = args[3]
		local self_arg = args[4]
		
		local lua = [==[
		local META, structs = ...
		META["ACCESSOR_NAME"] = function(a, ]==] .. (self_arg and "b, c" or "...") .. [==[)
			a.KEY = math.FUNC_NAME(a.KEY, ]==] .. (self_arg and "b.KEY, c.KEY" or "...") .. [==[)
			
			return a 
		end
		]==]
		
		lua = parse_args(META, lua, "")
		
		lua = lua:gsub("CTOR", "structs."..META.ClassName)
		lua = lua:gsub("FUNC_NAME", func_name)
		lua = lua:gsub("ACCESSOR_NAME", accessor_name)
				
		assert(loadstring(lua, META.ClassName .. " operator " .. func_name))(META, structs)
		
		structs.AddGetFunc(META, accessor_name, accessor_name_get)
	elseif operator == "random" then
		local lua = [==[
		local META, structs = ...
		META["Random"] = function(a, ...)
				a.KEY = math.randomf(...)
				
				return a
			end
		]==]
		
		lua = parse_args(META, lua, "")
		
		lua = lua:gsub("CTOR", "structs."..META.ClassName)
		
		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
		
		structs.AddGetFunc(META, "Random")
		
		--_G[META.ClassName .. "Rand"] = function(min, max)
		--	return structs[META.ClassName]():GetRandom(min or -1, max or 1)
		--end
	elseif structs.OperatorTranslate[operator] then
		local lua = [==[
		local META, structs = ...
		META[structs.OperatorTranslate["OPERATOR"]] = function(a, b)
			if type(b) == "number" then
				return CTOR(
					a.KEY OPERATOR b
				)
			elseif type(a) == "number" then
				return CTOR(
					a OPERATOR b.KEY
				)
			elseif a and ffi.istype(a, b) then
				return CTOR(
					a.KEY OPERATOR b.KEY
				)
			else
				error(("tried to use operator OPERATOR on a %s value"):format(tostring(b)), 2)
			end
		end
		]==]
		
		lua = parse_args(META, lua, ", ", true)
				
		lua = lua:gsub("CTOR", "structs."..META.ClassName)
		
		lua = lua:gsub("OPERATOR", operator == "%" and "%%" or operator)
		lua = lua:gsub("PROTECT", "a.")
				
		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	elseif operator == "iszero" then
		local lua = [==[
		local META, structs = ...
		META["IsZero"] = function(a)
				return 
				a.KEY == 0
			end
		]==]
		
		lua = parse_args(META, lua, " and ")

		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	elseif operator == "isvalid" then
		local lua = [==[
		local META, structs = ...
		META["IsValid"] = function(a)
				return 
				math.isvalid(a.KEY)
			end
		]==]
		
		lua = parse_args(META, lua, " and ")

		assert(loadstring(lua, META.ClassName .. " operator " .. operator))(META, structs)
	else
		logn("unhandled operator " .. operator)
	end
end

function structs.AddAllOperators(META)
	structs.AddOperator(META, "+")
	structs.AddOperator(META, "-")
	structs.AddOperator(META, "*")
	structs.AddOperator(META, "/")
	structs.AddOperator(META, "^")
	structs.AddOperator(META, "unm")
	structs.AddOperator(META, "%")
	structs.AddOperator(META, "==")
	structs.AddOperator(META, "copy")
	structs.AddOperator(META, "iszero")
	structs.AddOperator(META, "isvalid")
	structs.AddOperator(META, "unpack")
	structs.AddOperator(META, "tostring")
	structs.AddOperator(META, "zero")
	structs.AddOperator(META, "random")
	structs.AddOperator(META, "set")
	structs.AddOperator(META, "math", "abs", "Abs")
	structs.AddOperator(META, "math", "round", "Round", "Rounded")
	structs.AddOperator(META, "math", "ceil", "Ceil", "Ceiled")
	structs.AddOperator(META, "math", "floor", "Floor", "Floored")
	structs.AddOperator(META, "math", "min", "Min", "Min")
	structs.AddOperator(META, "math", "max", "Max", "Max")
	structs.AddOperator(META, "math", "clamp", "Clamp", "Clamped", true)
end

include("structs/*", structs)

return structs