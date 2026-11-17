-- ycode-hermes: use the model providers configured in Hermes Agent from ycode.
--
-- At startup (and on Refresh) it asks the `hermes` CLI for its config, then:
-- * every custom OpenAI-compatible provider in hermes `providers:` (e.g. ollama) becomes
--   a ycode language-model provider `hermes-<name>` with the models the endpoint lists
--   (plus the hermes default_model), via the in-memory plugin settings layer
-- * a running `hermes proxy` (Nous Portal / xAI OAuth) becomes `hermes-proxy`
-- * "hermes: providers" (command palette) shows what hermes has and what was mapped
--
-- Secrets stay in Hermes: keys are never read. ycode asks for a key per provider (or
-- reads HERMES_<NAME>_API_KEY); local endpoints like Ollama accept any value.

local PROXY = "http://127.0.0.1:8645/v1"

local info = {
    status = "not loaded",
    model = nil,        -- { default = ..., provider = ... }
    providers = {},     -- name -> hermes provider table
    models = {},        -- name -> { model ids from the endpoint }
    pools = {},         -- { "anthropic (1 credentials)", ... }
    proxy = {},         -- status lines
    proxy_models = nil,
    mapped = {},        -- ycode provider id -> api_url
}

local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function decode(s)
    local ok, v = pcall(ycode.json_decode, s)
    return ok and v or nil
end

