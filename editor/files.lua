-- Golem editor: FILES, a file explorer inside the editor (Alt+E, or E on the dashboard).
--
--   left     places: Home, documents, projects, media, zones, Downloads, USB sticks, the Bin,
--            and your pinned groups
--   middle   the files here: name, size, date, kind. Folders first.
--   right    a look inside the chosen file or folder
--
--   Enter / →      open (a folder goes in; a file opens here or in its own app and zone)
--   Backspace / ←  up one folder            Tab     between the places and the files
--   Space          choose several            Ctrl+A  choose all
--   Ctrl+C / X / V copy / cut / paste here  F2      rename
--   Delete         to the Bin (restorable: in the Bin, R puts it back)
--   Alt+N          new folder               Ctrl+N  new file
--   Ctrl+F         show only names with...  S       sort: name, size, date, kind
--   Alt+H          hidden files on / off    Alt+Enter  details (size, who can see it)
--   Alt+P          pin to the dashboard (in a group)
--   Esc / Alt+E    back to your writing
-- Every change to your files is written in the truth log, in plain words.
-- Part of Golem: GADA, the editor; MAP.md section 5.7.

local api, fn, uv = vim.api, vim.fn, vim.uv or vim.loop
local S = _G.Golem
local HOME = vim.env.HOME
local BIN = HOME .. '/.local/share/golem-bin'

local st = { dir = HOME, sel = {}, clip = nil, clip_cut = false, hidden = false, sort = 'name', filter = '', items = {} }
local ui = nil   -- { tab, places = {win, buf}, list = {win, buf}, look = {win, buf}, back_tab }

-------------------------------------------------------------------------------
-- What a file is, how big, when
-------------------------------------------------------------------------------
local KINDS = {
  Text = { 'txt', 'md', 'rst', 'org', 'log', 'csv', 'tsv' },
  Code = { 'py', 'lua', 'js', 'ts', 'sh', 'c', 'h', 'cpp', 'rs', 'go', 'java', 'html', 'css', 'json', 'nix', 'toml', 'yaml', 'yml', 'xml', 'sql', 'rb', 'php' },
  Picture = { 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'tif', 'tiff' },
  Music = { 'mp3', 'ogg', 'flac', 'wav', 'm4a', 'opus' },
  Video = { 'mp4', 'mkv', 'webm', 'avi', 'mov' },
  PDF = { 'pdf' },
  Document = { 'doc', 'docx', 'odt', 'rtf', 'xls', 'xlsx', 'ods', 'ppt', 'pptx', 'odp' },
  Archive = { 'zip', 'tar', 'gz', 'xz', 'bz2', '7z', 'rar', 'zst' },
}
local KIND_OF = {}
for k, exts in pairs(KINDS) do for _, e in ipairs(exts) do KIND_OF[e] = k end end

local function kind(e)
  if e.dir then return 'Folder' end
  local ext = e.name:match('%.([%w]+)$')
  return (ext and KIND_OF[ext:lower()]) or 'File'
end

local function human(n)
  if not n then return '' end
  local u, i = { 'B', 'KB', 'MB', 'GB', 'TB' }, 1
  while n >= 1024 and i < #u do n, i = n / 1024, i + 1 end
  return i == 1 and string.format('%d B', n) or string.format('%.1f %s', n, u[i])
end

local function join(a, b) return a == '/' and ('/' .. b) or (a .. '/' .. b) end
local function tilde(p) return S.tilde and S.tilde(p) or p end
local function log(msg) if S.truth then S.truth('FILES: ' .. msg) end end
local function say(m) if S.say then S.say(m) end end

