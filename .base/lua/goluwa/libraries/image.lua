
render.active_textures = render.active_textures or {}

local loading_data = vfs.Read("textures/loading.jpg", "rb")

function Image(path, format)
	if render.active_textures[path] then 
		return render.active_textures[path]
	end
	
	local size = 16
	if not ERROR_TEXTURE then
		ERROR_TEXTURE = Texture(128, 128)
		ERROR_TEXTURE:Fill(function(x, y)
			if (math.floor(x/size) + math.floor(y/size % 2)) % 2 < 1 then
				return 255, 0, 255, 255
			else
				return 0, 0, 0, 255
			end
		end)
	end
		
	format = format or {}
	format.internal_format = format.internal_format or e.GL_RGBA8
	
	local w, h, buffer = freeimage.LoadImage(loading_data)
	local tex = Texture(w, h, buffer, format)

	vfs.ReadAsync(path, function(data)

		local w, h, buffer = freeimage.LoadImage(data)
		
		if w == 0 or h == 0 then
			errorf("could not decode %q properly (w = %i, h = %i)", 2, path, w, h)
		end
		
		tex:Replace(buffer, w, h) 
		
		render.active_textures[path] = tex
	end)
	
	return tex
end