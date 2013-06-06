-- enums
_E = {}
e = _E

_E.PLATFORM = PLATFORM or tostring(select(1, ...) or nil)

do -- helper constants	
	_G._F = {}
	
	local _F = _F
	local _G = _G
	local META = {}
	
	local val
	function META:__index(key)
		val = _F[key]
		
		if type(val) == "function" then
			return val()
		end
	end
	
	setmetatable(_G, META)
		
	do -- example
		_F["T"] = os.clock
		
		-- print(T + 1) = print(os.clock() + 1)
	end
end

-- put all c functions in a table
if not _OLD_G then
	_R = debug.getregistry()
	
	_OLD_G = {}
	local done = {[_G] = true}
	
	local function scan(tbl, store)
		for key, val in pairs(tbl) do
			local t = type(val)
			
			if t == "table" and not done[val] and val ~= store then
				store[key] = store[key] or {}
				done[val] = true
				scan(val, store[key])
			elseif t == "function" then
				store[key] = val
			end
		end
	end
	
	scan(_G, _OLD_G)
end

do -- logging
	local function call(str)
		return event and event.Call("ConsolePrint", str) ~= false
	end
	
	local function get_verbosity_level()
		return console and console.GetVariable("log_verbosity", 0) or 0
	end
	
	local function get_debug_filter()
		return console and console.GetVariable("log_debug_filter", "") or ""
	end	
	
	function log(...)		
		return io.write(...)
	end
	
	function logc(...)	
		
	end
		
	function warning(verbosity, ...)
		local level = get_verbosity_level()
		
		-- if the level is below 0 always log
		if level < 0 then
			return log(...)
		end
		
		-- if verbosity is a string only show warnings log_debug_filter is set to
		if type(verbosity) == "string" and verbosity == get_debug_filter() then
			return log(...)
		end	
		
		-- otherwise check the verbosity level against the input	
		if level <= verbosity then
			return log(...)
		end
	end
end

Msg = Msg or print
MsgN = MsgN or print

local time = os.clock()
local gtime = time

MsgN("loading mmyy")

_E.USERNAME = tostring(os.getenv("USERNAME")):upper():gsub(" ", "_"):gsub("%p", "")
_G[e.USERNAME] = true

MsgN("username constant = " .. e.USERNAME)

do -- ffi
	ffi = require("ffi")
	_G[ffi.os:upper()] = true
	_G[ffi.arch:upper()] = true

	 -- ffi's cdef is so anti realtime
	ffi.already_defined = {}
	old_ffi_cdef = old_ffi_cdef or ffi.cdef
	
	ffi.cdef = function(str, ...)
		local val = ffi.already_defined[str]
		
		if val then
			return val
		end
	
		ffi.already_defined[str] = str
		return old_ffi_cdef(str, ...)
	end
end

do -- file system
	lfs = require("lfs")

	-- the base folder is always 3 paths up (bin/os/arch)
	_E.BASE_FOLDER = "../../../" 
	_E.ABSOLUTE_BASE_FOLDER = lfs.currentdir():gsub("\\", "/"):match("(.+/).-/.-/")

	-- this is ugly but it's because we haven't included the global extensions yet..
	_G.check = function() end
	vfs = dofile(_E.BASE_FOLDER .. "/lua/platforms/standard/libraries/vfs.lua")

	-- mount the base folders
	
	-- current dir
	vfs.Mount(lfs.currentdir())
	
	-- and 3 folders up
	vfs.Mount(e.BASE_FOLDER)
	
	-- a nice global for loading resources externally from current dir
	R = vfs.GetAbsolutePath

	-- although vfs will add a loader for each mount, the module folder has to be an exception for modules only
	-- this loader should support more ways of loading than just adding ".lua"
	table.insert(package.loaders, function(path)
		local func = vfs.loadfile("lua/modules/" .. path)
		
		if not func then
			func = vfs.loadfile("lua/modules/" .. path .. ".lua")
		end
		
		return func
	end)
end

