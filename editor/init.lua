-- Golem's text editor: Neovim set up to behave like Notepad, inside Cool Retro Term.
--
--   Always typing (no Vim modes to learn). Keys like Notepad / VS Code:
--   Ctrl+S save   Ctrl+O open   Ctrl+P find a file   Ctrl+N new   Ctrl+Q close
--   Ctrl+F find   F3 next   Ctrl+R replace   Ctrl+G go to line   Ctrl+Z / Ctrl+Y undo / redo
--   Ctrl+A all    Shift+arrows select   Ctrl+C / Ctrl+X / Ctrl+V copy / cut / paste
--   Ctrl+L line numbers   Alt+Z word wrap   F1 the guide
--
-- Truthful state: the bottom line says SAVED only when the file on disk is exactly what
-- you see. Autosave writes ~2 s after you stop typing, never over a file that another app
-- changed meanwhile (it asks you instead). The first save of each file in a session goes
-- to the truth log.
--
-- Colours: brightness levels from Golem's theme (settings.nix). Cool Retro Term turns them
-- into the screen's colours, so the editor never needs its own.

local api, fn = vim.api, vim.fn
local uv = vim.uv or vim.loop
local opt = vim.opt
local home = vim.env.HOME or ''

vim.g.loaded_netrwPlugin = 1 -- no built-in file browser panel
vim.g.loaded_netrw = 1

-------------------------------------------------------------------------------
-- Options
-------------------------------------------------------------------------------
opt.termguicolors = true
opt.number = true
opt.cursorline = true -- the line you are on glows faintly
opt.wrap = true -- long lines wrap at words, like Notepad with word wrap on
opt.linebreak = true
opt.breakindent = true
opt.scrolloff = 3
opt.undofile = true -- undo still works after closing and reopening a file
opt.swapfile = false -- autosave keeps your work; no recovery questions
opt.hidden = true
opt.shortmess:append('IcFsWAS')
opt.showmode = false
opt.showcmd = false
opt.ruler = false
opt.laststatus = 2 -- the one quiet line at the bottom
opt.cmdheight = 1
opt.mouse = 'a'
opt.mousemodel = 'extend' -- right click never opens a menu
opt.clipboard = 'unnamedplus' -- copy / paste work with every other app
opt.keymodel = { 'startsel', 'stopsel' } -- Shift+arrows select, arrows stop selecting
opt.selectmode = { 'key', 'mouse' } -- typing over a selection replaces it
opt.selection = 'exclusive'
opt.whichwrap = 'b,s,<,>,[,]' -- arrows move to the next / previous line
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true
opt.expandtab = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.autoindent = true
opt.fillchars = { eob = ' ' }
opt.title = true
opt.updatetime = 1000
opt.confirm = false
opt.autoread = false -- we decide what happens when another app changes a file
opt.wildmenu = true
opt.wildoptions = '' -- file name completion in the bottom line, not in a popup
opt.pumheight = 8

-------------------------------------------------------------------------------
-- Look: Golem's colours (settings.nix).
--   void, shade, mist, text, pale  +  three code colours: blue, teal, ember
-------------------------------------------------------------------------------
local face = 'shadow'
do -- the face set in the Control Panel
  local f = io.open('/var/lib/golem/settings.conf', 'r')
  if f then
    for line in f:lines() do
      if line:match('^face=negative') then face = 'negative' end
    end
    f:close()
  end
end
-- The editor always draws in the Shadow light (bright = strong). Cool Retro Term turns that
-- into whatever screen style you pick in its settings.
local P = { void = '#050506', shade = '#14161c', mist = '#6f7484', text = '#c8ccd8', pale = '#e6e9f2',
  blue = '#8e9bc0', teal = '#9fc3c9', ember = '#c46a6a' }
do
  local names = { 'void', 'shade', 'mist', 'text', 'pale', 'blue', 'teal', 'ember' }
  local i = 0
  local env = vim.env.GOLEM_PALETTE
  for c in (env or ''):gmatch('#%x%x%x%x%x%x') do
    i = i + 1
    if names[i] then P[names[i]] = c end
  end
end

local function hl(name, spec) api.nvim_set_hl(0, name, spec) end
local function mix(a, b, t) -- a colour between a and b
  local out = '#'
  for i = 2, 6, 2 do
    local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
    out = out .. string.format('%02x', math.floor(x + (y - x) * t + 0.5))
  end
  return out
