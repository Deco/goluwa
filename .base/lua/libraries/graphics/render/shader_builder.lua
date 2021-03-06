local SOMETHING = false
local BUILD_OUTPUT = false

local gl = require("lj-opengl") -- OpenGL
local render = (...) or _G.render

-- used to figure out how to upload types
local unrolled_lines = {
	number = "render.Uniform1f(%i, val)",

	vec2 = "render.Uniform2f(%i, val.x, val.y)",
	vec3 = "render.Uniform3f(%i, val.x, val.y, val.z)",

	color = "render.Uniform4f(%i, val.r, val.g, val.b, val.a)",

	mat4 = "render.UniformMatrix4fv(%i, 1, 0, val)",

	texture = "local channel = %i\n\trender.ActiveTexture(channel)\n\trender.BindTexture(val)\n\trender.Uniform1i(%i, channel)",
}

unrolled_lines.vec4 = unrolled_lines.color
unrolled_lines.sampler2D = unrolled_lines.texture
unrolled_lines.float = unrolled_lines.number

local type_info =  {
	int = {type = "int", arg_count = 1},
	float = {type = "float", arg_count = 1},
	number = {type = "float", arg_count = 1},
	vec2 = {type = "float", arg_count = 2},
	vec3 = {type = "float", arg_count = 3},
	vec4 = {type = "float", arg_count = 4},
}

do -- extend typeinfo
	local type_to_enum = {
		float = gl.e.GL_FLOAT,
	}

	-- add some extra information
	for k,v in pairs(type_info) do
		v.size = ffi.sizeof(v.type)
		v.enum_type = type_to_enum[v.type]
		v.real_type = "glw_glsl_" ..k
	end

	-- declare the types
	for type, info in pairs(type_info) do
		local line = info.type .. " "
		for i = 1, info.arg_count do
			line = line .. string.char(64+i)

			if i ~= info.arg_count then
				line = line .. ", "
			end
		end

		local dec = ("struct %s { %s; };"):format(info.real_type, line)
		ffi.cdef(dec)
	end
end

local type_translate = {
	color = "vec4",
	number = "float",
	texture = "sampler2D",
	matrix44 = "mat4",
}

local uniform_translate =
{
	int = render.Uniform1i,
	float = render.Uniform1f,
	vec2 = render.Uniform2f,
	vec3 = render.Uniform3f,
	vec4 = render.Uniform4f,
	mat4 = function(location, ptr) render.UniformMatrix4fv(location, 1, 0, ptr) end,
	sampler2D = render.Uniform1i,
	not_implemented = function() end,
}

-- this will be extended after the render context has been initialized (see bottom of this script)
local shader_translate = {
	vertex = gl.e.GL_VERTEX_SHADER,
	fragment = gl.e.GL_FRAGMENT_SHADER,
	geometry = gl.e.GL_GEOMETRY_SHADER,
	tess_eval = gl.e.GL_TESS_EVALUATION_SHADER,
	tess_control = gl.e.GL_TESS_CONTROL_SHADER,
}

-- used because of some reserved keywords
local reserve_prepend = "out_"

local source_template =
[[

@@SHARED UNIFORM@@
@@UNIFORM@@

@@IN@@

@@OUT@@
@@OUT3@@

//__SOURCE_START
@@SOURCE@@
//__SOURCE_END
void main()
{
@@OUT2@@
	mainx();
}
]]

local lazy_template = [[
	out vec4 out_color;
	
	vec4 shade()
	{
		%s
	}
	
	void main()
	{
		out_color = shade();
	}
]]

local function rebuild_info()
	-- grab all valid shaders from enums
	for k,v in pairs(gl.e) do
		local name = k:match("GL_(.+)_SHADER")

		if name then
			shader_translate[name] = v
			shader_translate[k] = v
			shader_translate[v] = v
		end

	end
end

local function type_of_attribute(var)
	local t = typex(var)
	local def = var
	local get

	if t == "string" then
		t = var
		def = nil
	elseif t == "table" then
		local k,v = next(var)
		if type(k) == "string" and type(v) == "function" then
			t = k
			get = v
		else
			t = "uniform_buffer"
		end
	end

	t = type_translate[t] or t

	return t, def, get
end

