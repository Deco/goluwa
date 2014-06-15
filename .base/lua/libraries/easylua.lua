local easylua = _G.easylua or {}
local s = easylua

local function compare(a, b)

	if not a or not b then return false end
	if a == b then return true end
	if a:find(b, nil, true) then return true end
	if a:lower() == b:lower() then return true end
	if a:lower():find(b:lower(), nil, true) then return true end

	return false
end

if CLIENT then
	function easylua.PrintOnServer(...)
		message.Send("prints", ...)
	end
end

if SERVER then
	message.AddListener("prints", function(client, ...)
		print(client:GetNick(), ...)
	end)
end

function easylua.Print(...)
	if CLIENT then
		easylua.PrintOnServer(...)
	end
	if SERVER then
		local args = {...}
		local str = ""

		logf("[EasyLua %s] \n", me and me:GetNick() or "Sv")

		for key, value in pairs(args) do
			str = str .. type(value) == "string" and value or serializer.GetLibrary("luadata").ToString(value) or tostring(value)

			if key ~= #args then
				str = str .. ","
			end
		end

		logn(str)
	end
end

function easylua.FindEntity(str)
	if not str then return end

	str = tostring(str)

	if str == "#this" and typex(this) == "entity" then
		return this
	end

	if str == "#me" and typex(me) == "client" then
		return me
	end

	if str == "#all" then
		return all
	end

	if str:sub(1,1) == "_" and tonumber(str:sub(2)) then
		str = str:sub(2)
	end

	for key, client in pairs(clients.GetAll()) do
		if not client:IsBot() and compare(client:GetNick(), str) then
			return client
		end
	end
	
	for key, client in pairs(clients.GetAll()) do
		if client:IsBot() and compare(client:GetNick(), str) then
			return client
		end
	end
end

function easylua.CopyToClipboard(var)
	me:SendLua([[system.SetClipboard("]]..tostring(var)..[[")]])
end

function easylua.Start(client)
	client = client or CLIENT and clients.GetLocalClient() or NULL

	if not client:IsValid() then return end

	local vars = {}
		--vars.all = utilities.CreateAllFunction(function(v) return typex(v) == "client" end)
		vars.me = client

		vars.copy = s.CopyToClipboard
		vars.prints = s.PrintOnServer

		vars.E = s.FindEntity
		vars.last = client.easylua_lastvars

		s.vars = vars
	for k,v in pairs(vars) do _G[k] = v end

	client.easylua_lastvars = vars
	client.easylua_iterator = (client.easylua_iterator or 0) + 1
end

function easylua.End()
	if s.vars then
		for key, value in pairs(s.vars) do
			_G[key] = nil
		end
		me = clients.GetLocalClient()
	end
end

do -- env meta
	local META = {}

	local _G = _G
	local easylua = easylua
	local tonumber = tonumber

	function META:__index(key)
		local var = _G[key]

		if var then
			return var
		end

		if key ~= "CLIENT" or key ~= "SERVER" then -- uh oh
			var = easylua.FindEntity(key) or NULL
			if var:IsValid() then
				return var
			end
		end

		return nil
	end

	function META:__newindex(key, value)
		_G[key] = value
	end

	easylua.EnvMeta = setmetatable({}, META)
end

function easylua.RunLua(client, code, env_name, print_error)
	local data =
	{
		error = false,
		args = {},
	}

	easylua.Start(client)
		if s.vars then
			local header = ""

			for key, value in pairs(s.vars) do
				header = header .. string.format("local %s = %s ", key, key)
			end

			code = header .. "; " .. code
		end

		data.env_name = env_name or client:IsValid() and client:GetNick() or "huh"

		local func, err = loadstring(code, env_name)

		if type(func) == "function" then
			setfenv(func, easylua.EnvMeta)

			local args = {xpcall(func, system.OnError)}

			if args[1] == false then
				data.error = args[2]
			end

			table.remove(args, 1)
			data.args = args
		else
			data.error = err
		end
	easylua.End()

	if print_error and data.error then
		logn(data.error)
	end

	return data
end

return easylua