end
local glow = mix(P.shade, P.mist, 0.06) -- the faint light on the line you are on
local function paint()
  vim.cmd('highlight clear')
  vim.g.colors_name = 'golem'
  local N = 'NONE'
  hl('Normal', { fg = P.text, bg = N })
  hl('NormalNC', { fg = P.text, bg = N })
  hl('NormalFloat', { fg = P.text, bg = P.void })
  hl('FloatBorder', { fg = P.shade, bg = P.void })
  hl('CursorLine', { bg = glow })
  hl('CursorLineNr', { fg = P.pale, bold = true })
  hl('LineNr', { fg = P.shade })
  hl('LineNrAbove', { fg = P.mist })
  hl('LineNrBelow', { fg = P.mist })
  hl('SignColumn', { bg = N })
  hl('NonText', { fg = P.shade })
  hl('Whitespace', { fg = P.shade })
  hl('EndOfBuffer', { fg = P.void })
  hl('Visual', { fg = P.void, bg = P.text })
  hl('Search', { fg = P.void, bg = P.mist })
  hl('IncSearch', { fg = P.void, bg = P.pale, bold = true })
  hl('CurSearch', { fg = P.void, bg = P.pale, bold = true })
  hl('MatchParen', { fg = P.pale, bold = true, underline = true })
  hl('StatusLine', { fg = P.mist, bg = N })
  hl('StatusLineNC', { fg = P.shade, bg = N })
  hl('GolemBright', { fg = P.pale, bold = true })
  hl('GolemDim', { fg = P.mist })
  hl('GolemWarn', { fg = P.void, bg = P.pale, bold = true })
  hl('GolemMote', { fg = P.mist })
  hl('GolemSigil', { fg = P.pale })
  hl('VertSplit', { fg = P.shade })
  hl('WinSeparator', { fg = P.shade })
  hl('Pmenu', { fg = P.mist, bg = P.void })
  hl('PmenuSel', { fg = P.pale, bg = P.shade })
  hl('WildMenu', { fg = P.pale, bg = P.shade })
  hl('MsgArea', { fg = P.text })
  hl('ModeMsg', { fg = P.mist })
  hl('MoreMsg', { fg = P.mist })
  hl('Question', { fg = P.pale })
  hl('ErrorMsg', { fg = P.pale, bold = true })
  hl('WarningMsg', { fg = P.pale })
  hl('Title', { fg = P.pale, bold = true })
  hl('Directory', { fg = P.pale })
  -- code and markup: only brightness and weight, the realm has one light
  hl('Comment', { fg = P.mist, italic = true })
  hl('Constant', { fg = P.ember })
  hl('String', { fg = P.teal })
  hl('Character', { fg = P.teal })
  hl('Identifier', { fg = P.text })
  hl('Function', { fg = P.pale, bold = true })
  hl('Statement', { fg = P.blue, bold = true })
  hl('PreProc', { fg = P.blue })
  hl('Type', { fg = P.teal, bold = true })
  hl('Special', { fg = P.ember })
  hl('Delimiter', { fg = P.mist })
  hl('Operator', { fg = P.mist })
  hl('htmlTag', { fg = P.mist })
  hl('htmlEndTag', { fg = P.mist })
  hl('htmlTagName', { fg = P.blue, bold = true })
  hl('htmlArg', { fg = P.teal })
  hl('NvimTreeNormal', { fg = P.mist, bg = N })
  hl('NvimTreeFolderName', { fg = P.text })
  hl('NvimTreeOpenedFolderName', { fg = P.pale, bold = true })
  hl('NvimTreeRootFolder', { fg = P.mist, bold = true })
  hl('NvimTreeOpenedFile', { fg = P.pale })
  hl('NvimTreeIndentMarker', { fg = P.shade })
  hl('NvimTreeCursorLine', { bg = glow })
  hl('NvimTreeWinSeparator', { fg = P.shade, bg = N })
  hl('Underlined', { underline = true })
  hl('Todo', { fg = P.void, bg = P.mist, bold = true })
  hl('Error', { fg = P.pale, bold = true, underline = true })
  hl('DiffAdd', { fg = P.pale })
  hl('DiffDelete', { fg = P.mist })
  hl('DiffChange', { fg = P.text })
  hl('DiffText', { fg = P.pale, bold = true })
  hl('markdownH1', { fg = P.pale, bold = true })
  hl('markdownH2', { fg = P.pale, bold = true })
  -- the Ctrl+P finder
  hl('MiniPickNormal', { fg = P.mist, bg = P.void })
  hl('MiniPickBorder', { fg = P.shade, bg = P.void })
  hl('MiniPickBorderText', { fg = P.mist, bg = P.void })
  hl('MiniPickPrompt', { fg = P.pale, bg = P.void })
  hl('MiniPickMatchCurrent', { fg = P.pale, bg = P.shade })
  hl('MiniPickMatchRanges', { fg = P.pale, bold = true })
  hl('MiniPickHeader', { fg = P.mist })
