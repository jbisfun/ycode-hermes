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
-- Hermes sessions (from any surface: CLI, gateway, other editors) started in the open
-- folders or their subdirectories are listed over ACP and kept in the threads sidebar:
-- shortly after startup, then every SYNC_SECONDS.
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

-- Only sessions started in an open folder or below it; Hermes threads from elsewhere are
-- taken out of the sidebar (they stay in Hermes and come back when that folder is open).
local function sync()
    local folders = ycode.workspace_folders()
    if #folders == 0 then return end
    ycode.dispatch("agent::SyncAgentThreads", { agent = AGENT, folders = folders })
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
    local fact = function(k, v) return { "list_item", k, detail = v } end
    return { "panel", header = { title = "Hermes over ACP", actions = {
            { "icon_button", icon = "rotate_cw", tooltip = "Re-check", on_click = function() check() end } } },
        footer = "Chats with the \"hermes\" agent are Hermes sessions; change the model with `hermes model`.",
        { "section", "Status",
            { "list_item", status.text, mono = true, size = "small",
              color = status.ok == true and "success" or status.ok == false and "error" or "muted" },
            fact("version", tostring(status.version or "?")),
            fact("model", tostring(m.provider or "?") .. " / " .. tostring(m.default or "?")),
            fact("sidebar sync", (last_sync and ("last at " .. last_sync) or "pending")
                .. ", every " .. SYNC_SECONDS .. "s") },
        { "toolbar",
            { "button", "New Hermes thread", style = "filled", on_click = function(w)
                ycode.dispatch("agent::NewExternalAgentThread", { agent = AGENT })
                w.close()
            end },
            { "button", "Sync threads", on_click = function() sync() end } },
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
            return { "empty", "ycode-hermes: " .. tostring(tree), color = "error" }
        end,
    }
end
%end