local function translate_fields(data)
	local out = {}

	for k, v in pairs(data) do

		if type(k) == "number" then
			k, v = next(v)
		end

		local t, default, get = type_of_attribute(v)
		local precision, type_ = t:match("(.-) (.+)")

		table.insert(out, {name = k, type = type_ or t, default = default, precision = precision or "highp", get = get})
	end

	return out
end

local function variables_to_string(type, variables, prepend, macro, array)
	array = array or ""

	local out = {}

	for i, data in ipairs(translate_fields(variables)) do
		if data.type == "uniform_buffer" then
			table.insert(out, "layout (std140) uniform " .. data.name)
			table.insert(out, "{")
			for i, data in ipairs(translate_fields(data.default)) do
				table.insert(out, ("\t%s %s;"):format(data.type, data.name))
			end
			table.insert(out, "};")
		else
			local name = data.name

			if prepend then
				name = prepend .. name
			end

			table.insert(out, ("%s %s %s %s%s;"):format(type, data.precision, data.type, name, array))

			if macro then
				table.insert(out, ("#define %s %s"):format(data.name, name))
			end
		end
	end
	
	return table.concat(out, "\n")
end

local function replace_field(str, key, val)
	return str:gsub("(@@.-@@)", function(str)
		if str:match("@@(.+)@@") == key then
			return val
		end
	end)
end

render.active_shaders = render.active_shaders or utility.CreateWeakTable()

function render.GetShaders()
	return render.active_shaders
end

local cdef_defined = {}

local META = prototype.CreateTemplate("shader")

