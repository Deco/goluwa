local META = utilities.FindMetaTable("player")

function META:GetChatAboveHead()
	return self.coh_str or ""
end

if CLIENT then
	function META:SetChatAboveHead(str, send)
		self.coh_str = str
		
		if send and players.GetLocalPlayer() == self then
			message.Send("coh", str)
		end
		
		event.Call("OnChatAboveHead", self, str)
	end

	event.AddListener("OnChatTextChanged", "coh", function(str)
		message.Send("coh", str)
		players.GetLocalPlayer():SetChatAboveHead(str)
	end)
	
	message.AddListener("coh", function(ply, str) 
		ply:SetChatAboveHead(str)
	end)
end

if SERVER then
	function META:SetChatAboveHead(str)
		self.coh_str = str
		message.Send("coh", nil, self, str)
	end
	
	message.AddListener("coh", function(ply, str)
		local filter = message.PlayerFilter()
		filter:AddAllExcept(ply)
		message.Send("coh", filter, ply, str)
	end)
end 