(function () {
    'use strict';

    // ============================================================
    // CANVAS REFERENCES
    // ============================================================

    const captureCanvas = document.getElementById('captureCanvas');
    const captureCtx    = captureCanvas.getContext('2d', { willReadFrequently: true });

    const processCanvas = document.getElementById('processCanvas');
    const processCtx    = processCanvas.getContext('2d', { willReadFrequently: true });

    const upscaleCanvas = document.getElementById('upscaleCanvas');
    const upscaleCtx    = upscaleCanvas.getContext('2d', { willReadFrequently: true });

    let initialized = false;

    // ============================================================
    // MESSAGE HANDLER
    // ============================================================

    window.addEventListener('message', function (event) {
        const msg = event.data;

        // ======================================
        // INIT: Load AI model on startup
        // ======================================
        if (msg.action === 'init') {
            if (!initialized) {
                initialized = true;

                // Attempt to load AI model if Segmentation module is available
                if (window.Segmentation && msg.aiConfig) {
                    window.Segmentation.init(msg.aiConfig);
                }
            }
            return;
        }

        // ======================================
        // CAPTURE: Process a mugshot
        // ======================================
        if (msg.action !== 'capture') return;

        const { id, txd, transparent, upscale, upscaleFactor, config } = msg;

        if (!txd) {
            sendResult(id, null, 'No TXD texture name provided');
            return;
        }

        captureMugshot(id, txd, transparent, upscale, upscaleFactor, config);
    });

    // ============================================================
    // CAPTURE PIPELINE
    // ============================================================

    /**
     * Main capture and processing pipeline
     * @param {number}  id            - Callback ID
     * @param {string}  txd           - TXD texture name
     * @param {boolean} transparent   - Whether to remove background
     * @param {boolean} doUpscale     - Whether to upscale
     * @param {number}  upscaleFactor - 2 or 4
     * @param {object}  config        - { transparency, ai, upscaleConf }
     */
    function captureMugshot(id, txd, transparent, doUpscale, upscaleFactor, config) {
        config = config || {};

        // Build image URL from TXD
        const url = 'https://nui-img/' + txd + '/' + txd + '?t=' + Date.now();

        const img = new Image();
        img.crossOrigin = 'anonymous';

        img.onload = function () {
            processImage(id, img, transparent, doUpscale, upscaleFactor, config);
        };

        img.onerror = function () {
            // Retry once after 500ms
            setTimeout(function () {
                const retryImg = new Image();
                retryImg.crossOrigin = 'anonymous';

                retryImg.onload = function () {
                    processImage(id, retryImg, transparent, doUpscale, upscaleFactor, config);
                };

                retryImg.onerror = function () {
                    sendResult(id, null, 'Failed to load headshot texture after retry');
                };

                retryImg.src = url + '&retry=1';
            }, 500);
        };

        img.src = url;
    }

    /**
     * Process loaded image through the pipeline
     * @param {number}       id
     * @param {HTMLImageElement} img
     * @param {boolean}      transparent
     * @param {boolean}      doUpscale
     * @param {number}       upscaleFactor
     * @param {object}       config
     */
    async function processImage(id, img, transparent, doUpscale, upscaleFactor, config) {
        try {
            // ======================================
            // Step 1: Draw source image to capture canvas
            // ======================================
            const w = img.naturalWidth  || img.width  || 128;
            const h = img.naturalHeight || img.height || 128;

            captureCanvas.width  = w;
            captureCanvas.height = h;
            captureCtx.clearRect(0, 0, w, h);
            captureCtx.drawImage(img, 0, 0, w, h);

            let currentImageData = captureCtx.getImageData(0, 0, w, h);

            // ======================================
            // Step 2: Background removal (if transparent)
            // ======================================
            if (transparent) {
                // Set up process canvas with same dimensions
                processCanvas.width  = w;
                processCanvas.height = h;
                processCtx.clearRect(0, 0, w, h);
                processCtx.putImageData(currentImageData, 0, 0);

                if (window.Segmentation) {
                    // Use Segmentation module (AI with fallback)
                    currentImageData = await window.Segmentation.process(processCanvas, {
                        ai:           config.ai || {},
                        transparency: config.transparency || {},
                    });
                } else {
                    // Segmentation module not loaded - skip transparency
                    console.warn('Segmentation module not available');
                }
            }

            // ======================================
            // Step 3: Upscale (if enabled)
            // ======================================
            if (doUpscale && window.Upscaler) {
                const factor = (upscaleFactor === 4) ? 4 : 2;
                currentImageData = window.Upscaler.process(currentImageData, factor, config.upscaleConf);
            }

            // ======================================
            // Step 4: Render to output canvas and export
            // ======================================
            const outputCanvas = doUpscale ? upscaleCanvas : processCanvas;
            const outputCtx    = doUpscale ? upscaleCtx : processCtx;

            outputCanvas.width  = currentImageData.width;
            outputCanvas.height = currentImageData.height;
            outputCtx.clearRect(0, 0, outputCanvas.width, outputCanvas.height);
            outputCtx.putImageData(currentImageData, 0, 0);

            const base64 = outputCanvas.toDataURL('image/png');
            sendResult(id, base64, null);

        } catch (err) {
            console.error('Processing error:', err);
            sendResult(id, null, 'Processing error: ' + err.message);
        }
    }

    // ============================================================
    // SEND RESULT TO LUA
    // ============================================================

    /**
     * Send processed result back to Lua client via NUI callback
     * @param {number}      id
     * @param {string|null} base64
     * @param {string|null} error
     */
    function sendResult(id, base64, error) {
        fetch('https://' + GetParentResourceName() + '/captureResult', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({
                id:     id,
                base64: base64 || null,
                error:  error  || null,
            }),
        }).catch(function (err) {
            console.error('Failed to send result to Lua:', err);
        });
    }

})();
