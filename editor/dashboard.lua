-- Golem editor: the dashboard (what you see when the editor opens without a file).
--
--   left    a big gada, gathered from drifting motes (LOW / OFF: already there)
--   right   GOLEM · EDITOR, the date and time
--           TODAY    lines written and saves today        RELICS  found, and a hint for the next
--           PINNED   files you pinned with Alt+P           RECENT  files you opened lately
--           1-9 open one of them; R reopens the files you had open last time
--           one letter for each thing: N new, O open, P find, B files, T terminal, K AI,
--           C codex, G settings, H guide, Q close; F1 the list of everything
--   bottom  a pulse: battery, memory, Wi-Fi, the time (looked at every 5 s, only while
--           the dashboard is showing), and a line for the day: from
--           ~/.local/share/golem-edit/daily.txt if you write your own (one per line)

local api, fn = vim.api, vim.fn
local uv = vim.uv or vim.loop
local S = _G.Golem
local tilde = S.tilde
local box = vim.env.HOME .. '/.local/share/golem-edit'
local ns = api.nvim_create_namespace('golem_dashboard')

local DAILY = {
  'Small steps, carved every day, become a temple.',
  'The gada is heavy only until it moves.',
  'Write it badly first. Then make it true.',
  'What you save today, you will not lose tomorrow.',
  'Quiet hands, sharp mind.',
  'Every error is a door you have not opened yet.',
  'Strike once, cleanly.',
  'The night is long; the work is longer; both end.',
  'Read the error. It is trying to help.',
  'One file at a time.',
}

