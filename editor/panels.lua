-- Golem editor: the panels and the tools around your text.
--
--   Ctrl+B       the files panel on the left (Enter opens; other kinds open in their own app)
--   Ctrl+J       the terminal panel at the bottom (also Ctrl+`); Alt+S there switches shell
--   F5           run this file (its output appears in the bottom panel)
--   F6           live preview on the right (HTML, CSS, JavaScript, Markdown; any other text file as
--                text, with Devanagari joined properly), updates as you type
--   F7           a picture of this code (PNG), saved in ~/media/code
--   F10          the block builder: snap blocks together, the code is written as you build
--   F11          wires: join boxes; the Python is written between two marker lines, the rest stays mine
--   F12          the program map: this project's Python as a 3D landscape; a click opens a function
--   Alt+Shift+F  tidy the code now (Ctrl+S also tidies before saving)
-- Part of Golem: GADA, the editor; MAP.md section 5.7.

local api, fn = vim.api, vim.fn
local S = _G.Golem
local say, ask, tilde, map, all = S.say, S.ask, S.tilde, S.map, S.all

local function have(cmd) return fn.executable(cmd) == 1 end

-------------------------------------------------------------------------------
-- What kind of file is it? Decided by its contents, not its name.
-------------------------------------------------------------------------------
local function mime(path)
  if not have('file') then return 'text/plain' end
  local out = fn.system({ 'file', '-b', '--mime-type', path })
  return (out:gsub('%s+$', ''))
end

function S.is_text_file(path)
  local m = mime(path)
  return m:match('^text/') or m == 'inode/x-empty' or m == 'application/json'
      or m == 'application/x-ndjson' or m:match('xml') or m:match('javascript') or m == 'application/x-empty'
end

-- Pictures, music, video, PDF -> their own app; Word/Excel -> inside the editor (golem-office);
-- links -> golem-browser (through the Gate). golem-open decides and says what it did.
function S.open_other(target)
  if not have('golem-open') then return say('GOLEM-OPEN IS MISSING') end
  local out = {}
  fn.jobstart({ 'golem-open', target }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, d) vim.list_extend(out, d) end,
    on_stderr = function(_, d) vim.list_extend(out, d) end,
    on_exit = function(_, code)
      local msg = vim.trim(table.concat(out, ' '))
      vim.schedule(function()
        if code == 3 then
          vim.cmd('edit ' .. fn.fnameescape(target)) -- it was text after all
        elseif code == 6 and msg ~= '' then          -- Word or Excel: its text copy, written back on each save
          vim.cmd('edit ' .. fn.fnameescape(msg))
          vim.b.golem_office = target
          say('A TEXT COPY OF ' .. tilde(target) .. ': SAVING WRITES IT BACK (THE UNTOUCHED FILE IS KEPT AS .orig)')
        else
          say(msg ~= '' and msg or ('OPENING ' .. tilde(target)))
        end
      end)
    end,
  })
end

-- Word and Excel copies: each save of the copy is written back into the real file.
vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = vim.env.HOME .. '/.local/share/golem-edit/office/*',
  callback = function(a)
    fn.jobstart({ 'golem-office', 'save', a.file }, {
      on_exit = function(_, code)
        if code ~= 0 then vim.schedule(function() say('COULD NOT WRITE BACK INTO THE WORD OR EXCEL FILE') end) end
      end,
    })
  end,
})

-------------------------------------------------------------------------------
-- The files panel (left). Extension: nvim-tree.
-------------------------------------------------------------------------------
local tree_ok, tree = pcall(require, 'nvim-tree')
local tree_api = tree_ok and require('nvim-tree.api') or nil

local function tree_open_node()
  local node = tree_api.tree.get_node_under_cursor()
  if not node then return end
  if node.type == 'directory' or node.nodes then return tree_api.node.open.edit() end
  local path = node.absolute_path
  if S.is_text_file(path) then
    tree_api.node.open.edit()
  else
    S.open_other(path)
  end
end

if tree_ok then
  tree.setup({
    hijack_cursor = true,
    sync_root_with_cwd = true,
    update_focused_file = { enable = true },
    view = { side = 'left', width = 30, signcolumn = 'no' },
    renderer = {
      root_folder_label = function(path) return tilde(path) end,
      indent_markers = { enable = true },
      icons = {
        show = { file = false, folder = false, folder_arrow = true, git = false, modified = false },
        glyphs = { folder = { arrow_closed = '▸', arrow_open = '▾' } },
      },
    },
    filters = { dotfiles = false, git_ignored = false }, -- Golem always shows hidden files
    git = { enable = false },
    diagnostics = { enable = false },
    actions = { open_file = { quit_on_open = false, window_picker = { enable = false } } },
    on_attach = function(b)
      -- Only a few, safe keys: stray typing in the panel never renames or deletes anything.
      local o = { buffer = b, nowait = true, silent = true }
      vim.keymap.set('n', '<F2>', tree_api.fs.rename, o)               -- rename
      vim.keymap.set('n', '<Del>', tree_api.fs.remove, o)              -- delete (asks first)
      vim.keymap.set('n', '+', tree_api.fs.create, o)                  -- new file (end with / for a folder)
      vim.keymap.set('n', '<F5>', tree_api.tree.reload, o)             -- look at the disk again
      vim.keymap.set('n', '.', tree_api.tree.change_root_to_node, o)   -- show only this folder
      vim.keymap.set('n', '<BS>', tree_api.tree.change_root_to_parent, o) -- go up a folder
      vim.keymap.set('n', '<LeftRelease>', function() end, o)
      vim.keymap.set('n', '<CR>', tree_open_node, o)
      vim.keymap.set('n', 'o', tree_open_node, o)
      vim.keymap.set('n', '<2-LeftMouse>', tree_open_node, o)
      vim.keymap.set('n', '<Right>', tree_open_node, o)
      vim.keymap.set('n', '<Left>', tree_api.node.navigate.parent_close, o)
      vim.keymap.set('n', '<C-b>', S.back_to_text, o)
      vim.keymap.set('n', '<Esc>', S.back_to_text, o)
    end,
  })
end

local function files_panel()
  if not tree_ok then return say('THE FILES PANEL EXTENSION (nvim-tree-lua) IS NOT INSTALLED') end
  if vim.bo.filetype == 'NvimTree' then return S.back_to_text() end -- back to your text
  vim.cmd('stopinsert')
  tree_api.tree.open({ find_file = true })
end

-------------------------------------------------------------------------------
-- The terminal panel (bottom): your own command line, any shell.
-------------------------------------------------------------------------------
local term = { buf = nil, win = nil, shell = nil }

local function shells()
  local list = {}
  for _, s in ipairs({ 'bash', 'fish', 'zsh', 'python3', 'node', 'lua', 'ghci', 'irb' }) do
    if have(s) then list[#list + 1] = s end
  end
  return list
end

local function show_bottom(buf)
  if term.win and api.nvim_win_is_valid(term.win) then
    api.nvim_win_set_buf(term.win, buf)
    api.nvim_set_current_win(term.win)
  else
    vim.cmd('botright 12split')
    term.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(term.win, buf)
  end
  vim.wo[term.win].number = false
  vim.wo[term.win].cursorline = false
  vim.wo[term.win].winfixheight = true
  vim.cmd('startinsert')
end

local function new_terminal(cmd, title)
  local buf = api.nvim_create_buf(false, true)
  show_bottom(buf)
  fn.termopen(cmd, { cwd = fn.getcwd() })
  vim.b[buf].golem_term = title
  vim.bo[buf].bufhidden = 'hide'
  return buf
end

-- Back to the window with your text (never into the files panel by accident).
function S.back_to_text()
  vim.schedule(function()
    local cur = api.nvim_get_current_win()
    if S.is_text(api.nvim_win_get_buf(cur)) then return end
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if S.is_text(api.nvim_win_get_buf(w)) or vim.b[api.nvim_win_get_buf(w)].golem_start then
        return api.nvim_set_current_win(w)
      end
    end
  end)
end

local function terminal_panel()
  if vim.bo.buftype == 'terminal' and term.win and api.nvim_get_current_win() == term.win then
    api.nvim_win_close(term.win, true) -- hide it, the shell keeps running
    term.win = nil
    return S.back_to_text()
  end
  if term.win and api.nvim_win_is_valid(term.win) then
    api.nvim_set_current_win(term.win) -- the bottom panel is open (a run or a shell): go there
    vim.cmd('startinsert')
  elseif term.buf and api.nvim_buf_is_valid(term.buf) then
    show_bottom(term.buf)
  else
    term.shell = term.shell or (have('bash') and 'bash' or vim.o.shell)
    term.buf = new_terminal({ term.shell }, term.shell:upper())
  end
end

local function switch_shell()
  local list = shells()
  vim.ui.select(list, { prompt = 'SHELL' }, function(choice)
    if not choice then return end
    term.shell = choice
    if term.buf and api.nvim_buf_is_valid(term.buf) then
      pcall(api.nvim_buf_delete, term.buf, { force = true })
    end
    term.buf = new_terminal({ choice }, choice:upper())
  end)
end

-------------------------------------------------------------------------------
-- Running code (F5): saved first, then run in the bottom panel by golem-run
-------------------------------------------------------------------------------
local run_buf

local function run()
  local b = api.nvim_get_current_buf()
  if not S.is_text(b) then return end
  local name = api.nvim_buf_get_name(b)
  if name == '' then
    if not S.save() then return end
    name = api.nvim_buf_get_name(b)
    if name == '' then return end
  end
  S.autosave_now()
  if vim.bo[b].modified then return say('NOT SAVED, SO NOT RUN (' .. S.state(b) .. ')') end
  local win = api.nvim_get_current_win()
  if run_buf and api.nvim_buf_is_valid(run_buf) then pcall(api.nvim_buf_delete, run_buf, { force = true }) end
  run_buf = new_terminal({ 'golem-run', name }, 'RUN ' .. fn.fnamemodify(name, ':t'):upper())
  local stop = S.busy and S.busy() or function() end -- the gada turns while it runs
  api.nvim_create_autocmd('TermClose', { buffer = run_buf, once = true, callback = function()
    stop()
    local code = vim.v.event and vim.v.event.status or 0
    vim.defer_fn(function() -- it ran fine: raised; it failed: trembles
      if code == 0 then S.raise() else S.shake() end
      if S.run_event then S.run_event(code == 0) end
    end, 150)
  end })
  api.nvim_create_autocmd('BufWipeout', { buffer = run_buf, once = true, callback = function() stop() end })
  if api.nvim_win_is_valid(win) then api.nvim_set_current_win(win) end
  say('RUNNING ' .. fn.fnamemodify(name, ':t') .. '  ·  CTRL+J GOES TO ITS PANEL (TO TYPE INTO IT)')
end

-------------------------------------------------------------------------------
-- Live preview (F6): a small browser on the right, showing this file from this computer only.
-- It reloads whenever the file is saved (autosave does that ~2 s after you stop typing).
-------------------------------------------------------------------------------
local function preview()
  local name = api.nvim_buf_get_name(0)
  if name == '' or not S.is_text() then return say('SAVE THE FILE FIRST (CTRL+S)') end
  -- HTML, Markdown and SVG are shown as pages; any other text file as text (where Hindi and
  -- Sanskrit letters join properly, which the CRT screen can't do)
  S.autosave_now()
  fn.jobstart({ 'golem-preview', fn.fnamemodify(name, ':p') }, { detach = true })
  local stop = S.busy and S.busy() or function() end
  vim.defer_fn(stop, 6000) -- the browser takes a few seconds to appear on the Celeron
  if S.relic then S.relic('mirror') end
  say('PREVIEW OPENS ON THE RIGHT. IT FOLLOWS YOUR TYPING.')
end

-------------------------------------------------------------------------------
-- The block builder (F10): snap blocks together in a window on the right; the code is
-- written into this file as you build, and the editor shows it within a second.
-------------------------------------------------------------------------------
local blocks_job, blocks_watch = nil, nil

local function blocks()
  local b = api.nvim_get_current_buf()
  if not S.is_text(b) then return end
  local name = api.nvim_buf_get_name(b)
  if name == '' then
    say('FIRST GIVE IT A NAME ENDING IN .py, .js OR .lua')
    if not S.save() then return end
    name = api.nvim_buf_get_name(b)
  end
  local ext = fn.fnamemodify(name, ':e'):lower()
  if not (ext == 'py' or ext == 'js' or ext == 'mjs' or ext == 'lua') then
    return say('BLOCKS MAKE PYTHON (.py), JAVASCRIPT (.js) OR LUA (.lua) FILES')
  end
  S.autosave_now()
  if blocks_job then return say('THE BLOCK BUILDER IS ALREADY OPEN') end
  blocks_job = fn.jobstart({ 'golem-blocks', name }, {
    on_exit = function()
      blocks_job = nil
      S.blocks_open = false
      if blocks_watch then blocks_watch:stop(); blocks_watch:close(); blocks_watch = nil end
    end,
  })
  if blocks_job <= 0 then blocks_job = nil; return say('THE BLOCK BUILDER (golem-blocks) IS MISSING') end
  S.blocks_open = true
  -- look at the disk often while it is open, so the code appears as you build
  blocks_watch = (vim.uv or vim.loop).new_timer()
  blocks_watch:start(700, 700, vim.schedule_wrap(function()
    if fn.mode() ~= 'c' then pcall(vim.cmd, 'silent! checktime') end
  end))
  local stop = S.busy and S.busy() or function() end
  vim.defer_fn(stop, 6000)
  if S.relic then S.relic('builder') end
  say('BLOCKS OPEN ON THE RIGHT. THE CODE APPEARS HERE AS YOU BUILD (F9 SHOWS ITS FLOWCHART).')
end

-------------------------------------------------------------------------------
-- Wires (F11): boxes joined by wires in a window on the right. Python only. The code goes between two
-- marker lines in this file; my own functions above stay untouched, and a box can use them.
-------------------------------------------------------------------------------
local wires_job, wires_watch = nil, nil

local function wires()
  local b = api.nvim_get_current_buf()
  if not S.is_text(b) then return end
  local name = api.nvim_buf_get_name(b)
  if name == '' then
    say('FIRST GIVE IT A NAME ENDING IN .py')
    if not S.save() then return end
    name = api.nvim_buf_get_name(b)
  end
  if fn.fnamemodify(name, ':e'):lower() ~= 'py' then return say('WIRES MAKE PYTHON (.py) FILES') end
  S.autosave_now()
  if wires_job then return say('WIRES ARE ALREADY OPEN') end
  wires_job = fn.jobstart({ 'golem-wires', name }, {
    on_exit = function()
      wires_job = nil
      if wires_watch then wires_watch:stop(); wires_watch:close(); wires_watch = nil end
    end,
  })
  if wires_job <= 0 then wires_job = nil; return say('WIRES (golem-wires) ARE MISSING') end
  wires_watch = (vim.uv or vim.loop).new_timer()
  wires_watch:start(700, 700, vim.schedule_wrap(function()
    if fn.mode() ~= 'c' then pcall(vim.cmd, 'silent! checktime') end
  end))
  local stop = S.busy and S.busy() or function() end
  vim.defer_fn(stop, 6000)
  say('WIRES OPEN ON THE RIGHT. THE CODE APPEARS AT THE END OF THIS FILE AS YOU WIRE; F5 RUNS IT.')
end

-------------------------------------------------------------------------------
-- The program map (F12): files as districts, functions as towers, calls as beams, the gada over where I am.
-- The project is the git folder this file is in (or just its folder). A click on a tower comes back here.
-------------------------------------------------------------------------------
local map_job = nil

local function program_map()
  local name = api.nvim_buf_get_name(0)
  if name == '' then return say('OPEN A PYTHON FILE OF THE PROJECT FIRST') end
  if map_job then return say('THE MAP IS ALREADY OPEN') end
  local dir = fn.fnamemodify(name, ':p:h')
  local ok, top = pcall(fn.systemlist, { 'git', '-C', dir, 'rev-parse', '--show-toplevel' })
  if ok and vim.v.shell_error == 0 and top[1] and top[1] ~= '' then dir = top[1] end
  local args = { 'golem-map', dir, '--here', name .. ':' .. fn.line('.') }
  if S.anim_level and S.anim_level() <= 1 then table.insert(args, '--low') end
  map_job = fn.jobstart(args, {
    on_stdout = function(_, lines)
      for _, l in ipairs(lines) do
        local file, ln = l:match('^OPEN (.+):(%d+)$')
        if file then vim.schedule(function()
          vim.cmd('edit ' .. fn.fnameescape(file)); pcall(api.nvim_win_set_cursor, 0, { tonumber(ln), 0 })
          vim.cmd('normal! zz')
        end) end
      end
    end,
    on_exit = function() map_job = nil end,
  })
  if map_job <= 0 then map_job = nil; return say('THE MAP (golem-map) IS MISSING') end
  local stop = S.busy and S.busy() or function() end
  vim.defer_fn(stop, 6000)
  say('THE MAP OPENS ON THE RIGHT: DRAG TO TURN, CLICK A TOWER TO OPEN IT HERE.')
end

-------------------------------------------------------------------------------
-- A picture of the code (F7): PNG in ~/Pictures/code, then shown in the picture viewer.
-------------------------------------------------------------------------------
local function picture()
  if not have('silicon') then return say('THE CODE PICTURE TOOL (silicon) IS NOT INSTALLED') end
  local b = api.nvim_get_current_buf()
  local name = api.nvim_buf_get_name(b)
  local lines
  local mode = fn.mode()
  if mode == 'v' or mode == 'V' or mode == 's' or mode == 'S' then
    local a, z = fn.line('v'), fn.line('.')
    if a > z then a, z = z, a end
    lines = api.nvim_buf_get_lines(b, a - 1, z, false)
  else
    lines = api.nvim_buf_get_lines(b, 0, -1, false)
  end
  local ext = name ~= '' and fn.fnamemodify(name, ':e') or 'txt'
  local dir = vim.env.HOME .. '/media/code' -- Golem's media folder
  fn.mkdir(dir, 'p')
  local out = string.format('%s/%s-%s.png', dir, name ~= '' and fn.fnamemodify(name, ':t:r') or 'code',
    os.date('%Y%m%d-%H%M%S'))
  local face = S.face == 'negative'
  local args = { 'silicon', '--output', out, '--language', ext ~= '' and ext or 'txt',
    '--font', 'DejaVu Sans Mono=22', '--no-window-controls', '--theme', face and 'GitHub' or 'Nord',
    '--background', face and (vim.env.GOLEM_NEGATIVE_VOID or '#eceae4') or S.P.void, '--pad-horiz', '48', '--pad-vert', '40', '--shadow-blur-radius', '0' }
  local res = fn.system(args, table.concat(lines, '\n'))
  if vim.v.shell_error ~= 0 then
    -- an unknown language name: try again as plain text
    args[5] = 'txt'
    res = fn.system(args, table.concat(lines, '\n'))
  end
  if vim.v.shell_error ~= 0 then return say('PICTURE FAILED: ' .. vim.trim(res):sub(1, 80)) end
  S.truth('Editor made a picture of code: ' .. tilde(out))
  if S.relic then S.relic('etching') end
  say('PICTURE SAVED: ' .. tilde(out))
  S.open_other(out)
end

-------------------------------------------------------------------------------
-- Tidy the code (Ctrl+S, Alt+Shift+F): the language's own formatter, if Golem has it.
-------------------------------------------------------------------------------
local tidiers = {
  python = { 'ruff', 'format', '--quiet', '-' },
  sh = { 'shfmt', '-i', '4' },
  bash = { 'shfmt', '-i', '4' },
  lua = { 'stylua', '-' },
  c = { 'clang-format' },
  cpp = { 'clang-format' },
  java = { 'clang-format', '--assume-filename=x.java' },
  go = { 'gofmt' },
  rust = { 'rustfmt', '--emit', 'stdout' },
}
for _, ft in ipairs({ 'javascript', 'typescript', 'json', 'css', 'scss', 'html', 'markdown', 'yaml', 'vue' }) do
  tidiers[ft] = 'prettier'
end

function S.tidy(b, loud)
  b = b or api.nvim_get_current_buf()
  local ft = vim.bo[b].filetype
  local cmd = tidiers[ft]
  if cmd == 'prettier' then
    local name = api.nvim_buf_get_name(b)
    cmd = { 'prettier', '--stdin-filepath', name ~= '' and name or ('x.' .. ft) }
  end
  if not cmd or not have(cmd[1]) then
    if loud then say('NO TIDIER FOR ' .. (ft ~= '' and ft:upper() or 'THIS FILE') .. ' IN GOLEM YET') end
    return
  end
  local lines = api.nvim_buf_get_lines(b, 0, -1, false)
  local out = fn.system(cmd, table.concat(lines, '\n') .. '\n')
  if vim.v.shell_error ~= 0 then
    if loud then say("COULDN'T TIDY (THE CODE HAS A MISTAKE?): " .. vim.trim(out):gsub('\n.*', ''):sub(1, 70)) end
    return
  end
  local new = vim.split(out:gsub('\n$', ''), '\n', { plain = true })
  if vim.deep_equal(new, lines) then
    if loud then say('ALREADY TIDY') end
    return
  end
  local view = fn.winsaveview()
  vim.b[b].golem_tidying = true -- tidying is not deleting: no shatter
  api.nvim_buf_set_lines(b, 0, -1, false, new)
  vim.schedule(function() if api.nvim_buf_is_valid(b) then vim.b[b].golem_tidying = false end end)
  fn.winrestview(view)
  if S.relic then S.relic('tamer') end
  if loud then say('TIDIED') end
end

-------------------------------------------------------------------------------
-- Keys
-------------------------------------------------------------------------------
map(all, '<C-b>', files_panel)
map({ 'n', 'i', 'v', 's', 't' }, '<C-j>', terminal_panel)
map({ 'n', 'i', 'v', 's', 't' }, '<C-@>', terminal_panel) -- Ctrl+` arrives as this
map({ 'n', 'i', 'v', 's', 't' }, '<C-Space>', terminal_panel)
map({ 'n', 't' }, '<M-s>', switch_shell)
map(all, '<F5>', run)
map(all, '<F6>', preview)
map(all, '<F7>', picture)
map(all, '<F10>', blocks)
map(all, '<F11>', wires)
map(all, '<F12>', program_map)
map(all, '<M-F>', function() S.tidy(nil, true) end)

-- Alt+arrows move between the panels and your text.
for k, d in pairs({ ['<M-Left>'] = 'h', ['<M-Right>'] = 'l', ['<M-Up>'] = 'k', ['<M-Down>'] = 'j' }) do
  map({ 'n', 'i', 'v', 's', 't' }, k, function() vim.cmd('stopinsert'); vim.cmd('wincmd ' .. d) end)
end

-- When a run or shell finishes, Enter / Esc / any key closes its panel.
api.nvim_create_autocmd('TermClose', {
  callback = function(a)
    vim.keymap.set('t', '<CR>', function()
      if api.nvim_buf_is_valid(a.buf) then pcall(api.nvim_buf_delete, a.buf, { force = true }) end
      if a.buf == term.buf then term.buf = nil end
      S.back_to_text()
    end, { buffer = a.buf })
  end,
})
api.nvim_create_autocmd('WinClosed', {
  callback = function(a)
    if term.win and tonumber(a.match) == term.win then term.win = nil end
  end,
})
