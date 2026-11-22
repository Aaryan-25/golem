-- Golem editor: the AI (Ctrl+K opens its menu at the bottom).
--
-- Each question is handed to a tiny helper, golem-ai, which sends it and writes the answer
-- back. Your key and settings live in ~/.local/share/golem-edit/ai. Every ask is noted in
-- the truth log.
--
-- AIs: Gemini (online, your key) now; your own offline AI later (Ctrl+K, "Choose the AI",
-- and give its address: any OpenAI-style one, e.g. llama.cpp's server).

local api, fn = vim.api, vim.fn
local S = _G.Golem
local say, ask, tilde = S.say, S.ask, S.tilde
local box = vim.env.HOME .. '/.local/share/golem-edit/ai'

local function read_conf()
  local c = { provider = 'gemini', model = 'gemini-flash-latest', own_url = '', own_model = 'local' }
  local f = io.open(box .. '/ai.conf', 'r')
  if f then
    for line in f:lines() do
      local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
      if k and v then c[k] = v end
    end
    f:close()
  end
  return c
end

local function write_conf(c)
  fn.mkdir(box, 'p')
  fn.writefile({
    '# The editor\'s AI. provider = gemini or own',
    'provider=' .. c.provider,
    'model=' .. c.model,
    '# your own offline AI (later): an OpenAI-style address, e.g. http://127.0.0.1:8080/v1/chat/completions',
    'own_url=' .. (c.own_url or ''),
    'own_model=' .. (c.own_model or 'local'),
  }, box .. '/ai.conf')
end

-------------------------------------------------------------------------------
-- What to send: the selection if there is one, otherwise the whole file
-------------------------------------------------------------------------------
local function grab()
  local b = api.nvim_get_current_buf()
  local m = fn.mode()
  if m == 'v' or m == 'V' or m == 's' or m == 'S' then
    local a, z = fn.line('v'), fn.line('.')
    if a > z then a, z = z, a end
    return table.concat(api.nvim_buf_get_lines(b, a - 1, z, false), '\n'), 'the selected part of '
  end
  return table.concat(api.nvim_buf_get_lines(b, 0, -1, false), '\n'), ''
end

local function filename()
  local n = api.nvim_buf_get_name(0)
  return n ~= '' and fn.fnamemodify(n, ':t') or 'a new file'
end

-------------------------------------------------------------------------------
-- Asking: write the question into the helper's folder, start it, read the answer
-------------------------------------------------------------------------------
local busy = false

local function request(what, prompt, image, done)
  if busy then return say('THE AI IS STILL ANSWERING THE LAST QUESTION') end
  local c = read_conf()
  if c.provider == 'gemini' and fn.filereadable(box .. '/gemini.key') == 0 then
    return say('NO GEMINI KEY YET: CTRL+K, THEN "SET MY GEMINI KEY"')
  end
  if c.provider == 'own' and (c.own_url or '') == '' then
    return say('YOUR OWN AI IS NOT READY YET. CTRL+K, "CHOOSE THE AI" TO USE GEMINI')
  end
  fn.mkdir(box .. '/ask', 'p')
  local id = os.date('%Y%m%d%H%M%S') .. tostring(math.random(1000, 9999))
  local req = { provider = c.provider, model = c.model, url = c.own_url, own_model = c.own_model, prompt = prompt }
  if image then
    local m = vim.trim(fn.system({ 'file', '-b', '--mime-type', image }))
    if not m:match('^image/') then return say('THAT IS NOT A PICTURE: ' .. tilde(image)) end
    fn.system({ 'cp', '--', image, box .. '/ask/' .. id .. '.img' })
    req.image_mime = m
  end
  fn.writefile({ vim.json.encode(req) }, box .. '/ask/' .. id .. '.json')
  busy = true
  S.truth('Editor asked the AI (' .. c.provider .. '): ' .. what)
  say('ASKING ' .. (c.provider == 'gemini' and 'GEMINI' or 'YOUR AI') .. '…  (' .. what .. ')')
  local errs = {}
  local stop = S.busy and S.busy() or function() end
  fn.jobstart({ 'golem-ai', box, id }, {
    stderr_buffered = true,
    on_stderr = function(_, d) vim.list_extend(errs, d) end,
    on_exit = function()
      vim.schedule(function()
        busy = false
        stop()
        local base = box .. '/ask/' .. id
        local out = fn.filereadable(base .. '.out') == 1 and table.concat(fn.readfile(base .. '.out'), '\n') or nil
        local err = fn.filereadable(base .. '.err') == 1 and table.concat(fn.readfile(base .. '.err'), ' ') or nil
        for _, ext in ipairs({ '.json', '.out', '.err', '.img' }) do os.remove(base .. ext) end
        if out and vim.trim(out) ~= '' then
          done(out)
          if S.relic then S.relic('oracle') end
          if S.throw then vim.defer_fn(function() S.throw(2, math.floor(vim.o.columns * 0.78)) end, 100) end
        else
          say('THE AI DID NOT ANSWER: ' .. (err or vim.trim(table.concat(errs, ' '))):sub(1, 120))
          if S.shake then S.shake() end
        end
      end)
    end,
  })
end

-------------------------------------------------------------------------------
-- Showing answers
-------------------------------------------------------------------------------
local answer_win

local function show_answer(text, title)
  local b = api.nvim_create_buf(false, true)
  if S.carve then
    S.carve(b, text) -- carved in, a little at a time
  else
    api.nvim_buf_set_lines(b, 0, -1, false, vim.split(text, '\n', { plain = true }))
  end
  vim.bo[b].filetype = 'markdown'
  vim.bo[b].bufhidden = 'wipe'
  vim.b[b].golem_ai = title
  if answer_win and api.nvim_win_is_valid(answer_win) then
    api.nvim_win_set_buf(answer_win, b)
  else
    local back = api.nvim_get_current_win()
    vim.cmd('botright vsplit')
    answer_win = api.nvim_get_current_win()
    api.nvim_win_set_buf(answer_win, b)
    api.nvim_win_set_width(answer_win, math.floor(vim.o.columns * 0.4))
    api.nvim_set_current_win(back)
  end
  vim.wo[answer_win].wrap = true
  vim.wo[answer_win].linebreak = true
  vim.wo[answer_win].number = false
  say('THE ANSWER IS ON THE RIGHT  ·  ALT+RIGHT GOES THERE  ·  CTRL+K, "CLOSE" HIDES IT')
end

local function code_only(text)
  local body = text:match('```[%w%+%-#_]*\n(.-)\n```')
  return body or text
end

local exts = {
  python = 'py', javascript = 'js', js = 'js', typescript = 'ts', c = 'c', ['c++'] = 'cpp', cpp = 'cpp',
  java = 'java', go = 'go', golang = 'go', rust = 'rs', lua = 'lua', bash = 'sh', shell = 'sh', sh = 'sh',
  html = 'html', css = 'css', ruby = 'rb', php = 'php', kotlin = 'kt', swift = 'swift', r = 'r',
  sql = 'sql', ['c#'] = 'cs', csharp = 'cs', dart = 'dart', haskell = 'hs', markdown = 'md',
}

local function new_code_buffer(code, lang)
  vim.cmd('enew')
  api.nvim_buf_set_lines(0, 0, -1, false, vim.split(code, '\n', { plain = true }))
  local ext = exts[(lang or ''):lower()]
  local ft = ext and vim.filetype.match({ filename = 'x.' .. ext }) or (lang or ''):lower()
  if ft and ft ~= '' then vim.bo.filetype = ft end
  vim.cmd('startinsert')
  say('A NEW FILE FROM THE AI. CTRL+S TO NAME AND KEEP IT' .. (ext and (' (e.g. something.' .. ext .. ')') or ''))
end

-------------------------------------------------------------------------------
-- The menu
-------------------------------------------------------------------------------
local function lang_of_buffer()
  local ft = vim.bo.filetype
  return ft ~= '' and ft or 'plain text'
end

local actions = {
  { 'Ask anything about this code', function()
    local q = ask('ASK THE AI  ')
    if not q or q == '' then return end
    local code, part = grab()
    request('a question about ' .. filename(), q .. '\n\nThis is ' .. part .. filename() .. ' (' .. lang_of_buffer()
      .. '):\n```\n' .. code .. '\n```', nil, function(a) show_answer(a, 'ANSWER') end)
  end },
  { 'Explain this code in simple words', function()
    local code, part = grab()
    request('explain ' .. filename(), 'Explain in simple, plain words (the reader is new to code) what '
      .. part .. filename() .. ' does, step by step:\n```' .. lang_of_buffer() .. '\n' .. code .. '\n```', nil,
      function(a) show_answer(a, 'EXPLAINED') end)
  end },
  { 'Find and fix mistakes', function()
    local code, part = grab()
    request('fix ' .. filename(), 'Find mistakes in ' .. part .. filename() .. '. First list them in plain words, '
      .. 'then give the whole corrected code in one code block:\n```' .. lang_of_buffer() .. '\n' .. code .. '\n```',
      nil, function(a) show_answer(a, 'FIXES') end)
  end },
  { 'Change it to another language', function()
    local to = ask('CHANGE TO WHICH LANGUAGE?  ')
    if not to or to == '' then return end
    local code, part = grab()
    request('change ' .. filename() .. ' to ' .. to, 'Rewrite ' .. part .. filename() .. ' (' .. lang_of_buffer()
      .. ') in ' .. to .. ', doing exactly the same thing. Reply with only one code block.\n```\n' .. code .. '\n```',
      nil, function(a)
        new_code_buffer(code_only(a), to)
        if S.relic then S.relic('tongues') end
      end)
  end },
  { 'Turn a picture into code', function()
    local img = ask('WHICH PICTURE?  ', '~/', 'file')
    if not img or img == '' then return end
    img = fn.fnamemodify(fn.expand(img), ':p')
    local lang = ask('INTO WHICH LANGUAGE? (Enter = HTML)  ')
    if lang == nil then return end
    if lang == '' then lang = 'html' end
    request('picture ' .. fn.fnamemodify(img, ':t') .. ' to ' .. lang, 'Turn this picture into ' .. lang
      .. ' code. If it shows code, copy that code exactly. If it shows a page or a design, write code that '
      .. 'recreates it. Reply with only one code block.', img, function(a) new_code_buffer(code_only(a), lang) end)
  end },
  { 'Write new code from a description', function()
    local d = ask('DESCRIBE IT  ')
    if not d or d == '' then return end
    local lang = ask('IN WHICH LANGUAGE?  ', 'python')
    if not lang or lang == '' then return end
    request('write new ' .. lang .. ' code', 'Write ' .. lang .. ' code that does this: ' .. d
      .. '\nAdd short comments in plain words. Reply with only one code block.', nil,
      function(a) new_code_buffer(code_only(a), lang) end)
  end },
  { 'Close the answer panel', function()
    if answer_win and api.nvim_win_is_valid(answer_win) then api.nvim_win_close(answer_win, true) end
    answer_win = nil
  end },
  { 'Choose the AI (Gemini, or my own when ready)', function()
    local c = read_conf()
    vim.ui.select({ 'gemini', 'own' }, {
      prompt = 'AI (now: ' .. c.provider .. ')',
      format_item = function(i) return i == 'gemini' and 'Gemini (online, your key)' or 'My own offline AI' end,
    }, function(choice)
      if not choice then return end
      c.provider = choice
      if choice == 'own' then
        local url = ask('YOUR AI\'S ADDRESS (OpenAI-style)  ', c.own_url ~= '' and c.own_url
          or 'http://127.0.0.1:8080/v1/chat/completions')
        if url then c.own_url = url end
      else
        local m = ask('GEMINI MODEL  ', c.model)
        if m and m ~= '' then c.model = m end
      end
      write_conf(c)
      say('AI: ' .. c.provider:upper())
    end)
  end },
  { 'Set my Gemini key', function()
    local ok, key = pcall(fn.inputsecret, 'GEMINI KEY (from aistudio.google.com, not shown)  ')
    api.nvim_echo({ { '' } }, false, {})
    if not ok or not key or vim.trim(key) == '' then return end
    fn.mkdir(box, 'p')
    fn.writefile({ vim.trim(key) }, box .. '/gemini.key')
    fn.setfperm(box .. '/gemini.key', 'rw-------')
    if fn.filereadable(box .. '/ai.conf') == 0 then write_conf(read_conf()) end
    S.truth('Editor: Gemini key saved for the AI helper')
    say('GEMINI KEY SAVED')
  end },
}

local function menu()
  local back = api.nvim_get_current_win()
  vim.ui.select(actions, {
    prompt = 'AI  ·  ' .. read_conf().provider:upper(),
    format_item = function(a) return a[1] end,
  }, function(choice)
    if not choice then return end
    if api.nvim_win_is_valid(back) then api.nvim_set_current_win(back) end
    choice[2]()
  end)
end

S.map(S.all, '<C-k>', menu)
-- for other parts (the flowchart of non-Python code)
S.ask_ai = function(what, prompt, done) request(what, prompt, nil, done) end
S.ai_actions = actions -- for the F1 list
