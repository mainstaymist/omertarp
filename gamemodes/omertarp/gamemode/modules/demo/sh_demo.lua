-- Demo module: the reference for module authors and the in-engine smoke test
-- for every M0 surface (module lifecycle, config, logging, audit, validated
-- and rate-limited networking).
--
-- Inert unless the server config enables it:
--   data/omertarp/config/server.txt  ->  return { ["demo.enabled"] = true }
--
-- With it enabled, run `omerta_demo_ping` in a client console: the client
-- sends a validated request, the server audits it and replies to that client
-- only, and the client logs the round-trip.

local MODULE = Omerta.Module.Get("demo")
if SERVER then
    Omerta.Config.Define("demo.enabled", {
        type = "boolean",
        default = false,
        scope = "server",
        description = "Enable the M0 demo/smoke-test module.",
    })
end

Omerta.Net.Register("demo.ping", {
    realm = "client_to_server",
    schema = {
        { name = "message", type = "string", maxlen = 64 },
    },
    rate = { burst = 4, per = 4 },
    handler = function(ply, payload)
        if not Omerta.Config.Get("demo.enabled") then return end
        Omerta.Log.Audit("demo.ping", {
            actor = ply:SteamID64(),
            data = { message = payload.message },
        })
        Omerta.Net.Send("demo.pong", { echo = payload.message }, ply)
    end,
})

Omerta.Net.Register("demo.pong", {
    realm = "server_to_client",
    schema = {
        { name = "echo", type = "string", maxlen = 64 },
    },
    handler = function(payload)
        Omerta.Log.Info("demo", "pong: %s", payload.echo)
    end,
})

function MODULE:OnLoad()
    Omerta.Log.Debug("demo", "OnLoad (%s realm)", SERVER and "server" or "client")
end

function MODULE:OnEnable()
    if SERVER and Omerta.Config.Get("demo.enabled") then
        Omerta.Log.Info("demo", "demo module enabled")
    end
end

function MODULE:OnReload()
    Omerta.Log.Debug("demo", "OnReload")
end

if CLIENT and Omerta.InEngine then
    concommand.Add("omerta_demo_ping", function()
        Omerta.Net.Request("demo.ping", { message = "hello from client" })
    end)
end
