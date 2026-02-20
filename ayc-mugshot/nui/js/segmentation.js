(function () {
    'use strict';

    let bodyPixNet    = null;
    let aiAvailable   = false;
    let aiLoading     = false;
    let aiLoadPromise = null;

    // ============================================================
    // AI MODEL LOADER
    // ============================================================

    async function loadAIModel(aiConfig) {
        if (aiAvailable && bodyPixNet) return true;
        if (aiLoading && aiLoadPromise) return aiLoadPromise;

        aiLoading = true;

        aiLoadPromise = new Promise(async (resolve) => {
            try {
                if (typeof tf === 'undefined') {
                    console.warn('TensorFlow.js not found');
                    aiLoading = false;
                    resolve(false);
                    return;
                }

                if (typeof bodyPix === 'undefined') {
                    console.warn('BodyPix not found');
                    aiLoading = false;
                    resolve(false);
                    return;
                }

                bodyPixNet = await bodyPix.load({
                    architecture: aiConfig.Architecture || 'MobileNetV1',
                    outputStride: aiConfig.OutputStride || 16,
                    multiplier:   aiConfig.Multiplier   || 0.75,
                    quantBytes:   2,
                    modelUrl:     aiConfig.ModelUrl || './models/bodypix/model-stride16.json'
                });

                aiAvailable = true;
                aiLoading   = false;
                resolve(true);

            } catch (err) {
                console.error('BodyPix load failed:', err);
                aiAvailable = false;
                aiLoading   = false;
                resolve(false);
            }
        });

        return aiLoadPromise;
    }

    // ============================================================
    // AI SEGMENTATION (BodyPix)
    // ============================================================

    async function aiRemoveBackground(canvas, aiConfig) {
        if (!aiAvailable || !bodyPixNet) return null;

        try {
            const ctx = canvas.getContext('2d');
            const w   = canvas.width;
            const h   = canvas.height;

            const segmentation = await bodyPixNet.segmentPerson(canvas, {
                flipHorizontal:        false,
                internalResolution:    aiConfig.InternalResolution || 'medium',
                segmentationThreshold: aiConfig.SegThreshold       || 0.4,
            });

            const map       = segmentation.data;
            const imageData = ctx.getImageData(0, 0, w, h);
            const imgData   = imageData.data;

            const newImg     = ctx.createImageData(w, h);
            const newImgData = newImg.data;

            let personCount = 0;

            for (let i = 0; i < map.length; i++) {
                const idx = i * 4;

                if (map[i]) {
                    newImgData[idx]     = imgData[idx];
                    newImgData[idx + 1] = imgData[idx + 1];
                    newImgData[idx + 2] = imgData[idx + 2];
                    newImgData[idx + 3] = imgData[idx + 3];
                    personCount++;
                } else {
                    newImgData[idx]     = 255;
                    newImgData[idx + 1] = 255;
                    newImgData[idx + 2] = 255;
                    newImgData[idx + 3] = 0;
                }
            }


            if (aiConfig.SmoothEdges) {
                smoothEdges(newImgData, w, h, aiConfig.SmoothRadius || 2);
            }

            return newImg;

        } catch (err) {
            console.error('AI processing error:', err);
            return null;
        }
    }

    // ============================================================
    // EDGE SMOOTHING
    // ============================================================

    function smoothEdges(imgData, w, h, radius) {
        const isEdge = new Uint8Array(w * h);

        for (let y = 1; y < h - 1; y++) {
            for (let x = 1; x < w - 1; x++) {
                const idx   = y * w + x;
                const alpha = imgData[idx * 4 + 3];

                if (alpha === 0) continue;

                const neighbors = [
                    imgData[((y - 1) * w + x) * 4 + 3],
                    imgData[((y + 1) * w + x) * 4 + 3],
                    imgData[(y * w + x - 1) * 4 + 3],
                    imgData[(y * w + x + 1) * 4 + 3],
                ];

                if (neighbors.some(n => n === 0)) {
                    isEdge[idx] = 1;
                }
            }
        }

        for (let y = 0; y < h; y++) {
            for (let x = 0; x < w; x++) {
                const idx = y * w + x;
                if (!isEdge[idx]) continue;

                let alphaSum = 0;
                let count    = 0;

                for (let ky = -radius; ky <= radius; ky++) {
                    for (let kx = -radius; kx <= radius; kx++) {
                        const nx = x + kx;
                        const ny = y + ky;
                        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;

                        alphaSum += imgData[(ny * w + nx) * 4 + 3];
                        count++;
                    }
                }

                imgData[idx * 4 + 3] = Math.round(alphaSum / count);
            }
        }
    }

    // ============================================================
    // COLOR-BASED BACKGROUND REMOVAL (Fallback)
    // ============================================================

    function detectBackgroundColor(imageData) {
        const { data, width, height } = imageData;
        const samples = [];

        const points = [
            [2, 2],
            [width - 3, 2],
            [Math.floor(width / 4), 2],
            [Math.floor(width / 2), 2],
            [Math.floor((width * 3) / 4), 2],
            [2, Math.floor(height / 4)],
            [width - 3, Math.floor(height / 4)],
        ];

        for (const [sx, sy] of points) {
            for (let dy = -2; dy <= 2; dy++) {
                for (let dx = -2; dx <= 2; dx++) {
                    const x   = Math.max(0, Math.min(width - 1, sx + dx));
                    const y   = Math.max(0, Math.min(height - 1, sy + dy));
                    const idx = (y * width + x) * 4;
                    samples.push({ r: data[idx], g: data[idx + 1], b: data[idx + 2] });
                }
            }
        }

        let tr = 0, tg = 0, tb = 0;
        for (const s of samples) { tr += s.r; tg += s.g; tb += s.b; }
        const c = samples.length;
        return { r: Math.round(tr / c), g: Math.round(tg / c), b: Math.round(tb / c) };
    }


    function colorDistance(r1, g1, b1, r2, g2, b2) {
        const dr = r1 - r2, dg = g1 - g2, db = b1 - b2;
        return Math.sqrt(dr * dr + dg * dg + db * db);
    }

    function colorRemoveBackground(imageData, config) {
        const { data, width, height } = imageData;

        let bg;
        if (config.TargetR !== undefined && config.TargetG !== undefined && config.TargetB !== undefined) {
            bg = { r: config.TargetR, g: config.TargetG, b: config.TargetB };
        } else {
            bg = detectBackgroundColor(imageData);
        }

        const tolerance = config.Tolerance || 45;

        const newImg     = new ImageData(width, height);
        const newImgData = newImg.data;

        const alphaMap = new Float32Array(width * height);

        for (let y = 0; y < height; y++) {
            for (let x = 0; x < width; x++) {
                const idx  = (y * width + x) * 4;
                const dist = colorDistance(
                    data[idx], data[idx + 1], data[idx + 2],
                    bg.r, bg.g, bg.b
                );

                if (dist < tolerance * 0.5) {
                    alphaMap[y * width + x] = 0.0;
                } else if (dist < tolerance) {
                    alphaMap[y * width + x] = (dist - tolerance * 0.5) / (tolerance * 0.5);
                } else {
                    alphaMap[y * width + x] = 1.0;
                }
            }
        }

        const isBackground = new Uint8Array(width * height);
        const visited      = new Uint8Array(width * height);
        const queue        = [];

        for (let x = 0; x < width; x++) {
            if (alphaMap[x] < 0.5) { queue.push(x); visited[x] = 1; }
            const bi = (height - 1) * width + x;
            if (alphaMap[bi] < 0.5) { queue.push(bi); visited[bi] = 1; }
        }

        for (let y = 1; y < height - 1; y++) {
            const li = y * width;
            if (alphaMap[li] < 0.5) { queue.push(li); visited[li] = 1; }
            const ri = y * width + (width - 1);
            if (alphaMap[ri] < 0.5) { queue.push(ri); visited[ri] = 1; }
        }

        let head = 0;
        while (head < queue.length) {
            const pos = queue[head++];
            isBackground[pos] = 1;
            const px = pos % width;
            const py = Math.floor(pos / width);

            const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
            for (const [ddx, ddy] of dirs) {
                const nx = px + ddx, ny = py + ddy;
                if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
                const ni = ny * width + nx;
                if (visited[ni] || alphaMap[ni] >= 0.8) continue;
                visited[ni] = 1;
                queue.push(ni);
            }
        }

        let bgCount = 0;
        for (let i = 0; i < width * height; i++) {
            const idx = i * 4;

            if (isBackground[i]) {
                newImgData[idx]     = 255;
                newImgData[idx + 1] = 255;
                newImgData[idx + 2] = 255;
                newImgData[idx + 3] = 0;
                bgCount++;
            } else {
                newImgData[idx]     = data[idx];
                newImgData[idx + 1] = data[idx + 1];
                newImgData[idx + 2] = data[idx + 2];
                newImgData[idx + 3] = 255; 
            }
        }

        if (config.SmoothEdges !== false) {
            smoothEdges(newImgData, width, height, config.SmoothRadius || 1);
        }

        const percent = ((bgCount / (width * height)) * 100).toFixed(1);

        return newImg;
    }

    // ============================================================
    // PUBLIC API
    // ============================================================

    window.Segmentation = {

        init: function (aiConfig) {
            if (!aiConfig || !aiConfig.Enabled) {
                return Promise.resolve(false);
            }
            return loadAIModel(aiConfig);
        },

        isAIAvailable: function () {
            return aiAvailable;
        },

        process: async function (canvas, config) {
            const aiConfig  = config.ai           || {};
            const colorConf = config.transparency || {};
            const ctx       = canvas.getContext('2d');

            let result = null;

            if (!aiConfig.Enabled) {
                const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
                result = colorRemoveBackground(imageData, colorConf);
                ctx.putImageData(result, 0, 0);
                return result;
            }

            if (aiAvailable) {
                result = await aiRemoveBackground(canvas, aiConfig);

                if (result) {
                    ctx.putImageData(result, 0, 0);
                    return result;
                }

                console.warn('AI segmentation failed');
            }

            if (aiConfig.FallbackOnFail !== false) {
                const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
                result = colorRemoveBackground(imageData, colorConf);
                ctx.putImageData(result, 0, 0);
                return result;
            }

            console.warn('No segmentation was performed');
            return null;
        },

        aiRemove: async function (canvas, aiConfig) {
            return aiRemoveBackground(canvas, aiConfig);
        },

        colorRemove: function (canvas, config) {
            const ctx       = canvas.getContext('2d');
            const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
            return colorRemoveBackground(imageData, config);
        },
    };

})();
