Config = {}

-- ============================================================
-- GENERAL
-- ============================================================
Config.Debug          = false
Config.Timeout        = 10000   -- ms - Maximum wait time for capture
Config.HeadshotDelay  = 500     -- ms - Delay after headshot registration for texture loading

-- ============================================================
-- CACHE
-- ============================================================
Config.Cache = {
    Enabled = true,
    TTL     = 60000,    -- ms - Cache entry lifetime
    MaxSize = 50,       -- Maximum cached items
}

-- ============================================================
-- QUEUE
-- ============================================================
Config.Queue = {
    MaxConcurrent = 2,      -- Maximum simultaneous captures
    RetryCount    = 2,      -- Number of retries on failure
    RetryDelay    = 1000,   -- ms - Delay between retries
}

-- ============================================================
-- CLONE SETTINGS
-- ============================================================
Config.Clone = {
    Offset  = vector3(0.0, 0.0, -100.0),   -- Clone position offset (under the map)
    Timeout = 5000,                          -- ms - Safety timeout for clone lifetime
}

-- ============================================================
-- MASK COMPONENT
-- ============================================================
-- Component 1 = Head/Mask in GTA V
Config.MaskComponent        = 1
Config.MaskDefaultDrawable  = 0
Config.MaskDefaultTexture   = 0

-- ============================================================
-- PROP INDICES TO REMOVE
-- ============================================================
-- 0 = Hat, 1 = Glasses, 2 = Ear, 6 = Watch, 7 = Bracelet
Config.PropIndices = { 0, 1, 2 }

-- ============================================================
-- NUI TRANSPARENCY SETTINGS (Color-based Fallback)
-- ============================================================
Config.Transparency = {
    Tolerance = 45
}

-- ============================================================
-- AI SEGMENTATION SETTINGS
-- ============================================================
Config.AI = {
    Enabled            = false, -- not recommended
    Architecture       = 'MobileNetV1',
    OutputStride       = 16,
    Multiplier         = 0.75,
    ModelUrl           = './models/bodypix/model-stride16.json',

    SegThreshold       = 0.4,
    InternalResolution = 'medium',
    SmoothEdges        = true,
    SmoothRadius       = 2,
    FallbackOnFail     = true,
}
-- ============================================================
-- UPSCALE SETTINGS
-- ============================================================
Config.Upscale = {
    NoiseThreshold    = 15,
    SharpenAmount   = 1.5
}

-- ============================================================
-- SERVER SETTINGS
-- ============================================================
Config.SaveToFile       = false
Config.SavePath         = 'saved_photos'
Config.AdminPermission  = 'command.mugshot'

-- ============================================================
-- WEBHOOK
-- ============================================================
Config.Webhook = {
    Enabled  = false,
    URL      = '',
    Username = 'Mugshot Bot',
    Avatar   = '',
}
