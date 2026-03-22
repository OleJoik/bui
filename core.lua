local current_effect = nil

local M = {}

-- ============================================================
-- Reactive core
-- ============================================================

local Signal = {}
Signal.__index = Signal

function Signal.new(initial)
  return setmetatable({
    _value = initial,
    _subs = {},
  }, Signal)
end

function Signal:get()
  if current_effect then
    self._subs[current_effect] = true
  end
  return self._value
end

function Signal:set(value)
  if self._value == value then
    return
  end

  self._value = value

  for sub, _ in pairs(self._subs) do
    sub()
  end
end

local function effect(fn)
  local wrapped
  wrapped = function()
    current_effect = wrapped
    fn()
    current_effect = nil
  end
  wrapped()
  return wrapped
end

M.Signal = Signal
M.effect = effect

-- ============================================================
-- Elements
-- ============================================================

local function Text(props)
  return {
    type = "text",
    props = props or {},
  }
end

local function Input(props)
  return {
    type = "input",
    props = props or {},
  }
end

local function Column(children, props)
  return {
    type = "column",
    children = children or {},
    props = props or {},
  }
end

local function Row(children, props)
  return {
    type = "row",
    children = children or {},
    props = props or {},
  }
end

M.Text = Text
M.Input = Input
M.Column = Column
M.Row = Row

-- ============================================================
-- Box helpers
-- ============================================================

local function strw(text)
  return vim.fn.strdisplaywidth(tostring(text or ""))
end

local function pad_right(text, width)
  text = tostring(text or "")
  local len = strw(text)
  if len >= width then
    return text
  end
  return text .. string.rep(" ", width - len)
end

local function blank_line(width)
  return string.rep(" ", math.max(0, width))
end

local function extend(dst, src)
  for _, item in ipairs(src or {}) do
    table.insert(dst, item)
  end
end

local function charcol_to_bytecol(line, char_col)
  local byte_col = vim.fn.byteidx(line, char_col)
  if byte_col < 0 then
    return #line
  end
  return byte_col
end

local function shift_focusables(focusables, row_delta, col_delta)
  local shifted = {}

  for _, item in ipairs(focusables or {}) do
    table.insert(shifted, {
      focused = item.focused,
      on_edit = item.on_edit,
      label = item.label,
      width = item.width,

      line_start = item.line_start + row_delta,
      line_end = item.line_end + row_delta,

      input_row = (item.input_row or 0) + row_delta,
      input_col = (item.input_col or 0) + col_delta,

      top = item.top + row_delta,
      bottom = item.bottom + row_delta,
      left = item.left + col_delta,
      right = item.right + col_delta,
    })
  end

  return shifted
end

local function make_box(lines, focusables)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, strw(line))
  end

  local normalized = {}
  for i, line in ipairs(lines) do
    normalized[i] = pad_right(line, width)
  end

  return {
    width = width,
    height = #normalized,
    lines = normalized,
    focusables = focusables or {},
  }
end

local function preview_text(text, max_chars)
  text = tostring(text or "")
  max_chars = math.max(0, tonumber(max_chars) or 0)

  local chars = vim.fn.strchars(text)
  if chars <= max_chars then
    return text
  end

  if max_chars <= 0 then
    return ""
  end

  if max_chars == 1 then
    return "…"
  end

  return vim.fn.strcharpart(text, 0, max_chars - 1) .. "…"
end

local function make_input_lines(label, value, width, opts)
  label = tostring(label or "")
  value = tostring(value or "")
  width = tonumber(width) or 24
  opts = opts or {}

  local inner_width = width - 4
  local shown_value = opts.truncate and preview_text(value, inner_width) or value

  local top_fill = math.max(0, width - strw(label) - 5)
  local top = "┌─ " .. label .. " " .. string.rep("─", top_fill) .. "┐"
  local mid = "│ " .. pad_right(shown_value, inner_width) .. " │"
  local bot = "└" .. string.rep("─", width - 2) .. "┘"

  return { top, mid, bot }