-------------------------------------------------------------------------------
-- Reading a folder
-------------------------------------------------------------------------------
local function read_dir(dir)
  local out = {}
  local h = uv.fs_scandir(dir)
  if not h then return out end
  while true do
    local name, t = uv.fs_scandir_next(h)
    if not name then break end
    if st.hidden or name:sub(1, 1) ~= '.' then
      local path = join(dir, name)
      local s = uv.fs_stat(path)
      local e = { name = name, path = path, dir = (s and s.type == 'directory') or t == 'directory',
        size = s and s.size, mtime = s and s.mtime and s.mtime.sec or 0 }
      e.kind = kind(e)
      if st.filter == '' or name:lower():find(st.filter:lower(), 1, true) then out[#out + 1] = e end
    end
  end
  table.sort(out, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    if st.sort == 'size' and a.size ~= b.size then return (a.size or 0) > (b.size or 0) end
    if st.sort == 'date' and a.mtime ~= b.mtime then return a.mtime > b.mtime end
    if st.sort == 'kind' and a.kind ~= b.kind then return a.kind < b.kind end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

-------------------------------------------------------------------------------
-- Places
-------------------------------------------------------------------------------
local function places()
  local P = {}
  local function add(label, path) if fn.isdirectory(path) == 1 then P[#P + 1] = { label = label, path = path } end end
  add('Home', HOME)
  for _, d in ipairs({ 'documents', 'projects', 'media', 'zones', 'Downloads' }) do add(d, HOME .. '/' .. d) end
  for _, root in ipairs({ '/run/media/' .. (vim.env.USER or ''), '/media' }) do
    for _, d in ipairs(fn.glob(root .. '/*', false, true)) do add('USB  ' .. fn.fnamemodify(d, ':t'), d) end
  end
  fn.mkdir(BIN .. '/files', 'p')
  add('Bin', BIN .. '/files')
  for _, g in ipairs(S.pin_groups and S.pin_groups() or {}) do
    P[#P + 1] = { label = '', path = nil }
    P[#P + 1] = { label = g.name, path = nil, head = true }
    for _, p in ipairs(g.items) do P[#P + 1] = { label = '  ' .. fn.fnamemodify(p, ':t'), path = p } end
  end
  return P
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
local function set(buf, lines)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function cut(t, w)
  if fn.strdisplaywidth(t) <= w then return t .. string.rep(' ', w - fn.strdisplaywidth(t)) end
  return fn.strcharpart(t, 0, w - 1) .. '…'
end

local function current()
  if not ui or not api.nvim_win_is_valid(ui.list.win) then return nil end
  local row = api.nvim_win_get_cursor(ui.list.win)[1]
  return st.items[row - 2], row
end

local function preview()
  if not ui then return end
  local e = current()
  local L = {}
  if not e then
    set(ui.look.buf, { '', '  ' .. tilde(st.dir) })
    return
  end
  L[#L + 1] = ''
  L[#L + 1] = '  ' .. e.name
  L[#L + 1] = '  ' .. e.kind .. (e.dir and '' or ('  ·  ' .. human(e.size))) .. '  ·  ' .. os.date('%d %b %Y %H:%M', e.mtime)
  L[#L + 1] = ''
  if e.dir then
    local inside = read_dir(e.path)
    L[#L + 1] = string.format('  %d things inside', #inside)
    L[#L + 1] = ''
    for i = 1, math.min(#inside, 40) do L[#L + 1] = '  ' .. inside[i].name .. (inside[i].dir and '/' or '') end
  elseif (e.kind == 'Text' or e.kind == 'Code' or e.kind == 'File') and (e.size or 0) < 2000000 and S.is_text_file and S.is_text_file(e.path) then
    for _, l in ipairs(fn.readfile(e.path, '', 60)) do L[#L + 1] = '  ' .. l:gsub('\t', '  ') end
  else
    local what = vim.trim(fn.system({ 'file', '-b', '--', e.path }))
    L[#L + 1] = '  ' .. what
    L[#L + 1] = ''
    L[#L + 1] = '  Enter opens it in its own app.'
  end
  set(ui.look.buf, L)
end

local function draw()
  if not ui then return end
  st.items = read_dir(st.dir)
  local w = api.nvim_win_get_width(ui.list.win)
  local nw = math.max(12, w - 40)
  local L = { '  ' .. tilde(st.dir) .. (st.filter ~= '' and ('   ·   names with "' .. st.filter .. '"') or '')
      .. '   ·   sorted by ' .. st.sort .. (st.clip and string.format('   ·   %d %s', #st.clip, st.clip_cut and 'cut' or 'copied') or ''),
    '  ' .. cut('NAME', nw) .. '  ' .. cut('SIZE', 10) .. cut('CHANGED', 18) .. 'KIND' }
  for _, e in ipairs(st.items) do
    local mark = st.sel[e.path] and '◆ ' or '  '
    L[#L + 1] = mark .. cut(e.name .. (e.dir and '/' or ''), nw) .. '  ' .. cut(e.dir and '' or human(e.size), 10)
        .. cut(os.date('%d %b %Y %H:%M', e.mtime), 18) .. e.kind
  end
  if #st.items == 0 then L[#L + 1] = '  (nothing here)' end
  set(ui.list.buf, L)
  api.nvim_buf_clear_namespace(ui.list.buf, -1, 0, -1)
  api.nvim_buf_add_highlight(ui.list.buf, -1, 'GolemBright', 0, 0, -1)
  api.nvim_buf_add_highlight(ui.list.buf, -1, 'GolemDim', 1, 0, -1)
  local pl = {}
  ui.place_list = places()
  for _, p in ipairs(ui.place_list) do pl[#pl + 1] = ' ' .. p.label end
  set(ui.places.buf, pl)
  for i, p in ipairs(ui.place_list) do
    if p.head then api.nvim_buf_add_highlight(ui.places.buf, -1, 'GolemBright', i - 1, 0, -1) end
    if p.path == st.dir then api.nvim_buf_add_highlight(ui.places.buf, -1, 'GolemBright', i - 1, 0, -1) end
  end
  local row = api.nvim_win_get_cursor(ui.list.win)[1]
  pcall(api.nvim_win_set_cursor, ui.list.win, { math.max(3, math.min(row, #L)), 0 })
  preview()
end

-------------------------------------------------------------------------------
-- Doing
-------------------------------------------------------------------------------
local function go(dir, keep_row)
  if fn.isdirectory(dir) == 0 then return say('THAT FOLDER IS GONE') end
  local from = st.dir
  st.dir, st.sel, st.filter = fn.fnamemodify(dir, ':p'):gsub('/$', ''), {}, ''
  if st.dir == '' then st.dir = '/' end
  draw()
  if not keep_row then
    local target = 3
    for i, e in ipairs(st.items) do if e.path == from then target = i + 2 end end
    pcall(api.nvim_win_set_cursor, ui.list.win, { target, 0 })
    preview()
  end
end

local function close()
  if not ui then return end
  local back = ui.back_tab
  ui = nil
  pcall(vim.cmd, 'tabclose')
  if back and api.nvim_tabpage_is_valid(back) then api.nvim_set_current_tabpage(back) end
end

local function open_file(path)
  close()
  if S.open_path then S.open_path(path) else vim.cmd('edit ' .. fn.fnameescape(path)) end
end

local function enter()
  local e = current()
  if not e then return end
  if e.dir then return go(e.path) end
  if fn.fnamemodify(st.dir, ':p'):find(BIN, 1, true) then return say('IN THE BIN: R PUTS IT BACK, DELETE REMOVES IT FOREVER') end
  open_file(e.path)
end

local function chosen()
  local out = {}
  for p in pairs(st.sel) do out[#out + 1] = p end
  if #out == 0 then
    local e = current()
    if e then out[1] = e.path end
  end
  table.sort(out)
  return out
end

local function free_name(dir, name)
  local p = join(dir, name)
  if not uv.fs_stat(p) then return p end
  local base, ext = name:match('^(.-)(%.[^.]*)$')
  if not base or base == '' then base, ext = name, '' end
  for i = 2, 999 do
    p = join(dir, string.format('%s (%d)%s', base, i, ext))
    if not uv.fs_stat(p) then return p end
  end
  return p
end

local function run(cmd)
  local out = fn.system(cmd)
  if vim.v.shell_error ~= 0 then say('COULD NOT: ' .. vim.trim(out)); return false end
  return true
end

local function paste()
  if not st.clip then return say('NOTHING COPIED OR CUT YET') end
  local n = 0
  for _, src in ipairs(st.clip) do
    if uv.fs_stat(src) then
      local dst = free_name(st.dir, fn.fnamemodify(src, ':t'))
      if st.clip_cut then
        if run({ 'mv', '--', src, dst }) then n = n + 1; log('moved ' .. tilde(src) .. ' to ' .. tilde(dst)) end
      else
        if run({ 'cp', '-r', '--', src, dst }) then n = n + 1; log('copied ' .. tilde(src) .. ' to ' .. tilde(dst)) end
      end
    end
  end
  if st.clip_cut then st.clip = nil end
  draw()
  say(string.format('%d %s HERE', n, n == 1 and 'THING PUT' or 'THINGS PUT'))
end

local function to_bin()
  local list = chosen()
  if #list == 0 then return end
  local in_bin = fn.fnamemodify(st.dir, ':p'):find(BIN, 1, true)
  local q = in_bin and string.format('REMOVE %d FOREVER? (type yes) ', #list)
      or string.format('MOVE %d TO THE BIN? (Enter = yes, Esc = no) ', #list)
  local a = S.ask(q, in_bin and '' or 'yes')
  if not a or (in_bin and a ~= 'yes') then return end
  for _, p in ipairs(list) do
    if in_bin then
      if run({ 'rm', '-rf', '--', p }) then
        pcall(os.remove, BIN .. '/info/' .. fn.fnamemodify(p, ':t'))
        log('removed forever ' .. fn.fnamemodify(p, ':t'))
      end
    else
      fn.mkdir(BIN .. '/info', 'p')
      local dst = free_name(BIN .. '/files', fn.fnamemodify(p, ':t'))
      if run({ 'mv', '--', p, dst }) then
        fn.writefile({ p }, BIN .. '/info/' .. fn.fnamemodify(dst, ':t'))
        log('put ' .. tilde(p) .. ' in the Bin')
      end
    end
  end
  st.sel = {}
  draw()
end

local function restore()
  if not fn.fnamemodify(st.dir, ':p'):find(BIN, 1, true) then return end
  for _, p in ipairs(chosen()) do
    local info = BIN .. '/info/' .. fn.fnamemodify(p, ':t')
    local back = fn.filereadable(info) == 1 and fn.readfile(info)[1] or (HOME .. '/' .. fn.fnamemodify(p, ':t'))
    fn.mkdir(fn.fnamemodify(back, ':h'), 'p')
    local dst = free_name(fn.fnamemodify(back, ':h'), fn.fnamemodify(back, ':t'))
    if run({ 'mv', '--', p, dst }) then os.remove(info); log('took ' .. tilde(dst) .. ' back out of the Bin') end
  end
  st.sel = {}
  draw()
end

local function rename()
  local e = current()
  if not e then return end
  local new = S.ask('NEW NAME: ', e.name)
  if not new or new == '' or new == e.name or new:find('/') then return end
  local dst = join(st.dir, new)
  if uv.fs_stat(dst) then return say('THAT NAME IS TAKEN HERE') end
  if run({ 'mv', '--', e.path, dst }) then log('renamed ' .. tilde(e.path) .. ' to ' .. new) end
  draw()
end

local function new_folder()
  local n = S.ask('NEW FOLDER NAME: ', '')
  if not n or n == '' or n:find('/') then return end
  local p = free_name(st.dir, n)
  fn.mkdir(p, 'p')
  log('made the folder ' .. tilde(p))
  draw()
end

local function new_file()
  local n = S.ask('NEW FILE NAME: ', '')
  if not n or n == '' or n:find('/') then return end
  local p = free_name(st.dir, n)
  fn.writefile({}, p)
  log('made the file ' .. tilde(p))
  open_file(p)
end

local function who_sees(path)
  local z = path:match('^' .. vim.pesc(HOME) .. '/zones/([^/]+)')
  if z == 'settings' then return 'only Golem itself and you (zone settings)' end
  if z then return 'you, GREEN apps, and the app "' .. z .. '" (its OFFLINE or YELLOW home)' end
  if path:find(HOME, 1, true) == 1 then return 'you and GREEN apps only (RED, OFFLINE and YELLOW apps never see it)' end
  return 'the system: outside your home folder'
end

local function details()
  local e = current()
  if not e then return end
  local size = e.size
  if e.dir then size = tonumber((fn.system({ 'du', '-sb', '--', e.path }):match('^(%d+)'))) end
  local s = uv.fs_stat(e.path) or {}
  local L = { '', '  ' .. e.name, '', '  Kind        ' .. e.kind, '  Size        ' .. human(size),
    '  Changed     ' .. os.date('%d %b %Y %H:%M', e.mtime), '  Where       ' .. tilde(st.dir),
    '  Who sees it ' .. who_sees(e.path), '  Allowed     ' .. string.format('%o', (s.mode or 0) % 4096) }
  if not e.dir then L[#L + 1] = '  Inside      ' .. vim.trim(fn.system({ 'file', '-b', '--', e.path })) end
  set(ui.look.buf, L)
end

local function pin()
  local list = chosen()
  if #list == 0 then return end
  for _, p in ipairs(list) do if S.toggle_pin_path then S.toggle_pin_path(p) end end
  draw()
end

-------------------------------------------------------------------------------
-- Opening it
-------------------------------------------------------------------------------
local function scratch(name)
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'wipe'
  vim.bo[b].modifiable = false
  pcall(api.nvim_buf_set_name, b, name)
  return b
end

local function keys()
  local function k(buf, lhs, f) vim.keymap.set('n', lhs, f, { buffer = buf, nowait = true, silent = true }) end
  local L = ui.list.buf
  for _, lhs in ipairs({ '<CR>', '<Right>', 'l', '<2-LeftMouse>' }) do k(L, lhs, enter) end
  for _, lhs in ipairs({ '<BS>', '<Left>', 'h' }) do k(L, lhs, function() go(fn.fnamemodify(st.dir, ':h')) end) end
  k(L, '<Space>', function()
    local e = current()
    if not e then return end
    st.sel[e.path] = (not st.sel[e.path]) or nil
    local row = api.nvim_win_get_cursor(ui.list.win)[1]
    draw()
    pcall(api.nvim_win_set_cursor, ui.list.win, { row + 1, 0 })
    preview()
  end)
  k(L, '<C-a>', function() for _, e in ipairs(st.items) do st.sel[e.path] = true end; draw() end)
  k(L, '<C-c>', function() st.clip, st.clip_cut = chosen(), false; st.sel = {}; draw(); say(#st.clip .. ' COPIED: GO WHERE IT SHOULD GO, THEN CTRL+V') end)
  k(L, '<C-x>', function() st.clip, st.clip_cut = chosen(), true; st.sel = {}; draw(); say(#st.clip .. ' CUT: GO WHERE IT SHOULD GO, THEN CTRL+V') end)
  k(L, '<C-v>', paste)
  k(L, '<F2>', rename)
  k(L, '<Del>', to_bin)
  k(L, 'R', restore)
  k(L, '<M-n>', new_folder)
  k(L, '<C-n>', new_file)
  k(L, '<C-f>', function()
    local f = S.ask('SHOW ONLY NAMES WITH (empty = all): ', st.filter)
    if f then st.filter = f; draw() end
  end)
  k(L, 's', function()
    local order = { name = 'size', size = 'date', date = 'kind', kind = 'name' }
    st.sort = order[st.sort]; draw()
  end)
  k(L, 'S', function()
    local order = { name = 'size', size = 'date', date = 'kind', kind = 'name' }
    st.sort = order[st.sort]; draw()
  end)
  k(L, '<M-h>', function() st.hidden = not st.hidden; draw() end)
  k(L, '<M-CR>', details)
  k(L, '<M-p>', pin)
  k(L, '<C-r>', draw)
  k(L, '<F5>', draw)
  for _, b in ipairs({ L, ui.places.buf, ui.look.buf }) do
    k(b, '<Esc>', close); k(b, '<M-e>', close); k(b, '<C-q>', close); k(b, 'q', close)
    k(b, '<Tab>', function()
      api.nvim_set_current_win(api.nvim_get_current_win() == ui.list.win and ui.places.win or ui.list.win)
    end)
  end
  local function place_go()
    local i = api.nvim_win_get_cursor(ui.places.win)[1]
    local p = ui.place_list[i]
    if not p or not p.path then return end
    if fn.isdirectory(p.path) == 1 then
      go(p.path, true)
      api.nvim_set_current_win(ui.list.win)
    else
      open_file(p.path)
    end
  end
  for _, lhs in ipairs({ '<CR>', '<Right>', 'l', '<2-LeftMouse>' }) do k(ui.places.buf, lhs, place_go) end
  api.nvim_create_autocmd('CursorMoved', { buffer = L, callback = preview })
end

function S.explorer(dir)
  if ui and api.nvim_tabpage_is_valid(ui.tab) then
    api.nvim_set_current_tabpage(ui.tab)
    if dir then go(dir) end
    return
  end
  vim.cmd('stopinsert')
  local back = api.nvim_get_current_tabpage()
  vim.cmd('tabnew')
  ui = { tab = api.nvim_get_current_tabpage(), back_tab = back }
  ui.list = { win = api.nvim_get_current_win(), buf = scratch('FILES') }
  api.nvim_win_set_buf(ui.list.win, ui.list.buf)
  vim.cmd('topleft vsplit')
  ui.places = { win = api.nvim_get_current_win(), buf = scratch('PLACES') }
  api.nvim_win_set_buf(ui.places.win, ui.places.buf)
  api.nvim_win_set_width(ui.places.win, 24)
  api.nvim_set_current_win(ui.list.win)
  vim.cmd('botright vsplit')
  ui.look = { win = api.nvim_get_current_win(), buf = scratch('LOOK INSIDE') }
  api.nvim_win_set_buf(ui.look.win, ui.look.buf)
  api.nvim_win_set_width(ui.look.win, math.floor(vim.o.columns * 0.34))
  for _, w in ipairs({ ui.places.win, ui.list.win, ui.look.win }) do
    vim.wo[w].number, vim.wo[w].relativenumber, vim.wo[w].signcolumn = false, false, 'no'
    vim.wo[w].wrap, vim.wo[w].cursorline = false, w ~= ui.look.win
  end
  api.nvim_set_current_win(ui.list.win)
  keys()
  st.dir = st.dir ~= '' and st.dir or HOME
  go(dir or st.dir, true)
  pcall(api.nvim_win_set_cursor, ui.list.win, { 3, 0 })
  preview()
end

if S.map and S.all then S.map(S.all, '<M-e>', function() S.explorer() end) end
