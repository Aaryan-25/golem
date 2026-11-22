-- Golem editor: help while writing.
--
--   Spell check     misspelled words are underlined in ember (English; in code, only comments
--                   and text). F8 turns it on / off. Alt+. on a word: suggestions, or "add to my
--                   dictionary" (kept in ~/.local/share/golem-edit/spell).
--   Suggestions     after a few letters, words already in your files are offered below the
--                   cursor. Tab takes the first one (or the one you picked with the arrows);
--                   Esc closes the list; just keep typing to ignore it.
--   Open files      with two or more files open, a bar at the top names them (● = not saved).
--                   Ctrl+PageDown / Ctrl+PageUp next / previous, Ctrl+W closes the file.
--   Pinned          Alt+P pins this file to the dashboard (again: unpins it).
--   Last session    the files you had open are remembered when you close; R on the dashboard
--                   opens them again where you left off.
--
-- Alt+G (settings) can turn spell check and suggestions on or off too.

local api, fn = vim.api, vim.fn
local S = _G.Golem
local P = S.P
local say, map, all = S.say, S.map, S.all
local box = vim.env.HOME .. '/.local/share/golem-edit'

-- Small on/off choices, kept in ~/.local/share/golem-edit/writing.conf
local W = { spell = 'on', suggest = 'on' }
do
  local f = io.open(box .. '/writing.conf', 'r')
  if f then
    for line in f:lines() do
      local k, v = line:match('^(%w+)=(%w+)$')
      if k and W[k] then W[k] = v end
    end
    f:close()
  end
end
local function keep()
  fn.mkdir(box, 'p')
  fn.writefile({ 'spell=' .. W.spell, 'suggest=' .. W.suggest }, box .. '/writing.conf')
end

-------------------------------------------------------------------------------
-- Spell check
-------------------------------------------------------------------------------
fn.mkdir(box .. '/spell', 'p')
vim.opt.spelllang = { 'en' }
vim.opt.spellfile = box .. '/spell/en.utf-8.add'
vim.opt.spellcapcheck = '' -- no nagging about capital letters
pcall(function() vim.opt.spelloptions = { 'camel' } end) -- "myVariableName" counts as words
api.nvim_set_hl(0, 'SpellBad', { fg = P.ember, underline = true, sp = P.ember })
api.nvim_set_hl(0, 'SpellCap', {})
api.nvim_set_hl(0, 'SpellRare', {})
api.nvim_set_hl(0, 'SpellLocal', {})

local function apply_spell()
  for _, w in ipairs(api.nvim_list_wins()) do
    local b = api.nvim_win_get_buf(w)
    if S.is_text(b) then vim.wo[w].spell = W.spell == 'on' end
  end
end
api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'FileType' }, {
  callback = function() if S.is_text() then vim.wo.spell = W.spell == 'on' end end,
})

local function toggle_spell()
  W.spell = W.spell == 'on' and 'off' or 'on'
  keep()
  apply_spell()
  say('SPELL CHECK ' .. W.spell:upper())
end