function render.CreateShader(data, vars)
	
	if type(data) == "string" then
		local fragment_source = data
		local name = "shader_lazy_" .. crypto.CRC32(fragment_source)
	
		data = {
			name = name,			
			vertex = {
				uniform = {
					pwm_matrix = {mat4 = render.GetPVWMatrix2D},
				},			
				attributes = {
					{pos = "vec3"},
					{uv = "vec2"},
				},	
				source = "gl_Position = pwm_matrix * vec4(pos, 1);"
			},
			
			fragment = { 
				uniform = vars,
				attributes = {
					{uv = "vec2"},
				},			
				source = fragment_source,
			} 
		}
	end

	if not render.CheckSupport("CreateShader") then
		return NULL
	end
	
	-- rebuild the type info when creating the first shader to ensure
	-- we have all the enums and functions nessceary to build it
	if rebuild_info then
		rebuild_info()
		rebuild_info = nil
	end

	-- make a copy of the data since we're going to modify it
	local original_data = data
	local data = table.copy(data)

	-- these arent actually shaders
	local shader_id = data.name data.name = nil
	local base = data.base data.base = nil
	local shared = data.shared data.shared = nil

	-- inherit from base shader provided
	if base and render.active_shaders[base] then
		local temp = table.copy(render.active_shaders[base].original_data)
		
		temp.name = nil
		temp.base = nil
		
		table.merge(temp, data)
		data = temp
		
		shared = data.shared shared = nil
	end

	if not data.vertex then
		error("no vertex shader was found", 2)
	end

	local build_output = {}

	for shader, info in pairs(data) do
		local source = source_template
		
		if OPENGL_ES then
			source = "#version 300 es" .. source
		else
			if shader:find("tess") then
				source = "#version 400" .. source
			else
				source = "#version 150" .. source
			end
		end
		
		build_output[shader] = {source = source, original_source = info.source, out = {}}
	end

	do -- figure out vertex attributes other shaders need

		for shader, info in pairs(data) do
			if shader ~= "vertex" then
				if info.attributes then
					for i, v in ipairs(info.attributes) do
						build_output.vertex.out[i] = v
					end
				end
			end
		end

		local source = build_output.vertex.source
		
		if SOMETHING then
			print(variables_to_string("out", build_output.vertex.out))
			source = replace_field(source, "OUT3", variables_to_string("out", build_output.vertex.out))
		else
			-- declare them as
			-- out highp vec3 glw_out_foo;
			source = replace_field(source, "OUT", variables_to_string("out", build_output.vertex.out, reserve_prepend))

			-- and then in main do
			-- glw_out_normal = normal;
			-- to avoid name conflicts
			local vars = {}

			for i, v in pairs(build_output.vertex.out) do
				local name = next(v)
				table.insert(vars, ("\t%s = %s;"):format(reserve_prepend .. name, name))
			end

			source = replace_field(source, "OUT2", table.concat(vars, "\n"))		
		end

		build_output.vertex.source = source
	end

	-- get type info from the vertex attributes
	if data.vertex.attributes then

		-- this info is used when binding
		build_output.vertex.vtx_info = {}

		do -- build_output and define the struct information with ffi
			local type = "glw_vtx_atrb_" .. shader_id
			type = type:gsub("%p", "_")

			local declaration = {"struct "..type.." { "}

			for key, val in pairs(data.vertex.attributes) do
				local name, t = next(val)
				local info = type_info[t]
				
				if info then
					if info.arg_count == 1 then
						table.insert(declaration, ("%s %s;"):format(info.type, name))
					else
						table.insert(declaration, ("struct %s %s; "):format(info.real_type, name))
					end
					table.insert(build_output.vertex.vtx_info, {name = name, type = t, info = info})
				else
					errorf("undefined type %q in attributes", 2, t)
				end
			end

			table.insert(declaration, " };")
			declaration = table.concat(declaration, "")
			
			if not cdef_defined[declaration] then
				ffi.cdef(declaration)
				cdef_defined[declaration] = true
			end

			type = "struct " .. type

			build_output.vertex.vtx_atrb_dec = declaration
			build_output.vertex.vtx_atrb_size = ffi.sizeof(type)
			build_output.vertex.vtx_atrb_type = type
		end
	end

	for shader, info in pairs(data) do
		local source = build_output[shader].source

		if info.uniform then
			source = replace_field(source, "UNIFORM", variables_to_string("uniform", info.uniform))
			build_output[shader].uniform = translate_fields(info.uniform)
		end

		if info.attributes then
			if shader == "vertex" then
				-- in highp vec3 foo;
				source = replace_field(source, "IN", variables_to_string("in", info.attributes))
				build_output[shader].attributes = translate_fields(info.attributes)
			else
				-- in highp vec3 glw_out_foo;
				-- #define foo glw_out_foo
				source = replace_field(source, "IN", variables_to_string("in", info.attributes, reserve_prepend, true, shader == "tess_control" and "[]"))
			end
		end

		if info.source then
			if info.source:find("\n") then
				if not info.source:find("main", nil, true) and info.source:find("return", nil, true) then
					info.source = lazy_template:format(info.source)
				end
			
			--	source = replace_field(source, "SOURCE", ("void mainx()\n{\n\t%s\n}\n"):format(info.source))
				-- replace void *main* () with mainx
				info.source = info.source:gsub("void%s+([main]-)%s-%(", function(str) if str == "main" then return "void mainx(" end end)

				source = replace_field(source, "SOURCE", info.source)
			else
				-- if it's just a single line then wrap void mainx() {*line*} around it
				source = replace_field(source, "SOURCE", ("void mainx()\n{\n\t%s\n}\n"):format(info.source))
			end

			-- get line numbers for errors
			build_output[shader].line_start = select(2, source:match(".+__SOURCE_START"):gsub("\n", "")) + 2
			build_output[shader].line_end = select(2, source:match(".+__SOURCE_END"):gsub("\n", ""))
		end

		build_output[shader].source = source
	end

	-- shared uniform across all shaders
	if shared and shared.uniform then
		for shader in pairs(data) do
			if build_output[shader] then
				build_output[shader].source = replace_field(build_output[shader].source, "SHARED UNIFORM", variables_to_string("uniform", shared.uniform))
			end
		end

		-- merge shared uniforms to vertex so they can be used
		for k,v in pairs(translate_fields(shared.uniform)) do
			table.insert(build_output.vertex.uniform, v)
		end
	end
	
	vfs.CreateFolder("shader_builder_output/" .. shader_id) 

	if BUILD_OUTPUT then
		serializer.WriteFile("luadata", "shader_builder_output/" .. shader_id .. "/build_output.lua", build_output)
	end

	local shaders = {}

	for shader, data in pairs(build_output) do
		local enum = shader_translate[shader]

		if enum then
			-- strip data that wasnt found from the source_template
			data.source = data.source:gsub("(@@.-@@)", "")

			if BUILD_OUTPUT then
				vfs.Write("data/shader_builder_output/" .. shader_id .. "/" .. shader .. ".c", data.source)
			end

			local ok, shader = pcall(render.CreateGLShader, enum, data.source)

			if not ok then
				
				local line_offset = 0
				local source = debug.getinfo(2).source
				
				if source then
					local lua_file = vfs.Read(source:sub(2))
					if lua_file then
						lua_file = lua_file:gsub("[ %t\r]", "")
						local source = data.original_source:gsub("[ %t\r]", "")
						
						local start, stop = lua_file:find(source, 0, true)
						if start then
							line_offset = lua_file:sub(0, -stop):count("\n")
						end
					end
				end
				
				
				local err = "\n" .. shader
				
				if source then
					err = source:match(".+/(.+)") .. ":" .. err
				end
				
				local goto_line
				
				err = err:gsub("0%((%d+)%) ", function(line)
					line = tonumber(line)
					goto_line = line - data.line_start + 1 + line_offset
					return goto_line
				end)
				
				debug.openfunction(debug.getinfo(2).func, tonumber(goto_line))
				
				error(err, 2)
			end

			table.insert(shaders, shader)
		else
			errorf("shader %q is unknown", 2, shader)
		end
	end
	
	local self = prototype.CreateObject(META)

	local ok, prog = pcall(render.CreateGLProgram, function(prog) 
		local vertex_attributes = {}
		local pos = 0

		for i, data in pairs(build_output.vertex.vtx_info) do
			gl.BindAttribLocation(prog, i - 1, data.name)

			vertex_attributes[i] = {
				arg_count = data.info.arg_count,
				enum = data.info.enum_type,
				stride = build_output.vertex.vtx_atrb_size,
				type_stride = ffi.cast("void*", data.info.size * pos),
				location = i - 1,
			}

			pos = pos + data.info.arg_count
		end

		self.vertex_attributes = vertex_attributes

		if BUILD_OUTPUT then
			serializer.WriteFile("luadata", "shader_builder_output/" .. shader_id .. "/vertex_attributes.lua", vertex_attributes)
		end
	end, unpack(shaders))

	if not ok then
		error(prog, 2)
	end

	do -- build lua code from uniform data
		local uniforms = {}
		local temp = {}
		
		self.defaults = {} -- default values for shaders

		for shader, data in pairs(build_output) do
			if data.uniform then
				for key, val in pairs(data.uniform) do
					if val.type == "uniform_buffer" then
						local id = gl.GetUniformBlockIndex(prog, val.name)

						local init_table = {}
						
						do
							val.struct_name = "shader_builder_ufb_" .. val.name
							local declaration = {"typedef struct "..val.struct_name.."\n{"}
							
							for name, obj in pairs(val.default) do
								local t = typex(obj)
								
								init_table[name] = {}
								
								if t == "matrix44" or obj == "mat4" then	
									table.insert(declaration, "\tfloat " .. name .. "[16];")
									
									if t == "matrix44" then
										for i = 1, 16 do
											init_table[name][i] = obj.m[i - 1]
										end
									else
										for i = 1, 16 do
											init_table[name][i] = 0
										end
									end
								elseif t == "color" or obj == "vec4" then
									table.insert(declaration, "\tfloat " .. name .. "[4];")
																	
									if t == "color" then
										init_table[name][1] = obj.r
										init_table[name][2] = obj.g
										init_table[name][3] = obj.b
										init_table[name][4] = obj.a
									else
										for i = 1, 4 do
											init_table[name][i] = 0
										end
									end
								elseif t == "vec3" or obj == "vec3" then
									table.insert(declaration, "\tfloat " .. name .. "[3];")
									if t == "vec3" then
										init_table[name][1] = obj.x
										init_table[name][2] = obj.y
										init_table[name][3] = obj.z
									else
										for i = 1, 3 do
											init_table[name][i] = 0
										end
									end
								elseif t == "vec2" or obj == "vec2" then
									table.insert(declaration, "\tfloat " .. name .. "[2];")
									if t == "vec2" then
										init_table[name][1] = obj.x
										init_table[name][2] = obj.y
									else
										for i = 1, 2 do
											init_table[name][i] = 0
										end
									end
								elseif t == "number" or obj == "float" then
									table.insert(declaration, "\tfloat " .. name .. ";")
									if t == "number" then
										init_table[name] = obj
									else
										init_table[name] = 0
									end
								end
							
								self[name] = obj
							end

							table.insert(declaration, "}"..val.struct_name..";")
							declaration = table.concat(declaration, "\n")
							
							ffi.cdef(declaration)
							val.struct_type = ffi.typeof(val.struct_name)
							
							self[val.name .. "_ufb_type"] = ffi.typeof(val.struct_name .. " *")
						end
												
						local struct = ffi.new(val.struct_type, init_table)
						
						local buffer_id = gl.GenBuffer()
						gl.BindBuffer(gl.e.GL_UNIFORM_BUFFER, buffer_id)
							gl.BufferData(gl.e.GL_UNIFORM_BUFFER, ffi.sizeof(struct), struct, gl.e.GL_DYNAMIC_DRAW)
						gl.BindBuffer(gl.e.GL_UNIFORM_BUFFER, 0)
						
						self[val.name .. "_ufb_struct"] = struct
						
						uniforms[val.name] = {
							id = id,
							info = val,
							uniform_buffer = true,
						}
						
						table.insert(temp, {id = id, key = val.name, val = val, uniform_buffer = true, buffer_id = buffer_id})
						
					elseif uniform_translate[val.type] or val.type == "function" then
						local id = gl.GetUniformLocation(prog, val.name)

						uniforms[val.name] = {
							id = id,
							func = uniform_translate[val.type],
							info = val,
						}

						table.insert(temp, {id = id, key = val.name, val = val})
						
						self.defaults[val.name] = val.default
						self[val.name] = val.default
						
						if val.get then
							self[val.name] = val.get
						end

						if render.debug and id < 0 and val.type ~= "sampler2D" then
							logf("%s: uniform in %s %s %s is not being used (uniform location < 0)\n", shader_id, shader, val.name, val.type)
						end
					else
						errorf("%s: %s is an unknown uniform type", 2, key, val.type)
					end
				end
			end
		end

		self.uniforms = uniform

		table.sort(temp, function(a, b) return a.id < b.id end) -- sort the data by uniform id

		local texture_channel = 0
		local lua = ""
		
		for i, data in ipairs(temp) do
			if data.uniform_buffer then
				lua = lua .. "if \n"
				for k, v in pairs(data.val.default) do
					lua = lua .. "\tself."..k.." ~= self.last_" .. k .. " or \n"
				end
				
				lua = lua:sub(0, -5) .. "\n"
				
				lua = lua .. "then \n"
				lua = lua .. "\tlocal ptr = ffi.cast(self."..data.key.."_ufb_type, gl.MapBuffer(gl.e.GL_UNIFORM_BUFFER, gl.e.GL_WRITE_ONLY));\n\n"
				lua = lua .. "\tif ptr ~= nil then \n"
				for k, v in pairs(data.val.default) do
					if type(v) == "number" then
						lua = lua .. "\t\tptr." .. k .. " = self."..k.."\n"
						lua = lua .. "\t\tself.last_" .. k .. " = self."..k.." \n"
					else
						if typex(v) == "matrix44" then
							lua = lua .. "\t\tffi.copy(ptr." .. k .. ", self."..k..".m, "..ffi.sizeof(self[data.val.name .. "_ufb_struct"][k])..") \n"
						else
							lua = lua .. "\t\tffi.copy(ptr." .. k .. ", self."..k..", "..ffi.sizeof(self[data.val.name .. "_ufb_struct"][k])..") \n"
						end
						lua = lua .. "\t\tself.last_" .. k .. " = self."..k..":Copy() \n"
					end
				end
				
				lua = lua .. "\tend\n\n"
				
				lua = lua .. "\tgl.UnmapBuffer(gl.e.GL_UNIFORM_BUFFER)\n"
				lua = lua .. "end\n"
				
				lua = lua .. "gl.BindBufferBase(gl.e.GL_UNIFORM_BUFFER, "..data.id..", "..data.buffer_id..")\n\n"
			else
				local line = tostring(unrolled_lines[data.val.type] or data.val.type)

				if data.val.type == "texture" or data.val.type == "sampler2D" then
					line = line:format(texture_channel, data.id)
					texture_channel = texture_channel + 1
				else
					line = line:format(data.id)
				end

				lua = lua .. "local val = self."..data.key.." or self.defaults."..data.key.."\n"
				lua = lua .. "if val then\n"
				lua = lua .. "\tif type(val) == 'function' then val = val() end\n"
				lua = lua .. "\t" .. line .. "\n"
				lua = lua .. "end\n\n"
			end
		end

		if BUILD_OUTPUT then
			vfs.Write("data/shader_builder_output/" .. shader_id .. "/unrolled_lines.lua", lua)
			serializer.WriteFile("luadata", "shader_builder_output/" .. shader_id .. "/uniforms.lua", uniforms)
		end

		local func, err = loadstring(lua, shader_id)

		if not func then
			error(err, 2)
		end

		setfenv(func, {gl = gl, self = self, loc = prog, type = type, render = render, logn = logn, ffi = ffi})

		self.unrolled_bind_func = func
	end
	
	self.original_data = original_data
	self.data = data
	self.base_shader = base

	self.vtx_atrb_type = build_output.vertex.vtx_atrb_type
	self.program_id = prog
	self.shader_id = shader_id
	self.build_output = build_output
	
	render.active_shaders[shader_id] = self

	return self
