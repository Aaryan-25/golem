-- Golem editor: the gada (the Indian mace), drawn with fine Braille motes, and everything it does.
--
-- Alt+G opens the settings: how much animation (HIGH, MEDIUM, LOW or OFF), which weapon
-- (gada, vajra, trishul), sound on/off, the codex of relics you have found, and (from
-- writing.lua) spell check and word suggestions on/off.
--
--   what happens                         from level   what you see (and hear)
--   start screen                          MEDIUM      it flies in beside the sigil and floats there
--   something working (AI, running code)  LOW         it travels the bottom line like a pendulum
--   save (Ctrl+S)                         LOW         it strikes; the more you changed, the more motes
--                                                     (HIGH: a hit-stop and the bottom line flashes)
--   something failed                      LOW         it trembles, motes fall; MEDIUM: a crack that heals
--   code ran fine                         MEDIUM      it rises in a ring of light
--   the AI answered                       MEDIUM      thrown to the answer and back; the answer is carved in
--   find / F3                             MEDIUM      a tap; the matches on screen light up one by one
--   replace                               MEDIUM      one slam per change (up to three), each new word flashes
--   undo / redo                           MEDIUM      it spins backwards / forwards
--   lines deleted                         MEDIUM      they shatter into falling motes
--   3 minutes without a key               MEDIUM      it rests on the bottom line, dust settles; a key wakes it
--   typing without a pause                HIGH        the line you are on glows brighter, then calms down
--   late at night (22:00 to 06:00)        all         its light is dimmer
--   closing                               MEDIUM      it flies to the middle and fades into motes
--   a relic found                         LOW         a chime, and it rises; the relic goes into the codex
--
-- Everything is text in small see-through windows: no pictures, little work for the processor.
-- LOW draws fewer frames and fewer motes; OFF draws nothing and plays nothing.
-- Part of Golem: GADA, the editor; MAP.md section 5.7.

local api, fn = vim.api, vim.fn
local uv = vim.uv or vim.loop
local S = _G.Golem
local P = S.P

-------------------------------------------------------------------------------
-- Settings (Alt+G), kept in ~/.local/share/golem-edit/gada.conf
-------------------------------------------------------------------------------
local box = vim.env.HOME .. '/.local/share/golem-edit'
local conf_file = box .. '/gada.conf'
local cfg = { level = 'high', form = 'gada', sound = 'on' }
local LEVEL = { off = 0, low = 1, medium = 2, high = 3 }

do
  local f = io.open(conf_file, 'r')
  if f then
    for line in f:lines() do
      local k, v = line:match('^(%w+)=(%w+)$')
      if k and cfg[k] then cfg[k] = v end
    end
    f:close()
  end
  if fn.filereadable(box .. '/gada-off') == 1 then cfg.level = 'off' end -- the older on/off switch
  if not LEVEL[cfg.level] then cfg.level = 'high' end
end

local function save_conf()
  fn.mkdir(box, 'p')
  fn.writefile({ 'level=' .. cfg.level, 'form=' .. cfg.form, 'sound=' .. cfg.sound }, conf_file)
  os.remove(box .. '/gada-off')
end

local NEED = {
  busy = 1, strike = 1, shake = 1, relic = 1, fly = 2, hover = 2, crack = 2, raise = 2, throw = 2,
  tap = 2, slam = 2, farewell = 2, rest = 2, shatter = 2, rewind = 2, sweep = 2, carve = 2,
  hammer = 2, streak = 3, flash = 3,
}
local function can(what) return LEVEL[cfg.level] >= (NEED[what] or 2) end
local function lvl() return LEVEL[cfg.level] end
local function every(ms) return math.floor(ms * ({ 1.8, 1.25, 1 })[math.max(1, lvl())]) end -- slower frames on LOW
local function motes(n) return math.max(2, math.floor(n * ({ 0.4, 0.7, 1 })[math.max(1, lvl())])) end
if _G.Golem then _G.Golem.anim_level = lvl end -- the program map (F12) draws flat on LOW and OFF

-------------------------------------------------------------------------------
-- Colours: its light, dimmer at night
-------------------------------------------------------------------------------
local function mix(a, b, t)
  local out = '#'
  for i = 2, 6, 2 do
    local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
    out = out .. string.format('%02x', math.floor(x + (y - x) * t + 0.5))
  end
  return out
end

local function light()
  local h = os.date('*t').hour
  local night = h >= 22 or h < 6
  api.nvim_set_hl(0, 'GolemMace', { fg = night and mix(P.pale, P.mist, 0.45) or P.pale, bg = 'NONE' })
  api.nvim_set_hl(0, 'GolemFlash', { fg = P.void, bg = night and P.mist or P.pale, bold = true })
end
light()

-------------------------------------------------------------------------------
-- Sound: small WAV files made at build time (sounds.py), played with aplay
-------------------------------------------------------------------------------
local sound_dir = vim.env.GOLEM_EDIT_SOUNDS
local last_played = {}

local function sound(name)
  if cfg.sound ~= 'on' or lvl() == 0 or not sound_dir then return end
  local now = uv.now()
  if last_played[name] and now - last_played[name] < 150 then return end
  last_played[name] = now
  local f = sound_dir .. '/' .. name .. '.wav'
  if fn.filereadable(f) == 1 and fn.executable('aplay') == 1 then
    pcall(fn.jobstart, { 'aplay', '-q', f }, { detach = true })
  end
end
S.sound = sound

