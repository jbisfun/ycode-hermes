# ycode-hermes

ycode Lua plugin that makes the model providers configured in
[Hermes Agent](https://github.com/NousResearch/hermes-agent) available in ycode.

- Each custom OpenAI-compatible provider in hermes `providers:` (e.g. a local Ollama)
  becomes a ycode language-model provider `hermes-<name>`, with the hermes default model
  plus every model the endpoint lists at `/models`.
- A running `hermes proxy` (Nous Portal / xAI OAuth) becomes `hermes-proxy`.
- "hermes: providers" in the command palette shows Hermes' default model, providers,
  credential pools and proxy status, and has a Refresh button.

It reads Hermes through the `hermes` CLI (`hermes config get ... --json`, `hermes auth
list`, `hermes proxy status`) in the background at startup. It never reads keys: ycode asks
for one per provider, or reads `HERMES_<NAME>_API_KEY` (local Ollama accepts any value).
OAuth/subscription providers (e.g. Anthropic via Hermes) stay inside Hermes; expose one
with `hermes proxy start`.

Settings are applied through ycode's in-memory plugin settings layer, nothing is written
to settings.json.

## Install

    ln -s ~/jbisfun/ycode-hermes ~/.config/zed/hooks/ycode-hermes

then "ycode: reload hooks".
