CloneManager = {}

--- Create a clone of the source ped with specified options
--- @param sourcePed number     The original ped
--- @param options   table      { removeProps = bool, removeMask = bool }
--- @return number|nil clonePed
--- @return string|nil error
function CloneManager.Create(sourcePed, options)
    if not DoesEntityExist(sourcePed) then
        return nil, 'Source ped does not exist'
    end

    options = options or {}

    -- ========================================
    -- 1. Create the Clone
    -- ========================================
    local clonePed = ClonePed(sourcePed, false, false, true)

    if not clonePed or clonePed == 0 then
        return nil, 'Failed to clone ped'
    end

    -- Move clone under the map so it is invisible to players
    local sourceCoords = GetEntityCoords(sourcePed)
    local clonePos     = sourceCoords + Config.Clone.Offset

    SetEntityCoords(clonePed, clonePos.x, clonePos.y, clonePos.z, false, false, false, false)
    FreezeEntityPosition(clonePed, true)
    SetEntityVisible(clonePed, false, false)
    SetEntityInvincible(clonePed, true)
    SetBlockingOfNonTemporaryEvents(clonePed, true)

    -- ========================================
    -- 2. Remove Props (hat, glasses, etc.)
    -- ========================================
    if options.removeProps then
        for _, propIndex in ipairs(Config.PropIndices) do
            if GetPedPropIndex(clonePed, propIndex) ~= -1 then
                ClearPedProp(clonePed, propIndex)
                if Config.Debug then
                    print(('[ayc-mugshot] [CLONE] Removed prop %d'):format(propIndex))
                end
            end
        end
    end

    -- ========================================
    -- 3. Remove Mask
    -- ========================================
    if options.removeMask then
        local currentMask = GetPedDrawableVariation(clonePed, Config.MaskComponent)
        if currentMask ~= Config.MaskDefaultDrawable then
            SetPedComponentVariation(
                clonePed,
                Config.MaskComponent,
                Config.MaskDefaultDrawable,
                Config.MaskDefaultTexture,
                0
            )
            if Config.Debug then
                print(('[ayc-mugshot] [CLONE] Removed mask (was drawable %d)'):format(currentMask))
            end
        end
    end

    -- ========================================
    -- 4. Wait one frame for changes to apply
    -- ========================================
    Citizen.Wait(100)

    if Config.Debug then
        print(('[ayc-mugshot] [CLONE] Created clone %d from ped %d (props:%s mask:%s)')
            :format(clonePed, sourcePed,
                tostring(options.removeProps), tostring(options.removeMask)))
    end

    return clonePed, nil
end

--- Cleanup and delete a clone
--- @param clonePed number
function CloneManager.Destroy(clonePed)
    if clonePed and DoesEntityExist(clonePed) then
        SetEntityAsNoLongerNeeded(clonePed)
        DeleteEntity(clonePed)
        if Config.Debug then
            print(('[ayc-mugshot] [CLONE] Destroyed clone %d'):format(clonePed))
        end
    end
end

--- Create clone, execute callback, then cleanup automatically
--- @param sourcePed number
--- @param options   table
--- @param callback  function(clonePed)
--- @return any      Result of callback
function CloneManager.WithClone(sourcePed, options, callback)
    local clonePed, err = CloneManager.Create(sourcePed, options)
    if not clonePed then
        return nil, err
    end

    -- Safety timeout: destroy clone if callback hangs
    local destroyed = false
    local timeoutTimer = SetTimeout(Config.Clone.Timeout, function()
        if not destroyed then
            destroyed = true
            CloneManager.Destroy(clonePed)
            if Config.Debug then
                print('[ayc-mugshot] [CLONE] Safety timeout - clone destroyed')
            end
        end
    end)

    -- Execute callback
    local results = { pcall(callback, clonePed) }

    -- Cleanup
    if not destroyed then
        destroyed = true
        ClearTimeout(timeoutTimer)
        CloneManager.Destroy(clonePed)
    end

    if results[1] then
        return table.unpack(results, 2)
    else
        return nil, tostring(results[2])
    end
end
