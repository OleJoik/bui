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
local status = Signal.new("Focus a text row and press <CR> to trigger on_enter.")
local status_count = Signal.new(0)

local element_gap = 0
local input_padding = 0

local function App()
  return Column({
    Text({
      text = "Profile editor",
    }),
    Text({
      text = "Resize the window: rows collapse to single-column on narrow widths, then expand via width_sm (6/6 and 8/4).",
    }),
    Text({
      text = function()
        return string.format(
          "Action row (%d): press <CR> or `gr` here to fire text handlers.",
          status_count:get()
        )
      end,
      on_enter = function()
        local next_count = status_count:get() + 1
        status_count:set(next_count)
        status:set(string.format("Text on_enter fired %d times.", next_count))
      end,
      on_keymap = {
        ["gr"] = function()
          status:set("Custom text keymap `gr` fired on focused text.")
        end,
      },
    }),
    Text({
      text = function()
        return "Status: " .. status:get()
      end,
      focusable = true,
      on_keymap = {
        ["gs"] = function()
          status:set("Global keymap `gs` fired (focused_only = false).")
        end,
      },
      on_keymap_config = {
        focused_only = false,
      },
    }),

    Row({
      Input({
        label = "First name",
        width_sm = 6,
        padding = input_padding,
        value = function()
          return first_name:get()
        end,
        on_edit = live_signal_editor("First name", first_name),
      }),
      Input({
        label = "Last name",
        width_sm = 6,
        padding = input_padding,
        value = function()
          return last_name:get()
        end,
        on_edit = live_signal_editor("Last name", last_name),
      }),
    }, { gap = element_gap }),

    Row({
      Input({
        label = "Email",
        width_sm = 8,
        padding = input_padding,
        value = function()
          return email:get()
        end,
        on_edit = live_signal_editor("Email", email),
        on_keymap = {
          ["gr"] = function(_, item)
            status:set("Custom input keymap `gr` fired on " .. item.label .. ".")
          end,
        },
      }),
      Column({
        Input({
          label = "City",
          width = 18,
          padding = input_padding,
          value = function()
            return city:get()
          end,
          on_edit = live_signal_editor("City", city),
        }),
        Input({
          label = "Company",
          width = 24,
          padding = input_padding,
          value = function()
            return company:get()
          end,
          on_edit = live_signal_editor("Company", company),
        }),
      }, {
        gap = element_gap,
        width_sm = 4,
      }),
    }, { gap = element_gap }),

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
  }, { gap = element_gap })
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

  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    callback = function()
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_win_get_buf(win) == buf
      then
        runtime:render()
      end
    end,
  })
end

mount()