end

function META:Bind()
	render.UseProgram(self.program_id)
	self.unrolled_bind_func()
end

do -- create data for vertex buffer
	-- this will unpack all structs  so ffi.new can accept the table
	local function unpack_structs(output)
		local found = {}
		
		-- only bother doing this if the first line has structs
		for key, val in pairs(output[1]) do
			if hasindex(val) and val.Unpack then
				found[key] = true
			end
		end

		if next(found) then
			for index, struct in pairs(output) do
				for key, val in pairs(struct) do
					if found[key] then
						struct[key] = {val:Unpack()}
					end
				end
			end
		end
	end
	
	local USE_MALLOC = false

	function META:CreateBuffersFromTable(vertices, indices, is_valid_table)
	
		if type(vertices) == "number" then
			local size = vertices
			
			local indices = ffi.malloc("unsigned int", size)
			for i = 0, size - 1 do indices[i] = i end

			if USE_MALLOC then
				local a, b = ffi.malloc(self.vtx_atrb_type, size), indices
				
				local a_size = #vertices * ffi.sizeof(self.vtx_atrb_type) 
				local b_size = #indices * ffi.sizeof("unsigned int")
				
				ffi.fill(a, a_size)
				ffi.fill(b, b_size)
							
				return a, b, #vertices * a_size, #indices * b_size
			end
			
			return 
				ffi.new(self.vtx_atrb_type.."[?]", size), 
				indices, 
				size * ffi.sizeof(self.vtx_atrb_type), 
				size * ffi.sizeof("unsigned int")
		end
		
		if not is_valid_table then
			unpack_structs(vertices)	
			
			if not indices then
				indices = {}
				for i in ipairs(vertices) do
					indices[i] = i-1
				end
			end
		end
		
		if USE_MALLOC then			
			local a, b = ffi.malloc(self.vtx_atrb_type, #vertices), ffi.malloc("unsigned int", #indices)
			
			local a_size = #vertices * ffi.sizeof(self.vtx_atrb_type) 
			local b_size = #indices * ffi.sizeof("unsigned int")
			
			ffi.fill(a, a_size)
			ffi.fill(b, b_size)
			
			for i = 1, #vertices do
				for _, val in ipairs(self.build_output.vertex.vtx_info) do	
					if vertices[i][val.name] then
						if type(vertices[i][val.name]) == "table" then
							for j = 1, #vertices[i][val.name] do
								a[i - 1][val.name][string.char(64 + j)] = vertices[i][val.name][j]
							end
						else
							table.print(vertices[i])
						end
					end
				end
			end
			
			for i = 1, #indices do b[i - 1] = indices[i] end
			
			return a, b, a_size, b_size
		end
		
		return 
			ffi.new(self.vtx_atrb_type.."["..#vertices.."]", vertices), 
			ffi.new("unsigned int[" .. #indices .. "]", indices), 
			#vertices * ffi.sizeof(self.vtx_atrb_type), 
			#indices * ffi.sizeof("unsigned int")
	end

	function META:GetVertexAttributes()
		return self.vertex_attributes
	end

	function META:CreateVertexBuffer(vertices, indices, is_valid_table)
		return render.CreateVertexBuffer(self, vertices, indices, is_valid_table)
	end
	
	prototype.Register(META)
end

function render.RebuildShaders()
	for k,v in pairs(render.active_shaders) do
		local shader = render.CreateShader(v.original_data)
		for k,_ in pairs(v) do
			if type(shader[k]) == "function" then
				v[k] = shader[k]
			end
		end
	end
end

if RELOAD then
	render.RebuildShaders()
end  