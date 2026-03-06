local M = {}

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function system(args, cwd)
  if cwd then
    local prefixed = { "git", "-C", cwd }
    for i = 2, #args do
      table.insert(prefixed, args[i])
    end
    args = prefixed
  end
  local out = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    local err = trim(out)
    if err == "" then
      err = "command failed: " .. table.concat(args, " ")
    end
    error(err)
  end
  return trim(out)
end

local function repo_root(cwd)
  return system({ "git", "rev-parse", "--show-toplevel" }, cwd)
end

local function current_branch(cwd)
  return system({ "git", "branch", "--show-current" }, cwd)
end

local function remote_name(cwd)
  local branch = current_branch(cwd)
  if branch ~= "" then
    local ok, remote = pcall(system, { "git", "config", "--get", "branch." .. branch .. ".remote" }, cwd)
    if ok and remote ~= "" then
      return remote
    end
  end
  return "origin"
end

local function remote_url(name, cwd)
  return system({ "git", "remote", "get-url", name }, cwd)
end

local function remote_head_commit(remote, branch, cwd)
  local ok, commit = pcall(system, {
    "git",
    "rev-parse",
    remote .. "/" .. branch,
  }, cwd)

  if ok and commit ~= "" then
    return commit
  end
end

local function resolve_ref(ref, cwd)
  local ok, commit = pcall(system, {
    "git",
    "rev-parse",
    ref,
  }, cwd)

  if ok and commit ~= "" then
    return commit
  end
end

local function merge_base(ref, cwd)
  local ok, commit = pcall(system, {
    "git",
    "merge-base",
    "HEAD",
    ref,
  }, cwd)

  if ok and commit ~= "" then
    return commit
  end
end

local function default_branch_ref(remote, cwd)
  local ok, ref = pcall(system, {
    "git",
    "symbolic-ref",
    "--short",
    "refs/remotes/" .. remote .. "/HEAD",
  }, cwd)

  if ok and ref ~= "" then
    return ref
  end
end

local function permalink_commit(remote, branch, cwd)
  local candidates = {
    remote .. "/" .. branch,
    default_branch_ref(remote, cwd),
    remote .. "/main",
    remote .. "/master",
  }

  for _, ref in ipairs(candidates) do
    if ref and resolve_ref(ref, cwd) then
      local commit = merge_base(ref, cwd)
      if commit then
        return commit
      end
    end
  end

  return system({ "git", "rev-parse", "HEAD" }, cwd)
end

local function parse_remote(url)
  local host, path

  if url:match("^git@") then
    host, path = url:match("^git@([^:]+):(.+)$")
  elseif url:match("^ssh://") then
    host, path = url:match("^ssh://git@([^/]+)/(.+)$")
  elseif url:match("^https?://") then
    host, path = url:match("^https?://([^/]+)/(.+)$")
  end

  if not host or not path then
    error("unsupported remote URL: " .. url)
  end

  path = path:gsub("%.git$", "")

  local provider
  if host:find("github", 1, true) then
    provider = "github"
  elseif host:find("gitlab", 1, true) then
    provider = "gitlab"
  else
    error("only GitHub and GitLab remotes are supported: " .. host)
  end

  return provider, ("https://%s/%s"):format(host, path)
end

local function encode_path(path)
  local parts = vim.split(path, "/", { plain = true })
  for i, part in ipairs(parts) do
    parts[i] = vim.uri_encode(part)
  end
  return table.concat(parts, "/")
end

local function line_fragment(provider, first, last)
  if not first or not last then
    return ""
  end

  if provider == "github" then
    if first == last then
      return "#L" .. first
    end
    return "#L" .. first .. "-L" .. last
  end

  if first == last then
    return "#L" .. first
  end
  return "#L" .. first .. "-" .. last
end

local function buffer_path()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    error("current buffer has no file path")
  end
  return vim.fn.fnamemodify(path, ":p")
end

local function relative_path(root, file)
  local prefix = root .. "/"
  if file:sub(1, #prefix) ~= prefix then
    error("current file is not inside the git repository")
  end
  return file:sub(#prefix + 1)
end

local function copy_to_clipboard(text)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
end

function M.permalink(first, last)
  local file_path = buffer_path()
  local cwd = vim.fn.fnamemodify(file_path, ":h")
  local root = repo_root(cwd)
  local file = relative_path(root, file_path)
  local branch = current_branch(cwd)
  local remote = remote_name(cwd)
  local provider, remote_base = parse_remote(remote_url(remote, cwd))
  local commit = permalink_commit(remote, branch, cwd)
  local encoded_file = encode_path(file)

  if provider == "github" then
    return ("%s/blob/%s/%s%s"):format(remote_base, commit, encoded_file, line_fragment(provider, first, last))
  end

  return ("%s/-/blob/%s/%s%s"):format(remote_base, commit, encoded_file, line_fragment(provider, first, last))
end

function M.open(opts)
  opts = opts or {}
  local first = opts.first_line
  local last = opts.last_line

  local ok, url = pcall(M.permalink, first, last)
  if not ok then
    vim.notify(url, vim.log.levels.ERROR)
    return
  end

  copy_to_clipboard(url)
  vim.notify("Copied permalink:\n" .. url)
end

function M.setup()
  vim.api.nvim_create_user_command("GitPermalinkCopy", function(command)
    local has_range = command.range > 0
    M.open({
      first_line = has_range and command.line1 or nil,
      last_line = has_range and command.line2 or nil,
    })
  end, {
    desc = "Copy a GitHub/GitLab permalink for the current line or range",
    range = true,
  })
end

return M
