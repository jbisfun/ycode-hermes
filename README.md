# ycode-hermes

ycode Lua plugin that makes [Hermes Agent](https://github.com/NousResearch/hermes-agent)
ycode's agent, over ACP (Agent Client Protocol).

It registers `hermes acp` as an external agent (`agent_servers.hermes`) through ycode's
in-memory plugin settings layer. Threads you start with the "hermes" agent in the agent
panel run inside Hermes, so they are Hermes sessions (saved in Hermes' `state.db`), with
Hermes' memory, skills, tools and model providers, including OAuth ones. ycode holds no
credentials; change the model with `hermes model`.

Command palette:

- **hermes: new thread**: new agent-panel thread with Hermes
- **hermes: status**: ACP check (`hermes acp --check`), version and Hermes' default model
- **hermes: sync threads**: show Hermes sessions in the sidebar now

## Hermes plugin

`hermes-plugin/` adds `hermes ycode-acp`: the stock ACP adapter, except that `session/list`
and `session/load` include CLI, TUI/desktop and gateway sessions (stock `hermes acp` only
shows sessions an editor created). Subagent, cron and one-shot sessions stay hidden.
Install it once:

    # from the ycode-hermes clone
    ln -s "$PWD/hermes-plugin" ~/.hermes/plugins/ycode-hermes
    hermes plugins enable ycode-hermes

## Sidebar

Hermes sessions from every surface (CLI, gateway, other editors) are listed over ACP
(`session/list`) and shown as threads in the sidebar, 5 seconds after startup and then
every 2 minutes, through ycode's `agent::SyncAgentThreads` action. Only sessions whose
working directory is an open folder or below it are shown; Hermes threads from other
directories are taken out of the sidebar (they stay in Hermes and return when their folder
is open). Opening one
loads it from Hermes (`session/load`).

At startup the plugin resolves `hermes` on PATH and runs the ACP check in the background.

## Install

    # from the ycode-hermes clone
    ln -s "$PWD" ~/.config/zed/hooks/ycode-hermes

then "ycode: reload hooks".
