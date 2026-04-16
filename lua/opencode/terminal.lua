local M = {}

---@class opencode.terminal.Opts : vim.api.keyset.win_config

local winid
local bufnr

local session_name = "opencode"

local function tmux_run(cmd)
  vim.fn.system(string.format("tmux new-session -d -s %s '%s'", session_name, cmd))
end

local function tmux_kill()
  vim.fn.system("tmux kill-session -t " .. session_name .. " 2>/dev/null")
end

---Start if not running, else show/hide the window.
---@param cmd string
---@param opts? opencode.terminal.Opts
function M.toggle(cmd, opts)
  opts = opts or {
    split = "right",
    width = math.floor(vim.o.columns * 0.35),
  }

  if winid ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_hide(winid)
    winid = nil
  elseif bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    local previous_win = vim.api.nvim_get_current_win()
    winid = vim.api.nvim_open_win(bufnr, true, opts)
    vim.api.nvim_set_current_win(previous_win)
  else
    M.open(cmd, opts)
  end
end

---@param cmd string
---@param opts? opencode.terminal.Opts
function M.open(cmd, opts)
  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  opts = opts or {
    split = "right",
    width = math.floor(vim.o.columns * 0.35),
  }

  local previous_win = vim.api.nvim_get_current_win()
  bufnr = vim.api.nvim_create_buf(false, false)
  winid = vim.api.nvim_open_win(bufnr, true, opts)

  vim.api.nvim_create_autocmd("ExitPre", {
    once = true,
    callback = function()
      M.close()
    end,
  })

  M.setup(winid)

  -- Redraw hack (igual que tu versión original)
  local auid
  auid = vim.api.nvim_create_autocmd("TermRequest", {
    buffer = bufnr,
    callback = function(ev)
      if ev.data.cursor[1] > 1 then
        vim.api.nvim_del_autocmd(auid)
        vim.api.nvim_set_current_win(winid)
        vim.cmd([[startinsert | call feedkeys("\<C-\>\<C-n>\<C-w>p", "n")]])
      end
    end,
  })

  -- 🔁 CAMBIO CLAVE: ahora corre en tmux
  tmux_run(cmd)

  vim.api.nvim_set_current_win(previous_win)
end

function M.close()
  -- 🔥 matar sesión tmux completa (opencode + hijos)
  tmux_kill()

  if winid ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
    winid = nil
  end

  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    bufnr = nil
  end
end

---Apply buffer-local keymaps
---@param buf integer
local function keymaps(buf)
  local opts = { buffer = buf }

  vim.keymap.set("n", "<C-u>", function()
    require("opencode").command("session.half.page.up")
  end, vim.tbl_extend("force", opts, { desc = "Scroll up half page" }))

  vim.keymap.set("n", "<C-d>", function()
    require("opencode").command("session.half.page.down")
  end, vim.tbl_extend("force", opts, { desc = "Scroll down half page" }))

  vim.keymap.set("n", "gg", function()
    require("opencode").command("session.first")
  end, vim.tbl_extend("force", opts, { desc = "Go to first message" }))

  vim.keymap.set("n", "G", function()
    require("opencode").command("session.last")
  end, vim.tbl_extend("force", opts, { desc = "Go to last message" }))

  vim.keymap.set("n", "<Esc>", function()
    require("opencode").command("session.interrupt")
  end, vim.tbl_extend("force", opts, { desc = "Interrupt current session (esc)" }))
end

---@param pid integer
local function terminate(pid)
  if vim.fn.has("unix") == 1 then
    os.execute("kill -TERM -" .. pid .. " 2>/dev/null")
  else
    pcall(vim.uv.kill, pid, "SIGTERM")
  end
end

---@param win integer
function M.setup(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local pid

  vim.api.nvim_create_autocmd("TermOpen", {
    buffer = buf,
    once = true,
    callback = function(event)
      keymaps(event.buf)
      _, pid = pcall(vim.fn.jobpid, vim.b[event.buf].terminal_job_id)
    end,
  })

  -- ⚠️ ahora menos importante con tmux, pero lo dejamos intacto
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    once = true,
    callback = function()
      if pid then
        terminate(pid)
      end
    end,
  })

  vim.api.nvim_create_autocmd("ExitPre", {
    once = true,
    callback = function()
      if pid then
        terminate(pid)
      end
    end,
  })
end

return M
