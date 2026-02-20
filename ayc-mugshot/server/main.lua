-- ============================================================
-- PATH UTILITIES
-- ============================================================

--- Normalize path separators and remove duplicates
--- @param path string
--- @return string
local function normalizePath(path)
    if not path then return '' end
    path = string.gsub(path, '\\', '/')
    path = string.gsub(path, '([^:])//+', '%1/')
    path = string.gsub(path, '/$', '')
    return path
end

--- Join multiple path segments
--- @vararg string
--- @return string
local function joinPath(...)
    local parts  = {...}
    local result = ''
    for i, part in ipairs(parts) do
        if not part or part == '' then goto continue end
        if i > 1 then part = string.gsub(part, '^/+', '') end
        part = string.gsub(part, '/+$', '')
        if result == '' then
            result = part
        else
            result = result .. '/' .. part
        end
        ::continue::
    end
    return normalizePath(result)
end

-- ============================================================
-- DIRECTORY & FILE OPERATIONS
-- ============================================================

--- Ensure a directory exists, creating it recursively if needed
--- @param dirPath string
--- @return boolean
local function ensureDirectory(dirPath)
    dirPath = normalizePath(dirPath)

    -- Test if directory already exists
    local testFile = dirPath .. '/.dirtest'
    local f = io.open(testFile, 'w')
    if f then
        f:close()
        os.remove(testFile)
        return true
    end

    -- Create directory using OS command
    local isWin = package.config:sub(1, 1) == '\\'
    if isWin then
        os.execute(('mkdir "%s" 2>nul'):format(string.gsub(dirPath, '/', '\\')))
    else
        os.execute(('mkdir -p "%s" 2>/dev/null'):format(dirPath))
    end

    -- Verify creation
    f = io.open(testFile, 'w')
    if f then
        f:close()
        os.remove(testFile)
        return true
    end
    return false
end