-------------------------------------------------------------------------------
-- Drawing: a canvas of letter cells, each 2 x 4 motes (Braille)
-------------------------------------------------------------------------------
local BITS = { [0] = { 0x01, 0x02, 0x04, 0x40 }, [1] = { 0x08, 0x10, 0x20, 0x80 } }
local function braille(mask)
  local cp = 0x2800 + mask
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local function canvas(w, h)
  local c = { w = w, h = h, cells = {} }
  function c.dot(x, y)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x < 0 or y < 0 or x >= w * 2 or y >= h * 4 then return end
    local i = math.floor(y / 4) * w + math.floor(x / 2) + 1
    local bit = BITS[x % 2][y % 4 + 1]
    local m = c.cells[i] or 0
    if math.floor(m / bit) % 2 == 0 then c.cells[i] = m + bit end
  end
  function c.lines()
    local out = {}
    for row = 0, h - 1 do
      local parts = {}
      for col = 1, w do
        local m = c.cells[row * w + col]
        parts[col] = m and braille(m) or ' '
      end
      out[#out + 1] = table.concat(parts)
    end
    return out
  end
  return c
end

-- The weapons, around (cx, cy), turned by a (0 = head up), size s (1 = about 22 motes long).
local FORMS = {}

FORMS.gada = function(put) -- Hanuman's gada: a ribbed round head with a band, a crown and a point,
  --                             a lotus collar, a handle wound with cord, a round pommel
  local cy, R = 5.5, 4.2
  for t = 0, 2 * math.pi, 0.03 do put(R * math.cos(t), cy + R * math.sin(t)) end   -- the head
  for _, k in ipairs({ -0.55, 0, 0.55 }) do                                       -- its ribs
    for y = -R, R, 0.1 do put(k * math.sqrt(math.max(0, R * R - y * y)), cy + y) end
  end
  for _, yb in ipairs({ -0.3, 0.3 }) do                                           -- the band round its middle
    for x = -R, R, 0.1 do if x * x + yb * yb < R * R then put(x, cy + yb) end end
  end
  for x = -1.4, 1.4, 0.1 do put(x, cy + R + 0.25) end                             -- the crown and its point
  for t = 0, math.pi, 0.06 do put(1.2 * math.cos(t), cy + R + 0.25 + math.sin(t)) end
  for y = cy + R + 1.25, cy + R + 2.6, 0.1 do put(0, y) end
  put(-0.3, cy + R + 2); put(0.3, cy + R + 2)
  for _, c in ipairs({ -1.4, 0, 1.4 }) do                                         -- lotus petals under the head
    for t = math.pi, 2 * math.pi, 0.12 do put(c + 0.7 * math.cos(t), cy - R + 0.15 + 0.8 * math.sin(t)) end
  end
  for y = -8.4, cy - R - 0.6, 0.1 do put(-0.45, y); put(0.45, y) end              -- the handle
  for _, yb in ipairs({ -1.6, -4.2 }) do for x = -0.9, 0.9, 0.1 do put(x, yb) end end
  for i = 0, 4 do                                                                  -- the grip, wound with cord
    local y0 = -4.6 - i * 0.7
    for u = 0, 1, 0.1 do put(-0.45 + 0.9 * u, y0 - 0.4 * u) end
  end
  for t = 0, 2 * math.pi, 0.1 do put(math.cos(t), -9.4 + 0.9 * math.sin(t)) end   -- the pommel
  put(0, -10.6)
end

FORMS.vajra = function(put) -- Indra's thunderbolt: a grip with a bead, prongs closing to a point at each end
  for y = -2.5, 2.5, 0.5 do put(-0.6, y); put(0.6, y) end
  for a = 0, 11 do put(math.cos(a / 12 * 2 * math.pi) * 1.6, math.sin(a / 12 * 2 * math.pi) * 1.6) end
  for _, side in ipairs({ -1, 1 }) do
    for _, k in ipairs({ -1, -0.45, 0, 0.45, 1 }) do
      for u = 0, 1, 0.08 do
        put(k * 3.6 * math.sin(math.pi * u * 0.92), side * (3 + 8.5 * u))
      end
    end
  end
end

FORMS.trishul = function(put) -- Shiva's trident: a long shaft, three prongs, the outer ones curving out
  for y = -11, 3, 0.5 do put(0, y) end
  for x = -4, 4, 0.5 do put(x, 3) end
  for y = 3, 12, 0.5 do put(0, y) end
  put(-0.6, 11); put(0.6, 11)
  for _, side in ipairs({ -1, 1 }) do
    for u = 0, 1, 0.08 do put(side * (4 + 1.2 * u * u), 3 + 7 * u) end
    put(side * 5.4, 10.4)
  end
  put(-1, -2); put(1, -2); put(-1, -1.5); put(1, -1.5) -- a small binding on the shaft
end

local function weapon(c, cx, cy, a, s)
  s = s or 1
  local ca, sa = math.cos(a), math.sin(a)
  local function put(x, y) c.dot(cx + (x * ca + y * sa) * s, cy - (y * ca - x * sa) * s) end
  ;(FORMS[cfg.form] or FORMS.gada)(put)
end

-------------------------------------------------------------------------------
-- Small see-through windows above your work
-------------------------------------------------------------------------------
local function float(w, h, row, col, anchor)
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'wipe'
  local ok, win = pcall(api.nvim_open_win, b, false, {
    relative = 'editor', anchor = anchor or 'SE', row = row, col = col, width = math.max(1, w),
    height = math.max(1, h), style = 'minimal', focusable = false, zindex = 200, noautocmd = true,
  })
  if not ok then return nil end
  vim.wo[win].winhighlight = 'Normal:GolemMace,NormalFloat:GolemMace'
  vim.wo[win].winblend = 100 -- see-through: only the motes cover what is below
  return b, win
end

local function show(b, lines)
  if b and api.nvim_buf_is_valid(b) then pcall(api.nvim_buf_set_lines, b, 0, -1, false, lines) end
end

local function close(win)
  if win and api.nvim_win_is_valid(win) then pcall(api.nvim_win_close, win, true) end
end

local function corner_row() return vim.o.lines - 3 end -- just above the bottom line
local function corner_col() return vim.o.columns - 2 end

-- A short animation: draw(c, f, W, H) for frames 1..n, in a small window.
local playing = {}
local busy_on = false

local function play(name, W, H, n, ms, draw, row, col, done, anchor)
  if not can(name) or playing[name] then return done and done() end
  playing[name] = true
  local b, win = float(W, H, row or corner_row(), col or corner_col(), anchor)
  if not b then playing[name] = nil; return done and done() end
  local f = 0
  local timer = uv.new_timer()
  timer:start(0, every(ms), vim.schedule_wrap(function()
    f = f + 1
    local c = canvas(W, H)
    draw(c, f, W, H, win)
    show(b, c.lines())
    if f >= n then
      timer:stop(); timer:close()
      close(win)
      playing[name] = nil
      if done then done() end
    end
  end))
end

-- The bottom line flashes for a moment (HIGH).
local function flash_line()
  if not can('flash') then return end
  api.nvim_set_hl(0, 'GolemDim', { fg = P.void, bg = P.pale })
  api.nvim_set_hl(0, 'GolemBright', { fg = P.void, bg = P.pale, bold = true })
  vim.cmd('redrawstatus')
  vim.defer_fn(function()
    api.nvim_set_hl(0, 'GolemDim', { fg = P.mist })
    api.nvim_set_hl(0, 'GolemBright', { fg = P.pale, bold = true })
    vim.cmd('redrawstatus')
  end, 90)
end

-------------------------------------------------------------------------------
-- Working: the gada travels the bottom line like a pendulum (LOW: turns in the corner)
-------------------------------------------------------------------------------
local busy_count, busy_win, busy_timer = 0, nil, nil

function S.busy()
  if not can('busy') then return function() end end
  busy_count = busy_count + 1
  if not busy_timer then
    busy_on = true
    local wide = lvl() >= 2
    local W, H = wide and 30 or 10, wide and 4 or 5
    local b, win = float(W, H, corner_row(), corner_col())
    if not b then busy_count = busy_count - 1; busy_on = false; return function() end end
    busy_win = win
    local t = 0
    busy_timer = uv.new_timer()
    busy_timer:start(0, every(70), vim.schedule_wrap(function()
      if not busy_timer then return end
      t = t + 1
      local c = canvas(W, H)
      if wide then
        local sw = math.sin(t * 0.09)                    -- back and forth
        local x = W + (W - 6) * sw
        local vel = math.cos(t * 0.09)
        weapon(c, x, H * 2 - 1, -vel * 0.9 + 0.2 * math.sin(t * 0.3), 0.55)
        for k = 0, W * 2 - 1, 3 do c.dot(k, H * 4 - 1) end -- the track
        for k = 1, motes(5) do c.dot(x - vel * k * 3, H * 2 + (k % 2) * 3) end -- its trail
      else
        weapon(c, W, H * 2, t * 0.3, 0.75)
        for k = 0, 2 do
          local a = t * 0.2 + k * 2.1
          c.dot(W + math.cos(a) * (W - 2), H * 2 + math.sin(a) * (H * 2 - 1))
        end
      end
      show(b, c.lines())
    end))
  end
  local stopped = false
  return function()
    if stopped then return end
    stopped = true
    busy_count = busy_count - 1
    if busy_count <= 0 then
      busy_count = 0
      if busy_timer then busy_timer:stop(); busy_timer:close(); busy_timer = nil end
      busy_on = false
      vim.schedule(function() close(busy_win); busy_win = nil end)
    end
  end
end

-------------------------------------------------------------------------------
-- Save: the strike. power 1..3 grows with how much you changed since the last save.
-------------------------------------------------------------------------------
function S.strike(power)
  if busy_on then return end
  power = math.max(1, math.min(3, power or 1))
  local sparks = {}
  for i = 1, motes(8 + power * 6) do
    sparks[i] = { a = math.random() * math.pi - math.pi, v = 1.2 + math.random() * (1.5 + power) }
  end
  local stop_frames = can('flash') and 2 or 0 -- the hit-stop: the moment of impact, held
  play('strike', 14, 6, 16 + stop_frames, 33, function(c, f, W, H)
    local cx, cy = W + 4, H * 4 - 2
    if f <= 7 then
      local t = f / 7
      weapon(c, cx - 12, cy - 1, -2.4 + 3.85 * t * t, 0.85)
      if f == 7 then sound('thud'); flash_line() end
    elseif f <= 7 + stop_frames then
      weapon(c, cx - 12, cy - 1, 1.45, 0.85)
    else
      local k = f - 7 - stop_frames
      weapon(c, cx - 12, cy - 1, 1.45 + math.sin(f) * 0.04, 0.85)
      for _, s in ipairs(sparks) do
        if k < 8 then c.dot(cx + 3 + math.cos(s.a) * s.v * k, cy + math.sin(s.a) * s.v * k * 0.6 + k * k * 0.08) end
      end
    end
  end)
end

-------------------------------------------------------------------------------
-- Failure: it trembles and motes fall; then a crack across the bottom that heals
-------------------------------------------------------------------------------
local function crack()
  local W = math.max(10, vim.o.columns - 4)
  local path, y = {}, 1.5
  for x = 0, W * 2 - 1 do
    y = math.max(0, math.min(3, y + (math.random() - 0.5) * 1.6))
    path[x] = y
  end
  play('crack', W, 1, 26, 70, function(c, f)
    local healed = math.max(0, (f - 8) * (W / 18)) -- it closes from both ends toward the middle
    for x = 0, W * 2 - 1 do
      if x > healed and x < W * 2 - 1 - healed then c.dot(x, path[x]) end
    end
  end, corner_row() + 1, corner_col())
end

function S.shake()
  sound('crack')
  play('shake', 10, 5, 18, 40, function(c, f, W, H)
    local jit = (f <= 10) and ((f % 2 == 0) and 1.2 or -1.2) or 0
    local a = (f <= 10) and 0.25 * jit or math.min(0.9, (f - 10) * 0.12)
    weapon(c, W + jit, H * 2 + 1, a, 0.75)
    if f > 8 then
      for k = 0, motes(6) - 1 do c.dot(W - 5 + k * 2, H * 2 - 6 + (f - 8) * (1 + k % 3) * 0.8) end
    end
  end)
  vim.defer_fn(crack, 200)
end

-------------------------------------------------------------------------------
-- Success: it rises in a ring of light
-------------------------------------------------------------------------------
function S.raise()
  sound('rise')
  play('raise', 12, 6, 20, 40, function(c, f, W, H)
    local t = math.min(1, f / 8)
    local e = 1 - (1 - t) ^ 3
    weapon(c, W, H * 2 + (1 - e) * 10, (1 - e) * 1.6, 0.8)
    if f > 6 then
      local r = (f - 6) * 1.3
      local n = motes(24)
      for i = 0, n - 1 do
        local a = i / n * 2 * math.pi
        if (i + f) % 3 ~= 0 then c.dot(W + math.cos(a) * r, H * 2 - 3 + math.sin(a) * r * 0.8) end
      end
    end
  end)
end

-------------------------------------------------------------------------------
-- The AI answered: thrown out to the answer, a ring where it lands, then back
-------------------------------------------------------------------------------
function S.throw(to_row, to_col)
  if not can('throw') or busy_on then return end
  sound('whoosh')
  local W, H = 8, 4
  local from_row, from_col = corner_row() - H, corner_col() - W
  local b, win = float(W, H, from_row, from_col, 'NW')
  if not b then return end
  to_row = to_row or 2
  to_col = to_col or math.floor(vim.o.columns * 0.75)
  local f, n = 0, 30
  local timer = uv.new_timer()
  timer:start(0, every(35), vim.schedule_wrap(function()
    f = f + 1
    if not api.nvim_win_is_valid(win) then timer:stop(); timer:close(); return end
    local t
    if f <= 12 then t = f / 12 elseif f <= 18 then t = 1 else t = 1 - (f - 18) / 12 end
    local e = t * t * (3 - 2 * t)
    local row = from_row + (to_row - from_row) * e - math.sin(e * math.pi) * 3
    local col = from_col + (to_col - from_col) * e
    pcall(api.nvim_win_set_config, win, { relative = 'editor', anchor = 'NW', row = math.floor(row), col = math.floor(col) })
    local c = canvas(W, H)
    if f > 12 and f <= 18 then
      weapon(c, W, H * 2, 0, 0.6)
      local r = (f - 12) * 1.4
      for i = 0, 11 do
        local a = i / 12 * 2 * math.pi
        c.dot(W + math.cos(a) * r, H * 2 + math.sin(a) * r * 0.7)
      end
    else
      weapon(c, W, H * 2, f * 0.7, 0.6)
    end
    show(b, c.lines())
    if f >= n then timer:stop(); timer:close(); close(win) end
  end))
end

-- The answer is carved in, a little at a time (LOW: all at once). Never more than ~1.5 s.
function S.carve(buf, text, done)
  local all_lines = vim.split(text, '\n', { plain = true })
  if not can('carve') or #text < 40 then
    api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)
    return done and done()
  end
  local total, shown = #text, 0
  local step = math.max(8, math.floor(total / 90))
  local timer = uv.new_timer()
  timer:start(0, 16, vim.schedule_wrap(function()
    if not api.nvim_buf_is_valid(buf) then timer:stop(); timer:close(); return end
    shown = math.min(total, shown + step)
    local part = text:sub(1, shown)
    -- don't cut a letter in half (Unicode letters are several bytes)
    while #part > 0 and part:byte(#part) >= 0x80 and part:byte(#part) < 0xC0 do part = part:sub(1, -2) end
    local lines = vim.split(part, '\n', { plain = true })
    if shown < total then lines[#lines] = lines[#lines] .. '▌' end
    pcall(api.nvim_buf_set_lines, buf, 0, -1, false, lines)
    if shown >= total then
      timer:stop(); timer:close()
      pcall(api.nvim_buf_set_lines, buf, 0, -1, false, all_lines)
      if done then done() end
    end
  end))
end

-------------------------------------------------------------------------------
-- Find and replace: a tap, and the words on screen light up one after another
-------------------------------------------------------------------------------
function S.tap()
  sound('tap')
  play('tap', 8, 4, 8, 35, function(c, f, W, H)
    local a = (f <= 3) and (-0.6 + f * 0.5) or (0.9 - (f - 3) * 0.18)
    weapon(c, W - 2, H * 3, a, 0.55)
    if f == 4 or f == 5 then for k = 0, 3 do c.dot(W + 4 + k, H * 3 + 3 - (k % 2) * 2) end end
  end)
end

local flash_ns = api.nvim_create_namespace('golem_flash')

-- Light up the matches of a search pattern on screen, one by one.
local function light_up(pat, gap)
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  local ok, re = pcall(vim.regex, pat)
  if not ok or not re then return end
  local top, bot = fn.line('w0'), fn.line('w$')
  local hits = {}
  for l = top, bot do
    local start = 0
    local line = api.nvim_buf_get_lines(buf, l - 1, l, false)[1] or ''
    while #hits < 40 and start < #line do
      local s, e = re:match_line(buf, l - 1, start)
      if not s then break end
      if e == s then e = s + 1 end
      hits[#hits + 1] = { l - 1, start + s, start + e }
      start = start + e
    end
  end
  if #hits == 0 then return end
  local i = 0
  local timer = uv.new_timer()
  timer:start(0, gap, vim.schedule_wrap(function()
    if not api.nvim_buf_is_valid(buf) then timer:stop(); timer:close(); return end
    api.nvim_buf_clear_namespace(buf, flash_ns, 0, -1)
    i = i + 1
    if i > #hits then
      timer:stop(); timer:close()
      return
    end
    local h = hits[i]
    pcall(api.nvim_buf_set_extmark, buf, flash_ns, h[1], h[2], { end_col = h[3], hl_group = 'GolemFlash', priority = 300 })
  end))
  local _ = win
end

function S.sweep(pat)
  if can('sweep') then light_up(pat, 45) end
end

function S.slam(times, new_text)
  times = math.max(1, math.min(3, times or 1))
  local per = 8
  play('slam', 12, 5, per * times, 32, function(c, f, W, H)
    local k = (f - 1) % per + 1
    local a = (k <= 4) and (-1.8 + k * 0.85) or 1.4
    weapon(c, W - 6, H * 3, a, 0.7)
    if k == 5 then sound('thud') end
    if k > 4 then
      local r = (k - 4) * 1.6
      for i = 0, 7 do
        local ang = -math.pi + i / 7 * math.pi
        c.dot(W + 5 + math.cos(ang) * r, H * 3 + 2 + math.sin(ang) * r * 0.6)
      end
    end
  end)
  if new_text and new_text ~= '' and can('hammer') then
    light_up('\\V' .. fn.escape(new_text, '\\'), 60) -- each new word flashes where it landed
  end
end

-------------------------------------------------------------------------------
-- Undo and redo: it spins backwards or forwards
-------------------------------------------------------------------------------
function S.rewind(dir)
  play('rewind', 8, 4, 9, 30, function(c, f, W, H)
    weapon(c, W, H * 2, (dir or -1) * f * 0.7, 0.55)
    for k = 1, 3 do
      local a = (dir or -1) * (f * 0.7 - k * 0.5)
      c.dot(W + math.sin(a) * 6, H * 2 - math.cos(a) * 6)
    end
  end)
end

-------------------------------------------------------------------------------
-- Lines deleted: they shatter into motes that fall away
-------------------------------------------------------------------------------
function S.shatter(count)
  if not can('shatter') then return end
  local win = api.nvim_get_current_win()
  local pos = fn.win_screenpos(win)
  local row = pos[1] - 1 + fn.winline() - 1
  local width = math.min(api.nvim_win_get_width(win), 80)
  local W, H = width, 4
  local bits = {}
  for i = 1, motes(math.min(60, 14 + count * 10)) do
    bits[i] = { x = math.random(0, W * 2 - 1), y = math.random(0, 3), vx = (math.random() - 0.5) * 1.2, vy = math.random() * -1.5 }
  end
  play('shatter', W, H, 14, 35, function(c, f)
    for _, m in ipairs(bits) do
      local x = m.x + m.vx * f
      local y = m.y + m.vy * f + 0.35 * f * f
      if (m.x + f) % 7 ~= 0 or f < 9 then c.dot(x, y) end
    end
  end, row, pos[2] - 1, nil, 'NW')
end

-------------------------------------------------------------------------------
-- Closing: it flies to the middle, shrinking, and the motes spiral in
-------------------------------------------------------------------------------
function S.farewell(done)
  if not can('farewell') then return done and done() end
  local W, H = 16, 8
  local fr, fc = corner_row() - H, corner_col() - W
  local b, win = float(W, H, fr, fc, 'NW')
  if not b then return done and done() end
  local f, n = 0, 16
  local tr, tc = math.floor((vim.o.lines - H) / 2), math.floor((vim.o.columns - W) / 2)
  local timer = uv.new_timer()
  timer:start(0, every(35), vim.schedule_wrap(function()
    f = f + 1
    local t = f / n
    local e = t * t * (3 - 2 * t)
    pcall(api.nvim_win_set_config, win, { relative = 'editor', anchor = 'NW', row = math.floor(fr + (tr - fr) * e), col = math.floor(fc + (tc - fc) * e) })
    local c = canvas(W, H)
    if f <= 11 then weapon(c, W, H * 2, f * 0.6, 0.9 - f * 0.06) end
    for i = 0, 11 do
      local a = i / 12 * 2 * math.pi + f * 0.35
      local r = math.max(0, 14 - f * 0.9)
      c.dot(W + math.cos(a) * r, H * 2 + math.sin(a) * r * 0.7)
    end
    show(b, c.lines())
    if f >= n then
      timer:stop(); timer:close()
      close(win)
      if done then done() end
    end
  end))
end

-------------------------------------------------------------------------------
-- Start screen: it flies in along an arc, lands, then floats there slowly turning
-------------------------------------------------------------------------------
function S.fly(to_row, to_col, on_done)
  if not can('fly') then return on_done and on_done() end
  local W, H = 12, 6
  local b, win = float(W, H, 0, 0, 'NW')
  if not b then return end
  sound('whoosh')
  local from_row, from_col = math.floor(vim.o.lines * 0.15), 0
  local f, frames = 0, 26
  local timer = uv.new_timer()
  timer:start(0, every(40), vim.schedule_wrap(function()
    f = f + 1
    if not api.nvim_win_is_valid(win) then timer:stop(); timer:close(); return end
    local t = math.min(1, f / 20)
    local e = 1 - (1 - t) ^ 2
    local row = from_row + (to_row - H / 2 - from_row) * e - math.sin(t * math.pi) * vim.o.lines * 0.12
    local col = from_col + (to_col - W / 2 - from_col) * e
    pcall(api.nvim_win_set_config, win, { relative = 'editor', anchor = 'NW', row = math.floor(row), col = math.floor(col) })
    local c = canvas(W, H)
    if f <= 20 then
      weapon(c, W, H * 2, f * 0.55, 0.95)
      for k = 1, 4 do c.dot(math.max(0, W - k * 3), H * 2 + (k % 2) * 2) end
    else
      if f == 21 then sound('thud') end
      weapon(c, W, H * 2, 0, 0.95)
      local k = f - 20
      for a = 0, 5 do
        local ang = a / 6 * 2 * math.pi
        c.dot(W + math.cos(ang) * k * 2.2, H * 2 + math.sin(ang) * k * 1.6)
      end
    end
    show(b, c.lines())
    if f >= frames then
      timer:stop(); timer:close()
      close(win)
      if on_done then on_done() end
    end
  end))
end

function S.hover(b, row, col)
  if not can('hover') then return end
  local W, H = 10, 7
  local fb, win = float(W, H, row - math.floor(H / 2), col - math.floor(W / 2), 'NW')
  if not fb then return end
  local t = 0
  local timer = uv.new_timer()
  local function stop()
    if timer then timer:stop(); timer:close(); timer = nil end
    close(win)
  end
  timer:start(0, every(110), vim.schedule_wrap(function()
    if not timer then return end
    if not api.nvim_buf_is_valid(b) or api.nvim_get_current_buf() ~= b or not api.nvim_win_is_valid(win) then
      return stop()
    end
    t = t + 1
    local c = canvas(W, H)
    weapon(c, W, H * 2 + math.sin(t * 0.25) * 1.5, math.sin(t * 0.08) * 0.5, 0.95)
    for k = 0, 2 do
      local a = t * 0.15 + k * 2.1
      c.dot(W + math.cos(a) * (W - 1), H * 2 + math.sin(a) * (H * 2 - 2))
    end
    show(fb, c.lines())
  end))
  api.nvim_create_autocmd({ 'BufLeave', 'BufWipeout' }, { buffer = b, once = true, callback = stop })
end

-------------------------------------------------------------------------------
-- Rest, and typing streaks: both follow your keys (vim.on_key is told of every key)
-------------------------------------------------------------------------------
local last_key = uv.now()
local resting = nil -- { win, buf, timer } while it rests
local streak, streak_timer, glow_step = 0, nil, -1

local function set_glow(level)
  local step = math.floor(level * 6 + 0.5)
  if step == glow_step then return end
  glow_step = step
  api.nvim_set_hl(0, 'CursorLine', { bg = mix(P.shade, P.mist, 0.06 + 0.05 * step) })
  api.nvim_set_hl(0, 'CursorLineNr', { fg = mix(P.pale, '#ffffff', 0.15 * step), bold = true })
end

local function wake()
  if not resting then return end
  local r = resting
  resting = nil
  if r.timer then r.timer:stop(); r.timer:close() end
  local f = 0
  local t = uv.new_timer()
  t:start(0, every(35), vim.schedule_wrap(function()
    f = f + 1
    local c = canvas(r.W, r.H)
    weapon(c, r.W, r.H * 2 + 6 - f * 1.4, 1.3 - f * 0.13, 0.8) -- lifts and turns upright
    show(r.buf, c.lines())
    if f >= 10 then t:stop(); t:close(); close(r.win) end
  end))
end

local function rest()
  if resting or not can('rest') or busy_on or not S.is_text() then return end
  local W, H = 14, 5
  local b, win = float(W, H, corner_row(), corner_col())
  if not b then return end
  local dust = {}
  for i = 1, motes(16) do dust[i] = { x = math.random(0, W * 2 - 1), y = -math.random(0, 12) } end
  local f = 0
  local timer = uv.new_timer()
  resting = { win = win, buf = b, timer = timer, W = W, H = H }
  timer:start(0, every(250), vim.schedule_wrap(function()
    if not resting or resting.timer ~= timer then return end
    f = f + 1
    local c = canvas(W, H)
    weapon(c, W, H * 2 + 6, 1.3, 0.8) -- leaning, head down on the line
    for _, d in ipairs(dust) do c.dot(d.x, math.min(H * 4 - 1, d.y + f * 0.9)) end
    show(b, c.lines())
    if f >= 30 then timer:stop() end -- the dust has settled: nothing more to draw
  end))
end

local key_ns = api.nvim_create_namespace('golem_keys')
vim.on_key(function(key)
  last_key = uv.now()
  if resting then vim.schedule(wake) end
  if can('streak') and api.nvim_get_mode().mode == 'i' and key and #key == 1 and key:byte() >= 32 then
    streak = math.min(60, streak + 1)
    if not streak_timer then
      streak_timer = uv.new_timer()
      streak_timer:start(250, 250, vim.schedule_wrap(function()
        streak = math.max(0, streak - 3)
        set_glow(streak / 60)
        if streak == 0 and streak_timer then
          streak_timer:stop(); streak_timer:close(); streak_timer = nil
        end
      end))
    end
  end
end, key_ns)

-- Every 5 s: rest after 3 quiet minutes; keep the night light right.
local watch = uv.new_timer()
watch:start(5000, 5000, vim.schedule_wrap(function()
  light()
  if not resting and uv.now() - last_key > 180000 then rest() end
end))

-------------------------------------------------------------------------------
-- Company: while you write, a small gada floats in the top-right corner (LOW and up),
-- breathing slowly; it steps aside while it rests or works elsewhere.
-------------------------------------------------------------------------------
NEED.company = 1
local comp = { t = 0 }
local CW, CH = 8, 7
local function comp_hide()
  close(comp.win)
  comp.win, comp.buf = nil, nil
end
local comp_timer = uv.new_timer()
comp_timer:start(1500, 240, vim.schedule_wrap(function()
  local here = can('company') and not resting and not busy_on and S.is_text() and vim.o.columns > 50
      and api.nvim_get_mode().mode ~= 'c'
  if not here then return comp_hide() end
  if not (comp.win and api.nvim_win_is_valid(comp.win)) then
    comp.buf, comp.win = float(CW, CH, 0, vim.o.columns, 'NE')
    if not comp.buf then return end
  end
  comp.t = comp.t + 1
  local c = canvas(CW, CH)
  weapon(c, CW, CH * 2 + math.sin(comp.t * 0.12) * 1.2, 0.35 + math.sin(comp.t * 0.05) * 0.15, 0.75)
  show(comp.buf, c.lines())
end))

-------------------------------------------------------------------------------
-- Relics: small things found along the way, kept in ~/.local/share/golem-edit/relics.json
-------------------------------------------------------------------------------
local RELICS = {
  { 'first_light', 'First Light', 'your first save' },
  { 'dawn', 'Seven Dawns', 'saved something on 7 different days' },
  { 'night_owl', 'Night Owl', 'saved after midnight' },
  { 'hundred', 'A Hundred Lines', 'wrote 100 lines' },
  { 'scribe', 'Scribe', 'wrote 1,000 lines' },
  { 'spark', 'Spark', 'your first program run' },
  { 'steady', 'Steady Hand', '10 programs ran without an error' },
  { 'phoenix', 'Phoenix', 'a program failed, then ran fine' },
  { 'oracle', 'Oracle', 'the first answer from the AI' },
  { 'tongues', 'Many Tongues', 'code changed into another language' },
  { 'mirror', 'Mirror', 'your first live preview' },
  { 'etching', 'Etching', 'your first picture of code' },
  { 'hammer', 'Hammer of Many', 'replaced 20 or more words at once' },
  { 'tamer', 'Tamer of Chaos', 'tidied a file that needed it' },
  { 'architect', 'Architect', 'saw your code as a flowchart' },
  { 'builder', 'Builder', 'built a program from blocks' },
}
local relic_file = box .. '/relics.json'
local R = { found = {}, stats = { lines = 0, runs_ok = 0, days = {} } }
do
  local f = io.open(relic_file, 'r')
  if f then
    local ok, data = pcall(vim.json.decode, f:read('*a'))
    f:close()
    if ok and type(data) == 'table' then
      R.found = type(data.found) == 'table' and data.found or {}
      R.stats = type(data.stats) == 'table' and data.stats or R.stats
      R.stats.days = type(R.stats.days) == 'table' and R.stats.days or {}
      R.stats.lines = tonumber(R.stats.lines) or 0
      R.stats.runs_ok = tonumber(R.stats.runs_ok) or 0
    end
  end
end

local function keep_relics()
  fn.mkdir(box, 'p')
  pcall(fn.writefile, { vim.json.encode(R) }, relic_file)
end

function S.relic(id)
  if R.found[id] then return end
  local name, why
  for _, r in ipairs(RELICS) do if r[1] == id then name, why = r[2], r[3] end end
  if not name then return end
  R.found[id] = os.date('%Y-%m-%d')
  keep_relics()
  vim.defer_fn(function()
    if lvl() > 0 then sound('chime') end
    S.say('RELIC FOUND:  ' .. name:upper() .. '  ·  ' .. why .. '  ·  ALT+G, CODEX')
    if can('raise') then S.raise() end
  end, 700)
end

-- Today's counts, for the dashboard
local function today()
  local d = os.date('%Y-%m-%d')
  if type(R.stats.today) ~= 'table' or R.stats.today.date ~= d then
    R.stats.today = { date = d, lines = 0, saves = 0 }
  end
  return R.stats.today
end

function S.relic_info()
  local found, total, hint = 0, #RELICS, nil
  for _, r in ipairs(RELICS) do
    if R.found[r[1]] then found = found + 1 elseif not hint then hint = r[3] end
  end
  return { found = found, total = total, next = hint, today = today(), lines = R.stats.lines,
    runs_ok = R.stats.runs_ok }
end

-- What the rest of the editor reports
function S.saved_event()
  local t = today()
  t.saves = t.saves + 1
  if not R.found.first_light then S.relic('first_light') end
  local today = os.date('%Y-%m-%d')
  if not R.stats.days[today] then
    R.stats.days[today] = true
    local n = 0
    for _ in pairs(R.stats.days) do n = n + 1 end
    if n >= 7 then S.relic('dawn') end
    keep_relics()
  end
  local h = os.date('*t').hour
  if h < 4 then S.relic('night_owl') end
end

local last_run_failed = false
function S.run_event(ok)
  S.relic('spark')
  if ok then
    R.stats.runs_ok = R.stats.runs_ok + 1
    if R.stats.runs_ok >= 10 then S.relic('steady') end
    if last_run_failed then S.relic('phoenix') end
    keep_relics()
  end
  last_run_failed = not ok
end

-- Lines added (relics) and lines deleted (shatter): watch each text buffer's length.
api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter', 'BufNewFile' }, {
  callback = function(a) vim.b[a.buf].golem_lines = api.nvim_buf_line_count(a.buf) end,
})
api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
  callback = function(a)
    if not S.is_text(a.buf) then return end
    local now = api.nvim_buf_line_count(a.buf)
    local before = vim.b[a.buf].golem_lines or now
    vim.b[a.buf].golem_lines = now
    local d = now - before
    if d > 0 and d < 200 then -- typed or pasted (a huge jump is a whole file loaded)
      R.stats.lines = R.stats.lines + d
      local t = today()
      t.lines = t.lines + d
      if R.stats.lines >= 100 then S.relic('hundred') end
      if R.stats.lines >= 1000 then S.relic('scribe') end
    elseif d < 0 and not vim.b[a.buf].golem_tidying then
      S.shatter(-d)
    end
  end,
})
api.nvim_create_autocmd('VimLeavePre', { callback = keep_relics })

