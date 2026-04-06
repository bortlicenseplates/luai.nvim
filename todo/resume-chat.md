# Resume Chat Idea

Keep this as a future improvement for `luai.nvim`, not an active implementation.

## Goal

Persist a Cursor Agent conversation ID for each generated function so later improve/regenerate calls can resume the same chat instead of starting from scratch.

## Recommended Shape

Store a top-level `conversation_id` alongside `history` and `implementation` in generated modules.

Why this shape:
- `history` is a revision log, while the Cursor chat session belongs to the whole generated file.
- A top-level field avoids repeating the same ID in every history entry.
- It is backward-compatible with older generated files that only contain `history`.

## Likely Files

- `lua/luai.lua`
- `lua/luai/prompt.lua`
- `test/manual.lua`

## Current Seam

`lua/luai.lua` currently shells out through `request_generation()` using:

```lua
"agent",
"-p",
"--mode",
"ask",
"--output-format",
"json",
"--model",
model,
"--trust",
"--workspace",
workspace,
prompt,
```

The generated files currently persist `history` and `implementation`, but not any chat/session identifier.

## Proposed Plan

1. Extend generated module metadata to support optional `conversation_id`.
2. Refactor `request_generation(prompt, model, conversation_id?)` to use `agent --resume <id>` when present.
3. Create a chat ID once for new generations, likely via `agent create-chat`.
4. Reuse that ID in improve/update flows.
5. If resume fails because the chat is stale, create a fresh chat, retry once, and persist the replacement ID.
6. Keep the existing prompt/history context in place initially so behavior stays stable.

## Verification

- Generate a new function and confirm the saved module includes `conversation_id`.
- Improve the same function and confirm the same ID is reused.
- Confirm older generated files still load without `conversation_id`.
- Confirm subsequent calls include `--resume <id>`.

## Notes

- Cursor CLI help confirms both `--resume [chatId]` and `create-chat` exist.
- The JSON response format does not clearly document a returned chat ID, so `create-chat` is the safer source of truth.
- There is not an obvious automated test harness here beyond `test/manual.lua`, so this likely starts with manual verification.