--- Decode base64 string to binary data
--- @param data string
--- @return string
local function b64decode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^' .. b .. '=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r, f = '', (b:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i-1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

--- Save base64 image data to a PNG file
--- @param filename   string
--- @param base64Data string
--- @return boolean success
--- @return string|nil filePath
--- @return string|nil error
local function saveToFile(filename, base64Data)
    if not filename or not base64Data or base64Data == '' then
        return false, nil, 'Invalid input'
    end

    local resourcePath = GetResourcePath(GetCurrentResourceName())
    local dirPath      = joinPath(resourcePath, Config.SavePath)
    local filePath     = joinPath(dirPath, filename)

    if not ensureDirectory(dirPath) then
        return false, nil, 'Failed to create directory: ' .. dirPath
    end

    -- Strip data URI prefix if present
    local raw = string.gsub(base64Data, '^data:image/[%w]+;base64,', '')
    local ok, decoded = pcall(b64decode, raw)
    if not ok or not decoded or #decoded == 0 then
        return false, nil, 'Base64 decode failed'
    end

    local file, err = io.open(filePath, 'wb')
    if not file then
        return false, nil, 'Cannot open file: ' .. (err or filePath)
    end
    file:write(decoded)
    file:close()


    return true, filePath, nil
end

-- ============================================================
-- WEBHOOK
-- ============================================================

--- Send a Discord webhook notification
--- @param playerId   number
--- @param base64Data string
--- @param identifier string
local function sendWebhook(playerId, base64Data, identifier)
    if not Config.Webhook or not Config.Webhook.Enabled then return end
    if not Config.Webhook.URL or Config.Webhook.URL == '' then return end

    local playerName = GetPlayerName(playerId) or 'Unknown'

    PerformHttpRequest(Config.Webhook.URL, function() end, 'POST', json.encode({
        username   = Config.Webhook.Username or 'Mugshot Bot',
        avatar_url = Config.Webhook.Avatar or nil,
        embeds     = {{
            title       = 'Mugshot Captured',
            description = ('**Player:** %s\n**Server ID:** %d\n**Identifier:** %s')
                :format(playerName, playerId, identifier or 'N/A'),
            color       = 3447003,
            footer      = {
                text = 'ayc-mugshot v3.0.0 | ' .. os.date('%Y-%m-%d %H:%M:%S')
            },
        }},
    }), { ['Content-Type'] = 'application/json' })
end

-- ============================================================
-- EVENTS
-- ============================================================

--- Handle mugshot save request from client
RegisterNetEvent('ayc-mugshot:server:saveMugshot', function(data)
    local src = source
    if not data or not data.base64 then
        TriggerClientEvent('ayc-mugshot:client:saveResult', src, {
            success = false,
            error   = 'No data received',
        })
        return
    end

    local safeName = string.gsub(data.identifier or GetPlayerName(src) or 'Unknown', '[^%w_%-]', '_')
    local filename = ('%s_%s.png'):format(safeName, os.date('%Y%m%d_%H%M%S'))
    local result   = { success = true, base64 = data.base64 }

    -- Save to file if enabled
    if Config.SaveToFile then
        local ok, path, err = saveToFile(filename, data.base64)
        result.success  = ok
        result.filePath = path
        if err then result.error = err end
    end

    -- Send webhook if enabled
    if Config.Webhook and Config.Webhook.Enabled then
        sendWebhook(src, data.base64, data.identifier)
    end

    TriggerClientEvent('ayc-mugshot:client:saveResult', src, result)
end)

-- ============================================================
-- SERVER-SIDE EXPORTS
-- ============================================================

--- Request a mugshot from a specific player (triggers client capture)
--- @param netId number  Entity network ID
--- @param options  table|nil  { transparent, removeProps, removeMask, upscale, upscaleFactor }
--- @return string|nil base64
--- @return string|nil error
exports('GetMugshot', function(ped, options)
    if not netId or not DoesEntityExist(ped) then
        return nil, 'Invalid network ID'
    end

    local p = promise.new()
    local entity = ped
    local playerId = NetworkGetEntityOwner(entity)
    -- Trigger client-side capture
    if not options then options = {} end
    options.netId = NetworkGetNetworkIdFromEntity(entity)
    TriggerClientEvent('ayc-mugshot:client:requestCapture', playerId, options or {})

    -- Listen for result
    local evtName = ('ayc-mugshot:server:captureResult_%d'):format(playerId)
    local handler
    handler = RegisterNetEvent(evtName, function(data)
        RemoveEventHandler(handler)
        p:resolve(data or {})
    end)

    -- Safety timeout
    SetTimeout(Config.Timeout or 10000, function()
        pcall(function() RemoveEventHandler(handler) end)
        if not p.resolved then
            p:resolve({ error = 'Server-side capture timed out' })
        end
    end)

    local result = Citizen.Await(p)
    return result.base64, result.error
end) 

--- Get the path where mugshots are saved
--- @return string
exports('GetSavePath', function()
    return joinPath(GetResourcePath(GetCurrentResourceName()), Config.SavePath)
end)

-- ============================================================
-- ADMIN COMMAND
-- ============================================================

RegisterCommand('mugshot', function(source, args)
    local src = source

    -- Permission check (skip for console)
    if src ~= 0 and Config.AdminPermission then
        if not IsPlayerAceAllowed(src, Config.AdminPermission) then
            return
        end
    end

    local target = tonumber(args[1]) or (src ~= 0 and src or nil)
    if not target or not GetPlayerName(target) then
        if src == 0 then
            print('Usage: mugshot <player_id>')
        end
        return
    end

    -- Parse options from command arguments
    local cmdOptions = {
        transparent = args[2] == 'true' or args[2] == '1',
        removeProps = args[3] == 'true' or args[3] == '1',
        removeMask  = args[4] == 'true' or args[4] == '1',
        upscale  = args[5] == 'true' or args[5] == '1',
        upscaleFactor = tonumber(args[6]) or 2,
    }

    TriggerClientEvent('ayc-mugshot:client:requestCapture', target, cmdOptions)

    local msg = ('Mugshot requested for player %d'):format(target)
    if src == 0 then
        print(msg)
    else
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'ayc-mugshot', msg }
        })
    end
end, false)

-- ============================================================
-- STARTUP
-- ============================================================

Citizen.CreateThread(function()
    if Config.SaveToFile and Config.SavePath then
        local savePath = joinPath(GetResourcePath(GetCurrentResourceName()), Config.SavePath)
        ensureDirectory(savePath)
    end
end)
