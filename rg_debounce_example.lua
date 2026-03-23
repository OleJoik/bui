local core = require("core")

local Signal = core.Signal
local Text = core.Text
local Input = core.Input
local Column = core.Column

local query = Signal.new("")
local results = Signal.new({ "Type to search with ripgrep..." })
local is_searching = Signal.new(false)
local last_error = Signal.new("")

local debounce_ms = 120
local max_lines = 10
local timer = vim.uv.new_timer()
local request_id = 0

local function set_lines(lines)
  results:set(lines)
end

local function render_result_lines()
  local lines = results:get()
  local children = {}

  for i, line in ipairs(lines) do
    children[i] = Text({ text = line })
  end

  return children
end

local function run_rg(term)
  request_id = request_id + 1
  local this_request = request_id

  if term == "" then
    is_searching:set(false)
    last_error:set("")
    set_lines({ "Type to search with ripgrep..." })
    return
  end

  is_searching:set(true)
  last_error:set("")

  local args = {
    "rg",
    "--line-number",
    "--no-heading",
    "--smart-case",
    term,
    ".",
  }

  vim.system(args, { text = true }, function(obj)
    vim.schedule(function()
      if this_request ~= request_id then
        return
      end

      is_searching:set(false)

      if obj.code ~= 0 and obj.code ~= 1 then
        last_error:set(string.format("rg exited with %d", obj.code))
        set_lines({ "Search failed." })
        return
      end

      if obj.code == 1 or obj.stdout == "" then
        set_lines({ "No matches." })
        return
      end

      local lines = vim.split(obj.stdout, "\n", { trimempty = true })
      local shown = {}
      for i = 1, math.min(#lines, max_lines) do
        shown[i] = lines[i]
      end

      if #lines > max_lines then
        table.insert(shown, string.format("...and %d more", #lines - max_lines))
      end

      set_lines(shown)
    end)
  end)
end

local function schedule_rg(term)
  timer:stop()
  timer:start(debounce_ms, 0, function()
    vim.schedule(function()
      run_rg(term)
    end)
  end)
end

local function App()
  local children = {
    Text({ text = "Debounced ripgrep" }),
    Input({
      label = "Search",
      value = function()
        return query:get()
      end,
      on_changed = function(next, ctx)
        query:set(next)

        if ctx.phase == "change" then
          schedule_rg(next)
        elseif ctx.phase == "submit" then
          timer:stop()
          run_rg(next)
        end
      end,
    }),
    Text({
      text = function()
        if is_searching:get() then
          return "Searching..."
        end

        local err = last_error:get()
        if err ~= "" then
          return "Error: " .. err
        end

        return "Results"
      end,
    }),
  }

  local lines = render_result_lines()
  for _, line in ipairs(lines) do
    table.insert(children, line)
  end

  return Column(children)
end

core.mount(App)
