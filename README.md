# 🚄 Express
A lightning-fast networking library for Garry's Mod that allows you to quickly send large amounts of data between server/client with ease.

Seriously, [it's really easy](#Usage)!

## Details
Instead of using Garry's Mod's throttled _(<1mb/s!)_ and already-polluted networking system, Express uses unthrottled HTTP requests to transmit data between the client and server.

Doing it this way comes with a number of practical benefits:
 - 📬 These messages don't run on the main thread, meaning it won't block networking/physics/lua
 - 💪 A dramatic increase to maximum message size (~100mb, compared to the `net` library's 64kb limit)
 - 🏎️ Big improvements to speed in many circumstances
 - 🤙 It's simple! You don't have to worry about serializing, compressing, and splitting your table up. Just send a table!

By default, Express uses a free-forever public API provided by CFC Servers, but anyone can easily host their own!
<details>
<summary>Click here to learn more</summary>

<br>

[The Express Service](https://github.com/CFC-Servers/gm_express_service) is a Cloudflare Workers project, meaning that all of the code runs on Cloudflare's Edge servers.
All data is stored using Cloudflare's K/V system - an ultra low-latency key-value storage tool that enables Express to send large chunks of data as quickly as your internet connection will allow.

If you'd like to host your own Service, just click this button!

[![Deploy to Cloudflare Workers](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/CFC-Servers/gm_express_service)

**Note:** You'll also need to update the `express_domain` convar to whatever your new domain is. By default it'll probably look like: `gmod-express.<your cloudflare username>.workers.dev`. _(Don't include the protocol, just the raw domain)_

</details>

## Requirements
 - [gm_playerload](https://github.com/CFC-Servers/gm_playerload)
 - [gm_pon](https://github.com/CFC-Servers/gm_pon) by [@thelastpenguin](https://github.com/thelastpenguin)

## Usage

### Examples

#### Broadcast a message from Server
```lua
-- Server
local data = ents.GetAll()
express.Broadcast( "all_ents", data )

-- Client
express.Listen( "all_ents", function( data )
    print( "Got " .. #data .. " ents!" )
end )
```

#### Client -> Server
```lua
-- Client
local data = ents.GetAll()
express.Send( "all_ents", data )

-- Server
express.Listen( "all_ents", function( data, ply )
    print( "Got " .. #data .. " ents from " .. ply:Nick() )
end )
```

#### Server -> Multiple clients with confirmation callback
```lua
-- Server
local meshData = prop:GetPhysicsObject():GetMesh
local data = { data = data, entIndex = prop:EntIndex() }

-- Will be called after the player successfully downloads the data
local confirmCallback = function( ply )
    receivedMesh[ply] = true
end

express.Send( "prop_mesh", data, { ply1, ply2, ply3 }, confirmCallback )


-- Client
express.Listen( "prop_mesh", function( data )
    Entity( data.entIndex ).meshData = data.data
end )
```

## Interested in using Express?
This addon ships with a GPLv3 License, so please use it however you'd like according to the License.

If you'd like to use this addon as a dependency of your own, you may link to this page, or mark it as a Dependency on your Workshop addon: 

https://steamcommunity.com/sharedfiles/filedetails/?id=2885046932
