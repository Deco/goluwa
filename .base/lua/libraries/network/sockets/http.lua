local sockets = (...) or _G.sockets

function sockets.EscapeURL(str)
	return str:gsub("([^A-Za-z0-9_])", function(char)
		return ("%%%02x"):format(string.byte(char))
	end)
end

function sockets.HeaderToTable(header)
	local tbl = {}
	
	if not header then return tbl end

	for line in header:gmatch("(.-)\n") do
		local key, value = line:match("(.+):%s+(.+)\r")

		if key and value then
			tbl[key:lower()] = tonumber(value) or value
		end
	end

	return tbl
end

function sockets.TableToHeader(tbl)
	local str = ""

	for key, value in pairs(tbl) do
		str = str .. tostring(key) .. ": " .. tostring(value) .. "\r\n"
	end

	return str
end

local function request(info)

	if info.url then
		local protocol, host, location = info.url:match("(.+)://(.-)/(.+)")
		
		if not protocol then
			host, location = info.url:match("(.-)/(.+)")
			protocol = "http"
		end
		
		info.location = info.location or location
		info.host = info.host or host
		info.protocol = info.protocol or protocol
	end
	
	if info.protocol == "https" and not info.ssl_parameters then
		info.ssl_parameters = "https"
	end
	
	if info.ssl_parameters and not info.protocol then
		info.protocol = "https"
	end
	
	if not info.port then
		if info.protocol == "https" then
			info.port = 443
		else
			info.port = 80
		end
	end
	
	info.method = info.method or "GET"
	info.user_agent = info.user_agent or "Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/34.0.1847.131 Safari/537.36"
	info.connection = info.connection or "Keep-Alive"
	info.receive_mode = info.receive_mode or 61440
	info.timeout = info.timeout or 2
	info.callback = info.callback or table.print
	
	if info.method == "POST" and not info.post_data then
		error("no post data!", 2)
	end
	
	if sockets.debug then
		logn("sockets request:")
		table.print(info)
	end
	
	local socket = sockets.CreateClient("tcp")
	socket.debug = info.debug
	socket:SetTimeout(info.timeout)
	
	if info.ssl_parameters then 
		socket:SetSSLParams(info.ssl_parameters) 
	end
	
	socket:Connect(info.host, info.port)
	socket:SetReceiveMode(info.receive_mode)

	socket:Send(("%s /%s HTTP/1.1\r\n"):format(info.method, info.location))
	socket:Send(("Host: %s\r\n"):format(info.host))
	
	if not info.header or not info.header.user_agent then socket:Send(("User-Agent: %s\r\n"):format(info.user_agent)) end
	if not info.header or not info.header.user_agent then socket:Send(("Connection: %s\r\n"):format(info.connection)) end
	
	if info.header then
		for k,v in pairs(info.header) do
			socket:Send(("%s: %s\r\n"):format(k, v))
		end
	end

	if info.method == "POST" then
		socket:Send(("Content-Length: %i"):format(#info.post_data))
		socket:Send(info.post_data)
	end

	socket:Send("\r\n")
	
	local header = {}
	local content = {}
	local temp = {}
	local length = 0
	local in_header = true
	
	function socket:OnReceive(str)
		if in_header then
			table.insert(temp, str)
			
			local str = table.concat(temp, "")
			local header_data, content_data = str:match("(.-\r\n\r\n)(.+)")
			if header_data then
				header = sockets.HeaderToTable(header_data)
				
				if header.location then					
					if header.location ~= "" then
						info.url = header.location
						request(info)
						self:Remove()
						return
					end
				end
				
				if content_data then
					table.insert(content, content_data)
					length = length + #content_data
				end

				in_header = false
			end
		else
			table.insert(content, str)
			length = length + #str
		end
		
		if header["content-length"] then
			if length >= header["content-length"] then
				self:Remove()
			end
		elseif header["transfer-encoding"] == "chunked" then
			if str:sub(-5) == "0\r\n\r\n" then 
				self:Remove()
			end
		end
	end
	
	function socket:OnClose()			
		local content = table.concat(content, "")

		if content ~= "" then
			local ok, err = xpcall(info.callback, system.OnError, {content = content, header = header})
			
			if err then
				warning(err)
			end
		else
			--warning("no content was found")
		end
	end
end

function sockets.Download(url, callback)
	if not url:find("^(.-)://") then return end
	
	if callback then
		sockets.Request({
			url = url, 
			receive_mode = "all",
			callback = function(data) 
				callback(data.content) 
			end, 
		})
		return true
	end
	
	return 
	{
		Download = function(_, callback) 
			sockets.Download(url, function(data) 
				callback(data.content, data.header) 
			end) 
		end
	}
end

function sockets.Get(url, callback, timeout, user_agent, binary, debug)
	check(url, "string")
	check(callback, "function", "nil", "false")
	check(user_agent, "nil", "string")
	
	return request({
		url = url, 
		callback = callback, 
		method = "GET", 
		timeout = timeout, 
		user_agent = user_agent, 
		receive_mode = binary and "all", 
		debug = debug
	})
end

function sockets.Post(url, post_data, callback, timeout, user_agent, binary, debug)
	check(url, "string")
	check(callback, "function", "nil", "false")
	check(post_data, "table", "string")
	check(user_agent, "nil", "string")
	
	if type(post_data) == "table" then
		post_data = sockets.TableToHeader(post_data)
	end
	
	return request({
		url = url, 
		callback = callback, 
		method = "POST", 
		timeout = timeout, 
		post_data = post_data, 
		user_agent = user_agent, 
		receive_mode = binary and "all", 
		debug = debug
	})
end

sockets.Request = request