end
paint()

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------
local function tilde(path) -- /home/x/notes.txt -> ~/notes.txt
  if home ~= '' and (path == home or path == home .. '/') then return '~' end
  if home ~= '' and path:sub(1, #home + 1) == home .. '/' then return '~' .. path:sub(#home + 1) end
  return path
end

local function say(msg) -- a quiet line at the bottom, never a popup
  api.nvim_echo({ { msg, 'GolemDim' } }, false, {})
end

local function ask(prompt, default, complete)
  -- Returns nil if you press Esc.
  local win, pos = api.nvim_get_current_win(), api.nvim_win_get_cursor(0)
  local ok, r = pcall(fn.input, { prompt = prompt, default = default or '', completion = complete,
    cancelreturn = '\1' })
  -- back exactly where you were typing (the question can nudge the cursor one letter left)
  if api.nvim_win_is_valid(win) then pcall(api.nvim_win_set_cursor, win, pos) end
  api.nvim_echo({ { '' } }, false, {})
  vim.cmd('redraw')
  if not ok or r == '\1' then return nil end
  return r
end

local function is_text(b)
  b = b or api.nvim_get_current_buf()
  return api.nvim_buf_is_valid(b) and vim.bo[b].buftype == ''
end

local function truth(msg) -- one line in the truth log, in plain words
  pcall(fn.jobstart, { 'logger', '-t', 'zone', msg }, { detach = true })
end

-------------------------------------------------------------------------------
-- Always typing: whenever the editor would fall back to Vim's command mode in a
-- file, it goes straight back to typing. (The start screen and the guide are menus.)
-------------------------------------------------------------------------------
local function back_to_typing()
  vim.schedule(function()
    if fn.mode() == 'n' and is_text() and vim.bo.modifiable and fn.getcmdwintype() == '' then
      vim.cmd('startinsert')
    end
  end)
end
api.nvim_create_autocmd('ModeChanged', { pattern = '*:n', callback = back_to_typing })

-- Your view choices (Ctrl+L, Alt+Z) follow you into every file.
vim.g.golem_numbers, vim.g.golem_wrap = true, true
api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter' }, {
  callback = function()
    if is_text() then
      vim.wo.number = vim.g.golem_numbers
      vim.wo.wrap = vim.g.golem_wrap
      vim.wo.cursorline = true
    elseif vim.bo.buftype ~= 'terminal' and vim.bo.buftype ~= 'prompt' then
      vim.cmd('stopinsert') -- panels and menus are moved in with arrows, not typed into
    end
  end,
})
api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, { callback = back_to_typing })

-------------------------------------------------------------------------------
-- Saving, and the truth about it
--   vim.b.golem_disk = 'changed' | 'deleted' when another app touched the file
--   vim.b.golem_err  = why the last save failed
-------------------------------------------------------------------------------
local logged = {} -- files already noted in the truth log this session

local function write_buf(b, force)
  local name = api.nvim_buf_get_name(b)
  if name == '' then return false end
  local ok, err = pcall(api.nvim_buf_call, b, function()
    vim.cmd((force and 'silent keepalt keepjumps write!' or 'silent keepalt keepjumps write'))
  end)
  if ok then
    vim.b[b].golem_err = nil
    vim.b[b].golem_disk = nil
    if not logged[name] then
      logged[name] = true
      truth('Editor saved ' .. tilde(name))
    end
    return true
  end
  local e = tostring(err)
  if e:find('E212') or e:find('E505') or e:find('ermission') then
    vim.b[b].golem_err = "CAN'T WRITE HERE"
  elseif e:find('E13') then
    vim.b[b].golem_err = 'A FOLDER HAS THAT NAME'
  else
    vim.b[b].golem_err = 'SAVE FAILED'
  end
  return false
end

