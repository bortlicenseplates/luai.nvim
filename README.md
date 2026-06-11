# `luai.nvim`

Generate, Demand, and Improve Lua Functions on the fly.

## Setup

This fork uses the local Pi CLI for generation. Make sure `pi` is installed, available on your `PATH`, and already authenticated before using the plugin.

```lua
require("luai").setup {
  model = "anthropic/claude-sonnet-4-6",
}
```

Internally, `luai.nvim` invokes Pi in non-interactive JSON mode with a plugin-local system prompt:

```bash
PI_CODING_AGENT_DIR="$PLUGIN_ROOT/.pi" pi -p --mode json --model anthropic/claude-sonnet-4-6 --no-tools --no-extensions --no-skills --no-prompt-templates --no-themes --no-context-files --no-session --append-system-prompt "$PLUGIN_ROOT/pi/luai-system-prompt.md" "<prompt>"
```

The plugin reads the final assistant text from Pi's JSON event stream and treats it like Cursor Agent's former `.result` field. The response is expected to be raw Lua code that starts with `return function(opts)` and ends with `end`.
If Pi accidentally returns fenced Lua or a small amount of prose before the code, `luai.nvim` will try to normalize that automatically.
You can override the default model for any single generation by passing `__model` in the opts table, for example `generate.some_fn { __model = "anthropic/claude-opus-4-7" }`.

## Usage

### `demand`

```lua
-- Load demand into the scope.
local demand = require("luai").demand

-- Demand is like `require` - just give it a module name
-- (must have a base module somewhere with a shared name)
--
-- If you have already demanded this function before, it will
-- re-use the generated function. Otherwise, it will generate
-- a function definition for you on the fly, and then save it.
--
-- NOTE: `demand` automatically executes the code. So if you
-- care about that, you should probably use `generate` first ;)
local win = demand("custom.utils").create_floating_window {
    title = "Hello, World!",
    filetype = "lua"
}
```

This will create a new file wherever you have a `lua/custom` folder somewhere in your runtime path.

The folder structure will look like:

```
lua/custom/utils/init.lua
lua/custom/utils/create_floating_window.lua
```

Going forward, you can just `require("custom.utils").create_floating_window` if you want! I made it so that
afterwards, loading it just works as normal with Lua. Or you can delete the file and it will generate something
fresh next time you `demand` it.

### `generate`

You can generate functions with a command:

```vim
:LuaiGenerate
```

This will lead you through several prompts and then generate the code, where you can review it afterwards.

### `improve`

```vim
" The coolest way to use the command:
:LuaiImprove
```

This will open up a selection window for you to select from
the generated modules on your runtimepath, then a second selection
for the generated functions inside that module, and finally it will
prompt you for what you want improved.
