window.Open(1000, 1000)

local frame = utilities.RemoveOldObject(aahh.Create("frame"), "lol")
	frame:SetSize(Vec2()+1000)
	frame:Center()
	frame:SetTitle("")

	local edit = aahh.Create("text_input", frame)
		edit:SetFont("default")
		edit:Dock("fill")
		edit:SetWrap(false)
		edit:SetLineNumbers(true)
		edit:SetMultiLine(true)
		edit:SetText(vfs.Read("lua/textbox.lua"))
		edit:MakeActivePanel()
	frame:RequestLayout(true)
	
	LOL = edit
 