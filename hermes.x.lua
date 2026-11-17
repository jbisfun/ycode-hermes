-- ycode-hermes: Hermes Agent as ycode's agent, over ACP (Agent Client Protocol).
--
-- Registers `hermes acp` as an external agent, so threads in ycode's agent panel run
-- inside Hermes: they are Hermes sessions (state.db), with Hermes' memory, skills,
-- tools and model providers (including OAuth ones). ycode holds no credentials.
--
-- Command palette:
--   "hermes: new thread"  new agent-panel thread with Hermes
--   "hermes: status"      ACP check, version and Hermes' default model

local AGENT = "hermes"

local status = { text = "checking…", ok = nil, model = nil, version = nil }

local function register(command)
    ycode.settings{
        agent_servers = {
            [AGENT] = { type = "custom", command = command, args = { "acp" } },
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

local function render(w)
    local m = status.model or {}
    return { "col", w = "full", h = "full", p = 14, gap = 10,
        { "text", "Hermes over ACP", bold = true, size = 16 },
        { "text", status.text, mono = true, size = 12,
          fg = status.ok == true and "success" or status.ok == false and "error" or "muted" },
        { "text", "version " .. tostring(status.version or "?"), fg = "muted" },
        { "text", "model " .. tostring(m.provider or "?") .. " / " .. tostring(m.default or "?"),
          fg = "muted" },
        { "text", "Chats in the agent panel with the \"hermes\" agent are Hermes sessions;"
            .. " change the model with `hermes model`.", fg = "muted", size = 12 },
        { "row", gap = 8,
            { "button", "New Hermes thread", on_click = function(w)
                ycode.dispatch("agent::NewExternalAgentThread", { agent = AGENT })
                w.close()
            end },
            { "button", "Re-check", on_click = function() check() end },
        },
    }
end

%ctor
    -- Register right away with a PATH lookup; replaced by the resolved path after check.
    register("hermes")
    check()
end

%hook hermes
%new - NewThread
    ycode.dispatch("agent::NewExternalAgentThread", { agent = AGENT })
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