end
local GRID_BREAKPOINTS = {
  sm = 64,
  md = 96,
  lg = 128,
  xl = 160,
}

local function is_grid_units(value)
  local n = tonumber(value)
  if not n then
    return false
  end

  if n < 1 or n > 12 then
    return false
  end

  return math.floor(n) == n
end

local function resolve_span(props, container_width)
  props = props or {}

  local span = nil
  if is_grid_units(props.width) then
    span = props.width
  elseif props.width == nil then
    span = 12
  end

  local width_breakpoints = {
    xl = props.width_xl,
    lg = props.width_lg,
    md = props.width_md,
    sm = props.width_sm,
  }

  if container_width >= GRID_BREAKPOINTS.xl then
    span = width_breakpoints.xl or span
  elseif container_width >= GRID_BREAKPOINTS.lg then
    span = width_breakpoints.lg or span
  elseif container_width >= GRID_BREAKPOINTS.md then
    span = width_breakpoints.md or span
  elseif container_width >= GRID_BREAKPOINTS.sm then
    span = width_breakpoints.sm or span
  end

  if span == nil then
    return nil
  end

  if not is_grid_units(span) then
    return nil
  end

  return math.floor(span)
end


-- ============================================================
-- Renderer
-- ============================================================

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(bufnr, winid, width)
  local ns = vim.api.nvim_create_namespace("mini_react_ui")

  return setmetatable({
    bufnr = bufnr,
    winid = winid,
    width = width or 80,
    ns = ns,
    focusables = {},
  }, Renderer)
end

function Renderer:get_width()
  if vim.api.nvim_win_is_valid(self.winid) then
    return vim.api.nvim_win_get_width(self.winid)
  end
  return self.width or 80
end

function Renderer:render_text(node, _ctx)
  local text = node.props.text
  if type(text) == "function" then
    text = text()
  end
  return make_box({ tostring(text or "") })
end

function Renderer:render_input(node, ctx)
  local props = node.props
  local label = tostring(props.label or "")

  local value = props.value
  if type(value) == "function" then
    value = value()
  end
  value = tostring(value or "")

  local intrinsic_width = math.max(24, strw(label) + 6, strw(value) + 4)
  local width = props.width or intrinsic_width

  if ctx.available_width then
    width = math.max(6, ctx.available_width)
  end

  local lines = make_input_lines(label, value, width, { truncate = true })
  local top, mid, bot = lines[1], lines[2], lines[3]

  local my_focus_index = ctx.next_focus_index
  local focused = my_focus_index == ctx.focus_index
  ctx.next_focus_index = ctx.next_focus_index + 1

  local focusables = {
    {
      focused = focused,
      on_edit = props.on_edit,
      label = label,
      width = width,

      line_start = 0,
      line_end = 2,

      input_row = 1,
      input_col = 2,

      top = 0,
      bottom = 2,
      left = 0,
      right = width - 1,
    },
  }

  return make_box({ top, mid, bot }, focusables)
end

function Renderer:render_column(node, ctx)
  local children = node.children or {}
  local gap = node.props.gap or 0

  local child_boxes = {}
  local width = 0

  for _, child in ipairs(children) do
    local box = self:render_node(child, ctx)
    table.insert(child_boxes, box)
    width = math.max(width, box.width)
  end

  local lines = {}
  local focusables = {}
  local row_offset = 0

  for i, box in ipairs(child_boxes) do
    for _, line in ipairs(box.lines) do
      table.insert(lines, pad_right(line, width))
    end

    extend(focusables, shift_focusables(box.focusables, row_offset, 0))
    row_offset = row_offset + box.height

    if i < #child_boxes then
      for _ = 1, gap do
        table.insert(lines, blank_line(width))
      end
      row_offset = row_offset + gap
    end
  end

  return make_box(lines, focusables)
end

