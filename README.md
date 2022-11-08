# 🚄 Express
A lightning-fast networking library for Garry's Mod that allows you to quickly send large amounts of data between server/client with ease.

Seriously, it's really easy! Take a look:
```lua
-- Server
local data = file.Read( "huge_data_file.json" )
express.Broadcast( "stored_data", { data = data } )

-- Client
express.Receive( "stored_data", function( data )
    file.Write( "stored_data.json", data.data )
end )
```

In this example, `huge_data_file.json` could be in excess of 100mb without Express even breaking a sweat.
The client would receive the contents of the file as fast as their internet connection can carry it.


## Details
Instead of using Garry's Mod's throttled _(<1mb/s!)_ and already-polluted networking system, Express uses unthrottled HTTP requests to transmit data between the client and server.

Doing it this way comes with a number of practical benefits:
 - 📬 These messages don't run on the main thread, meaning it won't block networking/physics/lua
 - 💪 A dramatic increase to maximum message size (~100mb, compared to the `net` library's 64kb limit)
 - 🏎️ Big improvements to speed in many circumstances
 - 🤙 It's simple! You don't have to worry about serializing, compressing, and splitting your table up. Just send the table!

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

## Usage

### Examples

#### Broadcast a message from Server
```lua
-- Server
-- `data` can be a table of (nearly) any size, and may contain (almost) any values!
-- the recipient will get it exactly like you sent it
local data = ents.GetAll()
express.Broadcast( "all_ents", data )

-- Client
express.Receive( "all_ents", function( data )
    print( "Got " .. #data .. " ents!" )
end )
```

#### Client -> Server
```lua
-- Client
local data = ents.GetAll()
express.Send( "all_ents", data )

-- Server
-- Note that .Receive has `ply` before `data` when called from server
express.Receive( "all_ents", function( ply, data )
    print( "Got " .. #data .. " ents from " .. ply:Nick() )
end )
```

#### Server -> Multiple clients with confirmation callback
```lua
-- Server
local meshData = prop:GetPhysicsObject():GetMesh()
local data = { data = data, entIndex = prop:EntIndex() }

-- Will be called after the player successfully downloads the data
local confirmCallback = function( ply )
    receivedMesh[ply] = true
end

express.Send( "prop_mesh", data, { ply1, ply2, ply3 }, confirmCallback )


-- Client
express.Receive( "prop_mesh", function( data )
    entMeshes[data.entIndex] = data.data
end )
```

## Interested in using Express?
This addon ships with a GPLv3 License, so please use it however you'd like according to the License.

If you'd like to use this addon as a dependency of your own, you may link to this page, or mark it as a Dependency on your Workshop addon:

https://steamcommunity.com/sharedfiles/filedetails/?id=2885046932
