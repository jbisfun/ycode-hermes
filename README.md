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

At startup the plugin resolves `hermes` on PATH and runs the ACP check in the background.

## Install

    ln -s ~/jbisfun/ycode-hermes ~/.config/zed/hooks/ycode-hermes

then "ycode: reload hooks".
