# Express :bullettrain_side:
<p align="left">
    <a href="https://discord.gg/5JUqZjzmYJ" alt="Discord Invite"><img src="https://img.shields.io/discord/981394195812085770?label=Support&logo=discord&logoColor=white" /></a>
</p>

A lightning-fast networking library for Garry's Mod that allows you to quickly send large amounts of data between server/client with ease.

<br>

**FYI:** Please consider testing the next release, it has significant improvements over the base.
Read more here: https://github.com/CFC-Servers/gm_express/pull/37

<br>


Seriously, it's really easy! Take a look:
```lua
-- Server
local data = file.Read( "huge_data_file.json" )
express.Broadcast( "stored_data", { data } )

-- Client
express.Receive( "stored_data", function( data )
    file.Write( "stored_data.json", data[1] )
end )
```
<details>
<summary><i>Compared to doing it yourself...</i></summary>

```lua
-- Server
-- This is just an example!
-- It doesn't handle errors or clients joining, and it doesn't support multiple streams

util.AddNetworkString( "myaddon_datachunks" )
local buffer = ""

local function broadcastChunk()
    if #buffer == 0 then return end

    local chunkSize, isLast = math.min( 63000, #buffer ), false
    buffer = string.sub( buffer, chunkSize + 1 )

    if #pending <= chunkSize then
        buffer, isLast = "", true
    end

    net.Start( "myaddon_datachunks" )
    net.WriteUInt( chunkSize, 16 )
    net.WriteData( string.sub( pending, 1, chunkSize ), chunkSize )
    net.WriteBool( isLast )
    net.Broadcast()
end

function BroadcastFile( filePath )
    local fileData = file.Read( filePath, "DATA" )
    buffer = util.Compress( fileData )
end

local interval = engine.TickInterval() * 8
timer.Create( "MyAddon_DataSender", interval, 0, broadcastChunk )

BroadcastFile( "huge_data_file.json" )
```

```lua
-- Client
local buffer = ""
net.Receive( "myaddon_datachunks", function()
    buffer = buffer .. net.ReadData( net.ReadUInt( 16 ) )
    if not net.ReadBool() then return end

    local datas = util.Decompress( buffer )
    processData( datas )
end )
```

---

</details>



In this example, `huge_data_file.json` could be in excess of ~~100mb~~ _(soon)_ 25mb post-compression without Express even breaking a sweat.
The client would receive the contents of the file as fast as their internet connection can carry it.

