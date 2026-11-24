-- Golem editor: the flowchart view (F9). Your code, drawn as boxes and arrows on the right.
--
--   F9            open / close it (from the chart, F9 or Esc goes back to your text)
--   Python        drawn on this computer, and redrawn as you type (half a second after you stop)
--   other code    drawn by the AI when you open it (it needs Wi-Fi); F9 twice redraws it
--   in the chart  the boxes of the line you are on light up; Enter (or a click) on a box jumps
--                 to that line in your code; arrows move
--
-- The drawing comes from the helper golem-flow, which reads the code but never runs it.
-- Part of Golem: GADA, the editor; MAP.md section 5.7.

local api, fn = vim.api, vim.fn
local uv = vim.uv or vim.loop
local S = _G.Golem
local P = S.P
local say = S.say
local ns = api.nvim_create_namespace('golem_flow')

local view = { win = nil, buf = nil, src = nil, map = {}, ai = false }

api.nvim_set_hl(0, 'GolemFlowTitle', { fg = P.pale, bold = true })
api.nvim_set_hl(0, 'GolemFlowBox', { fg = P.mist })
api.nvim_set_hl(0, 'GolemFlowText', { fg = P.text })
api.nvim_set_hl(0, 'GolemFlowChoice', { fg = P.blue, bold = true })
api.nvim_set_hl(0, 'GolemFlowLoop', { fg = P.teal, bold = true })
api.nvim_set_hl(0, 'GolemFlowEnd', { fg = P.ember, bold = true })
api.nvim_set_hl(0, 'GolemFlowHere', { fg = P.void, bg = P.pale })

local function open_win()
  return view.win and api.nvim_win_is_valid(view.win)
end

-- Colour each row by what it is.
local function paint(lines)
  api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
  for i, l in ipairs(lines) do
    local g
    if l:find('■') or l:find('▣') or l:find('●') then g = 'GolemFlowTitle'
    elseif l:find('◆') or l:find('[├└]─') then g = 'GolemFlowChoice'
    elseif l:find('⟳') or l:find('↺') then g = 'GolemFlowLoop'
    elseif l:find('⏎') or l:find('⇥') or l:find('⚠') or l:find('↻') then g = 'GolemFlowEnd'
    elseif l:find('│ ') and l:find(' │$') then g = 'GolemFlowText'
    else g = 'GolemFlowBox' end
    pcall(api.nvim_buf_add_highlight, view.buf, ns, g, i - 1, 0, -1)
  end
end

-- The rows for the line you're on light up.
local here_ns = api.nvim_create_namespace('golem_flow_here')
local function follow()
  if not open_win() or not view.buf or view.ai then return end
  api.nvim_buf_clear_namespace(view.buf, here_ns, 0, -1)
  local line = api.nvim_win_get_cursor(0)[1]
  -- the nearest drawn line at or above the cursor
  local best = 0
  for _, m in ipairs(view.map) do
    if m <= line and m > best then best = m end
  end
  if best == 0 then return end
  local first
  for i, m in ipairs(view.map) do
    if m == best then
      first = first or i
      pcall(api.nvim_buf_add_highlight, view.buf, here_ns, 'GolemFlowHere', i - 1, 0, -1)
    end
  end
  if first then -- keep it in sight
    local top, h = fn.line('w0', view.win), api.nvim_win_get_height(view.win)
    if first < top or first > top + h - 2 then
      pcall(api.nvim_win_call, view.win, function() vim.cmd('normal! ' .. first .. 'Gzz') end)
    end
  end
end

local function show(lines, map, note)
  if not view.buf or not api.nvim_buf_is_valid(view.buf) then return end
  local head = { note or 'FLOWCHART  ·  ' .. fn.fnamemodify(api.nvim_buf_get_name(view.src), ':t'), '' }
  local all = vim.list_extend(head, lines)
  view.map = vim.list_extend({ 0, 0 }, map or {})
  vim.bo[view.buf].modifiable = true
  api.nvim_buf_set_lines(view.buf, 0, -1, false, all)
  vim.bo[view.buf].modifiable = false
  paint(all)
  pcall(api.nvim_buf_add_highlight, view.buf, ns, 'GolemDim', 0, 0, -1)
end

-- Python: drawn here. Returns at once; the chart appears when the helper answers.
local busy = false
local function draw_python()
  if busy or not view.src or not api.nvim_buf_is_valid(view.src) then return end
  busy = true
  local text = table.concat(api.nvim_buf_get_lines(view.src, 0, -1, false), '\n') .. '\n'
  local width = open_win() and api.nvim_win_get_width(view.win) - 2 or 44
  local chunks = {}
  local job = fn.jobstart({ 'golem-flow', '--width', tostring(width) }, {
    stdout_buffered = true,
    on_stdout = function(_, d) chunks = d end,
    on_exit = function()
      vim.schedule(function()
        busy = false
        local ok, res = pcall(vim.json.decode, table.concat(chunks, '\n'))
        if not ok or type(res) ~= 'table' then return end
        if res.error and res.error ~= vim.NIL then
          -- keep the last good chart; say where the mistake is
          if view.buf and api.nvim_buf_is_valid(view.buf) then
            vim.bo[view.buf].modifiable = true
            api.nvim_buf_set_lines(view.buf, 0, 1, false, { 'FLOWCHART  ·  waiting: the code has a mistake on ' .. res.error })
            vim.bo[view.buf].modifiable = false
            pcall(api.nvim_buf_add_highlight, view.buf, ns, 'GolemFlowEnd', 0, 0, -1)
          end
          return
        end
        show(res.lines, res.map)
        follow()
      end)
    end,
  })
  if job > 0 then
    fn.chansend(job, text)
    fn.chanclose(job, 'stdin')
  else
    busy = false
    say('THE FLOWCHART HELPER (golem-flow) IS MISSING')
  end
