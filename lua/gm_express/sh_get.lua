
function express:Get( id, cb )
    local url = self:makeAccessURL( "read", id )

    local attempts = 0
    local rangeStart = 0
    local tr = debug.traceback()
    local rangeEnd = self.downloadChunkSize:GetInt() - 1

    local headers = table.Copy( self._bytesHeaders )

    local function setRangeHeaders()
        headers.Range = "bytes=" .. rangeStart .. "-" .. rangeEnd
    end

    local makeRequest
    local function success( code, body, responseHeaders )
    end

    local function failure( reason )
    end

    makeRequest = function()
        HTTP( {
            method = "GET",
            url = url,
            headers = headers,
            success = success,
            failed = failure,
            timeout = self:_getTimeout()
        } )
    end
end