local function save_as(b)
  b = b or api.nvim_get_current_buf()
  local cur = api.nvim_buf_get_name(b)
  local start = cur ~= '' and cur or (fn.getcwd() .. '/')
  local name = ask('SAVE AS  ', tilde(start), 'file')
  if not name or name == '' or name:sub(-1) == '/' then
    say('NOT SAVED')
    return false
  end
  name = fn.fnamemodify(fn.expand(name), ':p')
  if fn.isdirectory(name) == 1 then
    say('NOT SAVED: THAT IS A FOLDER')
    return false
  end
  if fn.filereadable(name) == 1 and name ~= cur then
    local c = fn.confirm(tilde(name) .. ' ALREADY EXISTS.', '&Replace it\n&Cancel', 2)
    if c ~= 1 then
      say('NOT SAVED')
      return false
    end
  end
  fn.mkdir(fn.fnamemodify(name, ':h'), 'p')
  api.nvim_buf_call(b, function() vim.cmd('silent keepalt file ' .. fn.fnameescape(name)) end)
  vim.cmd('filetype detect')
  return write_buf(b, true)
end

local function save()
  local b = api.nvim_get_current_buf()
  if not is_text(b) then return end
  if api.nvim_buf_get_name(b) == '' then return save_as(b) end
  pcall(vim.cmd, 'silent! checktime ' .. b)
  if vim.b[b].golem_disk == 'changed' then
    local c = fn.confirm('ANOTHER APP CHANGED THIS FILE WHILE YOU EDITED IT.',
      '&Keep mine (replace theirs)\n&Load theirs (lose mine)\n&Cancel', 3)
    if c == 2 then
      vim.cmd('edit!')
      vim.b[b].golem_disk = nil
      say('LOADED THE VERSION ON DISK')
      return true
    elseif c ~= 1 then
      return false
    end
  end
  if _G.Golem and _G.Golem.tidy then _G.Golem.tidy(b) end -- arrange the code neatly
  local ok = write_buf(b, true)
  if _G.Golem then -- the gada strikes (harder the more you changed), or trembles if the save failed
    local G = _G.Golem
    if ok and G.strike then
      local tick = vim.b[b].changedtick
      local changed = tick - (vim.b[b].golem_struck or tick - 1)
      vim.b[b].golem_struck = tick
      G.strike(changed > 300 and 3 or changed > 40 and 2 or 1)
      if G.saved_event then G.saved_event() end
    elseif not ok and G.shake then
      G.shake()
    end
  end
  return ok
end

-- Autosave: ~2 s after the last change, and when you leave the window or close.
local function autosave_all()
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and is_text(b) and vim.bo[b].modified and vim.bo[b].modifiable
        and not vim.bo[b].readonly and api.nvim_buf_get_name(b) ~= '' then
      pcall(vim.cmd, 'silent! checktime ' .. b) -- never write over someone else's change
      if not vim.b[b].golem_disk and vim.bo[b].modified then write_buf(b, true) end
    end
  end
  vim.cmd('redraw') -- the bottom line and the window's name show the new state
end

local save_timer = uv.new_timer()
local function autosave_soon()
  save_timer:stop()
  save_timer:start(2000, 0, vim.schedule_wrap(function()
    if fn.mode() == 'c' then return autosave_soon() end -- wait until you finish answering
    autosave_all()
  end))
end
api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, { callback = autosave_soon })
api.nvim_create_autocmd({ 'FocusLost', 'VimLeavePre', 'VimSuspend' }, { callback = autosave_all })

-- Another app changed or deleted the file.
api.nvim_create_autocmd('FileChangedShell', {
  callback = function(a)
    local r = vim.v.fcs_reason
    if r == 'mode' or r == 'time' then
      vim.v.fcs_choice = ''
    elseif r == 'deleted' then
      vim.b[a.buf].golem_disk = 'deleted'
      vim.v.fcs_choice = ''
    elseif not vim.bo[a.buf].modified then
      vim.v.fcs_choice = 'reload' -- nothing of yours was unsaved: show their version
      vim.schedule(function()
        if _G.Golem and _G.Golem.blocks_open then
          say('THE BLOCKS WROTE NEW CODE INTO ' .. tilde(api.nvim_buf_get_name(a.buf)))
        else
          say('RELOADED: ANOTHER APP CHANGED ' .. tilde(api.nvim_buf_get_name(a.buf)))
        end
      end)
    else
      vim.b[a.buf].golem_disk = 'changed'
      vim.v.fcs_choice = ''
    end
  end,
})