end

-- Other languages: drawn by the AI, in the same signs.
local function draw_ai()
  if not S.ask_ai then return show({ '(the AI part is not loaded)' }, {}) end
  local name = api.nvim_buf_get_name(view.src)
  local code = table.concat(api.nvim_buf_get_lines(view.src, 0, -1, false), '\n')
  local width = open_win() and api.nvim_win_get_width(view.win) - 2 or 44
  show({ '', '  the AI is drawing it…' }, {}, 'FLOWCHART  ·  ' .. fn.fnamemodify(name, ':t') .. '  ·  by the AI')
  S.ask_ai('a flowchart of ' .. fn.fnamemodify(name, ':t'),
    'Draw this code as a flowchart in plain text, at most ' .. width .. ' characters wide, using exactly these '
    .. 'signs: "■ def name(args)" for each function with its steps indented below; boxes drawn with ┌─┐ │ │ └─┘ '
    .. 'for plain steps; "  ▼" between steps; "◆ if <condition> ?" for choices with branches "├─ yes", '
    .. '"├─ else if ...", "└─ no" and their steps indented; "⟳ for/while ..." for loops ending with '
    .. '"↺ back to the loop"; "⏎ return ..." for returns. Functions first, then "● the program". Reply with '
    .. 'only the drawing in one code block.\n```\n' .. code .. '\n```',
    function(answer)
      local body = answer:match('```[%w]*\n(.-)\n```') or answer
      show(vim.split(body, '\n', { plain = true }), {}, 'FLOWCHART  ·  ' .. fn.fnamemodify(name, ':t') .. '  ·  by the AI  ·  F9 twice redraws')
    end)
end

local function draw()
  if not view.src or not api.nvim_buf_is_valid(view.src) then return end
  view.ai = vim.bo[view.src].filetype ~= 'python'
  if view.ai then draw_ai() else draw_python() end
end

local function close()
  if open_win() then pcall(api.nvim_win_close, view.win, true) end
  view.win = nil
end

local function back()
  if view.src then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if api.nvim_win_get_buf(w) == view.src then return api.nvim_set_current_win(w) end
    end
  end
  S.back_to_text()
end

local function jump()
  local row = api.nvim_win_get_cursor(0)[1]
  local line = view.map[row] or 0
  if line == 0 then -- an arrow or a gap: the box below it
    for r = row, #view.map do if view.map[r] > 0 then line = view.map[r]; break end end
  end
  if line == 0 then return end
  back()
  pcall(api.nvim_win_set_cursor, 0, { line, 0 })
  vim.cmd('normal! zz')
end

local function toggle()
  if vim.bo.filetype == 'golemflow' then return back() end
  if open_win() and view.src == api.nvim_get_current_buf() then
    if view.ai then return draw() end -- F9 again on an AI chart: draw it anew
    return close()
  end
  if not S.is_text() then return say('OPEN A FILE WITH CODE FIRST') end
  view.src = api.nvim_get_current_buf()
  if not view.buf or not api.nvim_buf_is_valid(view.buf) then
    view.buf = api.nvim_create_buf(false, true)
    vim.bo[view.buf].filetype = 'golemflow'
    vim.bo[view.buf].bufhidden = 'hide'
    local o = { buffer = view.buf, nowait = true, silent = true }
    vim.keymap.set('n', '<CR>', jump, o)
    vim.keymap.set('n', '<2-LeftMouse>', jump, o)
    vim.keymap.set('n', '<Esc>', back, o)
    vim.keymap.set('n', '<F9>', back, o)
  end
  if not open_win() then
    local src_win = api.nvim_get_current_win()
    vim.cmd('botright vsplit')
    view.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(view.win, view.buf)
    api.nvim_win_set_width(view.win, math.max(30, math.min(60, math.floor(vim.o.columns * 0.42))))
    for k, v in pairs({ number = false, wrap = false, cursorline = false, spell = false, winfixwidth = true }) do
      vim.wo[view.win][k] = v
    end
    api.nvim_set_current_win(src_win)
  end
  draw()
  if S.relic then S.relic('architect') end
end

-- Redraw Python as you type (after half a second of quiet), and follow your cursor.
local redraw_timer = uv.new_timer()
api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufReadPost', 'FileChangedShellPost' }, {
  callback = function(a)
    if not open_win() or a.buf ~= view.src or view.ai then return end
    redraw_timer:stop()
    redraw_timer:start(500, 0, vim.schedule_wrap(draw_python))
  end,
})
api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  callback = function(a) if open_win() and a.buf == view.src then follow() end end,
})
-- Switching to another file: the chart follows it.
api.nvim_create_autocmd('BufEnter', {
  callback = function(a)
    if open_win() and S.is_text(a.buf) and a.buf ~= view.src and vim.bo[a.buf].filetype == 'python' then
      view.src = a.buf
      draw()
    end
  end,
})
api.nvim_create_autocmd('WinClosed', {
  callback = function(a) if view.win and tonumber(a.match) == view.win then view.win = nil end end,
})

S.map(S.all, '<F9>', toggle)
S.flow = { toggle = toggle }
