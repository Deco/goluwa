-- strung.lua, a rewrite of the Lua string patterns in Lua + FFI, for LuaJIT
-- Copyright (C) 2013 Pierre-Yves Gérardy
-- MIT licensed (see the LICENSE file for the detais).
--
-- strung compiles patterns to Lua functions, asssociated with an FFI array
-- holding bit sets, for the character sets (`[...]`) and classes (`%x`), and
-- slots for the capture bounds. This array is allocated once at pattern
-- compile time, and reused for each matching attempt, minimizing memory
-- pressure.

local assert, error, getmetatable, ipairs, loadstring, pairs, print
    , rawset, require, setmetatable, tonumber, tostring, type, pcall
    = assert, error, getmetatable, ipairs, loadstring, pairs, print
    , rawset, require, setmetatable, tonumber, tostring, type, pcall

--[[DBG]] local unpack = unpack

local _u, expose, noglobals

pcall(function() -- used only for development.
  _u = require"util"
  expose, noglobals = _u.expose, _u.noglobals
end)

;(noglobals or type)("") -------------------------------------------------------------

local m_max = require"math".max

local o_setlocale = require"os".setlocale

local s, t = require"string", require"table"

local s_byte, s_char, s_find, s_gmatch, s_gsub, s_match, s_rep, s_sub
    = s.byte, s.char, s.find, s.gmatch, s.gsub, s.match, s.rep, s.sub

local t_concat, t_insert, t_remove
    = t.concat, t.insert, t.remove

local ffi = require"ffi"
local C = ffi.C

local     cdef,     copy,     metatype,     new, ffi_string,     typeof
    = ffi.cdef, ffi.copy, ffi.metatype, ffi.new, ffi.string, ffi.typeof

local bit = require("bit")
local band, bor, bxor = bit.band, bit.bor, bit.xor
local lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol

-- C types
local u32ary = typeof"uint32_t[?]"
local u32ptr = typeof"uint32_t *"
local constchar = typeof"const unsigned char *"

--[[DBG]] local ffimt = {__gc = function(self, ...)
-- [[DBG]]   print("GC", self, ...)
-- [[DBG]]   expose(self)
--[[DBG]] end}

--[[DBG]] local u32arys = metatype("struct {uint32_t ary[?];}", ffimt)

-- bit sets, code released by Mike Pall in the public domain.

-- local bitary = ffi.typeof"int32_t[?]"
-- local function bitnew(n)
--   return bitary(rshift(n+31, 5))
-- end

local function bittest(b, i)
  return band(rshift(b[rshift(i, 5)], i), 1) ~= 0
end

local function bitset(b, i)
  local x = rshift(i, 5); b[x] = bor(b[x], lshift(1, i))
end

-- pseudo-enum, just for the kicks. This might as well be a Lua table.
cdef[[
struct placeholder {
  static const int POS = 1;
  static const int VAL = 2;
  static const int INV = 2;
  static const int NEG = 3;
  static const int SET = 4;
  static const int UNTIL = 5;
  static const int FRETCAPS = 6;
  static const int MRETCAPS = 7;
  static const int RETURN = 8;
  static const int TEST = 9;
  static const int NEXT = 10;
  static const int OPEN = 11;
  static const int CLOSE = 12;
}
]]

local P = new"struct placeholder"

local g_i, g_subj, g_ins, g_start, g_end

---------------------- TEMPLATES -----------------------
-- patterns are compiled to Lua by stitching these:

local templates = {}

-- charsets, caps and qstn are the FFI pointers to the corresponding resources.
templates.head = {[=[
local bittest, charsetsS, caps, constchar, expose = ...
return function(subj, _, i)
  local charsets = charsetsS.ary
  local len = #subj
  local i0 = i - 1
  local chars = constchar(subj) - 1 -- substract one to keep the 1-based index
  local c, open, close, diff
  if i > len + 1 then return nil end
  ]=], --[[
  anchored and "do" or "repeat"]]"", [=[ --
    i0 = i0 + 1
    do
      i = i0]=]
}

templates.tail = {[=[ --
    ::done:: end
  ]=], P.UNTIL,
  P.RETURN, [=[ --
end]=]
}

