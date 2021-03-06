local data = {
	total_lines = 0,
	total_words = 0,
	total_chars = 0,
	words = {},
	files = {},
}

local words = {}

for _, path in ipairs(vfs.Search("lua/", ".lua")) do
	if not path:find("modules") or (path:find("lj-", nil, true) and (not path:find("header.lua") and not path:find("enums"))) then
		local str = vfs.Read(path)
		if str then
			local lines = str:count("\n")
			data.total_lines = data.total_lines + lines
			str = str:gsub("%s+", " ")
			data.total_words = data.total_words + str:count(" ")
			data.total_chars = data.total_chars + #str
			
			for i, word in ipairs(str:explode(" ")) do
				words[word] = (words[word] or 0) + 1
			end
			table.insert(data.files, {path = path, lines = lines})
		else
			print(path)
		end
	end
end

data.total_chars = data.total_chars - data.total_words

table.sort(data.files, function(a, b) return a.lines > b.lines end)

for word, count in pairs(words) do
	table.insert(data.words, {word = word, count = count})
end

table.sort(data.words, function(a, b) return a.count > b.count end)

for i = 20 + 1, #data.words do
	data.words[i] = nil
	data.files[i] = nil
end

table.print(data)