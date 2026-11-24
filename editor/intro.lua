-- Golem editor: a short tour. It shows the first time the editor opens, and again with W on the
-- dashboard or "A short tour" in the F1 list. Arrows or Enter turn the pages, Esc closes it.
-- Part of Golem: GADA, the editor; MAP.md section 5.7.

local api, fn = vim.api, vim.fn
local S = _G.Golem
local seen = vim.env.HOME .. '/.local/share/golem-edit/intro-seen'

local PAGES = {
  { 'WELCOME', {
    'This is GADA, your editor.',
    '',
    'Just type. There are no modes to learn: it works like Notepad.',
    '',
    'Everything you write saves by itself, about 2 seconds after you',
    'stop. The bottom line says SAVED only when the file on the disk',
    'is exactly what you see.',
  } },
  { 'FILES', {
    'Ctrl+N        a new file',
    'Ctrl+O        open a file (type its path; Tab finishes names)',
    'Ctrl+P        find a file by part of its name',
    'Alt+E         FILES: explore everything (copy, move, the Bin)',
    'Alt+P         pin a file or folder to the dashboard, in a group',
    'Ctrl+S        save now (a new file asks for its name)',
    'Ctrl+W        close this file',
    'Ctrl+Q        close the editor',
  } },
  { 'WRITING', {
    'Shift+arrows  select            Ctrl+A   select everything',
    'Ctrl+C / X / V                  copy / cut / paste',
    'Ctrl+Z / Ctrl+Y                 undo / redo',
    'Ctrl+F        find a word       F3       the next one',
    'Ctrl+R        replace a word everywhere in this file',
    'Ctrl+G        go to a line number',
  } },
  { 'CODE', {
    'F5            run this file (what it prints shows at the bottom)',
    'Ctrl+J        your own terminal at the bottom',
    'F6            a live preview of HTML or Markdown',
    'F9            your code as a flowchart',
    'F10           build code from snap-together blocks',
    'F11           build Python by joining boxes with wires',
    'F12           the whole project as a 3D map',
    'Ctrl+K        ask the AI',
  } },
  { 'THE LOOK', {
    'Alt+G         the gada: animations, which weapon, sounds',
    'Ctrl+Shift+M  the glass screen\'s menu: glow, curve, styles',
    'Ctrl+Plus     bigger letters      Ctrl+Minus   smaller',
    '',
    'The gada floats in the top-right corner while you write,',
    'and strikes when you save.',
  } },
  { 'LOST?', {
    'Press F1, anywhere.',
    '',
    'You get a list of everything the editor can do, each with its',
    'key. Type a word ("run", "find", "pin") and press Enter: it does',
    'it for you.',
    '',
    'W on the dashboard shows this tour again.',
  } },
}

function S.intro()
  local W = math.min(68, vim.o.columns - 4)
  local H = 12
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'wipe'
  local ok, win = pcall(api.nvim_open_win, b, true, {
    relative = 'editor', width = W, height = H, style = 'minimal', border = 'rounded', zindex = 250,
    row = math.max(0, math.floor((vim.o.lines - H) / 2) - 1), col = math.max(0, math.floor((vim.o.columns - W) / 2)),
    title = ' GADA  ·  A SHORT TOUR ', title_pos = 'center',
  })
  if not ok then return end
  vim.cmd('stopinsert')
  local i = 1
  local function draw()
    local title, body = PAGES[i][1], PAGES[i][2]
    local lines = { '', '  ' .. title, '' }
    for _, l in ipairs(body) do lines[#lines + 1] = '  ' .. l end
    while #lines < H - 1 do lines[#lines + 1] = '' end
    local foot = (i < #PAGES and 'Enter or →: next' or 'Enter: start writing') .. '    ←: back    Esc: close'
    lines[H] = '  ' .. foot .. string.rep(' ', math.max(1, W - #foot - 9)) .. i .. ' / ' .. #PAGES
    vim.bo[b].modifiable = true
    api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].modifiable = false
    api.nvim_buf_add_highlight(b, -1, 'Title', 1, 0, -1)
  end
  local function done()
    fn.mkdir(fn.fnamemodify(seen, ':h'), 'p')
    fn.writefile({ 'seen' }, seen)
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
  end
  local function go(d)
    if i + d > #PAGES then return done() end
    i = math.max(1, i + d)
    draw()
  end
  local function key(k, f) vim.keymap.set('n', k, f, { buffer = b, nowait = true, silent = true }) end
  for _, k in ipairs({ '<CR>', '<Right>', '<Space>', 'l', '<Down>' }) do key(k, function() go(1) end) end
  for _, k in ipairs({ '<Left>', 'h', '<BS>', '<Up>' }) do key(k, function() go(-1) end) end
  for _, k in ipairs({ '<Esc>', 'q', '<C-q>' }) do key(k, done) end
  draw()
end

-- The first time the editor opens, the dashboard asks for the tour (see dashboard.lua).
function S.intro_first()
  if fn.filereadable(seen) == 0 then vim.defer_fn(S.intro, 600) end
end