templates.one = {[[ -- c
  i = (]], P.TEST, [[) and i + 1 or 0
  if i == 0 then goto done end]]
}

templates['*'] = {[=[ -- c*
    local i0, i1 = i
  while true do
    if (]=], P.TEST,[=[) then i = i + 1 else break end
  end
  i1 = i
  repeat
    i = i1
    do
      ]=],
      P.NEXT, [[ --
    ::done:: end
    if i ~= 0 then break end
    i1 = i1 - 1
  until i1 < i0
  --if not i then goto done end]]
}

templates['-'] = {[[ -- c-
  local i1 = i
  while true do
    i = i1
    do --]],
      P.NEXT, [[ --
    ::done:: end
    if i ~= 0 then break end
    i = i1
    if not (]],P.TEST, [[) then i = 0; break end
    i1 = i1 + 1
  end
  if i == 0 then goto done end]]
}

templates["?"] = {[[ -- c?
  do
    local _i, q = i, false
    if ]], P.TEST, [[ then q = true; i = i + 1 end
    goto first
    ::second::
    i = _i
    ::first::
    do --]],
      P.NEXT, [[ --
    ::done:: end
    if i == 0 and q then q = false; goto second end
  end]]
}

templates.char = {[[(i <= len) and chars[i] == ]], P.VAL}
templates.any = {[[i <= len]]}
templates.set = {[[(i <= len) and ]], P.INV, [[ bittest(charsets, ]], P.SET, [=[ + chars[i])]=]}