-- Look at the disk every 3 s (a cheap check of the file's time and size).
local watch_timer = uv.new_timer()
watch_timer:start(3000, 3000, vim.schedule_wrap(function()
  if fn.mode() ~= 'c' and fn.getcmdwintype() == '' then
    pcall(vim.cmd, 'silent! checktime')
    for _, b in ipairs(api.nvim_list_bufs()) do
      local name = api.nvim_buf_get_name(b)
      if api.nvim_buf_is_loaded(b) and is_text(b) and name ~= '' and not vim.bo[b].modified
          and fn.filereadable(name) == 0 and not vim.b[b].golem_disk and vim.b[b].golem_seen then
        vim.b[b].golem_disk = 'deleted'
      end
    end
    vim.cmd('redraw')
  end
end))
api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, { callback = function(a) vim.b[a.buf].golem_seen = true end })
api.nvim_create_autocmd('FocusGained', { callback = function() pcall(vim.cmd, 'silent! checktime') end })

-------------------------------------------------------------------------------
-- The one quiet line at the bottom: file name and the honest state
-------------------------------------------------------------------------------
local function state(b)
  b = b or api.nvim_get_current_buf()
  local bt = vim.bo[b].buftype
  if vim.b[b].golem_start then return 'MENU', false end
  if vim.b[b].golem_guide then return 'GUIDE  ·  ESC TO GO BACK', false end
  if bt ~= '' then return '', false end
  local name = api.nvim_buf_get_name(b)
  local mod = vim.bo[b].modified
  if name == '' then
    if mod then return 'NOT SAVED  ·  CTRL+S TO NAME IT', true end
    return 'NEW FILE', false
  end
  if vim.b[b].golem_disk == 'changed' then return 'ANOTHER APP CHANGED IT  ·  CTRL+S TO CHOOSE', true end
  if vim.b[b].golem_disk == 'deleted' then return 'DELETED ON DISK  ·  CTRL+S TO SAVE AGAIN', true end
  if mod and vim.b[b].golem_err then return 'NOT SAVED  ·  ' .. vim.b[b].golem_err, true end
  if mod then return 'NOT SAVED', true end
  if vim.bo[b].readonly or (fn.filereadable(name) == 1 and fn.filewritable(name) == 0) then
    return 'SAVED  ·  READ ONLY', false
  end
  if fn.filereadable(name) == 0 then return 'NOT ON DISK YET', true end
  return 'SAVED', false
end

function _G.GolemStatus()
  local w = vim.g.statusline_winid or api.nvim_get_current_win()
  local b = api.nvim_win_get_buf(w)
  if vim.bo[b].filetype == 'NvimTree' then return '  %#GolemDim#FILES  ·  ESC BACK' end
  if vim.bo[b].filetype == 'golemflow' then return '  %#GolemDim#FLOWCHART  ·  ENTER JUMPS TO THE CODE  ·  ESC BACK' end
  if vim.bo[b].buftype == 'terminal' then
    return '  %#GolemDim#' .. (vim.b[b].golem_term or 'TERMINAL') .. '%=CTRL+J BACK TO YOUR TEXT  '
  end
  if vim.b[b].golem_ai then return '  %#GolemDim#AI  ·  ' .. vim.b[b].golem_ai end
  local name = api.nvim_buf_get_name(b)
  local label
  if vim.b[b].golem_start then
    label = 'GOLEM  /  EDITOR'
  elseif vim.b[b].golem_codex then
    label = 'GOLEM  /  CODEX'
  elseif vim.b[b].golem_guide then
    label = 'GOLEM  /  EDITOR GUIDE'
  else
    label = name == '' and 'NEW FILE' or tilde(name)
  end
  local s, loud = state(b)
  local where = ''
  if is_text(b) and not vim.b[b].golem_start then
    where = string.format('LINE %d / %d   ', api.nvim_win_get_cursor(w)[1], api.nvim_buf_line_count(b))
  end
  -- a narrow window: drop the line count, then show only the file's own name
  local width = api.nvim_win_get_width(w)
  if fn.strdisplaywidth(label .. where .. s) + 6 > width then where = '' end
  if fn.strdisplaywidth(label .. s) + 6 > width and name ~= '' then label = fn.fnamemodify(name, ':t') end
  label = label:gsub('%%', '%%%%')
  return '  %#GolemDim#' .. label .. '%=' .. '%#GolemDim#' .. where
      .. (loud and '%#GolemBright#' or '%#GolemDim#') .. s .. '  '
end
opt.statusline = '%!v:lua.GolemStatus()'

function _G.GolemTitle() -- the window's name, also shown in the Alt+Tab roster
  local b = api.nvim_get_current_buf()
  local name = api.nvim_buf_get_name(b)
  local s = state(b)
  if vim.b[b].golem_start or vim.b[b].golem_guide or name == '' then return 'EDITOR  ·  ' .. s end
  return 'EDITOR  ·  ' .. fn.fnamemodify(name, ':t') .. '  ·  ' .. s
