window.Open()

local gif1 = Gif("https://dl.dropboxusercontent.com/u/244444/angrykid.gif")
local gif2 = Gif("https://dl.dropboxusercontent.com/u/244444/pug.gif")
local gif3 = Gif("https://dl.dropboxusercontent.com/u/244444/envy.gif")
local gif4 = Gif("https://dl.dropboxusercontent.com/u/244444/greenkid.gif")
local gif5 = Gif("https://dl.dropboxusercontent.com/u/244444/zzzzz.gif")

event.AddListener("OnDraw2D", "gif", function()
	surface.Color(1, 1, 1, 1)
	gif1:Draw(0, 0)	
	gif2:Draw(291, 0)
	gif3:Draw(291, 215)
	gif4:Draw(-70, 240)
	gif5:Draw(40, 450)
end)       