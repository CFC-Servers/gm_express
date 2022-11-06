# ⚡ Express
A lightning-fast networking library for Garry's Mod that allows you to quickly send large amounts of data betwen server/client with ease.

Seriously, [it's really easy](#Usage)!

## Requirements
 - [gm_playerload](https://github.com/CFC-Servers/gm_playerload)
 - [gm_pon](https://github.com/CFC-Servers/gm_pon)

## Usage
```lua
-- Server
local data = ents.GetAll()
Express:Broadcast( "all_ents", data )

-- Client
Express:Listen( "all_ents", function( data )
    print( "Got " .. #data .. " ents!" )
end )
```