end
opt.titlestring = '%{v:lua.GolemTitle()}'

-------------------------------------------------------------------------------
-- Opening files
-------------------------------------------------------------------------------
local function open_path(path)
  if not path or path == '' then return end
  path = fn.fnamemodify(fn.expand(path), ':p')
  if fn.isdirectory(path) == 1 then
    vim.cmd('cd ' .. fn.fnameescape(path))
    return _G.GolemFind()
  end
  if fn.filereadable(path) == 1 and _G.Golem and _G.Golem.open_other and not _G.Golem.is_text_file(path) then
    return _G.Golem.open_other(path) -- pictures, music, video, PDF, documents: their own app and zone
  end
  vim.cmd('edit ' .. fn.fnameescape(path))
end

local function open_ask()
  local dir = fn.getcwd() .. '/'
  local cur = api.nvim_buf_get_name(0)
  if cur ~= '' then dir = fn.fnamemodify(cur, ':p:h') .. '/' end
  local p = ask('OPEN  ', tilde(dir), 'file')
  if p and p ~= '' and p ~= tilde(dir) then open_path(p) end
end

-- The finder's list: plain names, no icons (they need special fonts).
local function plain_list(buf, items, query)
  require('mini.pick').default_show(buf, items, query, { show_icons = false })
end

-- Ctrl+P: type part of a file's name; the list rises from the bottom like the launcher.
function _G.GolemFind()
  local ok, pick = pcall(require, 'mini.pick')
  if not ok then return open_ask() end
  local tool = fn.executable('rg') == 1 and 'rg' or 'fallback'
  pick.builtin.files({ tool = tool }, {
    source = { name = 'FIND A FILE  ·  ' .. tilde(fn.getcwd()), cwd = fn.getcwd(), show = plain_list },
  })
end

local function find_open_files()
  local ok, pick = pcall(require, 'mini.pick')
  if not ok then return end
  pick.builtin.buffers({}, { source = { name = 'OPEN FILES', show = plain_list } })
end

