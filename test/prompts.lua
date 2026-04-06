local exact_skip = {
  NIL = true,
  type_idx = true,
  val_idx = true,
}

local collapsed = {
  api = "large low-level editor API; details are omitted here because they are documented elsewhere. Prefer higher-level `vim.*` helpers first.",
  fn = "Vimscript bridge; details are omitted here because they are documented elsewhere. Prefer higher-level `vim.*` helpers first.",
}

local option_accessors = {
  "o",
  "go",
  "bo",
  "wo",
  "opt",
  "opt_local",
  "opt_global",
}

local scoped_variables = {
  "g",
  "b",
  "w",
  "t",
  "v",
  "env",
}

local preferred_modules = {
  "keymap",
  "ui",
  "fs",
  "diagnostic",
  "lsp",
  "treesitter",
  "filetype",
  "hl",
  "json",
  "base64",
  "uv",
  "api",
  "fn",
}

local preferred_helpers = {
  "notify",
  "notify_once",
  "schedule",
  "schedule_wrap",
  "defer_fn",
  "system",
  "wait",
  "split",
  "trim",
  "startswith",
  "endswith",
  "deepcopy",
  "validate",
}

local function is_public_key(key)
  if type(key) ~= "string" then
    return false
  end

  if exact_skip[key] or key == "" then
    return false
  end

  if key:match "^_" then
    return false
  end

  if key:match "^[A-Z][A-Z0-9_]*$" then
    return false
  end

  return true
end

local function sorted_keys(map)
  local keys = vim.tbl_keys(map)
  table.sort(keys)
  return keys
end

local function public_keys(tbl)
  local keys = {}
  for key, _ in pairs(tbl) do
    if is_public_key(key) then
      table.insert(keys, key)
    end
  end

  table.sort(keys)
  return keys
end

local function safe_get(tbl, key)
  local ok, value = pcall(function()
    return tbl[key]
  end)

  if ok then
    return value
  end
end

local function code_list(items)
  local parts = {}
  for _, item in ipairs(items) do
    table.insert(parts, ("`%s`"):format(item))
  end

  return table.concat(parts, ", ")
end

local function member_score(name, value)
  local score = type(value) == "function" and 40 or 10
  local underscore_count = select(2, name:gsub("_", ""))

  if underscore_count == 0 then
    score = score + 30
  elseif underscore_count == 1 then
    score = score + 15
  end

  if name:match "^nvim_" then
    score = score - 100
  end

  if name:match "#" then
    score = score - 50
  end

  if name:match "^[a-z]+$" then
    score = score + 10
  end

  return score
end

local function format_member(name, value, depth)
  local value_type = type(value)
  if value_type == "function" then
    return name .. "()"
  end

  if value_type ~= "table" then
    return ("%s:%s"):format(name, value_type)
  end

  if depth >= 2 then
    return name .. "{...}"
  end

  local keys = public_keys(value)
  if #keys == 0 then
    return name .. "{...}"
  end

  if #keys > 4 then
    return name .. "{...}"
  end

  local children = {}
  for _, key in ipairs(keys) do
    table.insert(children, format_member(key, safe_get(value, key), depth + 1))
  end

  return ("%s{ %s }"):format(name, table.concat(children, ", "))
end

local function pick_members(tbl, limit)
  local keys = public_keys(tbl)
  table.sort(keys, function(left, right)
    local left_value = safe_get(tbl, left)
    local right_value = safe_get(tbl, right)
    local left_score = member_score(left, left_value)
    local right_score = member_score(right, right_value)
    if left_score == right_score then
      return left < right
    end

    return left_score > right_score
  end)

  local picked = {}
  local used_prefix = {}
  local is_wide = #keys > 20

  for _, key in ipairs(keys) do
    if #picked >= limit then
      break
    end

    local prefix = key:match "^([a-z]+)_"
    if not is_wide or prefix == nil or not used_prefix[prefix] then
      table.insert(picked, format_member(key, safe_get(tbl, key), 1))
      if prefix then
        used_prefix[prefix] = true
      end
    end
  end

  return picked
end

