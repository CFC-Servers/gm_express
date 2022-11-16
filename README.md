# :bullettrain_side: Express
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

[![GLuaTest](https://github.com/CFC-Servers/gm_express/actions/workflows/gluatest.yml/badge.svg)](https://github.com/CFC-Servers/GLuaTest)
[![GLuaLint](https://github.com/CFC-Servers/gm_express/actions/workflows/glualint.yml/badge.svg)](https://github.com/FPtje/GLuaFixer)


## Details
Instead of using Garry's Mod's throttled _(<1mb/s!)_ and already-polluted networking system, Express uses unthrottled HTTP requests to transmit data between the client and server.

Doing it this way comes with a number of practical benefits:
 - :mailbox_with_mail: These messages don't run on the main thread, meaning it won't block networking/physics/lua
 - :muscle: A dramatic increase to maximum message size (~100mb, compared to the `net` library's 64kb limit)
 - :racing_car: Big improvements to speed in many circumstances
 - :call_me_hand: It's simple! You don't have to worry about serializing, compressing, and splitting your table up. Just send the table!

Express works by storing the data you send on Cloudflare's Edge servers. Using Cloudflare workers, KV, and D1, Express can cheaply serve millions of requests and store hundreds of gigabytes per month. Cloudflare's Edge servers offer extremely low-latency requests and data access to every corner of the globe.

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

<details>
<summary><h3> <u>Examples</u> </h3></summary>

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
</details>
<br>

## :open_book: <ins> Documentation </ins>


<details>
<summary><h4> <strong><img src="https://user-images.githubusercontent.com/7936439/200705159-4c51d043-82a3-4d15-a335-291bb26a5528.png" width="15"> <code>express.Receive( string name, function callback )</code></strong> </h4></summary>

#### <ins>**Description**</ins>
This function is very similar to `net.Receive`. It attaches a callback function to a given message name.

#### <ins>**Arguments**</ins>
1. **`string name`**
    - The name of the message. Think of this just like the name given to `net.Receive`
    - This parameter is case-insensitive, it will be `string.lower`'d
2. **`function callback`**
    - The function to call when data comes through for this message.
    - On <img src="https://user-images.githubusercontent.com/7936439/200705060-b5e57f56-a5a1-4c95-abfa-0d568be0aad6.png" width="15"> **CLIENT**, this callback receives a single parameter:
        - **`table data`**: The data table sent by server
    - On <img src="https://user-images.githubusercontent.com/7936439/200705110-55b19d08-b342-4e94-a7c3-6b45baf98c2b.png" width="15"> **SERVER**, this callback receives two parameters:
        - **`Player ply`**: The player who sent the data
        - **`table data`**: The data table sent by the player

#### <ins>**Example**</ins>
Set up a serverside receiver for the `"balls"` message:
```lua
express.Receive( "balls", function( ply, data )
    myTable.playpin = data

    if not IsValid( ply ) then return end
    ply:ChatPrint( "Thanks for the balls!" )
end )
```

</details>

<details>
<summary><h4> <strong><img src="https://user-images.githubusercontent.com/7936439/200705159-4c51d043-82a3-4d15-a335-291bb26a5528.png" width="15"> <code>express.ReceivePreDl( string name, function callback )</code></strong> </h4></summary>

#### <ins>**Description**</ins>
Very much like `express.Receive`, except this callback runs _before_ the `data` has actually been downloaded from the Express API.

#### <ins>**Arguments**</ins>
1. **`string name`**
    - The name of the message. Think of this just like the name given to `net.Receive`
    - This parameter is case-insensitive, it will be `string.lower`'d
2. **`function callback`**
    - The function to call just before downloading the data.
    - On <img src="https://user-images.githubusercontent.com/7936439/200705060-b5e57f56-a5a1-4c95-abfa-0d568be0aad6.png" width="15"> **CLIENT**, this callback receives:
        - **`string name`**: The name of the message
        - **`string id`**: The ID of the download _(used to retrieve the data from the API)_
        - **`int size`**: The size (in bytes) of the data
        - **`boolean needsProof`**: A boolean indicating whether or not the sender has requested proof-of-download
    - On <img src="https://user-images.githubusercontent.com/7936439/200705110-55b19d08-b342-4e94-a7c3-6b45baf98c2b.png" width="15"> **SERVER**, this callback receives:
        - **`string name`**: The name of the message
        - **`Player ply`**: The player that is sending the data
        - **`string id`**: The ID of the download _(used to retrieve the data from the API)_
        - **`int size`**: The size (in bytes) of the data
        - **`boolean needsProof`**: A boolean indicating whether or not the sender has requested proof-of-download

#### <ins>**Returns**</ins>
 1. **`boolean`**:
     - Return `false` to halt the transaction. The data will not be downloaded, and the regular receiver callback will not be called.

#### <ins>**Example**</ins>
Adds a normal message receiver and a pre-download receiver to prevent the server from downloading too much data:
```lua
express.Receive( "preferences", function( ply, data )
    ply.preferences = data
end )

express.ReceivePreDl( "preferences", function( name, ply, _, size, _ )
    local maxSize = maxMessageSizes[name]
    if size <= maxSize then return end

    print( ply, "tried to send a", size, "byte", name, "message! Rejecting!" )
    return false
end )
```
</details>

<details>
<summary><h4> <strong><img src="https://user-images.githubusercontent.com/7936439/200705060-b5e57f56-a5a1-4c95-abfa-0d568be0aad6.png" width="15"> <code>express.Send( string name, table data, function onProof )</code></strong> </h4></summary>

#### <ins>**Description**</ins>
The <img src="https://user-images.githubusercontent.com/7936439/200705060-b5e57f56-a5a1-4c95-abfa-0d568be0aad6.png" width="15"> **CLIENT** version of `express.Send`. Sends an arbitrary table of data to the server, and runs the given callback when the server has downloaded the data.

#### <ins>**Arguments**</ins>
1. **`string name`**
    - The name of the message. Think of this just like the name given to `net.Receive`
    - This parameter is case-insensitive, it will be `string.lower`'d
2. **`table data`**
    - The table to send
    - This table can be of any size, in any order, with nearly any data type. The only exception you might care about is `Color` objects not being fully supported (WIP).
3. **`function onProof() = nil`**
    - If provided, the server will send a token of proof after downloading the data, which will then call this callback
    - This callback takes no parameters

#### <ins>**Example**</ins>
Sends a table of queued actions (perhaps from a UI) and then allows the client to proceed when the server confirms it was received.
A timer is created to handle the case the server doesn't respond for some reason.
```lua
local queuedActions = {
    { "remove_ban", steamID1 },
    { "add_ban", steamID2, 60 },
    { "change_rank", steamID3, "developer" }
}

myPanel:StartSpinner()
myPanel:SetInteractable( false )
express.Send( "bulk_admin_actions", queuedActions, function()
    myPanel:StopSpinner()
    myPanel:SetInteractable( true )
    timer.Remove( "bulk_actions_timeout" )
end )

timer.Create( "bulk_actions_timeout", 5, 1, function()
    myPanel:SendError( "The server didn't respond!" )
    myPanel:StopSpinner()
    myPanel:SetInteractable( true )
end )
```
</details>

<details>
<summary><h4> <strong><img src="https://user-images.githubusercontent.com/7936439/200705110-55b19d08-b342-4e94-a7c3-6b45baf98c2b.png" width="15"> <code>express.Send( string name, table data, table/Player recipient, function onProof )</code></strong> </h4></summary>

#### <ins>**Description**</ins>
The <img src="https://user-images.githubusercontent.com/7936439/200705110-55b19d08-b342-4e94-a7c3-6b45baf98c2b.png" width="15"> **SERVER** version of `express.Send`. Sends an arbitrary table of data to the recipient(s), and runs the given callback when the server has downloaded the data.

#### <ins>**Arguments**</ins>
1. **`string name`**
    - The name of the message. Think of this just like the name given to `net.Receive`
    - This parameter is case-insensitive, it will be `string.lower`'d
2. **`table data`**
    - The table to send
    - This table can be of any size, in any order, with nearly any data type. The only exception you might care about is `Color` objects not being fully supported (WIP).
3. **`table/Player recipient`**
    - If given a table, it will be treated as a table of valid Players
    - If given a single Player, it will send only to that Player
3. **`function onProof( Player ply ) = nil`**
    - If provided, the client(s) will send a token of proof after downloading the data, which will then call this callback
    - This callback takes one parameter:
        - **`Player ply`**: The player who provided the proof

#### <ins>**Example**</ins>
Sends a table of all players' current packet loss to a single player. Note that this example does not use the optional `onProof` callback.
```lua
local loss = {}
for _, ply in ipairs( player.GetAll() ) do
    loss[ply] = ply:PacketLoss()
end

express.Send( "current_packet_loss", loss, targetPly )
```
</details>

<details>
<summary><h4> <strong><img src="https://user-images.githubusercontent.com/7936439/200705110-55b19d08-b342-4e94-a7c3-6b45baf98c2b.png" width="15"> <code>express.Broadcast( string name, table data, function onProof )</code></strong> </h4></summary>

#### <ins>**Description**</ins>
Operates exactly like `express.Send`, except it sends a message to all players.

#### <ins>**Arguments**</ins>
1. **`string name`**
    - The name of the message. Think of this just like the name given to `net.Receive`
    - This parameter is case-insensitive, it will be `string.lower`'d
2. **`table data`**
    - The table to send
    - This table can be of any size, in any order, with nearly any data type. The only exception you might care about is `Color` objects not being fully supported (WIP).
3. **`function onProof( Player ply ) = nil`**
    - If provided, each player will send a token of proof after downloading the data, which will then call this callback
    - This callback takes a single parameter:
        - **`Player ply`**: The player who provided the proof

#### <ins>**Example**</ins>
Sends the updated RP rules to all players
```lua
RP.UpdateRules( newRules )
    RP.Rules = newRules
    express.Broadcast( "rp_rules", newRules )
end
```
</details>

## Credits
A big thanks to [@thelastpenguin](https://github.com/thelastpenguin) for his [super fast pON encoder](https://github.com/thelastpenguin/gLUA-Library/blob/master/pON/pON-developmental.lua) that lets Express quickly serialize almost every GMod object into a compact message.
