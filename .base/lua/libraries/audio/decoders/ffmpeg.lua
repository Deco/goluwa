local ffmpeg = require("lj-ffmpeg")

audio.AddDecoder("ffmpeg", function(data, path_hint)
	local ext = path_hint:match(".+%.(.+)")
	
	if ext == "wav" and data:sub(1, 4) ~= "RIFF" then
		ext = "mp3" -- VALVE
	end
	
	local decoder, err = ffmpeg.Open(data, {audio_only = true, file_ext = ext})
	if not decoder then return nil, err end
	local data, err = decoder:ReadAll()
	if not data then return nil, err end
	return data.buffer, data.length, decoder:GetInfo().audio
end)