-- The codex: every relic, found or still hidden.
local function codex()
  local lines = { '', '   C O D E X   ·   R E L I C S                                  Esc = back', '' }
  local found = 0
  for _, r in ipairs(RELICS) do
    if R.found[r[1]] then
      found = found + 1
      lines[#lines + 1] = string.format('   ◆  %-18s %s   (%s)', r[2], r[3], R.found[r[1]])
    else
      lines[#lines + 1] = string.format('   ◇  %-18s %s', '? ? ?', r[3])
    end
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = string.format('   %d of %d found  ·  lines written: %d  ·  programs run fine: %d', found, #RELICS,
    R.stats.lines, R.stats.runs_ok)
  local b = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  vim.bo[b].bufhidden = 'wipe'
  vim.b[b].golem_guide = true
  vim.b[b].golem_codex = true
  api.nvim_set_current_buf(b)
  vim.wo.number = false
  vim.cmd('stopinsert')
  for _, k in ipairs({ '<Esc>', 'q', '<C-q>', '<M-g>' }) do
    vim.keymap.set('n', k, function()
      if fn.bufexists(fn.bufnr('#')) == 1 and fn.bufnr('#') ~= b then vim.cmd('buffer #') else _G.GolemStart() end
    end, { buffer = b, nowait = true })
  end
end

-------------------------------------------------------------------------------
-- Alt+G: the settings
-------------------------------------------------------------------------------
local function choose(prompt, items, label, apply)
  vim.ui.select(items, { prompt = prompt, format_item = label }, function(choice)
    if choice then apply(choice) end
  end)
end

local function settings()
  local L = { off = 'OFF', low = 'LOW', medium = 'MEDIUM', high = 'HIGH' }
  local items = {
    { 'level', 'Animations:  ' .. L[cfg.level] .. '   (HIGH / MEDIUM / LOW / OFF)' },
    { 'form', 'Weapon:  ' .. cfg.form:upper() .. '   (gada / vajra / trishul)' },
    { 'sound', 'Sound:  ' .. cfg.sound:upper() },
    { 'codex', 'Codex: the relics you have found' },
  }
  if S.writing then
    for _, x in ipairs(S.writing.items()) do items[#items + 1] = x end
  end
  choose('SETTINGS', items, function(i) return i[2] end, function(i)
    if i[3] then return i[3]() end -- spell check, suggestions (writing.lua)
    if i[1] == 'level' then
      choose('ANIMATIONS', { 'high', 'medium', 'low', 'off' }, function(x)
        return ({
          high = 'HIGH    everything: streak glow, flashes, hit-stop, the most motes',
          medium = 'MEDIUM  every animation, fewer motes, no glow or flashes',
          low = 'LOW     only working, save, failure and relics; fewer frames',
          off = 'OFF     no animations and no sounds',
        })[x]
      end, function(x)
        cfg.level = x
        save_conf()
        set_glow(0)
        S.say('ANIMATIONS: ' .. x:upper())
        if x ~= 'off' then vim.defer_fn(function() S.strike(3) end, 150) end
      end)
    elseif i[1] == 'form' then
      choose('WEAPON', { 'gada', 'vajra', 'trishul' }, function(x)
        return ({ gada = 'Gada     the mace', vajra = 'Vajra    the thunderbolt', trishul = 'Trishul  the trident' })[x]
      end, function(x)
        cfg.form = x
        save_conf()
        S.say('WEAPON: ' .. x:upper())
        vim.defer_fn(function() S.raise() end, 150)
      end)
    elseif i[1] == 'sound' then
      cfg.sound = cfg.sound == 'on' and 'off' or 'on'
      save_conf()
      S.say('SOUND: ' .. cfg.sound:upper())
      sound('tap')
    else
      codex()
    end
  end)
end

S.map(S.all, '<M-g>', settings)

-- For the dashboard: the gada's motes as points, and a canvas to draw them on.
function S.gada_points(cx, cy, a, s)
  local pts, seen = {}, {}
  local ca, sa = math.cos(a), math.sin(a)
  FORMS.gada(function(x, y)
    local px = math.floor(cx + (x * ca + y * sa) * s + 0.5)
    local py = math.floor(cy - (y * ca - x * sa) * s + 0.5)
    for dx = 0, (s > 1.5 and 1 or 0) do -- big: twice as thick, so it reads as solid metal
      local k = (px + dx) * 8192 + py
      if not seen[k] then seen[k] = true; pts[#pts + 1] = { x = px + dx, y = py } end
    end
  end)
  return pts
end
S.canvas = canvas
S.gada = { can = can, settings = settings, codex = codex }