local function prefix_groups(tbl)
  local counts = {}
  for _, key in ipairs(public_keys(tbl)) do
    local prefix = key:match "^([a-z]+)_"
    if prefix and prefix ~= key then
      counts[prefix] = (counts[prefix] or 0) + 1
    end
  end

  local groups = {}
  for prefix, count in pairs(counts) do
    if count >= 3 then
      table.insert(groups, { prefix = prefix, count = count })
    end
  end

  table.sort(groups, function(left, right)
    if left.count == right.count then
      return left.prefix < right.prefix
    end

    return left.count > right.count
  end)

  local result = {}
  for i = 1, math.min(#groups, 4) do
    table.insert(result, groups[i].prefix .. "_*")
  end

  return result
end

local function root_names()
  local names = {}
  for key, _ in pairs(vim) do
    if is_public_key(key) then
      names[key] = true
    end
  end

  for key, enabled in pairs(vim._submodules or {}) do
    if enabled and is_public_key(key) then
      names[key] = true
    end
  end

  return sorted_keys(names)
end

local function build_helper_lines()
  local helper_names = {}
  for _, name in ipairs(preferred_helpers) do
    if type(safe_get(vim, name)) == "function" then
      table.insert(helper_names, "vim." .. name .. "()")
    end
  end

  local lines = {}
  if #helper_names > 0 then
    table.insert(lines, "Start with top-level `vim` helpers when they fit:")
    table.insert(lines, "- " .. code_list(helper_names))
  end

  local families = {}
  for _, prefix in ipairs { "tbl", "list", "str" } do
    local found = false
    for _, name in ipairs(root_names()) do
      if name:match("^" .. prefix .. "_") then
        found = true
        break
      end
    end

    if found then
      table.insert(families, "vim." .. prefix .. "_*")
    end
  end

  if #families > 0 then
    table.insert(lines, "- Helper families also exist on the root table: " .. code_list(families))
  end

  return lines
end

local function build_module_lines()
  local available = {}
  for _, name in ipairs(root_names()) do
    available[name] = true
  end

  local lines = {
    "Major public branches on the live `vim` global:",
  }

  for _, name in ipairs(preferred_modules) do
    if available[name] then
      local value = safe_get(vim, name)
      if type(value) == "table" then
        local keys = public_keys(value)
        if collapsed[name] then
          table.insert(lines, ("- `vim.%s`: table with %d public keys; %s"):format(name, #keys, collapsed[name]))
        else
          local members = pick_members(value, #keys > 20 and 6 or 8)
          local line = ("- `vim.%s`: table with %d public keys"):format(name, #keys)
          if #members > 0 then
            line = line .. "; sample: " .. code_list(members)
          end

          local groups = prefix_groups(value)
          if #groups > 0 then
            line = line .. "; common prefixes: " .. code_list(groups)
          end

          table.insert(lines, line)
        end
      end
    end
  end

  return lines
end

local function build_accessor_lines()
  local option_names = {}
  for _, name in ipairs(option_accessors) do
    if safe_get(vim, name) ~= nil then
      table.insert(option_names, "vim." .. name)
    end
  end

  local scoped_names = {}
  for _, name in ipairs(scoped_variables) do
    if safe_get(vim, name) ~= nil then
      table.insert(scoped_names, "vim." .. name)
    end
  end

  local lines = {}
  if #option_names > 0 or #scoped_names > 0 then
    table.insert(lines, "Accessor tables:")
  end

  if #option_names > 0 then
    table.insert(lines, "- Options: " .. code_list(option_names))
  end

  if #scoped_names > 0 then
    table.insert(lines, "- Scoped variables and environment: " .. code_list(scoped_names))
  end

  return lines
end

local lines = {
  "The following is a shallow, runtime-generated map of the current `vim` global.",
  "Prefer `vim.*` helpers and submodules most of all, even before `vim.api.*` or `vim.fn.*` when they fit.",
  "This summary inspects the live object, keeps public names, skips private and constant-heavy noise, and only samples a few keys from each branch.",
  "",
}

vim.list_extend(lines, build_helper_lines())
table.insert(lines, "")
vim.list_extend(lines, build_module_lines())
table.insert(lines, "")
vim.list_extend(lines, build_accessor_lines())
table.insert(lines, "")
table.insert(
  lines,
  "Do not recurse through the full nested shape of `vim` unless the task specifically needs one of these branches."
)

return table.concat(lines, "\n")
