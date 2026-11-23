-- Golem editor: the "do anything" list (F1).
--
-- Every action of the editor in one list, each with its key beside it. Type a few letters of
-- what you want ("flow", "spell", "pin"); Enter does it. The whole guide is in the list too.
-- Nothing here is new: each line runs the same thing as its key, so the list can never drift
-- from what the keys do.

local api = vim.api
local S = _G.Golem

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), 'm', false)
end

-- { what it does, its key (as shown), what to do }; a string = press that key for you
local ITEMS = {
  { 'FILES', nil },
  { 'New file', 'Ctrl+N', '<C-n>' },
  { 'Open a file (type its path)', 'Ctrl+O', '<C-o>' },
  { 'Find a file by part of its name', 'Ctrl+P', '<C-p>' },
  { 'Files panel on the left', 'Ctrl+B', '<C-b>' },
  { 'FILES: explore your whole computer (copy, move, rename, the Bin)', 'Alt+E', '<M-e>' },
  { 'List of the files you have open', 'Ctrl+E', '<C-e>' },
  { 'Next open file', 'Ctrl+PageDown', '<C-PageDown>' },
  { 'Previous open file', 'Ctrl+PageUp', '<C-PageUp>' },
  { 'Save (and tidy the code)', 'Ctrl+S', '<C-s>' },
  { 'Close this file', 'Ctrl+W', '<C-w>' },
  { 'Pin this file to the dashboard, in a group (or unpin)', 'Alt+P', '<M-p>' },
  { 'Reopen the files I had open last time', 'R on the dashboard', function() if S.reopen then S.reopen() end end },
  { 'Dashboard', 'opening without a file', function() _G.GolemStart() end },
  { 'Close the editor', 'Ctrl+Q', '<C-q>' },

  { 'WRITING', nil },
  { 'Find a word', 'Ctrl+F', '<C-f>' },
  { 'Find the next one / the one before', 'F3 / Shift+F3', '<F3>' },
  { 'Replace a word everywhere in this file', 'Ctrl+R', '<C-r>' },
  { 'Go to a line number', 'Ctrl+G', '<C-g>' },
  { 'Undo / redo', 'Ctrl+Z / Ctrl+Y', '<C-z>' },
  { 'Fix the spelling of a word (or add it to my dictionary)', 'Alt+.', '<M-.>' },
  { 'Spell check on / off', 'F8', '<F8>' },
  { 'Word suggestions while typing on / off', 'Alt+G list', function() if S.toggle_suggest then S.toggle_suggest() end end },
  { 'Tidy the code now', 'Alt+Shift+F', '<M-F>' },
  { 'Line numbers on / off', 'Ctrl+L', '<C-l>' },
  { 'Word wrap on / off', 'Alt+Z', '<M-z>' },
  { 'Bigger / smaller letters', 'Ctrl+Plus / Ctrl+Minus', function()
    S.say('PRESS CTRL+PLUS OR CTRL+MINUS: THE SCREEN ITSELF DOES THAT (AND REMEMBERS IT)')
  end },
  { 'Screen style (Cool Retro Term settings)', 'Ctrl+Shift+M', function()
    S.say('PRESS CTRL+SHIFT+M: A MENU BAR WITH COOL RETRO TERM\'S OWN SETTINGS AND STYLES')
  end },
  { 'A short tour of the editor', 'W on the dashboard', function() if S.intro then S.intro() end end },

  { 'CODE', nil },
  { 'Run this file', 'F5', '<F5>' },
  { 'Terminal panel at the bottom', 'Ctrl+J', '<C-j>' },
  { 'Switch the terminal\'s shell (bash, python, node...)', 'Alt+S in the terminal', function()
    feed('<C-j>'); vim.defer_fn(function() feed('<M-s>') end, 150)
  end },
  { 'Live preview on the right (HTML, Markdown, any text)', 'F6', '<F6>' },
  { 'Picture of this code (PNG)', 'F7', '<F7>' },
  { 'Flowchart of this code', 'F9', '<F9>' },
  { 'Block builder (snap blocks, code is written)', 'F10', '<F10>' },
  { 'Move between my text and the panels', 'Alt+arrows', function()
    S.say('ALT+LEFT / RIGHT / UP / DOWN MOVE BETWEEN YOUR TEXT AND THE PANELS')
  end },

  { 'AI', nil },
  { 'AI menu', 'Ctrl+K', '<C-k>' },
  -- the AI's own actions are added below (from ai.lua)

  { 'GADA AND SETTINGS', nil },
  { 'Settings: animations, weapon, sound, spelling...', 'Alt+G', '<M-g>' },
  { 'Codex: the relics I have found', 'C on the dashboard', function() if S.gada then S.gada.codex() end end },

  { 'HELP', nil },
  { 'Read the whole guide', 'H on the dashboard', function() S.guide() end },
}

local function list()
  local out, section = {}, ''
  for _, it in ipairs(ITEMS) do
    if not it[2] and not it[3] then
      section = it[1]
    else
      out[#out + 1] = { section = section, label = it[1], key = it[2], run = it[3] }
    end
    if it[1] == 'AI menu' and S.ai_actions then
      for _, a in ipairs(S.ai_actions) do
        out[#out + 1] = { section = 'AI', label = 'AI: ' .. a[1], key = 'Ctrl+K list', run = a[2] }
      end
    end
  end
  return out
end

function S.palette()
  local items = list()
  local w = 0
  for _, it in ipairs(items) do w = math.max(w, vim.fn.strdisplaywidth(it.label)) end
  local back = api.nvim_get_current_win()
  vim.ui.select(items, {
    prompt = 'DO',
    format_item = function(it)
      -- the section's name is part of the line, so typing "code" or "files" finds a whole group
      local label = it.label .. string.rep(' ', w - vim.fn.strdisplaywidth(it.label) + 3)
      return label .. string.format('%-24s', it.key or '') .. it.section:lower()
    end,
  }, function(it)
    if not it then return end
    if api.nvim_win_is_valid(back) then api.nvim_set_current_win(back) end
    if type(it.run) == 'function' then it.run() else feed(it.run) end
  end)
end

S.map(S.all, '<F1>', S.palette)
