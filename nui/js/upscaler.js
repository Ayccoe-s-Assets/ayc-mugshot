(function () {
    'use strict';

    // ============================================================
    // HELPER: CLAMP
    // ============================================================
    function clamp(x, max) {
        return Math.max(0, Math.min(max, x));
    }

    // ============================================================
    // MITCHELL-NETRAVALI KERNEL (Excellent for "AI-like" smooth upscaling)
    // ============================================================
    // B = 1/3, C = 1/3 is the recommended setting for visual quality
    function mitchellKernel(x) {
        const B = 1/3;
        const C = 1/3;
        x = Math.abs(x);
        const x2 = x * x;
        const x3 = x * x * x;

        if (x < 1) {
            return ( (12 - 9 * B - 6 * C) * x3 + (-18 + 12 * B + 6 * C) * x2 + (6 - 2 * B) ) / 6;
        } else if (x < 2) {
            return ( (-B - 6 * C) * x3 + (6 * B + 30 * C) * x2 + (-12 * B - 48 * C) * x + (8 * B + 24 * C) ) / 6;
        }
        return 0;
    }

    function upscaleMitchell(src, factor) {
        const srcW = src.width;
        const srcH = src.height;
        const dstW = Math.floor(srcW * factor);
        const dstH = Math.floor(srcH * factor);
        
        const srcData = src.data;
        const dst     = new ImageData(dstW, dstH);
        const dstData = dst.data;

        for (let dstY = 0; dstY < dstH; dstY++) {
            const srcY  = (dstY + 0.5) / factor - 0.5;
            const srcY0 = Math.floor(srcY);

            for (let dstX = 0; dstX < dstW; dstX++) {
                const srcX  = (dstX + 0.5) / factor - 0.5;
                const srcX0 = Math.floor(srcX);

                let r = 0, g = 0, b = 0, alpha = 0;
                let weightSum = 0;

                for (let ky = -2; ky <= 2; ky++) {
                    const sy = Math.max(0, Math.min(srcH - 1, srcY0 + ky));
                    const wy = mitchellKernel(srcY - sy);

                    for (let kx = -2; kx <= 2; kx++) {
                        const sx = Math.max(0, Math.min(srcW - 1, srcX0 + kx));
                        const wx = mitchellKernel(srcX - sx);

                        const w = wx * wy;
                        const idx = (sy * srcW + sx) * 4;

                        r     += srcData[idx]     * w;
                        g     += srcData[idx + 1] * w;
                        b     += srcData[idx + 2] * w;
                        alpha += srcData[idx + 3] * w;
                        weightSum += w;
                    }
                }

                const dstIdx = (dstY * dstW + dstX) * 4;

                if (Math.abs(weightSum) > 0.0001) {
                    dstData[dstIdx]     = Math.max(0, Math.min(255, Math.round(r / weightSum)));
                    dstData[dstIdx + 1] = Math.max(0, Math.min(255, Math.round(g / weightSum)));
                    dstData[dstIdx + 2] = Math.max(0, Math.min(255, Math.round(b / weightSum)));
                    dstData[dstIdx + 3] = Math.max(0, Math.min(255, Math.round(alpha / weightSum)));
                }
            }
        }
        return dst;
    }

    // ============================================================
    // SMART LUMINANCE SHARPENING (AI-Like Detail Enhancement)
    // ============================================================
    function smartLuminanceSharpen(imageData, amount, threshold = 10) {
        if (!amount || amount <= 0) return imageData;

        const w = imageData.width;
        const h = imageData.height;
        const src = imageData.data;
        const dst = new ImageData(w, h);
        const out = dst.data;

        for (let y = 0; y < h; y++) {
            for (let x = 0; x < w; x++) {
                const idx = (y * w + x) * 4;

                const up    = (Math.max(0, y - 1) * w + x) * 4;
                const down  = (Math.min(h - 1, y + 1) * w + x) * 4;
                const left  = (y * w + Math.max(0, x - 1)) * 4;
                const right = (y * w + Math.min(w - 1, x + 1)) * 4;

                const lumCenter = 0.299*src[idx]   + 0.587*src[idx+1]   + 0.114*src[idx+2];
                const lumUp     = 0.299*src[up]    + 0.587*src[up+1]    + 0.114*src[up+2];
                const lumDown   = 0.299*src[down]  + 0.587*src[down+1]  + 0.114*src[down+2];
                const lumLeft   = 0.299*src[left]  + 0.587*src[left+1]  + 0.114*src[left+2];
                const lumRight  = 0.299*src[right] + 0.587*src[right+1] + 0.114*src[right+2];

                const lumAverage = (lumUp + lumDown + lumLeft + lumRight) / 4;
                const detail = lumCenter - lumAverage;

                if (Math.abs(detail) > threshold) {
                    const factor = 1 + (amount * detail / 255);
                    
                    out[idx]     = Math.max(0, Math.min(255, src[idx]     * factor));
                    out[idx + 1] = Math.max(0, Math.min(255, src[idx + 1] * factor));
                    out[idx + 2] = Math.max(0, Math.min(255, src[idx + 2] * factor));
                } else {
                    out[idx]     = src[idx];
                    out[idx + 1] = src[idx + 1];
                    out[idx + 2] = src[idx + 2];
                }
                
                out[idx + 3] = src[idx + 3]; // Alpha
            }
        }
        return dst;
    }

    // ============================================================
    // PUBLIC API
    // ============================================================
    window.Upscaler = {
        process: function (imageData, factor, config) {
            config = config || {};
            factor = Math.max(1, Math.floor(factor || 2));

            console.log('[Upscaler] Starting Smart Upscale | Factor: %dx', factor);

            if (factor === 1) return imageData;

            const startTime = performance.now();

            let result = upscaleMitchell(imageData, factor);

            const sharpenAmount = config.SharpenAmount || 1.2; 
            const noiseThreshold = config.NoiseThreshold || 12;

            console.log(`[Upscaler] Applying Smart Luminance Sharpening (Amount: ${sharpenAmount}, Threshold: ${noiseThreshold})`);
            result = smartLuminanceSharpen(result, sharpenAmount, noiseThreshold);

            const endTime = performance.now();
            console.log(`[Upscaler] Done in ${(endTime - startTime).toFixed(2)}ms. Size: ${imageData.width}x${imageData.height} -> ${result.width}x${result.height}`);

            return result;
        },
    };

})();
