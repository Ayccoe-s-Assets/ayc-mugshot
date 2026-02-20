--[[
    API Exports:
        exports['ayc-mugshot']:GetMugshot(ped, options)       -- Async (yields)
        exports['ayc-mugshot']:GetMugshotCb(ped, options, cb) -- Callback-based
        exports['ayc-mugshot']:GetPedShot(ped)                -- Raw native headshot
        exports['ayc-mugshot']:ClearCache()                   -- Clear all cached entries

    options = {
        transparent   = bool,           -- Transparent background (default: false)
        removeProps   = bool,           -- Remove hats, glasses, etc. (default: false)
        removeMask    = bool,           -- Remove face mask (default: false)
        upscale       = bool,           -- Enable upscaling (default: false)
        upscaleFactor = number,         -- 2 or 4 (default: 2)
    }
]]

-- ============================================================
-- STATE
-- ============================================================
local Cache       = {}      -- { [cacheKey] = { base64, timestamp } }
local QueueCount  = 0
local QueueWait   = {}

-- ============================================================
-- UTILITIES
-- ============================================================

--- Build a unique cache key based on ped appearance and options
--- @param ped     number
--- @param options table
--- @return string
local function makeCacheKey(ped, options)
    local model    = GetEntityModel(ped)
    local drawable = GetPedDrawableVariation(ped, 0)
    local flags    = string.format('%s_%s_%s_%s_%s',
        tostring(options.transparent or false),
        tostring(options.removeProps or false),
        tostring(options.removeMask  or false),
        tostring(options.upscale     or false),
        tostring(options.upscaleFactor or 2)
    )
    return ('%d_%d_%s'):format(model, drawable, flags)
end

--- Get entry from cache if valid
--- @param key string
--- @return string|nil base64
local function getFromCache(key)
    if not Config.Cache.Enabled then return nil end
    local entry = Cache[key]
    if not entry then return nil end
    if (GetGameTimer() - entry.timestamp) > Config.Cache.TTL then
        Cache[key] = nil
        return nil
    end
    return entry.base64
end

--- Save entry to cache (with eviction if full)
--- @param key    string
--- @param base64 string
local function setCache(key, base64)
    if not Config.Cache.Enabled then return end

    local count = 0
    local oldest_key, oldest_time
    for k, v in pairs(Cache) do
        count = count + 1
        if not oldest_time or v.timestamp < oldest_time then
            oldest_key  = k
            oldest_time = v.timestamp
        end
    end
    if count >= Config.Cache.MaxSize and oldest_key then
        Cache[oldest_key] = nil
    end

    Cache[key] = { base64 = base64, timestamp = GetGameTimer() }
end

--- Acquire a slot in the processing queue
local function acquireQueue()
    while QueueCount >= Config.Queue.MaxConcurrent do
        local p = promise.new()
        table.insert(QueueWait, p)
        Citizen.Await(p)
    end
    QueueCount = QueueCount + 1
end

--- Release a slot in the processing queue
local function releaseQueue()
    QueueCount = QueueCount - 1
    if #QueueWait > 0 then
        local p = table.remove(QueueWait, 1)
        p:resolve(true)
    end
end

-- ============================================================
-- NATIVE HEADSHOT CAPTURE
-- ============================================================

--- Capture a native headshot from a ped (no modifications applied)
--- @param ped number
--- @return string|nil txdName
--- @return number|nil handle
--- @return string|nil error
function GetPedShot(ped)
    if not DoesEntityExist(ped) then
        return nil, nil, 'Ped does not exist'
    end

    -- Attempt 1: RegisterPedheadshotTransparent
    local handle = RegisterPedheadshotTransparent(ped)

    if not handle or handle == 0 then
        -- Attempt 2: RegisterPedheadshot_3
        handle = RegisterPedheadshot_3(ped)
    end

    if not handle or handle == 0 then
        -- Attempt 3: Standard RegisterPedheadshot
        handle = RegisterPedheadshot(ped)
    end

    if not handle or handle == 0 then
        return nil, nil, 'All headshot registration methods failed'
    end

    -- Wait for headshot to be ready
    local timeout = GetGameTimer() + Config.Timeout
    while not IsPedheadshotReady(handle) do
        if GetGameTimer() > timeout then
            UnregisterPedheadshot(handle)
            return nil, nil, 'Headshot registration timed out'
        end
        Citizen.Wait(50)
    end

    local txd = GetPedheadshotTxdString(handle)
    if not txd or txd == '' then
        UnregisterPedheadshot(handle)
        return nil, nil, 'Failed to get TXD string'
    end

    if Config.Debug then
        print(('[HEADSHOT] Got TXD: %s (handle: %d)'):format(txd, handle))
    end

    return txd, handle, nil
