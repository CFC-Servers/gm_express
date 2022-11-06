# 🚄 Express
A lightning-fast networking library for Garry's Mod that allows you to quickly send large amounts of data between server/client with ease.

Seriously, [it's really easy](#Usage)!

## Requirements
 - [gm_playerload](https://github.com/CFC-Servers/gm_playerload)
 - [gm_pon](https://github.com/CFC-Servers/gm_pon)

## Usage
```lua
-- Server
-- data can be a table of any structure, with any types. The hard size limit is ~50Mb
local data = ents.GetAll()
express.Broadcast( "all_ents", data )

express.Listen( "all_ents", function( data, ply )
    print( "Got " .. #data .. " ents!" )
end )

-- Client
express.Listen( "all_ents", function( data )
    print( "Got " .. #data .. " ents!" )
    
    express.Send( "all_ents", data )
end )
```