do
  local ok, pick = pcall(require, 'mini.pick')
  if ok then
    pick.setup({
      options = { content_from_bottom = true, use_cache = true },
      window = {
        prompt_prefix = 'FIND  ',
        config = function()
          local h = math.max(6, math.floor(vim.o.lines * 0.4))
          return { anchor = 'SW', row = vim.o.lines - 1, col = 0, width = vim.o.columns, height = h,
            border = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' } }
        end,
      },
      mappings = { choose_marked = '', mark = '', mark_all = '' },
    })
    -- every menu (AI, shells, the gada) rises from the bottom like the finder, named by its prompt
    vim.ui.select = function(items, opts, on_choice)
      local name = ((opts or {}).prompt or ''):gsub(':?%s*$', '')
      local prefix = name ~= '' and (name:upper() .. '  ') or '  '
      local keep = pick.config.window.prompt_prefix
      pick.config.window.prompt_prefix = prefix -- the list waits for your choice, then it goes back
      pcall(pick.ui_select, items, opts, on_choice, { window = { prompt_prefix = prefix } })
      pick.config.window.prompt_prefix = keep
    end
  end
end

-------------------------------------------------------------------------------
-- Find and replace (questions are asked in the bottom line)
-------------------------------------------------------------------------------
local function lit(s) return '\\V' .. fn.escape(s, '\\/') end

local function show_matches() -- (setting v:hlsearch inside a function does not last)
  api.nvim_feedkeys(api.nvim_replace_termcodes('<Cmd>let v:hlsearch = 1<CR>', true, false, true), 'n', false)
end

local function find_next(back)
  local pat = fn.getreg('/')
  if pat == '' then return end
  show_matches()
  if fn.search(pat, back and 'bw' or 'w') == 0 then say('NOT FOUND') elseif _G.Golem.tap then _G.Golem.tap() end
end

local function last_find()
  local cur = fn.getreg('/'):gsub('^\\V', '')
  return cur
end

local function find()
  local cur = last_find()
  local s = ask(cur ~= '' and ('FIND  (Enter = ' .. cur .. ')  ') or 'FIND  ')
  if not s then return end
  if s == '' then s = cur end
  if s == '' then return end
  local pat = lit(s)
  fn.setreg('/', pat)
  fn.histadd('/', pat)
  show_matches()
  if fn.search(pat, 'cw') == 0 then
    say('NOT FOUND: ' .. s)
    if _G.Golem.shake then _G.Golem.shake() end
  else
    if _G.Golem.tap then _G.Golem.tap() end
    if _G.Golem.sweep then _G.Golem.sweep(pat) end -- the matches on screen light up in turn
    local n = fn.searchcount({ pattern = pat, maxcount = 0, timeout = 1000 }).total or 0
    say('FOUND ' .. n .. '  ·  F3 NEXT  ·  SHIFT+F3 BACK  ·  ESC STOPS SHOWING THEM')
  end
end

local function replace()
  local cur = last_find()
  local find = ask(cur ~= '' and ('REPLACE  ·  FIND  (Enter = ' .. cur .. ')  ') or 'REPLACE  ·  FIND  ')
  if not find then return end
  if find == '' then find = cur end
  if find == '' then return end
  local with = ask('REPLACE "' .. find .. '"  WITH  ')
  if not with then return end
  local pat = lit(find)
  local n = fn.searchcount({ pattern = pat, maxcount = 0, timeout = 2000 }).total or 0
  if n == 0 then
    say('NOT FOUND: ' .. find)
    return
  end
  local view = fn.winsaveview()
  vim.cmd('keeppatterns silent %s/' .. pat .. '/' .. fn.escape(with, '\\/&~') .. '/ge')
  fn.winrestview(view)
  say('REPLACED ' .. n .. (n == 1 and ' TIME' or ' TIMES'))
  if _G.Golem.slam then _G.Golem.slam(n, with) end
  if n >= 20 and _G.Golem.relic then _G.Golem.relic('hammer') end
end

local function goto_line()
  local n = tonumber(ask('GO TO LINE  ') or '')
  if not n then return end
  n = math.max(1, math.min(n, fn.line('$')))
  api.nvim_win_set_cursor(0, { n, 0 })
end

-------------------------------------------------------------------------------
-- Closing
-------------------------------------------------------------------------------
local function quit()
  autosave_all()
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and is_text(b) and vim.bo[b].modified then
      api.nvim_set_current_buf(b)
      local what = api.nvim_buf_get_name(b) == '' and 'THIS NEW FILE IS NOT SAVED.'
          or (tilde(api.nvim_buf_get_name(b)) .. ' IS NOT SAVED (' .. state(b) .. ').')
      local c = fn.confirm(what, '&Save it\n&Throw away the changes\n&Keep editing', 3)
      if c == 1 then
        if not save() or vim.bo[b].modified then return end
      elseif c == 2 then
        vim.bo[b].modified = false
      else
        return
      end
    end
  end
  if _G.Golem and _G.Golem.farewell then
    _G.Golem.farewell(function() vim.cmd('qall!') end) -- a last spin, then close
  else
    vim.cmd('qall!')
  end
end

-------------------------------------------------------------------------------
-- The guide (F1)
-------------------------------------------------------------------------------
local here = fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') -- the editor's own folder
local guide_file = here .. '/guide.txt'

local function guide()
  if vim.b.golem_guide then return vim.cmd('silent! buffer #') end
  local lines = fn.filereadable(guide_file) == 1 and fn.readfile(guide_file) or { '  (the guide file is missing)' }
  local b = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  vim.bo[b].bufhidden = 'wipe'
  vim.b[b].golem_guide = true
  api.nvim_set_current_buf(b)
  vim.wo.number = false
  vim.cmd('stopinsert')
  local close = function()
    if fn.bufexists(fn.bufnr('#')) == 1 and fn.bufnr('#') ~= b then vim.cmd('buffer #') else _G.GolemStart() end
  end
  for _, k in ipairs({ '<Esc>', '<F1>', 'q', '<C-q>' }) do
    vim.keymap.set('n', k, close, { buffer = b, nowait = true })
  end
end

-- The start screen (the dashboard) lives in dashboard.lua.
_G.GolemStart = function() end

-------------------------------------------------------------------------------
-- Keys
-------------------------------------------------------------------------------
local function map(modes, lhs, rhs) vim.keymap.set(modes, lhs, rhs, { silent = true }) end
local all = { 'n', 'i', 'v', 's' }
local function cmd(f) -- run f without leaving the mode you are in
  return function() f() end
end

map(all, '<C-s>', cmd(save))
map(all, '<C-o>', cmd(open_ask))
map(all, '<C-p>', cmd(function() _G.GolemFind() end))
map(all, '<C-e>', cmd(find_open_files))
map(all, '<C-n>', function() vim.cmd('enew'); vim.cmd('startinsert') end)
map(all, '<C-q>', cmd(quit))
map(all, '<F1>', cmd(guide))
map(all, '<C-g>', cmd(goto_line))
map(all, '<C-r>', cmd(replace))
map(all, '<C-l>', function()
  vim.g.golem_numbers = not vim.g.golem_numbers
  if is_text() then vim.wo.number = vim.g.golem_numbers end
end)
map(all, '<M-z>', function()
  vim.g.golem_wrap = not vim.g.golem_wrap
  if is_text() then vim.wo.wrap = vim.g.golem_wrap end
  say(vim.g.golem_wrap and 'WORD WRAP ON' or 'WORD WRAP OFF')
end)

-- find: type in the bottom line, Enter jumps there; F3 / Shift+F3 next / previous
map(all, '<C-f>', cmd(find))
map(all, '<F3>', cmd(function() find_next(false) end))
map(all, '<S-F3>', cmd(function() find_next(true) end))
map(all, '<F15>', cmd(function() find_next(true) end))
map('i', '<Esc>', '<Cmd>nohlsearch<CR>') -- Esc never leaves typing

-- undo / redo, in small steps (each word, line and sentence)
map('i', '<C-z>', '<C-g>u<Cmd>undo<CR><Cmd>lua if Golem.rewind then Golem.rewind(-1) end<CR>')
map('i', '<C-y>', '<Cmd>redo<CR><Cmd>lua if Golem.rewind then Golem.rewind(1) end<CR>')
map({ 'n', 'v', 's' }, '<C-z>', '<Esc>u<Cmd>lua if Golem.rewind then Golem.rewind(-1) end<CR>')
map({ 'n', 'v', 's' }, '<C-y>', '<Esc><C-r><Cmd>lua if Golem.rewind then Golem.rewind(1) end<CR>')
for _, k in ipairs({ '<Space>', '.', ',', '!', '?', ';', ':' }) do
  map('i', k, k .. '<C-g>u')
end
map('i', '<CR>', '<C-g>u<CR>')

-- select all, copy, cut, paste (shared with other apps)
map('i', '<C-a>', '<Esc>ggVG<C-g>')
map('n', '<C-a>', 'ggVG<C-g>')
map('s', '<C-c>', '<C-g>ygv<C-g>')
map('v', '<C-c>', 'ygv')
map('s', '<C-x>', '<C-g>c')
map('v', '<C-x>', 'c')
map('s', '<C-v>', '<C-g>c<C-r><C-o>+')
map('v', '<C-v>', 'c<C-r><C-o>+')
map('i', '<C-v>', '<C-g>u<C-r><C-o>+')
map('i', '<C-c>', '<Nop>') -- nothing selected: nothing to copy
map('s', '<BS>', '<C-g>"_c')
map('s', '<Del>', '<C-g>"_c')

-------------------------------------------------------------------------------
-- The panels (files, terminal, preview, running code) and the AI live in their own files
-------------------------------------------------------------------------------
_G.Golem = {
  say = say, ask = ask, tilde = tilde, is_text = is_text, truth = truth, P = P, face = face,
  save = save, open_path = open_path, open_ask = open_ask, map = map, all = all, here = here,
  write_buf = write_buf, autosave_now = autosave_all, state = state, quit = quit, guide = guide,
}
for _, part in ipairs({ 'mace.lua', 'panels.lua', 'ai.lua', 'writing.lua', 'flow.lua', 'dashboard.lua' }) do
  local ok, err = pcall(dofile, here .. '/' .. part)
  if not ok then vim.schedule(function() say('PART OF THE EDITOR FAILED TO LOAD: ' .. tostring(err)) end) end
end

-------------------------------------------------------------------------------
-- Your own extension settings (editor/extensions.lua), then the start
-------------------------------------------------------------------------------
local extra = vim.env.GOLEM_EDIT_EXTENSIONS
if extra and fn.filereadable(extra) == 1 then
  local ok, err = pcall(dofile, extra)
  if not ok then vim.schedule(function() say('AN EXTENSION SETTING FAILED: ' .. tostring(err)) end) end
end

api.nvim_create_autocmd('VimEnter', {
  callback = function()
    local args = fn.argv()
    if #args == 0 then
      _G.GolemStart()
    elseif #args == 1 and fn.isdirectory(args[1]) == 1 then
      local dir = fn.fnamemodify(args[1], ':p')
      vim.cmd('silent! bwipeout')
      vim.cmd('cd ' .. fn.fnameescape(dir))
      _G.GolemStart()
      vim.schedule(_G.GolemFind)
    else
      back_to_typing()
    end
  end,
})