end

-- ============================================================
-- NUI COMMUNICATION
-- ============================================================

local nuiCallbacks  = {}
local nuiCallbackId = 0

--- Send texture to NUI for processing (transparency, upscale, etc.)
--- @param txd     string   TXD texture name
--- @param options table    Full options table
--- @return string|nil base64
--- @return string|nil error
local function processViaNUI(txd, options)
    local p  = promise.new()
    nuiCallbackId = nuiCallbackId + 1
    local id = nuiCallbackId

    nuiCallbacks[id] = p

    SendNUIMessage({
        action        = 'capture',
        id            = id,
        txd           = txd,
        transparent   = options.transparent or false,
        upscale       = options.upscale or false,
        upscaleFactor = options.upscaleFactor or 2,
        config        = {
            transparency = Config.Transparency,
            ai           = Config.AI,
            upscaleConf  = Config.Upscale,
        },
    })

    -- Safety timeout for NUI response
    SetTimeout(Config.Timeout + 5000, function()
        if nuiCallbacks[id] then
            nuiCallbacks[id]:resolve({ error = 'NUI processing timed out' })
            nuiCallbacks[id] = nil
        end
    end)

    local result = Citizen.Await(p)
    return result.base64, result.error
end

--- Receive result from NUI
RegisterNUICallback('captureResult', function(data, cb)
    cb('ok')
    local id = data.id
    if id and nuiCallbacks[id] then
        local p = nuiCallbacks[id]
        nuiCallbacks[id] = nil
        p:resolve({
            base64 = data.base64,
            error  = data.error,
        })
    end
end)

-- ============================================================
-- MAIN CAPTURE FUNCTION
-- ============================================================

--- Main mugshot capture function
--- @param ped     number       Target ped
--- @param options table|nil    { transparent, removeProps, removeMask, upscale, upscaleFactor }
--- @return string|nil base64
--- @return string|nil error
local function CaptureMugshot(ped, options)
    options = options or {}

    -- Normalize options with defaults
    options.transparent   = options.transparent   == true
    options.removeProps   = options.removeProps   == true
    options.removeMask    = options.removeMask    == true
    options.upscale       = options.upscale       == true
    options.upscaleFactor = (options.upscaleFactor == 4) and 4 or 2

    if not DoesEntityExist(ped) then
        return nil, 'Ped does not exist'
    end

    -- Check cache
    local cacheKey = makeCacheKey(ped, options)
    local cached   = getFromCache(cacheKey)
    if cached then
        if Config.Debug then
            print('[CACHE] Hit')
        end
        return cached, nil
    end

    -- Acquire queue slot
    acquireQueue()

    local base64, err
    local retries = Config.Queue.RetryCount

    for attempt = 1, retries + 1 do
        if Config.Debug then
            print(('[CAPTURE] Attempt %d/%d'):format(attempt, retries + 1))
        end

        -- ======================================
        -- Determine target ped (original or clone)
        -- ======================================
        local needClone = options.removeProps or options.removeMask
        local targetPed = ped
        local clonePed  = nil

        if needClone then
            clonePed, err = CloneManager.Create(ped, {
                removeProps = options.removeProps,
                removeMask  = options.removeMask,
            })
            if not clonePed then
                if attempt <= retries then
                    Citizen.Wait(Config.Queue.RetryDelay)
                    goto continue
                end
                releaseQueue()
                return nil, ('Clone failed: %s'):format(err or 'unknown')
            end
            targetPed = clonePed

            -- Wait for clone changes to fully apply
            Citizen.Wait(200)
        end

        -- ======================================
        -- Capture native headshot
        -- ======================================
        local txd, handle
        txd, handle, err = GetPedShot(targetPed)

        if not txd then
            if clonePed then
                CloneManager.Destroy(clonePed)
            end
            if attempt <= retries then
                Citizen.Wait(Config.Queue.RetryDelay)
                goto continue
            end
            releaseQueue()
            return nil, ('Headshot failed: %s'):format(err or 'unknown')
        end

        -- Small delay for texture to fully load
        Citizen.Wait(Config.HeadshotDelay)

        -- ======================================
        -- Process via NUI (transparency + upscale)
        -- ======================================
        base64, err = processViaNUI(txd, options)

        -- Release headshot handle
        if handle then
            UnregisterPedheadshot(handle)
        end

        -- Cleanup clone
        if clonePed then
            CloneManager.Destroy(clonePed)
        end

        if base64 and base64 ~= '' then
            -- Success
            setCache(cacheKey, base64)
            releaseQueue()
            return base64, nil
        end

        -- Retry
        if attempt <= retries then
            Citizen.Wait(Config.Queue.RetryDelay)
        end

        ::continue::
    end

    releaseQueue()
    return nil, err or 'All capture attempts failed'