local function model_ids(listing)
    local ids = {}
    local v = listing and decode(listing)
    for _, m in ipairs(v and v.data or {}) do
        if m.id then ids[#ids + 1] = m.id end
    end
    table.sort(ids)
    return ids
end

-- Build the ycode settings from `info` and apply them.
local function apply()
    local compat = {}
    info.mapped = {}
    for name, p in pairs(info.providers) do
        if type(p) == "table" and p.api then
            local ids, seen = {}, {}
            if p.default_model then ids[1] = p.default_model; seen[p.default_model] = true end
            for _, id in ipairs(info.models[name] or {}) do
                if not seen[id] then ids[#ids + 1] = id; seen[id] = true end
            end
            local models = {}
            for _, id in ipairs(ids) do
                models[#models + 1] = {
                    name = id,
                    max_tokens = math.tointeger(p.context_length) or 128000,
                    capabilities = { tools = true, images = false,
                                     parallel_tool_calls = false, prompt_cache_key = false },
                }
            end
            local id = "hermes-" .. name
            compat[id] = { api_url = p.api, available_models = models }
            info.mapped[id] = p.api
        end
    end
    if info.proxy_models and #info.proxy_models > 0 then
        local models = {}
        for _, mid in ipairs(info.proxy_models) do
            models[#models + 1] = { name = mid, max_tokens = 128000,
                capabilities = { tools = true, images = false,
                                 parallel_tool_calls = false, prompt_cache_key = false } }
        end
        compat["hermes-proxy"] = { api_url = PROXY, available_models = models }
        info.mapped["hermes-proxy"] = PROXY
    end
    ycode.settings{ language_models = { openai_compatible = compat } }
end

local refreshing = false

-- Query hermes in the background, then each endpoint's /models, then apply.
local function refresh()
    if refreshing then return end
    refreshing = true
    info.status = "loading…"
    local cmd = table.concat({
        "echo '@@model'; hermes config get model --json",
        "echo '@@providers'; hermes config get providers --json",
        "echo '@@pools'; hermes auth list 2>&1 | grep -E '^[^ ].*credentials'",
        "echo '@@proxy'; hermes proxy status 2>&1 | grep '\\['",
        "echo '@@proxy_models'; curl -sf -m 2 " .. PROXY .. "/models",
        "true",
    }, "; ")
    ycode.spawn(cmd, function(ok, out)
        local sections, cur = {}, nil
        for line in (out .. "\n"):gmatch("(.-)\n") do
            local name = line:match("^@@(%w+)$")
            if name then cur = name; sections[cur] = {}
            elseif cur then table.insert(sections[cur], line) end
        end
        local function text(k) return table.concat(sections[k] or {}, "\n") end
        info.model = decode(text("model"))
        info.providers = decode(text("providers")) or {}
        info.pools = sections.pools or {}
        info.proxy = sections.proxy or {}
        info.proxy_models = model_ids(text("proxy_models"))
        if not info.model then
            info.status = "hermes not available: " .. text("model")
            refreshing = false
            return
        end
        -- endpoint model lists
        local parts = {}
        for name, p in pairs(info.providers) do
            if type(p) == "table" and p.api then
                parts[#parts + 1] = string.format("echo '@@%s'; curl -sf -m 2 %s",
                    name, sh_quote(p.api:gsub("/$", "") .. "/models"))
            end
        end
        parts[#parts + 1] = "true"
        ycode.spawn(table.concat(parts, "; "), function(_, out2)
            local cur2, lists = nil, {}
            for line in (out2 .. "\n"):gmatch("(.-)\n") do
                local name = line:match("^@@(.+)$")
                if name then cur2 = name; lists[cur2] = {}
                elseif cur2 then table.insert(lists[cur2], line) end
            end
            info.models = {}
            for name, lines in pairs(lists) do
                info.models[name] = model_ids(table.concat(lines, "\n"))
            end
            apply()
            local n = 0
            for _ in pairs(info.mapped) do n = n + 1 end
            info.status = string.format("hermes %s/%s · %d provider(s) mapped",
                info.model.provider or "?", info.model.default or "?", n)
            ycode.log("ycode-hermes: " .. info.status)
            refreshing = false
        end)
    end)
end

local function render(w)
    local rows = { "col", id = "body", scroll = true, grow = true, p = 12, gap = 10 }
    local function section(title, items)
        local col = { "col", gap = 3, { "text", title, bold = true } }
        for _, it in ipairs(items) do col[#col + 1] = it end
        rows[#rows + 1] = col
    end
    local m = info.model or {}
    section("Hermes default", {
        { "text", (m.provider or "?") .. " / " .. (m.default or "?"), mono = true },
        { "text", "OAuth/subscription providers stay inside Hermes; use `hermes proxy` to expose one.", fg = "muted", size = 12 },
    })
    local provs = {}
    local names = {}
    for name in pairs(info.providers) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local p = info.providers[name]
        local id = "hermes-" .. name
        provs[#provs + 1] = { "col", p = 6, rounded = 4, border = "border", gap = 2,
            { "row", gap = 8,
                { "text", name, bold = true },
                { "text", info.mapped[id] and ("→ " .. id) or "not mapped",
                  fg = info.mapped[id] and "success" or "muted" } },
            { "text", tostring(p.api), mono = true, size = 12 },
            { "text", "default " .. tostring(p.default_model) .. " · " ..
                #(info.models[name] or {}) .. " models listed · key: HERMES_" ..
                name:upper():gsub("[^%w]", "_") .. "_API_KEY or ycode's agent settings",
              fg = "muted", size = 12 },
        }
    end
    if #provs == 0 then provs[1] = { "text", "none", fg = "muted" } end
    section("Custom providers", provs)
    local pools = {}
    for _, l in ipairs(info.pools) do pools[#pools + 1] = { "text", l, mono = true, size = 12 } end
    section("Credential pools", pools)
    local proxy = {}
    for _, l in ipairs(info.proxy) do proxy[#proxy + 1] = { "text", l, mono = true, size = 12 } end
    proxy[#proxy + 1] = { "text", info.mapped["hermes-proxy"] and "proxy running → hermes-proxy"
        or "proxy not running (hermes proxy start)", fg = "muted", size = 12 }
    section("hermes proxy", proxy)

    return { "col", w = "full", h = "full",
        rows,
        { "row", px = 10, py = 6, gap = 8, align = "center", bg = "panel",
            { "button", refreshing and "Refreshing…" or "Refresh",
              on_click = function() refresh() end },
            { "text", info.status, fg = "muted", size = 12 },
        },
    }
end

%ctor
    refresh()
end

%hook hermes
%new - Providers
    gpui.open_window{
        title = "Hermes providers",
        width = 640, height = 560,
        poll_ms = 500,
        render = function(w)
            local ok, tree = pcall(render, w)
            if ok then return tree end
            return { "text", "ycode-hermes: " .. tostring(tree), fg = "error" }
        end,
    }
end
%end