templates.ballanced = {[[ -- %b
  if chars[i] ~= ]], P.OPEN, [[ then
    i = 0; goto done --break
  else
    count = 1
    repeat
      i = i + 1
      if i > len then i = 0; break end
      c = chars[i]
      if c == ]], P.CLOSE, [[ then
        count = count - 1
      elseif c == ]], P.OPEN, [[ then
        count = count + 1
      end
    until count == 0 or i == 0
  end
  if i == 0 then goto done end
  i = i + 1]]
}
templates.frontier = {[[ -- %f
  if ]], P.NEG, [[ bittest(charsets, ]], P.SET, [[ + chars[i])
  or ]], P.POS, [[ bittest(charsets, ]], P.SET, [[ + chars[i-1])
  then i = 0; goto done end]]
}
templates.poscap = {[[ -- ()
  caps[]], P.OPEN, [[] = i
  caps[]], P.CLOSE, [[] = 4294967295
]]
}
templates.refcap = {[[ -- %n for n = 1, 9
  open, close = caps[]], P.OPEN, [[], caps[]], P.CLOSE, [[]
  diff = close - open
  if subj:sub(open, close) == subj:sub(i, i + diff) then
    i = i + diff + 1
  else
    i = 0; goto done --break
  end]]
}
templates.open = {[[ -- (
  caps[]], P.OPEN, [[] = i]]
}
templates.close = {[[ -- )
  caps[]], P.CLOSE, [[] = i - 1]]
}
  templates.dollar = {[[ --
  if i ~= #subj + 1 then i = 0 end -- $]]
}


---- Simple pattern compiler ----

local function hash_find (s, p, i) --
  if p == "" then return i, i - 1 end
  local lp, ls = #p, #s
  if ls < lp then return nil end
  if p == s then return i, i + lp - 1 end
  local chars = constchar(s) - 1
  local c = s_byte(p)
  lp = lp -1
  local last = ls - lp
  repeat
    while c ~= chars[i] do
      i = i + 1
      if i > last then return nil end
    end
    if lp == 0 or s_sub(s, i, i + lp) == p then return i, i + lp end
    i = i + 1
  until i > last
  return nil
end

local function hash_match(s, p, i)
  local st, e = hash_find(s, p, i)
  if not st then return nil end
  return s_sub(s, st, e)
end

local specials = {} for _, c in ipairs{"^", "$", "*", "+", "?", ".", "(", "[", "%", "-"} do
  specials[c:byte()] = true
end

local function normal(s)
  for i = 1, #s do
    if specials[s:byte(i)] then return false end
  end
  return true
end

-- local specials = u32ary(8)
-- for _, c in ipairs{"^", "$", "*", "+", "?", ".", "(", "[", "%", "-"} do
--   bitset(specials, c:byte())
-- end

-- local function normal(s)
--   local ptr = constchar(s)
--   for i = 0, #s - 1 do
--     if bittest(specials, ptr[i]) then return false end
--   end
--   return true
-- end



---- Main pattern compiler ---

local --[[function]] compile

--- The caches for the compiled pattern matchers.
local findcodecache

local simplefind = {hash_find, {"simple find"}, 0}
findcodecache = setmetatable({}, {
  __mode="k",
  __index=function(codecache, pat)

    local code = normal(pat) and simplefind or compile(pat, "find")
    rawset(findcodecache, pat, code)
    return code
  end
})

local simplematch = {hash_match, {"simple match"}, 0}
local matchcodecache
matchcodecache = setmetatable({}, {
  __mode="k",
  __index=function(codecache, pat)

    local code = normal(pat) and simplematch or compile(pat, "match")
    rawset(matchcodecache, pat, code)
    return code
  end
})

local gmatchcodecache
gmatchcodecache = setmetatable({}, {
  __mode="k",
  __index=function(codecache, pat)

    local code = --[[normal(pat) and simple(pat) or]] compile(pat, "gmatch")
    rawset(gmatchcodecache, pat, code)
    return code
  end
})

local gsubcodecache
gsubcodecache = setmetatable({}, {
  __mode="k",
  __index=function(codecache, pat)

    local code = --[[normal(pat) and simple(pat) or]] compile(pat, "gsub")
    rawset(gsubcodecache, pat, code)
    return code
  end
})

local function indent(i, s) return s_gsub(tostring(s), '\n', '\n'..s_rep("  ", i*2)) end

--- Push the template parts in two buffers.
local function push (tpl, data, buf, backbuf, ind)
  local back
  for _, o in ipairs(tpl) do
    if type(o) ~= "string" then
      if o == P.NEXT then back = true; break end
      buf[#buf + 1] = indent(ind, data[o])
    else
      buf[#buf + 1] = indent(ind, o)
    end
  end
  if back then for i = #tpl, 1, -1 do local o = tpl[i]
    if type(o) ~= "string" then
      if o == P.NEXT then break end
      backbuf[#backbuf + 1] = indent(ind, data[o])
    else
      backbuf[#backbuf + 1] = indent(ind, o)
    end
  end end
end

-- Character classes...
cdef[[
  int isalpha (int c);
  int iscntrl (int c);
  int isdigit (int c);
  int islower (int c);
  int ispunct (int c);
  int isspace (int c);
  int isupper (int c);
  int isalnum (int c);
  int isxdigit (int c);
]]


local ccref = {
    a = "isalpha", c = "iscntrl", d = "isdigit",
    l = "islower", p = "ispunct", s = "isspace",
    u = "isupper", w = "isalnum", x = "isxdigit"
}
local allchars = {}; for i = 0, 255 do
    allchars[i] = s_char(i)
end
local charclass = setmetatable({}, {__index = function(self, c)
  local func = ccref[c:lower()]
  if not func then return nil end
  local cc0, cc1 = u32ary(8), u32ary(8)
  for i = 0, 255 do
    if C[func](i) ~= 0 then
      bitset(cc0, i)
    else
      bitset(cc1, i)
    end
  end
  self[c:lower()] = cc0
  self[c:upper()] = cc1
  return self[c]
end})

-- %Z
do
  local Z = u32ary(8)
  for i = 1, 255 do bitset(Z, i) end
  charclass.Z = Z
end
local function key (cs)
  return t_concat({cs[0], cs[1], cs[2], cs[3], cs[4], cs[5], cs[6], cs[7]}, ":")
end

local function makecc(pat, i, sets)
  local c = pat:sub(i , i)
  local class = charclass[c]
  local k = key(class)
  if not sets[k] then
    sets[#sets + 1] = class
    sets[k]  = #sets
  end
  return "", (sets[k] - 1) * 256
end

local hat = ('^'):byte()
local function makecs(pat, i, sets)
  local inv = s_byte(pat,i) == hat
  i = inv and i + 1 or i
  local cl, last = i + 1, #pat
  while ']' ~= s_sub(pat, cl, cl) do cl = cl + 1 if i > last then error"unfinished character class" end end
  local cs = u32ary(8)
  local c
  while i < cl do
    c = s_sub(pat,i, i)
    if c == '%' then
      i = i + 1
      if i == cl then error"invalid escape sequence" end
      local cc = charclass[s_sub(pat, i, i)]
      if cc then
        for i = 0, 7 do
          cs[i] = bor(cs[i], cc[i])
        end
        i = i + 1
        goto continue
      elseif s_sub(pat, i, i) == 'z'
        then bitset(cs, 0); i = i + 1; goto continue
      end -- else, skip the % and evaluate the character as itself.
    end
    if i + 2 < cl and s_sub(pat, i + 1, i + 1) == '-' then
      for i = s_byte(pat, i), s_byte(pat, i+2) do bitset(cs, i) end
      i = i + 3
    else
      bitset(cs, s_byte(pat, i)); i = i + 1
    end
    ::continue::
  end
  local k = key(cs)
  if not sets[k] then
    sets[#sets + 1] = cs
    sets[k]  = #sets
  end
  return inv, (sets[k] - 1) * 256, cl
end

cdef[[const char * strchr ( const char * str, int character );]]

local suffixes = {
  ["*"] = true,
  ["+"] = true,
  ["-"] = true,
  ["?"] = true
}

local function suffix(i, ind, len, pat, data, buf, backbuf)
  local c = pat:sub(i, i)
  if not suffixes[c] then
    push(templates.one, data, buf,backbuf, ind)
    return i - 1, ind
  end
  if c == "+" then
    push(templates.one, data, buf,backbuf, ind)
    c = "*"
  end
  push(templates[c], data, buf,backbuf, ind + (c == "?" and 0 or 1))
  return i, ind + 2
end

local function body(pat, i, caps, sets, data, buf, backbuf)
  local len = #pat
  local ind = 1
  local c = pat:sub(i,i)
  while i <= len do
        local op = 0
    local canmod = false
    if c == '(' then -- position capture
      if pat:sub(i + 1, i + 1) == ")" then
        caps[#caps + 1] = 1
        caps[#caps + 1] = 0
        caps.type[#caps.type + 1] = "pos"
        data[P.OPEN] = -#caps
        data[P.CLOSE] = -#caps + 1
        push(templates.poscap, data, buf,backbuf, ind)
        i = i + 1
      else -- open capture
        caps[#caps + 1] = 1
        caps[#caps + 1] = -1
        caps.open = caps.open + 1 -- keep track of opened captures
        caps.type[#caps.type + 1] = "txt"
        data[P.OPEN] = -#caps
        push(templates.open, data, buf,backbuf, ind)
      end
    elseif c == ")" then -- open capture
      data[P.CLOSE] = false
      for j = #caps, 2, -2 do
        if caps[j] == -1 then -- -1 means that the slot has not been closed yet.
          caps[j] = 1         -- colse it
          caps.open = caps.open - 1
          data[P.CLOSE] = - j + 1;
          break end
      end
      if not data[P.CLOSE] then error"invalid closing parenthesis" end
      push(templates.close, data, buf,backbuf, ind)
    elseif  c == '.' then
      data[P.TEST] = templates.any[1]
      i, ind = suffix(i + 1, ind, len, pat, data, buf, backbuf)
    elseif c == "[" then
      local inv
      inv, templates.set[P.SET], i = makecs(pat, i+1, sets)
      templates.set[P.INV] = inv and "not" or ""
      data[P.TEST] = t_concat(templates.set)
      i, ind = suffix(i + 1, ind, len, pat, data, buf, backbuf)
    elseif c == "%" then
      i = i + 1
      c = pat:sub(i, i)
      if not c then error"malformed pattern (ends with '%')" end
      if ccref[c:lower()] or c == "Z" then -- a character class
        templates.set[P.INV], templates.set[P.SET] = makecc(pat, i, sets)
                data[P.TEST] = t_concat(templates.set)
      i, ind = suffix(i + 1, ind, len, pat, data, buf, backbuf)
      elseif c == "0" then
        error("invalid capture index")
      elseif "1" <= c and c <= "9" then
        local n = tonumber(c) * 2
        if n > #caps or caps[n] == -1 then
          error"attempt to reference a non-existing capture"
        end
        data[P.OPEN] = -n
        data[P.CLOSE] = -n + 1
        push(templates.refcap, data, buf,backbuf, ind)
      elseif c == "b" then
        data[P.OPEN], data[P.CLOSE] = pat:byte(i + 1, i + 2)
        i = i + 2
        push(templates.ballanced, data, buf, backbuf, ind)
      elseif c == 'f' then
        if pat:sub(i+1, i +1) ~= '[' then error"missing '['' after '%f' in pattern" end
        local inv, set_i
        inv, data[P.SET], i = makecs(pat, i+2, sets)
        data[P.POS] = inv and "not" or ""
        data[P.NEG] = inv and "" or "not"
        push(templates.frontier, data, buf, backbuf, ind)
      else
        if c == 'z' then c = '\0' end
        templates.char[P.VAL] = c:byte()
        data[P.TEST] = t_concat(templates.char)
        i, ind = suffix(i + 1, ind, len, pat, data, buf, backbuf)
      end
    elseif c == '$' and i == #pat then
      push(templates.dollar, data, buf,backbuf, ind)
    else
      templates.char[P.VAL] = c:byte()
      data[P.TEST] = t_concat(templates.char)
      i, ind = suffix(i + 1, ind, len, pat, data, buf, backbuf)
    end
    i = i + 1
    c = pat:sub(i, i)
  end ---- /while
end

--- Create the uint32_t array that holds the character sets and capture bounds.
local function pack (sets, ncaps)
  local nsets = #sets
  local len = nsets*8 + ncaps*2
  local charsets = u32arys(len + 2) -- add two slots for the bounds of the match.
  local capsptr= u32ptr(charsets.ary) + len
  for i = 1, nsets do
    for j = 0, 7 do
      charsets.ary[(i - 1) * 8 + j] = sets[i][j]
    end
  end
  return charsets, capsptr
end

cdef[[
struct M {
  static const int CODE = 1;
  static const int SOURCE = 2;
  static const int NCAPS = 3;
  static const int CAPS = 4;
}]] local M = new"struct M" -- fields of the "_M_atchers" table.


function compile (pat, mode) -- local, declared above
  local anchored = (pat:sub(1,1) == "^")
  local caps, sets = {open = 0, type={}}, {}
  local data = {}
  local buf = {
    templates.head[1],
    anchored and "do" or "repeat",
    templates.head[3]
    }
  local backbuf = {}
  local i = anchored and 2 or 1

  body(pat, i, caps, sets, data, buf, backbuf)

  -- pack the charsets and captures in an FFI array.
  local ncaps = #caps / 2
  local charsets, capsptr = pack(
    sets,
    (mode == "gsub" and m_max(1, ncaps) or ncaps)
  )

  -- append the tail of the matcher to its head.
  for i = #backbuf, 1, -1 do buf[#buf + 1] = backbuf[i] end

  --
  data[P.UNTIL] = anchored and "end" or "until i ~=0 or i0 > len"


  -- prepare the return values
  assert(caps.open == 0, "invalid pattern: one or more captures left open")
  assert(#caps<400, "too many captures in pattern (max 200)")

  if ncaps == 0 then
    if mode == "find" then
      data[P.RETURN] = [[ --
  if i == 0 then return nil end
  return i0, i -1]]
    elseif mode == "match" then
      data[P.RETURN] = [[ --
  if i == 0 then return nil end
  return subj:sub(i0, i - 1)]]
    elseif mode == "gmatch" then
      data[P.RETURN] = [[ --
  caps[0], caps[1] = i0, i-1
  return i ~= 0]]
    elseif mode == "gsub" then
      data[P.RETURN] = [[ --
  caps[0], caps[1] = i0, i-1
  caps[-2], caps[-1] = i0, i-1
  return i ~= 0]]
    end
  elseif mode:sub(1,1) == "g" then
    data[P.RETURN] = [[ --
  caps[0], caps[1] = i0, i-1
  return i ~= 0]]
  else
    local rc = {}
    for i = 2, #caps, 2 do
      if caps.type[i/2] == "pos" then
        rc[#rc + 1] = "caps[".. -i.. "]"
      else
        rc[#rc + 1] = "subj:sub(caps[".. -i .."], caps[" .. -i + 1 .. "]) "
      end
    end

    if mode == "find" then t_insert(rc, 1, "i0, i - 1") end

    data[P.RETURN] = [[ --
  if i == 0 then return nil end
  return ]]..t_concat(rc, ", ")
  end
  push(templates.tail, data, buf, backbuf, 0)

  -- load the source
  local source = t_concat(buf)
  -- [[DBG]] print("Compile; mode, ncaps, source", mode, ncaps, "\n"..source)
  local loader, err = loadstring(source)
  if not loader then error(source.."\nERROR:"..err) end
  local code = loader(bittest, charsets, capsptr, constchar, expose)
  return {code,   source,   ncaps,   capsptr}
     -- m.CODE, m.SOURCE,   m.NCAPS, m.CAPS -- anchor the charset array? Seems to fix the segfault.
end


---- API ----

local function checki(i, subj)
  if not i then return 1 end
  if i < 0 then i = #subj + 1 + i end
  if i < 1 then i = 1 end
  return i
end

local function _wrp (src, pat, success, ...)
  if not success then error("-=-=-=-=-=-=-=-=-=-=-=-=-=-\n"..src.. "\n"..pat.. "\n".. (...)) end
  return ...
end

local producers = setmetatable({}, {__index = function(self, n)
  local acc = {}
  for open = -2, -n * 2, -2 do
    local close = open + 1
    acc[#acc + 1] =
      "c["..close.."] == 4294967295 and c["..open.."] or "..
        "subj:sub(c["..open.."], c["..close.."])"
  end
  local res = loadstring([=[ --
    return function(c, subj)
      return ]=]..t_concat(acc, ", ")..[[ --
    end
  ]])()
  self[n] = res
  return res
end})
producers[0] = function(caps, subj)
  return subj:sub(caps[0], caps[1])
end



local function find(subj, pat, i, plain)
  if plain then
    return s_find(subj, pat, i, true)
  end
  i = checki(i, subj)
  -- if plain then
  --   return hash_find(subj, pat, i, true)
  -- end
  --[==[
  return _wrp(
    codecache[pat][M.SOURCE],
    pat,
    pcall(codecache[pat][M.CODE], subj, pat, checki(i, subj), false, false)
  )
  --[=[]==]
  return findcodecache[pat][M.CODE](subj, pat, i)
  --]=]
end

local function match(subj, pat, i, raw)
  --[[
  return _wrp(
    codecache[pat][M.SOURCE],
    pat,
    pcall(codecache[pat][M.CODE], subj, pat, checki(i, subj), false, true)
  )
  --[=[]]
  return matchcodecache[pat][M.CODE](subj, pat, checki(i, subj))
  --]=]
end


-- gmatch paraphernalia --

--- lazily build a table of functions that produce n captures at a given offset.
--- the offset * n combo is encoded as a single number by lshifting the offset
--- by 8 then adding it to n.

local gmatch do
  cdef[[
  struct GM {
    static const int CODE = 1;
    static const int SUBJ = 2;
    static const int PAT = 3;
    static const int INDEX = 4;
    static const int PROD = 5;
    static const int CAPS = 6;
  }]] local GM = new"struct GM"

  local function gmatch_iter(state)
    local success = state[GM.CODE](state[GM.SUBJ], state[GM.PAT], state[GM.INDEX])
    if success then
      local caps = state[GM.CAPS]
      state[GM.INDEX] = m_max(caps[0], caps[1]) + 1
      return state[GM.PROD](caps, state[2])
    else
      return nil
    end
  end

  function gmatch(subj, pat)
    local c = gmatchcodecache[pat]
    local state = {
      c[M.CODE],
      subj,
      pat,
      1,                     -- GM.INDEX
      producers[c[M.NCAPS]], -- GM.PROD
      c[M.CAPS]              -- GM.CAPS
    }
    return gmatch_iter, state
  end
end

local gsub do
  local BUFF_INIT_SIZE = 16
  cdef"void* malloc (size_t size);"
  cdef"void free (void* ptr);"
  local acache = setmetatable({},{__mode = "k"})
  local Buffer = metatype(
    --               size,       index,            array
    "struct{uint32_t s; uint32_t i; unsigned char* a;}",
    {__gc = function(self) C.free(self.a) end}
  )
  local charsize = ffi.sizeof"char"
  local function buffer()
    local b = Buffer(
      BUFF_INIT_SIZE,
      0,
      C.malloc(BUFF_INIT_SIZE * charsize)
    )
    return b
  end

  local function reserve (buf, size)
    if size <= buf.s then return end
    local a = buf.a
    size = buf.s * 2
    buf.a = C.malloc(size * charsize)
    buf.s = size
    copy(buf.a, a, buf.i)
    C.free(a)
  end

  local function mergebuf (acc, new)
    reserve(acc, acc.i + new.i)
    copy(acc.a + acc.i, new.a, new.i)
    acc.i = acc.i + new.i
  end

  local function mergestr (acc, str)
    reserve(acc, acc.i + #str)
    copy(acc.a + acc.i, constchar(str), #str)
    acc.i = acc.i + #str
  end

  local function mergebytes (acc, ptr, len)
    reserve(acc, acc.i + len)
    copy(acc.a + acc.i, ptr, len)
    acc.i = acc.i + len
  end

  local function mergeonebyte (acc, byte)
    reserve(acc, acc.i + 1)
    acc.i = acc.i + 1
    acc.a[acc.i] = byte
  end

  local function table_handler (subj, caps, ncaps, producer, buf, tbl)
    local res = tbl[producer(caps, subj)]
    if not res then
      local i, e = caps[0], caps [1]
      mergebytes(buf, constchar(subj) + i - 1, e - i + 1)
    else
      local t = type(res)
      if t == "string" or t == "number" then
        res = tostring(res)
        mergestr(buf, res)
      else
        error("invalid replacement type (a "..t..")")
      end
    end
  end

  local function string_handler (_, _, _, _, buf, str)
    mergestr(buf, str)
  end

  local function prepare(repl, n, buf, i)
    local i0 = i
    local c = repl[i]
    if c == 37 then -- "%"
      i = i + 1
      if i == n then return end -- skip a "%" in terminal position.
      c = repl[i]
      if not (48 <= c and c <= 57) then return prepare(repl, n, buf, i) end
      i = i
      mergeonebyte(buf, 0)
      mergeonebyte(buf, c - 48)
      return prepare(repl, n, buf, i + 1)
    else
      local bufi =  buf.i + 2
      mergeonebyte(buf, 0)
      while true do
        mergeonebyte(buf, c)
        i = i + 1
        if buf.i - bufi > 255 then
          buf[bufi] = 255
          bufi = buf.i + 2
        end
        c = repl[i]
        if c == 37 then -- "%"
          i = i + 1
          if i == n then
            buf[bufi] = buf.i - bufi
            return
          end
          if 48 <= c and c <= 57 then return prepare(repl, n, buf, i - 1) end
        end
        mergeonebyte(buf, c)
        i = i + 1
      end
    end
  end

  local charary = typeof"unsigned char[?]"
  local long_pattern_cache = setmetatable({}, {__index = function(self, repl)
    local buf = buffer()
    repl = constchar(repl)
    prepare(repl, buf, 0)
    return buf
  end})

  local function long_pattern_handler (subj, caps, ncaps, replacement, buf, pat)
    local i, L, ary = 0, replacement.i, replacement.a
    ncaps = m_max(1, ncaps) -- for simple matchers, %0 and %1 mean the same thing.
    subj = constchar(subj) - 1 -- subj is anchored in `gsub()`
    while i < L do
      local l = ary[i]
      i = i + 1
      if l == 0 then
        local n = ary[i]
        if n > ncaps then error"invalid capture index" end
        local s = caps[-2*n]
        local ll = caps[-2*n + 1] - s
        mergebytes(buf, subj + s, ll)
        i = i + 1
      else
        mergebytes(buf, ary + i, l)
        i = i + l
      end
    end
  end

  local function short_pattern_handler (subj, caps, ncaps, _, buf, pat)
    local i, L = 1, #pat
    ncaps = m_max(1, ncaps) -- for simple matchers, %0 and %1 mean the same thing.
    subj = constchar(subj) - 1 -- subj is anchored in `gsub()`
    pat = constchar(pat) - 1 -- ditto
    while i <= L do
      local n = pat[i]
      if n == 37 then -- "%" --> capture or escape sequence.
        i = i + 1
        n = pat[i]
        if 48 <= n and n <= 57 then -- "0" <= n <= "9"
          n = n - 48
          if n > ncaps then error"invalid capture index" end
          local s = caps[-2*n]
          local ll = caps[-2*n + 1] - s + 1
          mergebytes(buf, subj + s, ll)
        else
          mergeonebyte(buf, n)
        end
      else
        mergeonebyte (buf, n)
      end
      i = i + 1
    end
  end

  local function function_handler (subj, caps, ncaps, producer, buf, fun)
    -- [[DBG]]local _ = {producer(caps, subj)}
    -- [[DBG]]for _,v in ipairs(_) do print("V:", v, tostring(v):byte())print("#",#tostring(v)) end
    -- [[DBG]]local res = fun(unpack(_))
    local res = fun(producer(caps, subj))
    if not res then
      local i, e = caps[0], caps [1]
      mergebytes(buf, constchar(subj) + i - 1, e - i + 1)
    else
      local t = type(res)
      if t == "string" or t == "number" then
        res = tostring(res)
        mergestr(buf, res)
      else
        error("invalid replacement type (a "..t..")")
      end
    end
  end

  local function select_handler (ncaps, repl)
    t = type(repl)
    if t == "string" then
      if repl:find("%%") then
        return short_pattern_handler, short_pattern_handler
        -- return short_pattern_handler, long_pattern_cache[repl]
      else
        return string_handler, string_handler
      end
    elseif t == "table" then
      return table_handler, producers[1]
    elseif t == "function" then
      return function_handler, producers[ncaps]
    else
      error("Bad replacement type for GSUB TODO IMPROVE MESSAGE.")
    end
  end

  function gsub (subj, pat, repl, n)
    n = n or -1
    local c = gsubcodecache[pat]
    local matcher = c[M.CODE]
    local handler, helper = select_handler(c[M.NCAPS], repl)
    local caps = c[M.CAPS]
    local ncaps = c[M.NCAPS]
    local success = matcher(subj, pat, 1)

    if not success then return subj, 0 end

    local count = 0
    local buf = buffer()
    local subjptr = constchar(subj)
    local last_e = 0
    while success and n ~= 0 do
      n = n - 1
      count = count + 1
      mergebytes(buf, subjptr + last_e, caps[0] - last_e - 1)
      last_e = caps[1]
      handler(subj, caps, ncaps, helper, buf, repl)
      success = matcher(subj, pat, m_max(caps[0], caps[1]) + 1)
    end
    mergebytes(buf, subjptr + last_e, #subj - last_e)
    return ffi_string(buf.a, buf.i), count
  end
end

-- used in the test suite.
local function _assert(test, pat, msg)
  if not test then
    local source = findcodecache[pat][M.SOURCE]
    print(("- -"):rep(60))
    print(source)
    print(("- "):rep(60))
    print(msg)
    error()
  end
end

-- reset the compiler cache to match the new locale.
local function reset ()
  codecache = setmetatable({}, getmetatable(codecache))
  charclass = setmetatable({}, getmetatable(charclass))
end
local function setlocale (loc, mode)
  reset()
  return o_setlocale(loc, mode)
end

local function showpat(p)
  print(p,"\n---------")
  print(gsubcodecache[p][M.SOURCE])
end
-------------------------------------------------------------------------------

return {
  find = find,
  match = match,
  gfind = gmatch,
  gmatch = gmatch,
  gsub = gsub,
  reset = reset,
  setlocale = setlocale,
  assert = _assert,
  showpat = showpat
}