end

-- ============================================================
-- EXPORTS
-- ============================================================

--- Primary export - Async (yields the calling thread)
--- @param ped     number
--- @param options table|nil  { transparent, removeProps, removeMask, upscale, upscaleFactor }
--- @return string|nil base64
--- @return string|nil error
exports('GetMugshot', function(ped, options)
    return CaptureMugshot(ped, options)
end)

--- Callback-based export (does not yield)
--- @param ped      number
--- @param options  table|nil
--- @param callback function(base64, error)
exports('GetMugshotCb', function(ped, options, callback)
    -- Backward compatibility: if options is a function, treat it as callback
    if type(options) == 'function' then
        callback = options
        options  = {}
    end

    Citizen.CreateThread(function()
        local base64, err = CaptureMugshot(ped, options)
        if callback then
            callback(base64, err)
        end
    end)
end)

--- Raw native headshot export (no clone, no NUI processing)
--- @param ped number
--- @return string|nil txd
--- @return number|nil handle
exports('GetPedShot', function(ped)
    return GetPedShot(ped)
end)

--- Clear all cached entries
exports('ClearCache', function()
    Cache = {}
    if Config.Debug then
        print('[CACHE] Cleared')
    end
end)

-- ============================================================
-- SERVER REQUEST HANDLER
-- ============================================================

RegisterNetEvent('ayc-mugshot:client:requestCapture', function(options)
    local src = source
    local ped = PlayerPedId()
    if options.netId then
        if not NetworkDoesNetworkIdExist(options.netId) then
            TriggerLatentServerEvent(
                ('ayc-mugshot:server:captureResult_%d'):format(GetPlayerServerId(PlayerId())), 100000,
                { base64 = nil, error = "Network Id does not exist" }
            )
            return
        end
        ped = NetworkGetEntityFromNetworkId(options.netId)
    end
    Citizen.CreateThread(function()
        local base64, err = CaptureMugshot(ped, options or {})
        TriggerLatentServerEvent('ayc-mugshot:server:saveMugshot', 100000, {
            base64     = base64,
            error      = err,
            identifier = GetPlayerName(PlayerId()),
        })
        -- Also fire the specific result event for server-side export
        TriggerLatentServerEvent(
            ('ayc-mugshot:server:captureResult_%d'):format(GetPlayerServerId(PlayerId())), 100000,
            { base64 = base64, error = err }
        )
    end)
end)

-- ============================================================
-- STARTUP
-- ============================================================

Citizen.CreateThread(function()
    Wait(1000)
    SendNUIMessage({ action = 'init', aiConfig = Config.AI })
    if Config.Debug then
        print('Client core loaded')
    end
end)
