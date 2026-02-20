# AYC Mugshot 📸

A highly optimized, feature-rich FiveM resource for capturing high-quality player mugshots (headshots). This script utilizes native GTA V functions combined with NUI Canvas processing to offer advanced features like AI background removal, image upscaling, and automatic prop/mask hiding.

## 🌟 Features

- **Advanced Processing:** Uses NUI to process raw textures (`txd`) into Base64 PNG formats.
- **AI Background Removal:** Built-in AI segmentation (MobileNetV1) to create transparent mugshots.
- **Image Upscaling:** Upscale captured headshots (2x or 4x) for crisp, high-quality UI elements.
- **Smart Ped Cloning:** Automatically creates an invisible clone under the map to safely remove props (hats, glasses) and masks before capturing, without affecting the actual player.
- **High Performance & Stability:** 
  - **Queue System:** Prevents NUI and server crashes by limiting concurrent capture requests.
  - **Cache System:** Caches generated base64 images (with TTL) to prevent redundant rendering.
- **Server-Side Integration:** Option to save generated mugshots directly as `.png` files on the server.
- **Discord Logs:** Built-in webhook support to log captured mugshots.
- **Developer Friendly:** Provides both Async (yield) and Callback-based exports.

## 📥 Installation

1. Download the resource and place it in your `resources` folder.
2. Rename the folder to `ayc-mugshot` (if it isn't already).
3. Add `ensure ayc-mugshot` to your `server.cfg`.
4. Configure the script to your liking in `config.lua`.

## ⚙️ Configuration (`config.lua`)

The script is highly customizable. Key configurations include:
- `Config.Cache`: Adjust cache Time-To-Live (TTL) and maximum size.
- `Config.Queue`: Set max concurrent captures and retry attempts.
- `Config.Clone`: Adjust the offset coordinate (under the map) where the clone is spawned.
- `Config.AI`: Enable/Disable AI segmentation and adjust model parameters.
- `Config.Webhook`: Set up Discord webhook for logging.
- `Config.SaveToFile`: Enable saving base64 strings as physical `.png` files on your server.

## 🛠️ Developer API (Exports)

You can easily integrate this script into your own resources (e.g., ID cards, MDT, inventory).

### 1. GetMugshot (Async)
Yields the calling thread until the image is processed. Best for modern, sequential code.
```lua
local ped = PlayerPedId()
local options = {
    transparent   = true,  -- Remove background
    removeProps   = true,  -- Remove hats, glasses, etc.
    removeMask    = true,  -- Remove masks
    upscale       = true,  -- Upscale the image
    upscaleFactor = 2      -- 2 or 4
}

local base64, err = exports['ayc-mugshot']:GetMugshot(ped, options)

if base64 then
    print("Mugshot captured successfully!")
    -- Send to NUI or Server
else
    print("Failed to capture mugshot: " .. tostring(err))
end
```
### 2. GetMugshotCb (Callback)
Standard callback method. Does not yield the thread.

```lua
local ped = PlayerPedId()

exports['ayc-mugshot']:GetMugshotCb(ped, { transparent = true, removeProps = true }, function(base64, err)
    if base64 then
        print("Mugshot captured successfully!")
    else
        print("Error: " .. tostring(err))
    end
end)
```
### 3. GetPedShot (Raw Native)
Returns the raw `txd` and `handle` without any NUI processing or ped cloning.

```lua
local txd, handle = exports['ayc-mugshot']:GetPedShot(PlayerPedId())
if txd then
    print("Raw TXD string: " .. txd)
    UnregisterPedheadshot(handle) -- Remember to unregister!
end
```
### 4. ClearCache
Manually flushes the image cache memory.

```lua
exports['ayc-mugshot']:ClearCache()
```
## 📡 Server-Side Exports

These exports are available to use on the **server-side** of your scripts.

### 1. GetMugshot (Async)
Requests a mugshot from a specific ped by triggering the client capture and yielding the server thread until the result is returned.

```lua
local ped = GetPlayerPed(1)
local options = {
    transparent = true,
    removeProps = true,
    upscale = true,
    upscaleFactor = 2
}

-- This will yield the server thread until the client responds or it times out
local base64, err = exports['ayc-mugshot']:GetMugshot(ped, options)

if base64 then
    print("Successfully captured mugshot for ped: " .. ped)
else
    print("Failed to capture mugshot: " .. tostring(err))
end
```
### 2. GetSavePath
Returns the absolute physical path on the server where the `.png` mugshots are currently being saved (based on `Config.SavePath`).

```lua
local path = exports['ayc-mugshot']:GetSavePath()
print("Mugshots are being saved at: " .. path)
```
## 💡 How the Clone System Works
When `removeProps` or `removeMask` is set to `true`, the script cannot modify the actual player directly (as it would look glitchy). Instead, it:
1. Clones the ped.
2. Teleports the clone under the map (`Config.Clone.Offset`).
3. Strips the requested props/masks from the clone.
4. Takes the mugshot of the clone.
5. Deletes the clone instantly.