do -- include
	local base = lfs.currentdir()

	local include_stack = {}
	
	function include(path, ...)
		local dir, file = path:match("(.+/)(.+)")
		
		if not dir then
			dir = ""
			file = path
		end
				
		vfs.Silence(true)
		
		
		local previous_dir = include_stack[#include_stack]		
		
		if previous_dir then
			dir = previous_dir .. dir
		end
		
		--print("")
		--print(("\t"):rep(#include_stack).."TRYING REL: ", dir .. file)
		
		local func, err = vfs.loadfile("lua/" .. dir .. file)
			
		if err and err:find("not found") then
			func, err = vfs.loadfile("lua/" .. path)
			--print(("\t"):rep(#include_stack).."TRYING ABS: ", dir .. file)
		end
		

		if func then 
			include_stack[#include_stack + 1] = dir
		
			--print(("\t"):rep(#include_stack + 1).."FILE FOUND: ", file)
			--print(("\t"):rep(#include_stack + 1).."DIR IS NOW: ", dir)
			--print("")
			local res = {pcall(func, ...)}
			
			if not res[1] then
				print(res[2])
			end
			
			include_stack[#include_stack] = nil
						 
			return select(2, unpack(res))
		end
		
		print(path:sub(1) .. " " .. err)
		
		vfs.Silence(false)
		
		return false, err
	end
end

local standard = "platforms/standard/"
local extensions = standard .. "extensions/"
local libraries = standard .. "libraries/"
local meta = standard .. "meta/"

-- library extensions
include(extensions .. "globals.lua")
include(extensions .. "debug.lua")
include(extensions .. "math.lua")
include(extensions .. "string.lua")
include(extensions .. "table.lua")
include(extensions .. "os.lua")

-- libraries
event = include(libraries .. "event.lua")
utilities = include(libraries .. "utilities.lua")
addons = include(libraries .. "addons.lua")
class = include(libraries .. "class.lua")
luadata = include(libraries .. "luadata.lua")
timer = include(libraries .. "timer.lua")
sigh = include(libraries .. "sigh.lua")
base64 = include(libraries .. "base64.lua")
input = include(libraries .. "input.lua")
msgpack = include(libraries .. "msgpack.lua")
json = include(libraries .. "json.lua")
console = include(libraries .. "console.lua")
mmyy = include(libraries .. "mmyy.lua")

-- meta
include(meta .. "function.lua")
include(meta .. "null.lua")

-- luasocket
luasocket = include(libraries .. "luasocket.lua") 
timer.Create("socket_think", 0,0, luasocket.Update)
event.AddListener("LuaClose", "luasocket", luasocket.Panic)

intermsg = include(libraries .. "intermsg.lua") 

-- this should be used for xpcall
function OnError(msg)
	if event.Call("OnLuaError", msg) == false then return end
	
	print("== LUA ERROR ==")
	
	for k, v in pairs(debug.traceback():explode("\n")) do
		local source, msg = v:match("(.+): in function (.+)")
		if source and msg then
			print((k-1) .. "    " .. source:trim() or "nil")
			print("     " .. msg:trim() or "nil")
			print("")
		end
	end	

	print("")
	local source, _msg = msg:match("(.+): (.+)")
	if source then
		print(source:trim())
		print(_msg:trim())
	else
		print(msg)
	end
	print("")
end

MsgN("mmyy loaded (took " .. (os.clock() - time) .. " ms)")

local time = os.clock()
MsgN("loading addons")
	addons.LoadAll()
MsgN("sucessfully loaded addons (took " .. (os.clock() - time) .. " ms)")

local time = os.clock()
MsgN("loading platform " .. e.PLATFORM)
include("platforms/".. e.PLATFORM .."/init.lua")
MsgN("sucessfully loaded platform " .. e.PLATFORM .. " (took " .. (os.clock() - time) .. " ms)")

addons.AutorunAll(e.USERNAME)

MsgN("sucessfully initialized (took " .. (os.clock() - gtime) .. " ms)")


if CREATED_ENV then
	mmyy.SetWindowTitle(TITLE)
	
	utilities.SafeRemove(ENV_SOCKET)
	
	ENV_SOCKET = luasocket.Client()

	ENV_SOCKET:Connect("localhost", PORT)	
	ENV_SOCKET:SetTimeout()
	
	ENV_SOCKET.OnReceive = function(self, line)		
		local func, msg = loadstring(line)

		if func then
			local ok, msg = pcall(func) 
			if not ok then
				print("runtime error:", client, msg)
			end
		else
			print("compile error:", client, msg)
		end
		
		timer.Simple(0, function() event.Call("OnConsoleEnvReceive", line) end)
	end
end

event.Call("Initialized")