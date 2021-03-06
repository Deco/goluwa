local gui = ... or _G.gui

local PANEL = {}

PANEL.ClassName = "text_button"
PANEL.Base = "button"

prototype.GetSetDelegate(PANEL, "Text", "", "label")
prototype.GetSetDelegate(PANEL, "ParseTags", false, "label")
prototype.GetSetDelegate(PANEL, "Font", nil, "label")
prototype.GetSetDelegate(PANEL, "TextColor", nil, "label")
prototype.GetSetDelegate(PANEL, "TextWrap", false, "label")
prototype.GetSetDelegate(PANEL, "ConcatenateTextToSize", false, "label")

prototype.Delegate(PANEL, "label", "CenterText", "Center")
prototype.Delegate(PANEL, "label", "CenterTextY", "CenterY")
prototype.Delegate(PANEL, "label", "CenterTextX", "CenterX")
prototype.Delegate(PANEL, "label", "GetTextSize", "GetSize")

function PANEL:Initialize()
	prototype.GetRegistered(self.Type, "button").Initialize(self)
	
	local label = self:CreatePanel("text", "label")
	label:SetIgnoreMouse(true)
	self:Layout(true)
end

function PANEL:SizeToText()
	local marg = self:GetMargin()
		
	self.label:SetPosition(marg:GetPosition())
	self:SetSize(self.label:GetSize() + marg:GetSize()*2)
	
	if self.LayoutSize then
		self.LayoutSize = self:GetSize():Copy()
	end
end

gui.RegisterPanel(PANEL)