-- Alt+.: the word at (or just before) the cursor: suggestions, or keep it as a real word.
local function fix_word()
  if not S.is_text() then return end
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  -- the misspelled word nearest before the cursor on this line (else the word at the cursor)
  local words, i = {}, 1
  while true do
    local a, b = line:find('[%a\128-\255\']+', i)
    if not a then break end
    words[#words + 1] = { a, b }
    i = b + 1
  end
  local pick, near = nil, nil
  for _, w in ipairs(words) do
    if w[1] - 1 <= col then
      near = w
      if fn.spellbadword(line:sub(w[1], w[2]))[1] ~= '' then pick = w end
    end
  end
  if not pick then
    for _, w in ipairs(words) do -- none before: the first one after
      if w[1] - 1 > col and fn.spellbadword(line:sub(w[1], w[2]))[1] ~= '' then pick = w; break end
    end
  end
  pick = pick or near
  if not pick then return say('NO WORD HERE') end
  local s, e = pick[1], pick[2]
  local word = line:sub(s, e)
  local bad = fn.spellbadword(word)[1]
  if bad == '' then return say('"' .. word .. '" IS SPELLED RIGHT') end
  local list = fn.spellsuggest(word, 8)
  local items = {}
  for _, w in ipairs(list) do items[#items + 1] = { w, w } end
  items[#items + 1] = { 'add', 'Add "' .. word .. '" to my dictionary (it is a real word)' }
  vim.ui.select(items, { prompt = 'SPELLING', format_item = function(x) return x[2] end }, function(choice)
    if not choice then return end
    if choice[1] == 'add' then
      vim.cmd('silent spellgood ' .. fn.fnameescape(word))
      say('"' .. word .. '" ADDED TO YOUR DICTIONARY')
    else
      local cur = api.nvim_buf_get_lines(0, row - 1, row, false)[1]
      if cur:sub(s, e) == word then
        api.nvim_buf_set_lines(0, row - 1, row, false, { cur:sub(1, s - 1) .. choice[1] .. cur:sub(e + 1) })
        pcall(api.nvim_win_set_cursor, 0, { row, s - 1 + #choice[1] })
      end
    end
  end)
end

-- In the questions at the bottom (OPEN, SAVE AS, FIND...): Ctrl+A clears what's there, so you
-- type over it (like "select all" would); Ctrl+V pastes.
vim.keymap.set('c', '<C-a>', '<C-e><C-u>', { silent = false })
vim.keymap.set('c', '<C-v>', '<C-r>+', { silent = false })

map(all, '<F8>', toggle_spell)
map(all, '<M-.>', fix_word)

-------------------------------------------------------------------------------
-- Word suggestions while typing (extension: mini.completion, words from your open files)
-------------------------------------------------------------------------------
local comp_ok, comp = pcall(require, 'mini.completion')
if comp_ok then
  comp.setup({
    delay = { completion = 250, info = 10000000, signature = 10000000 },
    lsp_completion = { source_func = 'omnifunc', auto_setup = false },
    fallback_action = '<C-n>',
    mappings = { force_twostep = '', force_fallback = '' },
    set_vim_settings = true,
  })
  vim.opt.complete = { '.', 'w', 'b' } -- words from this file and the other open ones
  vim.opt.pumheight = 6
  local function apply_suggest()
    vim.g.minicompletion_disable = W.suggest ~= 'on'
  end
  apply_suggest()
  S.toggle_suggest = function()
    W.suggest = W.suggest == 'on' and 'off' or 'on'
    keep()
    apply_suggest()
    say('WORD SUGGESTIONS ' .. W.suggest:upper())
  end
end
api.nvim_set_hl(0, 'Pmenu', { fg = P.mist, bg = P.void })
api.nvim_set_hl(0, 'PmenuSel', { fg = P.void, bg = P.pale, bold = true })
api.nvim_set_hl(0, 'PmenuSbar', { bg = P.void })
api.nvim_set_hl(0, 'PmenuThumb', { bg = P.shade })

-- Tab takes a suggestion; Esc closes the list (and, with no list, stops showing matches)
vim.keymap.set('i', '<Tab>', function()
  if fn.pumvisible() == 1 then
    return fn.complete_info({ 'selected' }).selected == -1 and '<C-n><C-y>' or '<C-y>'
  end
  return '<Tab>'
end, { expr = true, silent = true })
vim.keymap.set('i', '<Esc>', function()
  if fn.pumvisible() == 1 then return '<C-e>' end
  return '<Cmd>nohlsearch<CR>'
end, { expr = true, silent = true })

-------------------------------------------------------------------------------
-- The bar of open files (only when two or more are open)
-------------------------------------------------------------------------------
api.nvim_set_hl(0, 'TabLine', { fg = P.mist, bg = 'NONE' })
api.nvim_set_hl(0, 'TabLineSel', { fg = P.pale, bg = P.shade, bold = true })
api.nvim_set_hl(0, 'TabLineFill', { bg = 'NONE' })

local function open_files()
  local list = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and api.nvim_buf_is_loaded(b) and S.is_text(b) then
      local n = api.nvim_buf_get_name(b)
      if n ~= '' or vim.bo[b].modified then list[#list + 1] = b end
    end
  end
  return list
end

function _G.GolemTabs()
  local cur = api.nvim_get_current_buf()
  local out = { '%#TabLineFill# ' }
  for _, b in ipairs(open_files()) do
    local n = api.nvim_buf_get_name(b)
    local label = n ~= '' and fn.fnamemodify(n, ':t') or 'NEW FILE'
    if vim.bo[b].modified then label = label .. ' ●' end
    out[#out + 1] = (b == cur and '%#TabLineSel#' or '%#TabLine#') .. '  ' .. label:gsub('%%', '%%%%') .. '  '
  end
  out[#out + 1] = '%#TabLineFill#%=%#TabLine#CTRL+PGDN NEXT  ·  CTRL+W CLOSE  '
  return table.concat(out)
end
vim.o.tabline = '%!v:lua.GolemTabs()'

local function update_bar()
  local n = #open_files()
  vim.o.showtabline = n >= 2 and 2 or 0
end
api.nvim_create_autocmd({ 'BufAdd', 'BufDelete', 'BufWipeout', 'BufEnter', 'BufModifiedSet' }, {
  callback = function() vim.schedule(update_bar) end,
})

local function step(dir)
  local list = open_files()
  if #list < 2 then return end
  local cur = api.nvim_get_current_buf()
  local i = 1
  for k, b in ipairs(list) do if b == cur then i = k end end
  i = (i - 1 + dir) % #list + 1
  api.nvim_set_current_buf(list[i])
end

local function close_file()
  local b = api.nvim_get_current_buf()
  if not S.is_text(b) then return end
  S.autosave_now()
  if vim.bo[b].modified then
    local c = fn.confirm('THIS FILE IS NOT SAVED (' .. S.state(b) .. ').', '&Save it\n&Throw away the changes\n&Keep it open', 3)
    if c == 1 then
      if not S.save() or vim.bo[b].modified then return end
    elseif c ~= 2 then
      return
    end
  end
  local others = vim.tbl_filter(function(x) return x ~= b end, open_files())
  if #others > 0 then api.nvim_set_current_buf(others[#others]) else _G.GolemStart() end
  pcall(api.nvim_buf_delete, b, { force = true })
  update_bar()
end

map(all, '<C-PageDown>', function() step(1) end)
map(all, '<C-PageUp>', function() step(-1) end)
map(all, '<C-w>', close_file)

-------------------------------------------------------------------------------
-- Pinned files, and the last session
-------------------------------------------------------------------------------
local pin_file = box .. '/pinned'

function S.pinned()
  local out = {}
  if fn.filereadable(pin_file) == 1 then
    for _, p in ipairs(fn.readfile(pin_file)) do
      if p ~= '' and (fn.filereadable(p) == 1 or fn.isdirectory(p) == 1) then out[#out + 1] = p end
    end
  end
  return out
end

local function toggle_pin()
  local n = api.nvim_buf_get_name(0)
  if n == '' or not S.is_text() then return say('SAVE THE FILE FIRST, THEN PIN IT') end
  local list, found = S.pinned(), false
  for i, p in ipairs(list) do
    if p == n then table.remove(list, i); found = true; break end
  end
  if not found then table.insert(list, 1, n) end
  fn.mkdir(box, 'p')
  fn.writefile(list, pin_file)
  say(found and ('UNPINNED ' .. S.tilde(n)) or ('PINNED TO THE DASHBOARD: ' .. S.tilde(n)))
end
map(all, '<M-p>', toggle_pin)

local session_file = box .. '/session.json'

api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    local files, cur = {}, api.nvim_get_current_buf()
    for _, b in ipairs(open_files()) do
      local n = api.nvim_buf_get_name(b)
      if n ~= '' then
        local pos = api.nvim_buf_get_mark(b, '"')
        if b == cur then pos = api.nvim_win_get_cursor(0) end
        table.insert(files, b == cur and 1 or #files + 1, { file = n, line = pos[1], col = pos[2] })
      end
    end
    if #files > 0 then
      fn.mkdir(box, 'p')
      pcall(fn.writefile, { vim.json.encode(files) }, session_file)
    end
  end,
})

function S.session()
  if fn.filereadable(session_file) == 0 then return {} end
  local ok, list = pcall(vim.json.decode, table.concat(fn.readfile(session_file), ''))
  if not ok or type(list) ~= 'table' then return {} end
  return vim.tbl_filter(function(x) return type(x) == 'table' and fn.filereadable(x.file or '') == 1 end, list)
end

function S.reopen()
  local list = S.session()
  if #list == 0 then return say('NOTHING TO REOPEN') end
  for i = #list, 1, -1 do -- the one you were in last ends up in front
    vim.cmd('edit ' .. fn.fnameescape(list[i].file))
    pcall(api.nvim_win_set_cursor, 0, { list[i].line or 1, list[i].col or 0 })
  end
  update_bar()
  say('REOPENED ' .. #list .. (#list == 1 and ' FILE' or ' FILES'))
end

-- For the Alt+G settings list
S.writing = {
  items = function()
    local items = {
      { 'spell', 'Spell check:  ' .. W.spell:upper() .. '   (F8)', toggle_spell },
    }
    if S.toggle_suggest then
      items[#items + 1] = { 'suggest', 'Word suggestions while typing:  ' .. W.suggest:upper(), S.toggle_suggest }
    end
    return items
  end,
}
