fx_version 'cerulean'
game 'gta5'

name        'ayc-mugshot'
description 'Professional Mugshot Capture System'
version     '1.0.0'
author      'Wrench'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/clone.lua',
    'client/core.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/css/style.css',
    'nui/js/libs/bodypix.min.js',
    'nui/js/libs/tf.min.js ',
    'nui/js/app.js',
    'nui/js/segmentation.js',
    'nui/js/upscaler.js',
    'nui/models/bodypix/**/*',
}