local function daily()
  local lines = DAILY
  local f = box .. '/daily.txt'
  if fn.filereadable(f) == 1 then
    local own = vim.tbl_filter(function(l) return vim.trim(l) ~= '' end, fn.readfile(f))
    if #own > 0 then lines = own end
  end
  return lines[(tonumber(os.date('%j')) % #lines) + 1]
end

-------------------------------------------------------------------------------
-- The pulse: battery, memory, Wi-Fi, time
-------------------------------------------------------------------------------
local function read(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local v = f:read('*a')
  f:close()
  return v
end

local function bar(frac)
  local n = math.max(0, math.min(5, math.floor(frac * 5 + 0.5)))
  return string.rep('█', n) .. string.rep('░', 5 - n)
end

local function pulse()
  local parts = {}
  local bat = fn.glob('/sys/class/power_supply/BAT*', false, true)[1]
  if bat then
    local cap = tonumber(read(bat .. '/capacity') or '')
    local st = vim.trim(read(bat .. '/status') or '')
    if cap then
      parts[#parts + 1] = 'BATTERY ' .. bar(cap / 100) .. ' ' .. cap .. '%' .. (st == 'Charging' and ' ⌁' or '')
    end
  end
  local mem = read('/proc/meminfo') or ''
  local total = tonumber(mem:match('MemTotal:%s+(%d+)'))
  local avail = tonumber(mem:match('MemAvailable:%s+(%d+)'))
  if total and avail then
    local used = total - avail
    parts[#parts + 1] = string.format('MEMORY %s %.1f / %.1f GB', bar(used / total), used / 1048576, total / 1048576)
  end
  local wifi = 'OFF'
  for _, d in ipairs(fn.glob('/sys/class/net/*/wireless', false, true)) do
    local dev = fn.fnamemodify(d, ':h')
    if vim.trim(read(dev .. '/operstate') or '') == 'up' then wifi = 'ON' end
  end
  parts[#parts + 1] = 'WI-FI ' .. wifi
  parts[#parts + 1] = os.date('%H:%M')
  return table.concat(parts, '   ·   ')
end

-------------------------------------------------------------------------------
-- What goes in the lists
-------------------------------------------------------------------------------
local function entries()
  local list, seen = {}, {}
  for _, p in ipairs(S.pinned and S.pinned() or {}) do
    if #list < 9 and not seen[p] then list[#list + 1] = { path = p, pinned = true }; seen[p] = true end
  end
  local pins = #list
  for _, f in ipairs(vim.v.oldfiles or {}) do
    if #list >= 9 then break end
    if not seen[f] and fn.filereadable(f) == 1 and not f:find('/%.cache/') and not f:find('/%.local/share/golem%-edit/') then
      list[#list + 1] = { path = f }
      seen[f] = true
    end
  end
  return list, pins
end

-------------------------------------------------------------------------------
-- Drawing it
-------------------------------------------------------------------------------
-- right-hand lines are lists of { text, highlight } pieces
local function seg(t, g) return { t, g or 'GolemDim' } end

local function right_lines(list, pins, width)
  local info = S.relic_info and S.relic_info() or { found = 0, total = 0, today = { lines = 0, saves = 0 } }
  local L = {}
  local function add(...) L[#L + 1] = { ... } end
  local function cut(t, w) return fn.strdisplaywidth(t) > w and ('…' .. t:sub(-(w - 1))) or t end
  add(seg('G O L E M   ·   E D I T O R', 'GolemBright'))
  add(seg(os.date('%A %d %B  ·  %H:%M')))
  add()
  add(seg('TODAY    ', 'GolemBright'), seg(string.format('%d lines written  ·  %d saves', info.today.lines or 0,
    info.today.saves or 0)))
  add(seg('RELICS   ', 'GolemBright'), seg(string.format('%d / %d', info.found, info.total)),
    seg(info.next and ('  ·  next: ' .. info.next) or '  ·  all found'))
  add()
  if #list > 0 then
    if pins > 0 then add(seg('PINNED', 'GolemBright')) end
    for i, e in ipairs(list) do
      if i == pins + 1 then add(seg('RECENT', 'GolemBright')) end
      add(seg(tostring(i) .. '   ', 'GolemBright'), seg(cut(tilde(e.path), width - 6), 'Normal'))
    end
    add()
  end
  local sess = S.session and S.session() or {}
  if #sess > 0 then
    add(seg('R', 'GolemBright'), seg(string.format('   reopen the files you had open (%d)', #sess)))
  end
  local keys = { { 'N', 'new' }, { 'O', 'open' }, { 'P', 'find' }, { 'B', 'files' }, { 'T', 'terminal' },
    { 'K', 'AI' }, { 'C', 'codex' }, { 'G', 'settings' }, { 'H', 'guide' }, { 'W', 'tour' }, { 'Q', 'close' } }
  local line, used = {}, 0
  for _, k in ipairs(keys) do
    local w = #k[1] + 1 + #k[2] + 4
    if used + w > width and #line > 0 then
      add(unpack(line))
      line, used = {}, 0
    end
    line[#line + 1] = seg(k[1] .. ' ', 'GolemBright')
    line[#line + 1] = seg(k[2] .. '    ')
    used = used + w
  end
  if #line > 0 then add(unpack(line)) end
  return L
end

local function draw(b, t, geo)
  if not api.nvim_buf_is_valid(b) then return end
  local W = geo.W
  local list, pins = entries()
  local rl = right_lines(list, pins, geo.rw)

  -- the gada, its motes moving from the mist (t = 0) to their places (t = 1)
  local c = S.canvas(geo.aw, geo.ah)
  local e = 1 - (1 - t) ^ 3
  for _, p in ipairs(geo.pts) do
    c.dot(p.sx + (p.x - p.sx) * e, p.sy + (p.y - p.sy) * e)
  end
  local art = c.lines()

  local lines, marks = {}, {}
  local rows = math.max(geo.ah, #rl)
  if geo.stacked then
    -- narrow: the gada above, the lists below, both centred
    local pad = string.rep(' ', math.max(0, math.floor((W - geo.aw) / 2)))
    for i = 1, geo.ah do
      lines[#lines + 1] = pad .. art[i]
      marks[#marks + 1] = { #lines - 1, #pad, -1, t < 1 and 'GolemMote' or 'GolemMace' }
    end
    lines[#lines + 1] = ''
    local lp = string.rep(' ', math.max(0, math.floor((W - geo.rw) / 2)))
    geo.title = { #lines + 1, #lp }
    for _, pieces in ipairs(rl) do
      local text, col = lp, #lp
      for _, p in ipairs(pieces) do
        marks[#marks + 1] = { #lines, col, col + #p[1], p[2] }
        text = text .. p[1]
        col = col + #p[1]
      end
      lines[#lines + 1] = text
    end
  else
    local top = geo.top
    for _ = 1, top do lines[#lines + 1] = '' end
    local left = string.rep(' ', geo.left)
    local off = math.max(0, math.floor((rows - #rl) / 2))
    local aoff = math.max(0, math.floor((rows - geo.ah) / 2))
    for r = 1, rows do
      local a = art[r - aoff] or string.rep(' ', geo.aw)
      local text = left .. a .. string.rep(' ', geo.gap)
      marks[#marks + 1] = { #lines, #left, #left + #a, t < 1 and 'GolemMote' or 'GolemMace' }
      local col = #text
      if r - off == 1 then geo.title = { #lines + 1, col } end -- the cursor rests on the title
      for _, p in ipairs(rl[r - off] or {}) do
        marks[#marks + 1] = { #lines, col, col + #p[1], p[2] }
        text = text .. p[1]
        col = col + #p[1]
      end
      lines[#lines + 1] = text
    end
  end
  -- the pulse and the line for the day, centred near the bottom
  while #lines < geo.H - 3 do lines[#lines + 1] = '' end
  local pl = pulse()
  local dl = daily()
  local function centre(s) return string.rep(' ', math.max(0, math.floor((W - fn.strdisplaywidth(s)) / 2))) .. s end
  lines[#lines + 1] = centre(pl)
  marks[#marks + 1] = { #lines - 1, 0, -1, 'GolemDim' }
  lines[#lines + 1] = centre(dl)
  marks[#marks + 1] = { #lines - 1, 0, -1, 'Comment' }

  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  vim.bo[b].modified = false
  api.nvim_buf_clear_namespace(b, ns, 0, -1)
  for _, m in ipairs(marks) do pcall(api.nvim_buf_add_highlight, b, ns, m[4], m[1], m[2], m[3]) end
  if api.nvim_get_current_buf() == b and geo.title then pcall(api.nvim_win_set_cursor, 0, geo.title) end
end

local function geometry()
  local W, H = vim.o.columns, math.max(vim.o.lines - 2, 12)
  local stacked = W < 78
  local ah = stacked and math.max(6, math.min(9, H - 18)) or math.max(8, math.min(19, H - 5))
  local aw = math.floor(ah * 1.05)
  local pw, ph = aw * 2, ah * 4
  local s = ph / 24.5                                 -- the gada is about 23 motes long at s = 1
  local pts = S.gada_points(pw / 2, ph / 2 + 1.2 * s, -0.38, s)
  local gap = 6
  local rw = stacked and math.min(W - 4, 60) or math.min(64, W - aw - gap - 8)
  local left = math.max(2, math.floor((W - aw - gap - rw) / 2))
  local top = math.max(0, math.floor((H - 3 - math.max(ah, 18)) / 2))
  return { W = W, H = H, stacked = stacked, ah = ah, aw = aw, pw = pw, ph = ph, pts = pts, gap = gap, rw = rw,
    left = left, top = top }
end

-------------------------------------------------------------------------------
-- Opening it
-------------------------------------------------------------------------------
vim.api.nvim_set_hl(0, 'GolemMote', { fg = S.P.mist })

function _G.GolemStart()
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'wipe'
  vim.b[b].golem_start = true
  api.nvim_set_current_buf(b)
  vim.wo.number = false
  vim.wo.cursorline = false
  vim.wo.wrap = false
  vim.wo.spell = false
  vim.cmd('stopinsert')

  local geo = geometry()
  math.randomseed(uv.hrtime() % 2147483647)
  for _, p in ipairs(geo.pts) do -- each mote starts somewhere in the mist
    p.sx, p.sy = math.random(-geo.pw, geo.pw * 2), math.random(-geo.ph, geo.ph * 2)
  end

  local animate = S.gada and S.gada.can('fly')
  local timers = {}
  local function stop_all()
    for _, t in ipairs(timers) do if not t:is_closing() then t:stop(); t:close() end end
    timers = {}
  end
  local function settle()
    draw(b, 1, geo)
    local pt = uv.new_timer() -- the pulse, every 5 s while the dashboard shows
    timers[#timers + 1] = pt
    pt:start(5000, 5000, vim.schedule_wrap(function()
      if api.nvim_buf_is_valid(b) and api.nvim_get_current_buf() == b then draw(b, 1, geo) else stop_all() end
    end))
  end
  if animate then
    local i, steps = 0, 22
    local anim = uv.new_timer()
    timers[#timers + 1] = anim
    anim:start(0, 45, vim.schedule_wrap(function()
      i = i + 1
      if not api.nvim_buf_is_valid(b) then return stop_all() end
      draw(b, math.min(1, i / steps), geo)
      if i >= steps then
        anim:stop()
        if S.sound then S.sound('thud') end
        settle()
      end
    end))
  else
    settle()
  end
  api.nvim_create_autocmd({ 'BufWipeout' }, { buffer = b, once = true, callback = stop_all })
  api.nvim_create_autocmd('VimResized', {
    buffer = b,
    callback = function()
      if api.nvim_get_current_buf() ~= b then return end
      geo = geometry()
      for _, p in ipairs(geo.pts) do p.sx, p.sy = p.x, p.y end
      draw(b, 1, geo)
    end,
  })

  -- keys
  local function key(k, f) vim.keymap.set('n', k, f, { buffer = b, nowait = true, silent = true }) end
  local function feed(keys) api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), 'm', false) end
  local function new_file() vim.cmd('enew'); vim.cmd('startinsert') end
  key('n', new_file); key('<CR>', new_file); key('i', new_file)
  key('o', S.open_ask); key('<C-o>', S.open_ask)
  key('p', function() _G.GolemFind() end); key('<C-p>', function() _G.GolemFind() end)
  key('b', function() feed('<C-b>') end)
  key('t', function() feed('<C-j>') end)
  key('k', function() feed('<C-k>') end)
  key('c', function() if S.gada then S.gada.codex() end end)
  key('g', function() if S.gada then S.gada.settings() end end)
  key('h', S.guide); key('<F1>', function() S.palette() end)
  key('w', function() if S.intro then S.intro() end end)
  key('r', function() if S.reopen then S.reopen() end end)
  key('q', S.quit); key('<C-q>', S.quit)
  key('<Esc>', function() end)
  for n = 1, 9 do
    key(tostring(n), function()
      local list = entries()
      if list[n] then S.open_path(list[n].path) end
    end)
  end
  if S.intro_first then S.intro_first() end           -- the short tour, the very first time
end
