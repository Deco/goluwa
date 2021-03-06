do -- logging	
	local pretty_prints = {}
	
	pretty_prints.table = function(t)
		local str = tostring(t) or "nil"
				
		str = str .. " [" .. table.count(t) .. " subtables]"
		
		-- guessing the location of a library
		local sources = {}
		
		for k,v in pairs(t) do	
			if type(v) == "function" then
				local src = debug.getinfo(v).source
				sources[src] = (sources[src] or 0) + 1
			end
		end
		
		local tmp = {}
		
		for k,v in pairs(sources) do
			table.insert(tmp, {k=k,v=v})
		end
		
		table.sort(tmp, function(a,b) return a.v > b.v end)
		
		if #tmp > 0 then 
			str = str .. "[" .. tmp[1].k:gsub("!/%.%./", "") .. "]"
		end		
		
		return str
	end
	
	local function tostringx(val)
		local t = (typex or type)(val)
		
		return pretty_prints[t] and pretty_prints[t](val) or tostring(val)
	end

	local function tostring_args(...)
		local copy = {}
		
		for i = 1, select("#", ...) do
			table.insert(copy, tostringx(select(i, ...)))
		end
		
		return copy
	end

	local function formatx(str, ...)		
		local copy = {}
		local i = 1
		
		for arg in str:gmatch("%%(.)") do
			arg = arg:lower()
			
			if arg == "s" then
				table.insert(copy, tostringx(select(i, ...)))
			else
				table.insert(copy, (select(i, ...)))
			end
				
			i = i + 1
		end
		
		return string.format(str, unpack(copy))
	end
	
	local base_log_dir = e.USERDATA_FOLDER .. "logs/"
	
	local log_files = {}
	local log_file
	
	function setlogfile(name)
		name = name or "console"
		
		if not log_files[name] then
			local file = assert(io.open(base_log_dir .. name .. "_" .. jit.os:lower() .. ".txt", "w"))
		
			log_files[name] = file			
		end
		
		log_file = log_files[name]
	end
	
	function getlogfile(name)
		name = name or "console" 
		
		return log_files[name]
	end
	
	local last_line
	local count = 0
	local last_count_length = 0
		
	fs.createdir(base_log_dir)
		
	local function raw_log(args, sep, append)	
		local line = table.concat(args, sep)
	
		if append then
			line = line .. append
		end
	
		if vfs then						
			if not log_file then
				setlogfile()
			end
							
			if line == last_line then
				if count > 0 then
					local count_str = ("[%i x] "):format(count)
					log_file:seek("cur", -#line-1-last_count_length)
					log_file:write(count_str, line)
					last_count_length = #count_str
				end
				count = count + 1
			else
				log_file:write(line)
				count = 0
				last_count_length = 0
			end
			
			log_file:flush()
			
			last_line = line
		end
		
		if log_files.console == log_file then
			
			if console and console.Print then
				console.Print(line)
			else
				io.write(line)
			end
			
			if _G.LOG_BUFFER then
				table.insert(_G.LOG_BUFFER, line)
			end
		end
	end
		
	function log(...)
		raw_log(tostring_args(...), "")
	end
	
	function logn(...)
		raw_log(tostring_args(...), "", "\n")
		return ...
	end
	
	function print(...)
		raw_log(tostring_args(...), ",\t", "\n")
		return ...
	end

	function logf(str, ...)
		log(formatx(str, ...))
		return ...
	end

	function errorf(str, level, ...)
		error(formatx(str, ...), level)
	end
end

do
	local luadata

	function fromstring(str)
		local num = tonumber(str)
		if num then return num end
		luadata = luadata or serializer.GetLibrary("luadata")
		return unpack(luadata.Decode(str, true)) or str
	end
end

do -- verbose print
	function vprint(...)		
		logf("%s:\n", debug.getinfo(2, "n").name or "unknown")
		
		for i = 1, select("#", ...) do
			local name = debug.getlocal(2, i)
			local arg = select(i, ...)
			logf("\t%s:\n\t\ttype: %s\n\t\tprty: %s\n", name or "arg" .. i, type(arg), tostring(arg), serializer.Encode("luadata", arg))
			if type(arg) == "string" then
				logn("\t\tsize: ", #arg)
			end
			if typex(arg) ~= type(arg) then
				logn("\t\ttypx: ", typex(arg))
			end
		end
	end
end

do
	local level = 2

	function warning(format, ...)
		format = tostringx(format)
		
		local str = format:safeformat(...)
		local source = debug.getprettysource(level, true)

		logn(source, ": ", str)

		return format, ...
	end	

	function requirew(str, ...)
		local args = {pcall(require, str, ...)}

		if not args[1] then
			level = 3
			warning("unable to require %s: %s", str, args[2])
			level = 2
			
			return unpack(args)
		end
		
		return select(2, unpack(args))
	end
end
	
do -- nospam
	local last = {}

	function logf_nospam(str, ...)
		local str = string.format(str, ...)
		local t = os.clock()
		
		if not last[str] or last[str] < t then
			logn(str)
			last[str] = t + 3
		end
	end
	
	function logn_nospam(...)
		logf_nospam(("%s "):rep(select("#", ...)), ...)
	end
end

do -- wait
	local temp = {}
	
	function wait(seconds, frames)
		local time = system.GetElapsedTime()
		if not temp[seconds] or (temp[seconds] + seconds) < time then
			temp[seconds] = system.GetElapsedTime()
			return true
		end
		return false
	end
end

do -- check
	local level = 3

	local function check_custom(var, method, ...)
		local name = debug.getinfo(level, "n").name
		
		local types = {...}
		local allowed = ""
		local typ = method(var)

		local matched = false

		for key, expected in ipairs(types) do
			if typ == expected then
				matched = true
			end
		end

		if not matched then
			local arg = ""

		for i = 1, 32 do
			local key, value = debug.getlocal(level, i)
				-- I'm not sure what to do about this part with vars that have no reference
				if value == var then				
					if #arg > 0 then
						arg = arg .. " or #" .. i
					else
						arg = arg .. "#" ..i
					end
				end
				
				if not key then
					break
				end
			end
		
			local allowed = ""
					
			for key, expected in ipairs(types) do
				if #types ~= key then
					allowed = allowed .. expected .. " or "
				else
					allowed = allowed .. expected
				end
			end
			
			error(("bad argument %s to '%s' (%s expected, got %s)"):format(arg, name, allowed, typ), level + 1)
		end
	end

	function check(var, ...)
		check_custom(var, _G.type, ...)
	end
	
	function checkx(var, ...)
		check_custom(var, _G.typex, ...)
	end
end

local idx = function(var) return var.TypeX or var.Type end

function hasindex(var)
	if getmetatable(var) == getmetatable(NULL) then return false end

	local T = type(var)
	
	if T == "string" then
		return false
	end
	
	if T == "table" then
		return true
	end
	
	if not pcall(idx, var) then return false end
	
	local meta = getmetatable(var)
	
	if meta == "ffi" then return true end
	
	T = type(meta)
		
	return T == "table" and meta.__index ~= nil
end

function typex(var)

	local t = type(var)

	if 
		t == "nil" or
		t == "boolean" or
		t == "number" or
		t == "string" or
		t == "userdata" or
		t == "function" or
		t == "thread"
	then
		return t
	end
	
	if getmetatable(var) == getmetatable(NULL) then return "null" end

	if t == "table" then
		return var.TypeX or var.Type or t
	end
		
	local ok, res = pcall(idx, var)
		
	if ok then
		return res
	end

	return t
end

function istype(var, t)
	if 
		t == "nil" or
		t == "boolean" or
		t == "number" or
		t == "string" or
		t == "userdata" or
		t == "function" or
		t == "thread" or
		t == "table" or
		t == "cdata"
	then
		return type(var) == t
	end
	
	return typex(var) == t
end

local pretty_prints = {}

pretty_prints.table = function(t)
	local str = tostring(t)
			
	str = str .. " [" .. table.count(t) .. " subtables]"
	
	-- guessing the location of a library
	local sources = {}
	for k,v in pairs(t) do	
		if type(v) == "function" then
			local src = debug.getinfo(v).source
			sources[src] = (sources[src] or 0) + 1
		end
	end
	
	local tmp = {}
	for k,v in pairs(sources) do
		table.insert(tmp, {k=k,v=v})
	end
	
	table.sort(tmp, function(a,b) return a.v > b.v end)
	if #tmp > 0 then 
		str = str .. "[" .. tmp[1].k:gsub("!/%.%./", "") .. "]"
	end
	
	
	return str
end

function tostringx(val)
	local t = type(val)
	
	if t == "table" and getmetatable(val) then return tostring(val) end
	
	return pretty_prints[t] and pretty_prints[t](val) or tostring(val)
end

function tostring_args(...)
	local copy = {}
	
	for i = 1, select("#", ...) do
		table.insert(copy, tostringx(select(i, ...)))
	end
	
	return copy
end

function istype(var, ...)
	for _, str in pairs({...}) do
		if typex(var) == str then
			return true
		end
	end

	return false
end

do -- negative pairs
	local v
	local function iter(a, i)
		i = i - 1
		v = a[i]
		if v then
			return i, v
		end
	end

	function npairs(a)
		return iter, a, #a + 1
	end
end