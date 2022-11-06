# 🚄 Express
A lightning-fast networking library for Garry's Mod that allows you to quickly send large amounts of data betwen server/client with ease.

Seriously, [it's really easy](#Usage)!

## Requirements
 - [gm_playerload](https://github.com/CFC-Servers/gm_playerload)
 - [gm_pon](https://github.com/CFC-Servers/gm_pon)

## Usage
```lua
-- Server
local data = ents.GetAll()
express.Broadcast( "all_ents", data )

-- Client
express.Listen( "all_ents", function( data )
    print( "Got " .. #data .. " ents!" )
end )
```
