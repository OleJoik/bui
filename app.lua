local core = require("core")

local Signal = core.Signal
local Text = core.Text
local Input = core.Input
local Column = core.Column
local Row = core.Row
local Renderer = core.Renderer
local live_signal_editor = core.live_signal_editor

local first_name = Signal.new("Ada")
local last_name = Signal.new("Lovelace")
local email = Signal.new("ada@example.com")
local city = Signal.new("London")
local company = Signal.new("Analytical Engines Ltd")

local function App()
  return Column({
    Text({
      text = "Profile editor",
    }),

    Row({
      Input({
        label = "First name",
        width = 22,
        value = function()
          return first_name:get()
        end,
        on_edit = live_signal_editor("First name", first_name),
      }),
      Input({
        label = "Last name",
        width = 22,
        value = function()
          return last_name:get()
        end,
        on_edit = live_signal_editor("Last name", last_name),
      }),
    }, { gap = 2 }),

    Row({
      Input({
        label = "Email",
        width = 28,
        value = function()
          return email:get()
        end,
        on_edit = live_signal_editor("Email", email),
      }),
      Column({
        Input({
          label = "City",
          width = 18,
          value = function()
            return city:get()
          end,
          on_edit = live_signal_editor("City", city),
        }),
        Input({
          label = "Company",
          width = 24,
          value = function()
            return company:get()
          end,
          on_edit = live_signal_editor("Company", company),
        }),
      }, { gap = 1 }),
    }, { gap = 2 }),

    Text({
      text = function()
        return string.format(
          "Summary: %s %s <%s> from %s at %s",
          first_name:get(),
          last_name:get(),
          email:get(),
          city:get(),
          company:get()
        )
      end,
    }),
  }, { gap = 1 })
end

local function mount()
  core.setup_highlights()

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "mini_react_ui"

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false

  local renderer = Renderer.new(buf, win, 80)
  local runtime = core.create_runtime(renderer, App)
  core.setup_default_keymaps(buf, runtime)
end

return {
  mount = mount,
}
