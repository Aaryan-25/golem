-- Golem editor: the gada (the Indian mace), drawn with fine Braille motes.
--
--   Golem.busy(label)   a gada turning in the bottom-right corner while something works
--                       (the AI answering, code running, the preview opening). Returns stop().
--   Golem.strike()      the gada swings down and strikes when you save with Ctrl+S; motes burst
--   Golem.fly()         on the start screen the gada flies in along an arc and strikes the sigil
--   Golem.hover()       then it floats over the sigil, slowly turning, while the start screen is open
--   Golem.shake()       something failed (a save, a run, the AI): the gada trembles, motes fall
--   Golem.raise()       code ran fine: the gada rises upright inside a ring of light
--   Golem.throw(r, c)   the AI answered: the gada is thrown from the corner to the answer and back
--   Golem.tap()         each find (Ctrl+F, F3): a quick tap
--   Golem.slam(n)       replace: one slam per change, up to three
--   Golem.farewell(f)   closing the editor: a last spin and fade, then f()
--   Alt+G               all gada animations off / on (remembered)
--
-- Everything is text in a tiny window above your work: no images, almost no processor use.

local api = vim.api
local uv = vim.uv or vim.loop
local S = _G.Golem

local BITS = { [0] = { 0x01, 0x02, 0x04, 0x40 }, [1] = { 0x08, 0x10, 0x20, 0x80 } }
local function braille(mask)
  local cp = 0x2800 + mask
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

-- A canvas of w x h letter cells = 2w x 4h motes.
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

-- The gada: a round, fluted head with a small crown, a long handle and a knob at its end.
-- Drawn around (cx, cy), turned by angle a (0 = head up), size s (1 = about 20 motes long).
local function gada(c, cx, cy, a, s)
  s = s or 1
  local ca, sa = math.cos(a), math.sin(a)
  local function put(x, y) -- x across, y along the handle (head at +y)
    c.dot(cx + (x * ca + y * sa) * s, cy - (y * ca - x * sa) * s)
  end
  for y = -9, 2, 0.5 do put(0, y) end                      -- handle
  for _, d in ipairs({ { -1, -9 }, { 1, -9 }, { 0, -10 }, { 0, -8.5 } }) do put(d[1], d[2]) end -- knob
  put(-1, 1); put(1, 1)                                     -- collar
  for y = -4, 4, 0.5 do                                     -- the head, fluted
    for x = -4, 4, 0.5 do
      local r = x * x + y * y
      if r <= 16 and (r >= 9 or math.abs(x) < 0.6 or math.abs(y) < 0.6) then put(x, y + 6) end
    end
  end
  for y = 10.5, 12, 0.5 do put(0, y) end                    -- crown
  put(-1, 10.5); put(1, 10.5)
end

local function float(w, h, row, col, anchor)
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'wipe'
  local ok, win = pcall(api.nvim_open_win, b, false, {
    relative = 'editor', anchor = anchor or 'SE', row = row, col = col, width = w, height = h,
    style = 'minimal', focusable = false, zindex = 200, noautocmd = true,
  })
  if not ok then return nil end
  vim.wo[win].winhighlight = 'Normal:GolemMace,NormalFloat:GolemMace'
  vim.wo[win].winblend = 100 -- see-through: only the gada's motes cover what is below
  return b, win
end

local function show(b, lines)
  if api.nvim_buf_is_valid(b) then api.nvim_buf_set_lines(b, 0, -1, false, lines) end
end

local function close(win)
  if win and api.nvim_win_is_valid(win) then pcall(api.nvim_win_close, win, true) end
end

api.nvim_set_hl(0, 'GolemMace', { fg = S.P.pale, bg = 'NONE' })

-- Alt+G turns every gada animation off or on; the choice is kept in this small file.
local off_file = vim.env.HOME .. '/.local/share/golem-edit/gada-off'
local function on() return vim.fn.filereadable(off_file) == 0 end
S.map(S.all, '<M-g>', function()
  if on() then
    vim.fn.mkdir(vim.fn.fnamemodify(off_file, ':h'), 'p')
    vim.fn.writefile({}, off_file)
    S.say('GADA ANIMATIONS OFF  ·  ALT+G BRINGS THEM BACK')
  else
    os.remove(off_file)
    S.say('GADA ANIMATIONS ON')
    S.raise()
  end
end)

-------------------------------------------------------------------------------
-- Busy: the gada turns, steady and slow, until stop() is called.
-------------------------------------------------------------------------------
local busy_count, busy_win, busy_timer = 0, nil, nil