function Renderer:render_row(node, ctx)
  local children = node.children or {}
  local gap = node.props.gap or 1

  local win_width = self:get_width()
  local container_width = ctx.available_width or win_width
  local total_gap = math.max(0, (#children - 1) * gap)
  local available_width = math.max(0, container_width - total_gap)

  local child_spans = {}
  local total_span = 0
  for i, child in ipairs(children) do
    local span = resolve_span(child.props, container_width)
    child_spans[i] = span
    if span then
      total_span = total_span + span
    end
  end

  local child_constraints = {}
  if total_span > 0 then
    local span_parts = {}
    local consumed = 0

    for i, span in ipairs(child_spans) do
      if span then
        local raw = available_width * span / 12
        local base = math.floor(raw)
        child_constraints[i] = base
        consumed = consumed + base
        table.insert(span_parts, {
          index = i,
          frac = raw - base,
        })
      end
    end

    table.sort(span_parts, function(a, b)
      if a.frac == b.frac then
        return a.index < b.index
      end
      return a.frac > b.frac
    end)

    local leftover = math.max(0, math.min(available_width - consumed, #span_parts))
    for i = 1, leftover do
      local index = span_parts[i].index
      child_constraints[index] = child_constraints[index] + 1
    end
  end

  local child_boxes = {}
  local height = 0

  for i, child in ipairs(children) do
    local prev_available_width = ctx.available_width
    ctx.available_width = child_constraints[i]

    local box = self:render_node(child, ctx)

    ctx.available_width = prev_available_width

    table.insert(child_boxes, box)
    height = math.max(height, box.height)
  end

  local padded_children = {}
  for _, box in ipairs(child_boxes) do
    local padded_lines = {}
    for i = 1, height do
      padded_lines[i] = pad_right(box.lines[i] or blank_line(box.width), box.width)
    end
    table.insert(padded_children, {
      width = box.width,
      height = height,
      lines = padded_lines,
      focusables = box.focusables,
    })
  end

  local lines = {}
  for row = 1, height do
    local parts = {}
    for i, box in ipairs(padded_children) do
      table.insert(parts, box.lines[row])
      if i < #padded_children then
        table.insert(parts, blank_line(gap))
      end
    end
    table.insert(lines, table.concat(parts))
  end

  local focusables = {}
  local col_offset = 0
  for i, box in ipairs(padded_children) do
    extend(focusables, shift_focusables(box.focusables, 0, col_offset))
    col_offset = col_offset + box.width
    if i < #padded_children then
      col_offset = col_offset + gap
    end
  end

  return make_box(lines, focusables)
end


function Renderer:render_node(node, ctx)
  if type(node) == "function" then
    node = node()
  end

  if node.type == "text" then
    return self:render_text(node, ctx)
  elseif node.type == "input" then
    return self:render_input(node, ctx)
  elseif node.type == "column" then
    return self:render_column(node, ctx)
  elseif node.type == "row" then
    return self:render_row(node, ctx)
  else
    error("Unknown node type: " .. tostring(node.type))
  end
end

function Renderer:apply_highlights()
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)

  for _, item in ipairs(self.focusables) do
    local hl = item.focused and "MiniReactInputFocused" or "MiniReactInput"

    for line_nr = item.line_start, item.line_end do
      local line = vim.api.nvim_buf_get_lines(self.bufnr, line_nr, line_nr + 1, false)[1] or ""

      local start_col = charcol_to_bytecol(line, item.left)
      local end_col = charcol_to_bytecol(line, item.right + 1)

      vim.api.nvim_buf_add_highlight(
        self.bufnr,
        self.ns,
        hl,
        line_nr,
        start_col,
        end_col
      )
    end
  end
end

function Renderer:move_cursor_to_focus(index)
  local item = self.focusables[index]
  if not item then
    return
  end

  if not vim.api.nvim_win_is_valid(self.winid) then
    return
  end

  local row0 = item.input_row or item.line_start or 0
  local char_col = item.input_col or 0

  local line = vim.api.nvim_buf_get_lines(self.bufnr, row0, row0 + 1, false)[1] or ""

  local byte_col = vim.fn.byteidx(line, char_col)
  if byte_col < 0 then
    byte_col = #line
  end

  vim.api.nvim_win_set_cursor(self.winid, {
    row0 + 1,
    byte_col,
  })
end

function Renderer:render(root, focus_index)
  local ctx = {
    focus_index = focus_index or 1,
    next_focus_index = 1,
  }

  local box = self:render_node(root, ctx)
  local target_width = math.max(box.width, self:get_width())

  local full_width_lines = {}
  for i, line in ipairs(box.lines) do
    full_width_lines[i] = pad_right(line, target_width)
  end

  self.focusables = box.focusables

  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, full_width_lines)
  vim.bo[self.bufnr].modifiable = false

  self:apply_highlights()
  self:move_cursor_to_focus(focus_index or 1)
end

function Renderer:get_focusable_count()
  return #self.focusables
end

function Renderer:get_focused_item(index)
  return self.focusables[index]
end

M.Renderer = Renderer

-- ============================================================
-- Spatial focus movement
-- ============================================================

local function center_x(item)
  return (item.left + item.right) / 2
end

local function center_y(item)
  return (item.top + item.bottom) / 2
end

local function ranges_overlap(a1, a2, b1, b2)
  return not (a2 < b1 or b2 < a1)
end

local function find_next_focus(renderer, current_index, direction)
  local current = renderer:get_focused_item(current_index)
  if not current then
    return current_index
  end

  local candidates = {}

  for i, item in ipairs(renderer.focusables) do
    if i ~= current_index then
      local valid = false
      local primary = math.huge
      local secondary = math.huge
      local aligned = false

      if direction == "left" then
        if item.right < current.left then
          valid = true
          primary = current.left - item.right
          secondary = math.abs(center_y(item) - center_y(current))
          aligned = ranges_overlap(item.top, item.bottom, current.top, current.bottom)
        end
      elseif direction == "right" then
        if item.left > current.right then
          valid = true
          primary = item.left - current.right
          secondary = math.abs(center_y(item) - center_y(current))
          aligned = ranges_overlap(item.top, item.bottom, current.top, current.bottom)
        end
      elseif direction == "up" then
        if item.bottom < current.top then
          valid = true
          primary = current.top - item.bottom
          secondary = math.abs(center_x(item) - center_x(current))
          aligned = ranges_overlap(item.left, item.right, current.left, current.right)
        end
      elseif direction == "down" then
        if item.top > current.bottom then
          valid = true
          primary = item.top - current.bottom
          secondary = math.abs(center_x(item) - center_x(current))
          aligned = ranges_overlap(item.left, item.right, current.left, current.right)
        end
      end

      if valid then
        table.insert(candidates, {
          index = i,
          aligned = aligned,
          primary = primary,
          secondary = secondary,
        })
      end
    end
  end

  if #candidates == 0 then
    return current_index
  end

  table.sort(candidates, function(a, b)
    if a.aligned ~= b.aligned then
      return a.aligned
    end
    if a.primary ~= b.primary then
      return a.primary < b.primary
    end
    return a.secondary < b.secondary
  end)

  return candidates[1].index
end

M.find_next_focus = find_next_focus

local function clamp_focus(renderer, focus_index)
  local count = renderer:get_focusable_count()
  if count == 0 then
    return 1
  end

  if focus_index < 1 then
    return 1
  elseif focus_index > count then
    return count
  end

  return focus_index
end

local function move_focus_direction(direction, renderer, focus_index)
  local count = renderer:get_focusable_count()
  if count == 0 then
    return 1
  end

  return find_next_focus(renderer, focus_index, direction)
end

M.clamp_focus = clamp_focus
M.move_focus_direction = move_focus_direction

local function create_runtime(renderer, app_fn)
  local runtime = {
    renderer = renderer,
    app_fn = app_fn,
    focus_index = 1,
  }

  function runtime:render()
    self.renderer:render(self.app_fn(), self.focus_index)
    local clamped = clamp_focus(self.renderer, self.focus_index)
    if clamped ~= self.focus_index then
      self.focus_index = clamped
      self.renderer:render(self.app_fn(), self.focus_index)
    else
      self.focus_index = clamped
    end
  end

  effect(function()
    runtime:render()
  end)

  return runtime
end

M.create_runtime = create_runtime

local function edit_focused(runtime)
  local item = runtime.renderer:get_focused_item(runtime.focus_index)
  if not item or not item.on_edit then
    return
  end

  item.on_edit(runtime.renderer.winid, item, function()
    if vim.api.nvim_win_is_valid(runtime.renderer.winid) then
      vim.api.nvim_set_current_win(runtime.renderer.winid)
      vim.cmd("stopinsert")
      runtime.renderer:move_cursor_to_focus(runtime.focus_index)
    end
  end)
end

local function setup_default_keymaps(buf, runtime)
  local opts = { buffer = buf, silent = true }

  vim.keymap.set("n", "h", function()
    runtime.focus_index = move_focus_direction("left", runtime.renderer, runtime.focus_index)
    runtime:render()
  end, opts)

  vim.keymap.set("n", "l", function()
    runtime.focus_index = move_focus_direction("right", runtime.renderer, runtime.focus_index)
    runtime:render()
  end, opts)

  vim.keymap.set("n", "k", function()
    runtime.focus_index = move_focus_direction("up", runtime.renderer, runtime.focus_index)
    runtime:render()
  end, opts)

  vim.keymap.set("n", "j", function()
    runtime.focus_index = move_focus_direction("down", runtime.renderer, runtime.focus_index)
    runtime:render()
  end, opts)

  vim.keymap.set("n", "<CR>", function()
    edit_focused(runtime)
  end, opts)

  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, opts)
end

M.edit_focused = edit_focused
M.setup_default_keymaps = setup_default_keymaps

-- ============================================================
-- Floating live editor
-- ============================================================

local function open_live_input(opts)
  local anchor_item = opts.anchor_item
  local title = tostring((anchor_item and anchor_item.label) or opts.title or "Edit")
  local initial = tostring(opts.initial or "")
  local parent_win = opts.parent_win
  local on_change = opts.on_change
  local on_submit = opts.on_submit
  local on_cancel = opts.on_cancel
  local on_close = opts.on_close

  local width = assert(anchor_item.width, "anchor_item.width is required")
  local inner_width = width - 4

  local border_buf = vim.api.nvim_create_buf(false, true)
  local input_buf = vim.api.nvim_create_buf(false, true)

  vim.bo[border_buf].buftype = "nofile"
  vim.bo[border_buf].bufhidden = "wipe"
  vim.bo[border_buf].swapfile = false
  vim.bo[border_buf].modifiable = false
  vim.bo[border_buf].filetype = "mini_react_ui_input_border"

  vim.bo[input_buf].buftype = "nofile"
  vim.bo[input_buf].bufhidden = "wipe"
  vim.bo[input_buf].swapfile = false
  vim.bo[input_buf].modifiable = true
  vim.bo[input_buf].readonly = false
  vim.bo[input_buf].filetype = "mini_react_ui_input"

  local value = initial
  local original = initial
  local closed = false
  local syncing = false

  local border_ns = vim.api.nvim_create_namespace("mini_react_ui_input_border_" .. border_buf)

  local function render_border()
    local lines = make_input_lines(title, value, width, { truncate = true })

    vim.bo[border_buf].modifiable = true
    vim.api.nvim_buf_set_lines(border_buf, 0, -1, false, lines)
    vim.bo[border_buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(border_buf, border_ns, 0, -1)
    vim.api.nvim_buf_add_highlight(border_buf, border_ns, "MiniReactInputEditingBorder", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(border_buf, border_ns, "MiniReactInputEditingBorder", 2, 0, -1)
    vim.api.nvim_buf_add_highlight(border_buf, border_ns, "MiniReactInputEditingBorder", 1, 0, 2)
    vim.api.nvim_buf_add_highlight(border_buf, border_ns, "MiniReactInputEditingBorder", 1, width - 2, width)
  end

  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { value })

  local border_win = vim.api.nvim_open_win(border_buf, false, {
    relative = "win",
    win = parent_win,
    row = anchor_item.top,
    col = anchor_item.left,
    width = width,
    height = 3,
    border = "none",
    style = "minimal",
    focusable = false,
    zindex = 60,
    noautocmd = true,
  })

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "win",
    win = parent_win,
    row = anchor_item.top + 1,
    col = anchor_item.left + 2,
    width = inner_width,
    height = 1,
    border = "none",
    style = "minimal",
    focusable = true,
    zindex = 61,
    noautocmd = true,
  })

  vim.wo[border_win].number = false
  vim.wo[border_win].relativenumber = false
  vim.wo[border_win].cursorline = false
  vim.wo[border_win].wrap = false
  vim.wo[border_win].signcolumn = "no"
  vim.wo[border_win].foldcolumn = "0"
  vim.wo[border_win].spell = false
  vim.wo[border_win].list = false

  vim.wo[input_win].number = false
  vim.wo[input_win].relativenumber = false
  vim.wo[input_win].cursorline = false
  vim.wo[input_win].wrap = false
  vim.wo[input_win].signcolumn = "no"
  vim.wo[input_win].foldcolumn = "0"
  vim.wo[input_win].spell = false
  vim.wo[input_win].list = false
  vim.wo[input_win].winhighlight = "Normal:MiniReactInputEditingText,NormalNC:MiniReactInputEditingText"

  local function get_input_value()
    return vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
  end

  local function set_input_value(new_value)
    new_value = tostring(new_value or "")
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { new_value })
    value = new_value
  end

  local function close()
    if closed then
      return
    end
    closed = true

    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
    if vim.api.nvim_win_is_valid(border_win) then
      vim.api.nvim_win_close(border_win, true)
    end

    if on_close then
      vim.schedule(on_close)
    end
  end

  local function sync_from_input()
    if closed or syncing then
      return
    end

    syncing = true
    value = get_input_value()
    render_border()

    if on_change then
      on_change(value)
    end

    syncing = false
  end

  render_border()

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = input_buf,
    callback = sync_from_input,
  })

  vim.keymap.set("i", "<CR>", function()
    vim.cmd("stopinsert")
    value = get_input_value()
    if on_submit then
      on_submit(value)
    end
    close()
  end, { buffer = input_buf, silent = true })

  vim.keymap.set("n", "<CR>", function()
    value = get_input_value()
    if on_submit then
      on_submit(value)
    end
    close()
  end, { buffer = input_buf, silent = true })

  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    vim.cmd("stopinsert")
    set_input_value(original)
    render_border()

    if on_cancel then
      on_cancel()
    end
    close()
  end, { buffer = input_buf, silent = true })

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_set_current_win(input_win)
      vim.api.nvim_win_set_cursor(input_win, { 1, #value })
      vim.cmd("startinsert!")
    end
  end)

  return {
    border_buf = border_buf,
    border_win = border_win,
    input_buf = input_buf,
    input_win = input_win,
  }
end

local function live_signal_editor(label, signal)
  return function(parent_win, item, on_done)
    local original = signal:get()

    open_live_input({
      title = label,
      initial = original,
      parent_win = parent_win,
      anchor_item = item,
      on_change = function(v)
        signal:set(v)
      end,
      on_submit = function(v)
        signal:set(v)
      end,
      on_cancel = function()
        signal:set(original)
      end,
      on_close = function()
        if on_done then
          on_done()
        end
      end,
    })
  end
end

M.live_signal_editor = live_signal_editor

local function setup_highlights()
  vim.api.nvim_set_hl(0, "MiniReactInput", {
    fg = "#c0caf5",
  })

  vim.api.nvim_set_hl(0, "MiniReactInputFocused", {
    fg = "#ff9e64",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "MiniReactInputEditingBorder", {
    fg = "#7aa2f7",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "MiniReactInputEditingText", {
    fg = "#ffffff",
    bg = "#283457",
  })
end

M.setup_highlights = setup_highlights

return M
