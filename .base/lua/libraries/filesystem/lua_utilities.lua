local vfs = (...) or _G.vfs

vfs.included_files = vfs.included_files or {}

local function store(path)
	local path = vfs.FixPath(path)
	vfs.included_files[path] = fs.getattributes(path)
end

function loadfile(path, ...)		
	store(path)
	return _OLD_G.loadfile(path, ...)
end

function dofile(path, ...)
	store(path)		
	return _OLD_G.dofile(path, ...)
end
	
function vfs.GetLoadedLuaFiles()
	return vfs.included_files
end

function vfs.loadfile(path)
	check(path, "string")
	
	local full_path = vfs.GetAbsolutePath(path)
	
	if full_path then
		store(full_path)
		
		local res, err = vfs.Read(full_path)
		if not res then 
			return res, err, full_path 
		end
		
		local res, err = loadstring(res, "@" .. path) -- put @ in front of the path so it will be treated as such intenrally
		return res, err, full_path
	end
	
	return false, "No such file or directory"
end

function vfs.dofile(path, ...)
	check(path, "string")
	
	local func, err = vfs.loadfile(path)
	
	if func then
		local ok, err = xpcall(func, system.OnError, ...)
		return ok, err, path
	end
	
	return func, err
end

do -- include
	local base = fs.getcd()

	local include_stack = {}
	
	function vfs.PushToIncludeStack(path)
		include_stack[#include_stack + 1] = path
	end
	
	function vfs.PopFromIncludeStack()
		include_stack[#include_stack] = nil
	end
	
	local function not_found(err)
		return 
			err and 
			(
				err:find("No such file or directory", nil, true) or 
				err:find("Invalid argument", nil, true)
			)
	end
	
	function vfs.include(source, ...)
			
		local dir, file = source:match("(.+/)(.+)")
		
		if not dir then
			dir = ""
			file = source
		end
		
		if vfs and file == "*" then
			local previous_dir = include_stack[#include_stack]		
			local original_dir = dir
			
			if previous_dir then
				dir = previous_dir .. dir
			end
						
			if not vfs.IsDir(dir) then
				dir = "lua/" .. dir
			end

			if not vfs.IsDir(dir) then
				dir = "lua/" .. original_dir
			end
			
			for script in vfs.Iterate(dir, nil, true) do
				if script:find("%.lua") then
					local func, err = vfs.loadfile(script)
					
					if func then
						local ok, err = xpcall(func, system and system.OnError or logn, ...)

						if not ok then
							logn(err)
						end
					end
					
					if not func then
						logn(err)
					end
				end
			end
			
			return
		end
						
		-- try direct first
		local loaded_path = source
			
		local previous_dir = include_stack[#include_stack]		
					
		if previous_dir then
			dir = previous_dir .. dir
		end
		
		-- try first with the last directory
		-- once with lua prepended
		local path = "lua/" .. dir .. file
		func, err = vfs.loadfile(path)
					
		if not_found(err) then
			path = dir .. file
			func, err = vfs.loadfile(path)
			
			-- and without the last directory
			-- once with lua prepended
			if not_found(err) then
				path = "lua/" .. source
				func, err = vfs.loadfile(path)	
				
				-- try the absolute path given
				if not_found(err) then
					path = source
					func, err = vfs.loadfile(loaded_path)
				else
					path = source
				end
			end
		else
			path = dir .. file
		end
		
		if func then
			dir = path:match("(.+/)(.+)")
			include_stack[#include_stack + 1] = dir
					
			local res = {xpcall(func, system and system.OnError or logn, ...)}
			
			if not res[1] then
				logn(res[2])
			end
			
			--[[if res and CAPSADMIN then
				local lua, err = vfs.Read(path)
				if not include_buffer then 
					include_buffer = {}
					local lua = vfs.Read(e.ROOT_FOLDER .. "lua/init.lua")
					table.insert(include_buffer, "do")
					table.insert(include_buffer, lua)
					table.insert(include_buffer, "end")
				end
				table.insert(include_buffer, "do")
				table.insert(include_buffer, lua)
				table.insert(include_buffer, "end")
				vfs.Write("data/include.lua", table.concat(include_buffer, "\n"))
			end]]
			
			include_stack[#include_stack] = nil
						 
			return select(2, unpack(res))
		end		
		
		err = err or "no error"
		
		logn(source:sub(1) .. " " .. err)
		
		debug.openscript("lua/" .. path, err:match(":(%d+)"))
						
		return false, err
	end
end

-- although vfs will add a loader for each mount, the module folder has to be an exception for modules only
-- this loader should support more ways of loading than just adding ".lua"
function vfs.AddModuleDirectory(dir)
	do -- full path
		table.insert(package.loaders, function(path)
			return vfs.loadfile(path)
		end)
		
		table.insert(package.loaders, function(path)
			return vfs.loadfile(path .. ".lua")
		end)
		
		table.insert(package.loaders, function(path)
			path = path:gsub("(.)%.(.)", "%1/%2")
			return vfs.loadfile(path .. ".lua")
		end)
		
		table.insert(package.loaders, function(path)
			path = path:gsub("(.+/)(.+)", function(a, str) return a .. str:gsub("(.)%.(.)", "%1/%2") end)
			return vfs.loadfile(path .. ".lua")
		end)
	end
		
	do -- relative path
		table.insert(package.loaders, function(path)
			return vfs.loadfile(dir .. path)
		end)
		
		table.insert(package.loaders, function(path)
			return vfs.loadfile(dir .. path .. ".lua")
		end)
					
		table.insert(package.loaders, function(path)
			path = path:gsub("(.)%.(.)", "%1/%2")
			return vfs.loadfile(dir .. path .. ".lua")
		end)
	end
		
	table.insert(package.loaders, function(path)
		return vfs.loadfile(dir .. path .. "/init.lua")
	end)
	
	table.insert(package.loaders, function(path)
		return vfs.loadfile(dir .. path .. "/"..path..".lua")
	end)
	
	-- again but with . replaced with /	
	table.insert(package.loaders, function(path)
		path = path:gsub("\\", "/"):gsub("(%a)%.(%a)", "%1/%2")
		return vfs.loadfile(dir .. path .. ".lua")
	end)
		
	table.insert(package.loaders, function(path)
		path = path:gsub("\\", "/"):gsub("(%a)%.(%a)", "%1/%2")
		return vfs.loadfile(dir .. path .. "/init.lua")
	end)
	
	table.insert(package.loaders, function(path)
		path = path:gsub("\\", "/"):gsub("(%a)%.(%a)", "%1/%2")
		return vfs.loadfile(dir .. path .. "/" .. path ..  ".lua")
	end)
	
	table.insert(package.loaders, function(path)
		local c_name = "luaopen_" .. path:gsub("^.*%-", "", 1):gsub("%.", "_")
		path = R(dir .. "bin/" .. jit.os:lower() .. "/" .. jit.arch:lower() .. "/" .. path .. (jit.os == "Windows" and ".dll" or ".so")) or path
		return package.loadlib(path, c_name)
	end)
end	