function S.busy()
  if not on() then return function() end end
  busy_count = busy_count + 1
  if not busy_timer then
    local W, H = 10, 5
    local b, win = float(W, H, vim.o.lines - 3, vim.o.columns - 2)
    if not b then return function() end end
    busy_win = win
    local t = 0
    busy_timer = uv.new_timer()
    busy_timer:start(0, 70, vim.schedule_wrap(function()
      if not busy_timer then return end
      t = t + 1
      local c = canvas(W, H)
      gada(c, W, H * 2, t * 0.3, 0.75)
      -- three motes circling the head
      for k = 0, 2 do
        local a = t * 0.2 + k * 2.1
        c.dot(W + math.cos(a) * (W - 2), H * 2 + math.sin(a) * (H * 2 - 1))
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
      vim.schedule(function() close(busy_win); busy_win = nil end)
    end
  end
end

-------------------------------------------------------------------------------
-- Strike: when you save, the gada swings down onto the bottom line and motes burst.
-------------------------------------------------------------------------------
local striking = false

function S.strike()
  if striking or busy_timer or not on() then return end
  striking = true
  local W, H = 14, 6
  local b, win = float(W, H, vim.o.lines - 3, vim.o.columns - 2)
  if not b then striking = false; return end
  local sparks = {}
  for i = 1, 14 do sparks[i] = { a = math.random() * math.pi - math.pi, v = 1.5 + math.random() * 2.5 } end
  local f, frames = 0, 16
  local timer = uv.new_timer()
  timer:start(0, 33, vim.schedule_wrap(function()
    f = f + 1
    local c = canvas(W, H)
    local cx, cy = W + 4, H * 4 - 2 -- the strike point, low and to the right
    if f <= 7 then -- the swing: raised behind, then down hard
      local t = f / 7
      local a = -2.4 + (2.4 + 1.45) * (t * t)
      gada(c, cx - 12, cy - 1, a, 0.85)
    else -- the hit: the head rests, motes burst out and fade
      gada(c, cx - 12, cy - 1, 1.45 + math.sin(f) * 0.04, 0.85)
      local k = f - 7
      for _, s in ipairs(sparks) do
        if k < 8 then c.dot(cx + 3 + math.cos(s.a) * s.v * k, cy + math.sin(s.a) * s.v * k * 0.6) end
      end
    end
    show(b, c.lines())
    if f >= frames then
      timer:stop(); timer:close()
      close(win)
      striking = false
    end
  end))
end

-------------------------------------------------------------------------------
-- Fly: across the start screen in an arc, turning, then a strike at the given cell.
-------------------------------------------------------------------------------
function S.fly(to_row, to_col, on_done)
  if not on() then return on_done and on_done() end
  local W, H = 12, 6
  local b, win = float(W, H, 0, 0, 'NW')
  if not b then return end
  local from_row, from_col = math.floor(vim.o.lines * 0.15), 0
  local f, frames = 0, 26
  local timer = uv.new_timer()
  timer:start(0, 40, vim.schedule_wrap(function()
    f = f + 1
    if not api.nvim_win_is_valid(win) then timer:stop(); timer:close(); return end
    local t = math.min(1, f / 20)
    local e = 1 - (1 - t) ^ 2
    local row = from_row + (to_row - H / 2 - from_row) * e - math.sin(t * math.pi) * vim.o.lines * 0.12
    local col = from_col + (to_col - W / 2 - from_col) * e
    pcall(api.nvim_win_set_config, win, { relative = 'editor', row = math.floor(row), col = math.floor(col) })
    local c = canvas(W, H)
    if f <= 20 then
      gada(c, W, H * 2, f * 0.55, 0.95) -- turning in flight
      for k = 1, 4 do c.dot(math.max(0, W - k * 3), H * 2 + (k % 2) * 2) end -- a short trail
    else
      gada(c, W, H * 2, 0, 0.95) -- upright, landed
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

-------------------------------------------------------------------------------
-- A short animation in a small corner window: draw(c, f, W, H) for frames 1..n.
-------------------------------------------------------------------------------
local playing = {}

local function play(name, W, H, n, every, draw, row, col, done)
  if not on() or playing[name] or busy_timer then return done and done() end
  playing[name] = true
  local b, win = float(W, H, row or vim.o.lines - 3, col or vim.o.columns - 2)
  if not b then playing[name] = nil; return done and done() end
  local f = 0
  local timer = uv.new_timer()
  timer:start(0, every, vim.schedule_wrap(function()
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

-- Something failed: the gada trembles, tilts down, and its motes fall away.
function S.shake()
  play('shake', 10, 5, 18, 40, function(c, f, W, H)
    local jit = (f <= 10) and ((f % 2 == 0) and 1.2 or -1.2) or 0
    local a = (f <= 10) and 0.25 * jit or math.min(0.9, (f - 10) * 0.12)
    gada(c, W + jit, H * 2 + 1, a, 0.75)
    if f > 8 then
      for k = 0, 5 do c.dot(W - 5 + k * 2, H * 2 - 6 + (f - 8) * (1 + k % 3) * 0.8) end
    end
  end)
end

-- Code ran fine: the gada rises upright, a ring of light opens around it.
function S.raise()
  play('raise', 12, 6, 20, 40, function(c, f, W, H)
    local t = math.min(1, f / 8)
    local e = 1 - (1 - t) ^ 3
    gada(c, W, H * 2 + (1 - e) * 10, (1 - e) * 1.6, 0.8)
    if f > 6 then
      local r = (f - 6) * 1.3
      for i = 0, 23 do
        local a = i / 24 * 2 * math.pi
        if (i + f) % 3 ~= 0 then c.dot(W + math.cos(a) * r, H * 2 - 3 + math.sin(a) * r * 0.8) end
      end
    end
  end)
end

-- The AI answered: thrown from the corner to the answer, a ring where it lands, then home.
function S.throw(to_row, to_col)
  if not on() or busy_timer then return end
  local W, H = 8, 4
  local b, win = float(W, H, vim.o.lines - 3, vim.o.columns - 2)
  if not b then return end
  local from_row, from_col = vim.o.lines - 3 - H, vim.o.columns - 2 - W
  to_row = to_row or 2
  to_col = to_col or math.floor(vim.o.columns * 0.75)
  local f, n = 0, 30
  local timer = uv.new_timer()
  timer:start(0, 35, vim.schedule_wrap(function()
    f = f + 1
    if not api.nvim_win_is_valid(win) then timer:stop(); timer:close(); return end
    -- out (1..12), the landing (13..18), back (19..30): like a thrown mace that returns
    local t
    if f <= 12 then t = f / 12 elseif f <= 18 then t = 1 else t = 1 - (f - 18) / 12 end
    local e = t * t * (3 - 2 * t)
    local row = from_row + (to_row - from_row) * e - math.sin(e * math.pi) * 3
    local col = from_col + (to_col - from_col) * e
    pcall(api.nvim_win_set_config, win, { relative = 'editor', row = math.floor(row), col = math.floor(col) })
    local c = canvas(W, H)
    if f > 12 and f <= 18 then
      gada(c, W, H * 2, 0, 0.6)
      local r = (f - 12) * 1.4
      for i = 0, 11 do
        local a = i / 12 * 2 * math.pi
        c.dot(W + math.cos(a) * r, H * 2 + math.sin(a) * r * 0.7)
      end
    else
      gada(c, W, H * 2, f * 0.7, 0.6)
    end
    show(b, c.lines())
    if f >= n then
      timer:stop(); timer:close()
      close(win)
    end
  end))
end

-- Each find: a quick tap.
function S.tap()
  play('tap', 8, 4, 8, 35, function(c, f, W, H)
    local a = (f <= 3) and (-0.6 + f * 0.5) or (0.9 - (f - 3) * 0.18)
    gada(c, W - 2, H * 3, a, 0.55)
    if f == 4 or f == 5 then for k = 0, 3 do c.dot(W + 4 + k, H * 3 + 3 - (k % 2) * 2) end end
  end)
end

-- Replace: one slam per change (up to three), each with a small burst.
function S.slam(times)
  times = math.max(1, math.min(3, times or 1))
  local per = 8
  play('slam', 12, 5, per * times, 32, function(c, f, W, H)
    local k = (f - 1) % per + 1
    local a = (k <= 4) and (-1.8 + k * 0.85) or 1.4
    gada(c, W - 6, H * 3, a, 0.7)
    if k > 4 then
      local r = (k - 4) * 1.6
      for i = 0, 7 do
        local ang = -math.pi + i / 7 * math.pi
        c.dot(W + 5 + math.cos(ang) * r, H * 3 + 2 + math.sin(ang) * r * 0.6)
      end
    end
  end)
end

-- Closing: a last spin, the motes scatter, then the editor closes.
function S.farewell(done)
  play('farewell', 12, 6, 16, 35, function(c, f, W, H)
    if f <= 10 then
      gada(c, W, H * 2, f * 0.6, 0.8 - f * 0.03)
    end
    if f > 6 then
      for i = 0, 15 do
        local a = i / 16 * 2 * math.pi + f * 0.1
        local r = (f - 6) * 1.8
        if (i + f) % 2 == 0 then c.dot(W + math.cos(a) * r, H * 2 + math.sin(a) * r * 0.7) end
      end
    end
  end, math.floor(vim.o.lines / 2) + 3, math.floor(vim.o.columns / 2) + 6, done)
end

-- The start screen: after it lands, the gada floats over the sigil, slowly turning.
-- It stops as soon as you leave the start screen (no work done while you type).
function S.hover(b, row, col)
  if not on() then return end
  local W, H = 10, 7
  local fb, win = float(W, H, row - math.floor(H / 2), col - math.floor(W / 2), 'NW')
  if not fb then return end
  local t = 0
  local timer = uv.new_timer()
  local function stop()
    if timer then timer:stop(); timer:close(); timer = nil end
    close(win)
  end
  timer:start(0, 110, vim.schedule_wrap(function()
    if not timer then return end
    if not api.nvim_buf_is_valid(b) or api.nvim_get_current_buf() ~= b or not api.nvim_win_is_valid(win) then
      return stop()
    end
    t = t + 1
    local c = canvas(W, H)
    gada(c, W, H * 2 + math.sin(t * 0.25) * 1.5, math.sin(t * 0.08) * 0.5, 0.95)
    for k = 0, 2 do -- three motes orbiting it
      local a = t * 0.15 + k * 2.1
      c.dot(W + math.cos(a) * (W - 1), H * 2 + math.sin(a) * (H * 2 - 2))
    end
    show(fb, c.lines())
  end))
  api.nvim_create_autocmd({ 'BufLeave', 'BufWipeout' }, { buffer = b, once = true, callback = stop })
end
