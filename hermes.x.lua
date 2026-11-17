-- ycode-hermes: Hermes Agent as ycode's agent, over ACP (Agent Client Protocol).
--
-- Registers `hermes acp` as an external agent, so threads in ycode's agent panel run
-- inside Hermes: they are Hermes sessions (state.db), with Hermes' memory, skills,
-- tools and model providers (including OAuth ones). ycode holds no credentials.
--
-- Command palette:
--   "hermes: new thread"  new agent-panel thread with Hermes
--   "hermes: status"      ACP check, version and Hermes' default model
--   "hermes: sync threads" show Hermes sessions in the sidebar now
--
-- Hermes sessions (from any surface: CLI, gateway, other editors) are listed over ACP
-- and kept in the threads sidebar: shortly after startup, then every SYNC_SECONDS.
-- Opening one loads it from Hermes (ACP session/load).

local AGENT = "hermes"
local SYNC_SECONDS = 120

local status = { text = "checking…", ok = nil, model = nil, version = nil }

local function register(command)
    ycode.settings{
        agent_servers = {
            -- `hermes ycode-acp` (hermes-plugin/ in this repo) is `hermes acp` listing every
            -- Hermes session, not only editor-created ones.
            [AGENT] = { type = "custom", command = command, args = { "ycode-acp" } },
        },
    }
end

-- Resolve the hermes binary and verify the ACP adapter, off the UI thread.
local function check()
    status.text, status.ok = "checking…", nil
    ycode.spawn(table.concat({
        "echo \"@@path $(command -v hermes)\"",
        "echo \"@@version $(hermes acp --version 2>&1)\"",
        "echo \"@@model $(hermes config get model --json 2>&1)\"",
        "hermes acp --check 2>&1 | tail -1",
    }, "; "), function(ok, out)
        local path = out:match("@@path ([^\n]*)")
        status.version = out:match("@@version ([^\n]*)")
        local m = out:match("@@model ([^\n]*)")
        local okm, model = pcall(ycode.json_decode, m or "")
        status.model = okm and model or nil
        if path and path ~= "" then
            register(path)
            status.ok = ok and out:find("ACP check OK", 1, true) ~= nil
            status.text = status.ok and ("registered " .. path .. " acp")
                or ("hermes acp check failed:\n" .. out)
        else
            status.ok = false
            status.text = "hermes not found on PATH"
        end
        ycode.log("ycode-hermes: " .. status.text:gsub("\n.*", ""))
    end)
end

local last_sync = nil

local function sync()
    ycode.dispatch("agent::SyncAgentThreads", { agent = AGENT })
    last_sync = os.date("%H:%M:%S")
end

-- A timer via ycode.spawn; it stops by itself when hooks are reloaded.
local function every(seconds, f)
    ycode.spawn("sleep " .. seconds, function()
        f()
        every(seconds, f)
    end)
end

local function render(w)
    local m = status.model or {}
    return { "col", w = "full", h = "full", p = 14, gap = 10,
        { "text", "Hermes over ACP", bold = true, size = 16 },
        { "text", status.text, mono = true, size = 12,
          fg = status.ok == true and "success" or status.ok == false and "error" or "muted" },
        { "text", "version " .. tostring(status.version or "?"), fg = "muted" },
        { "text", "model " .. tostring(m.provider or "?") .. " / " .. tostring(m.default or "?"),
          fg = "muted" },
        { "text", "sidebar sync " .. (last_sync and ("last at " .. last_sync) or "pending")
            .. ", every " .. SYNC_SECONDS .. "s", fg = "muted" },
        { "text", "Chats in the agent panel with the \"hermes\" agent are Hermes sessions;"
            .. " change the model with `hermes model`.", fg = "muted", size = 12 },
        { "row", gap = 8,
            { "button", "New Hermes thread", on_click = function(w)
                ycode.dispatch("agent::NewExternalAgentThread", { agent = AGENT })
                w.close()
            end },
            { "button", "Sync threads", on_click = function() sync() end },
            { "button", "Re-check", on_click = function() check() end },
        },
    }
end

%ctor
    -- Register right away with a PATH lookup; replaced by the resolved path after check.
    register("hermes")
    check()
    -- First sync once the workspace and agent panel exist, then periodically.
    ycode.spawn("sleep 5", function()
        sync()
        every(SYNC_SECONDS, sync)
    end)
end

%hook hermes
%new - NewThread
    ycode.dispatch("agent::NewExternalAgentThread", { agent = AGENT })
end

%new - SyncThreads
    sync()
end

%new - Status
    gpui.open_window{
        title = "Hermes", width = 560, height = 300, poll_ms = 500,
        render = function(w)
            local ok, tree = pcall(render, w)
            if ok then return tree end
            return { "text", "ycode-hermes: " .. tostring(tree), fg = "error" }
        end,
    }
end
%end
