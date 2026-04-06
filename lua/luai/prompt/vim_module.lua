local exact_skip = {
  NIL = true,
  type_idx = true,
  val_idx = true,
}

local default_child_limit = 0

local child_limits = {
  uv = 2,
  keymap = 4,
  ui = 3,
  fs = 5,
  diagnostic = 5,
  lsp = 5,
  treesitter = 5,
  filetype = 3,
  hl = 2,
  json = 3,
  base64 = 2,
}

local function safe_get(tbl, key)
  local ok, value = pcall(function()
    return tbl[key]
  end)

  if ok then
    return value
  end
end

local function code(str)
  return ("`%s`"):format(str)
end

local function code_list(items)
  local parts = {}
  for _, item in ipairs(items) do
    table.insert(parts, code(item))
  end

  return table.concat(parts, ", ")
end

local function shorten_string(value)
  value = value:gsub("%s+", " ")
  if #value > 40 then
    value = value:sub(1, 37) .. "..."
  end

  return vim.inspect(value)
end

local function is_public_key(key)
  return type(key) == "string" and key ~= "" and not exact_skip[key] and not key:match "^_" and not key:match "^[A-Z][A-Z0-9_]*$"
end

local function compare_names(left, right)
  local left_underscores = select(2, left:gsub("_", ""))
  local right_underscores = select(2, right:gsub("_", ""))
  if left_underscores ~= right_underscores then
    return left_underscores < right_underscores
  end

  if #left ~= #right then
    return #left < #right
  end

  return left < right
end

local function root_items()
  local items = {}

  for key, value in pairs(vim) do
    if is_public_key(key) then
      items[key] = {
        value = value,
        loaded = true,
      }
    end
  end

  for key, enabled in pairs(vim._submodules or {}) do
    if enabled and is_public_key(key) and items[key] == nil then
      items[key] = {
        loaded = false,
      }
    end
  end

  local names = vim.tbl_keys(items)
  table.sort(names)

  return names, items
end

local function child_summary(path, key, value)
  local child_path = path .. "." .. key
  local value_type = type(value)

  if value_type == "function" then
    return child_path .. "()"
  end

  if value_type == "string" then
    return child_path .. " = " .. shorten_string(value)
  end

  if value_type == "number" or value_type == "boolean" then
    return child_path .. " = " .. tostring(value)
  end

  return child_path .. " [" .. value_type .. "]"
end

local function collect_children(path, tbl, limit)
  if limit <= 0 or type(tbl) ~= "table" then
    return {}
  end

  local keys = {}
  for key, _ in pairs(tbl) do
    if is_public_key(key) then
      table.insert(keys, key)
    end
  end

  local type_score = function(value)
    local value_type = type(value)
    if value_type == "function" then
      return 0
    end

    if value_type == "string" or value_type == "number" or value_type == "boolean" then
      return 1
    end

    return 2
  end

  table.sort(keys, function(left, right)
    local left_score = type_score(safe_get(tbl, left))
    local right_score = type_score(safe_get(tbl, right))

    if left_score ~= right_score then
      return left_score < right_score
    end

    return compare_names(left, right)
  end)

  if #keys > limit then
    keys = vim.list_slice(keys, 1, limit)
  end

  local items = {}
  for _, key in ipairs(keys) do
    table.insert(items, child_summary(path, key, safe_get(tbl, key)))
  end

  return items
end

local function summarize_root(name, info)
  local path = "vim." .. name
  local value = info.value

  if not info.loaded then
    local limit = child_limits[name] or default_child_limit
    if limit <= 0 then
      return { text = code(path) }
    end

    value = safe_get(vim, name)
  end

  local value_type = type(value)
  if value_type == "function" then
    return { text = code(path .. "()") }
  end

  if value_type == "string" then
    return { text = code(path) .. " = " .. shorten_string(value) }
  end

  if value_type == "number" or value_type == "boolean" then
    return { text = code(path) .. " = " .. tostring(value) }
  end

  local limit = child_limits[name] or default_child_limit
  local children = collect_children(path, value, limit)
  if #children == 0 then
    return { text = code(path) }
  end

  return { text = code(path) .. ": " .. code_list(children) }
end

local names, items = root_items()
local root_functions = {}
local root_entries = {}

for _, name in ipairs(names) do
  local info = items[name]
  if info.loaded and type(info.value) == "function" then
    table.insert(root_functions, "vim." .. name .. "()")
  else
    table.insert(root_entries, summarize_root(name, info))
  end
end

table.sort(root_functions, compare_names)
table.sort(root_entries, function(left, right)
  return left.text < right.text
end)

local lines = {
  "Live `vim` map, kept shallow for prompt size.",
  "",
}

if #root_functions > 0 then
  table.insert(lines, "Top-level functions:")
  for _, fn in ipairs(root_functions) do
    table.insert(lines, "- " .. code(fn))
  end
  table.insert(lines, "")
end

if #root_entries > 0 then
  table.insert(lines, "Top-level entries:")
  for _, entry in ipairs(root_entries) do
    table.insert(lines, "- " .. entry.text)
  end
end

return table.concat(lines, "\n")
