# 🚄 Express
A lightning-fast networking library for Garry's Mod that allows you to quickly send large amounts of data between server/client with ease.

Seriously, [it's really easy](#Usage)!

## Details
Instead of using Garry's Mod's throttled _(<1mb/s!)_ and already-polluted networking system, Express uses HTTP requests to transmit data between the client and server.

By default, Express uses a free-forever public API provided by CFC Servers, but anyone can easily host their own!

[The Express Service](https://github.com/CFC-Servers/gm_express_service) is a Cloudflare Workers project, meaning that all of the code runs on Cloudflare's Edge servers.
All data is stored using Cloudflare's K/V system - an ultra low-latency key-value storage tool that enables Express to send large chunks of data as quickly as your internet connection will allow.

If you'd like to host your own Service, just click this button!

[![Deploy to Cloudflare Workers](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/CFC-Servers/gm_express_service)

**Note:** You'll also need to update the `express_domain` convar to whatever your new domain is. By default it'll probably look like: `gmod-express.<your cloudflare username>.workers.dev`. _(Don't include the protocol, just the raw domain)_

## Requirements
 - [gm_playerload](https://github.com/CFC-Servers/gm_playerload)
 - [gm_pon](https://github.com/CFC-Servers/gm_pon)

## Usage

### Server -> Client(s)
```lua
-- Server
local data = ents.GetAll()
express.Broadcast( "all_ents", data )

-- Client
express.Listen( "all_ents", function( data )
    print( "Got " .. #data .. " ents!" )
end )
```

### Client -> Server
```lua
-- Client
local data = ents.GetAll()
express.Send( "all_ents", data )

-- Server
express.Listen( "all_ents", function( data, ply )
    print( "Got " .. #data .. " ents from " .. ply:Nick() )
end )
```