[![GLuaTest](https://github.com/CFC-Servers/gm_express/actions/workflows/gluatest.yml/badge.svg)](https://github.com/CFC-Servers/GLuaTest)
[![GLuaLint](https://github.com/CFC-Servers/gm_express/actions/workflows/glualint.yml/badge.svg)](https://github.com/FPtje/GLuaFixer)


## Details
Instead of using Garry's Mod's throttled _(<1mb/s!)_ and already-polluted networking system, Express uses unthrottled HTTP requests to transmit data between the client and server.

Doing it this way comes with a number of practical benefits:
 - :mailbox_with_mail: These messages don't run on the main thread, meaning it won't block networking/physics/lua
 - :muscle: A dramatic increase to maximum message size (~100mb, compared to the `net` library's <64kb limit)
 - :racing_car: Big improvements to speed in many circumstances
 - :call_me_hand: It's simple! You don't have to worry about serializing, compressing, and splitting your table up. Just send the table!

Express works by storing the data you send on Cloudflare's Edge servers. Using Cloudflare workers, KV, and D1, Express can cheaply serve millions of requests and store hundreds of gigabytes per month. Cloudflare's Edge servers offer extremely low-latency requests and data access to every corner of the globe.

By default, Express uses [gmod.express](https://gmod.express), the public and free API provided by CFC Servers, but anyone can easily host their own!
Check out the [Express Service](https://github.com/CFC-Servers/gm_express_service) README for more information.

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
<summary><h4> <strong><img src="https://user-images.githubusercontent.com/7936439/200705159-4c51d043-82a3-4d15-a335-291bb26a5528.png" width="15"> <code>express.ClearReceiver( string name )</code></strong> </h4></summary>

#### <ins>**Description**</ins>
Removes the callback associated with the given message name. Much like `net.Receive( message, nil )`.

#### <ins>**Arguments**</ins>
1. **`string name`**
    - The name of the message. Think of this just like the name given to `net.Receive`
    - This parameter is case-insensitive, it will be `string.lower`'d

#### <ins>**Example**</ins>
Create a new Receiver when the module is enabled, and remove the receiver when it's disabled
```lua
local function enable()
    express.Receive( "example", processData )
end

local function disable()
    express.ClearReceiver( "example" )
end
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

<details>
<summary><h3>:fishing_pole_and_fish: Hooks</h3></summary>

<details>
<summary><h4> <strong><img src="https://user-images.githubusercontent.com/7936439/200705159-4c51d043-82a3-4d15-a335-291bb26a5528.png" width="15"> <code>GM:ExpressLoaded()</code></strong> </h4></summary>

#### <ins>**Description**</ins>
This hook runs when all Express code has loaded. All `express` methods are available. Runs exactly once on both realms.

This is a good time to make your Receivers _(`express.Receive`)_.

#### <ins>**Example**</ins>
Creates the Express Receivers when Express is available

```lua
-- cl_init.lua

hook.Add( "ExpressLoaded", "MyAddon_SetupExpress", function()
    express.Receive( "MyAddon_ObjectData", function( data )
        processData( data )
    end )
end )
```

</details>

<details>
<summary><h4> <strong><img src="https://user-images.githubusercontent.com/7936439/200705110-55b19d08-b342-4e94-a7c3-6b45baf98c2b.png" width="15"> <code>GM:ExpressPlayerReceiver( Player ply, string message )</code></strong> </h4></summary>

#### <ins>**Description**</ins>
Called when `ply` creates a new receiver for `message` _(and, by extension, is ready for both `net` and `express` messages)_

Once this hook is called, it is guaranteed to be safe to `express.Send` to the player.

#### <ins>**Arguments**</ins>
1. **`Player ply`**
    - The player that registered a new Express Receiver
2. **`string message`**
    - The name of the message that a Receiver was registered for
    - (**Note:** This will be `string.lower`'d before calling this hook, so expect it to always be lowercase)


#### <ins>**Example**</ins>
Sends an initial dataset to the client as soon as they're ready

```lua
-- sv_init.lua

hook.Add( "ExpressPlayerReceiver", "MyAddon_InitData", function( ply, message )
    if message ~= "myaddon_initdata" then return end
    express.Send( "myaddon_initdata", MyAddon.CurrentData, ply )
end )
```

```lua
-- cl_init.lua

hook.Add( "ExpressLoaded", "MyAddon_SetupExpress", function()
    express.Receive( "MyAddon_InitData", function( data )
        processData( data )
    end )
end )
```
</details>

</details>


<br>


## Performance

We tested Express' performance against two other options:
 - **Manual Chunking**:
   - This is a bare-minimum example script that serializes, compresses, and splits the data up across as few net messages as possible. _(This is typically what people do in smaller addons.)_
   - _[Source](https://gist.github.com/sarahsturgeon/2e73b6e4595dd4476d87494ba4cb73b0#file-sender_chunking-lua)_
 - **NetStream**:
   - This library is very popular. It's the go-to choice for sending large chunks of data. It's currently used by Starfall, PAC3, AdvDupe2, etc.
   - _[Source](https://gist.github.com/sarahsturgeon/2e73b6e4595dd4476d87494ba4cb73b0#file-netstream-lua)_

#### Test Details
<details>
<summary><b>Test Setup</b></summary>

Our findings are based on a series of tests where we generated data sets filled with random elements across a range of data types. (`string`, `int`, `float`, `bool`, `Vector`, `Angle`, `Color`, `Entity`, `table`)

We sent this data using each of the options, one at a time.

These test were performed on a moderately-specced laptop. The server was a dedicated base-branch server run in WSL2. The client was base-branch clean-install run on Windows.

For each test, we collected two key metrics:
- **Duration**: The total time _(in seconds)_ it took to complete each test. This includes compression, serialization, sending, and acknowledgement.
- **Message Count**: The number of net messages sent during the transfer. Fewer is usually better.

**References**:
 - [This](https://gist.github.com/sarahsturgeon/15d195b2a5f8480c6579cc89816d2ac3) is an example of the data sets that we use during the test runs.
 - You can view the raw test setup [here](https://gist.github.com/sarahsturgeon/2e73b6e4595dd4476d87494ba4cb73b0).
</details>

<details>
<summary><b>Detailed Test Results</b></summary>
<details>
<summary><b>Test 1</b> <code>(74.75 KB)</code>:</summary>

<b>Summary: </b>This data can fit in only two net messages. In this situation, Express loses out to just sending net messages (by almost a full second).

| Data Size | Compressed Size |
| -------------- | -------------------- |
| 194.97 KB | 74.75 KB |

| Method | Duration (s) | Messages Sent |
| ------ | ------------ | ------------- |
| Manual Chunking | 1.265 | 2 |
| NetStream | 2.273 | 11 |
| Express | 1.909 | 1 |

</details>

<details>
<summary><b>Test 2</b> <code>(374.78 KB)</code>:</summary>

<b>Summary: </b>Requiring at least six net messages when sent normally, Express sends the data about 3x faster.

| Data Size | Compressed Size |
| -------------- | -------------------- |
| 988.2 KB | 374.78 KB |

| Method | Duration (s) | Messages Sent |
| ------ | ------------ | ------------- |
| Manual Chunking | 6.160 | 6 |
| NetStream | 10.303 | 51 |
| Express | 2.151 | 1 |

</details>

<details>
<summary><b>Test 3</b> <code>(1.5 MB)</code>:</summary>

<b>Summary: </b>After passing the "1 megabyte" mark, Express' advantages bein really shining through, beating the next fastest option by 21 seconds (8x faster!)

| Data Size | Compressed Size |
| -------------- | -------------------- |
| 3.97 MB | 1.5 MB |

| Method | Duration (s) | Messages Sent |
| ------ | ------------ | ------------- |
| Manual Chunking | 24.325 | 24 |
| NetStream | 40.849 | 200 |
| Express | 2.897 | 1 |

</details>

<details>
<summary><b>Test 4</b> <code>(11.22 MB)</code>:</summary>

<b>Summary: </b>With a much larger payload, it becomes abundantly clear how slow and prohibitive the built-in net library can be. Express sends this 11mb payload in under 20 seconds, while the net library is nearing **200 seconds**.

| Data Size | Compressed Size |
| -------------- | -------------------- |
| 29.67 MB | 11.22 MB |

| Method | Duration (s) | Messages Sent |
| ------ | ------------ | ------------- |
| Manual Chunking | 181.491 | 180 |
| NetStream | 304.552 | 1,485 |
| Express | 18.993 | 1 |

</details>

<details>
<summary><b>Test 5</b> <code>(11.96 KB)</code>:</summary>
<b>Summary: </b>Because this payload only requires a single net message, Express falls way behind of the pack in terms of transfer speed.

| Data Size | Compressed Size |
| -------------- | -------------------- |
| 29.79 KB | 11.96 KB |

| Method | Duration (s) | Messages Sent |
| ------ | ------------ | ------------- |
| Manual Chunking | 0.306 | 1 |
| NetStream | 0.833 | 3 |
| Express | 1.333 | 1 |

</details>
</details>

#### Test Result Takeaways

- Express sends data significantly faster than both Manual Chunking and NetStream when the data size exceeds a certain threshold _(Roughly whenever 3 or more net messages would be required)_.
- Express only sends up to 2 net messages per transfer, no matter the size of the data.
- Despite its impressive performance with large data sizes, Express is less efficient than other methods for smaller data sizes.
- _(NetStream is surprisingly slow, regardless of data size)_

#### Extra Notes
- These results will depend heavily on networking conditions. For some people, lots of smaller messages may actually perform better than one large Express download.
- Anything that uses the built-in net library _(like NetStream)_ will be more reliable than a library like Express, even if they may be slower overall.
- Express caches sends. This means that if you needed to send a dataset to more than one player, Express would only need to upload the data once, saving a significant amount of time and bandwidth. These savings aren't reflected in this test run.

These tests illustrate how Express can significantly improve data transfer speed and efficiency for large or even intermediate-scale data, but may underperform when handling smaller data sizes.

Understanding the trade-offs of Express can help you determine if it's a good fit for your project.

## Case Studies

<details>
<summary><h3>Intricate ACF-3 Tank dupe :gun:</h3></summary>
Here's a clip of me spawning a particularly detailed and Prop2Mesh-heavy ACF-3 dupe (both Prop2Mesh and Adv2 use Netstream to transmit their data).

<br>

https://user-images.githubusercontent.com/7936439/202295397-047736ce-43e5-4ab3-b741-6f5e7517e6bb.mp4

A few things to note:
 - It took ~20 seconds for the dupe to be transferred to the server via Netstream
 - It took an additional ~20 seconds for the Prop2Mesh data to be Netstreamed back to me
 - On the netgraph, you can see the `in` and `out` metrics (and the associated green horizontal progress bar) that shows Netstream sending each chunk
 - **Netstream only processes one request at a time**. This is important, because it means while Adv2 or Prop2Mesh are transmitting data, no other player can use any Netstream-based addon until it completes.


Using some custom backport code, I converted Prop2Mesh _and_ Advanced Duplicator 2 to use Express instead of Netstream.
Here's me spawning the same tank in the exact same conditions, but using Express instead:

https://user-images.githubusercontent.com/7936439/202296048-d3cbbb32-f3a9-47f3-a42c-6f59fd7f6697.mp4

The entire process took under 15 seconds - that's over 60% faster!
My PC actually lagged for a moment because of how quickly all of the meshes downloaded and were available to render.

Even better? **This doesn't block any other player from spawning their dupes**! Because this is using Express instead of Netstream, other players can freely spawn their dupes, Prop2Mesh, Starfalls, etc. without being blocked and without blocking others.

</details>

<details>
<summary><h3>Prop2Mesh + Adv2 stress test :test_tube:</h3></summary>
I had someone who knew more about Prop2Mesh than me create a highly complex controller. Here are the stats:

![XngzjRoTlZ](https://user-images.githubusercontent.com/7936439/202296941-3280c2dd-3660-45ac-9e20-24a180dd6ab2.png)

Nearly 1M triangles across 162 models! If you've ever worked with meshes before, you'll know those are crazy high numbers.

When spawning this dupe in a stock server with Adv2 and Prop2Mesh, it takes **nearly 4 minutes**! All the while, blocking other players from using any Netstream-based addon. I can't even upload the video here because it's too big. Hopefully this screenshot is informative enough:

![image](https://user-images.githubusercontent.com/7936439/202297362-eef07e2d-65dd-41f9-a00c-8b5bf4388b10.png)

Some metrics:
 - It took 1 minute and 50 seconds before the dupe was even spawnable (it had to send the full dupe over to the server first)
 - After an additional 3 minutes, the meshes were finally downloaded and rendered
 - Again, while this was happening, no other player could use Adv2, Prop2Mesh, or Starfall

With that same backport code, forcing Adv2 and Prop2Mesh to use Express, the entire process **takes under 30 seconds**!
That's almost a **90%** speed increase.

https://user-images.githubusercontent.com/7936439/202298284-bea90b54-c0b9-440b-b615-c9f58a1ed1f4.mp4

</details>




## Credits
A big thanks to [@thelastpenguin](https://github.com/thelastpenguin) for his [super fast pON encoder](https://github.com/thelastpenguin/gLUA-Library/blob/master/pON/pON-developmental.lua) that lets Express quickly serialize almost every GMod object into a compact message.
