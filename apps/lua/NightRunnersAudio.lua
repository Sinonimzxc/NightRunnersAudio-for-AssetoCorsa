local CFG = {
    bridgeURL = 'http://127.0.0.1:8765',

    -- Источник:
    -- yandex
    -- spotify
    -- chrome
    -- edge
    -- firefox
    -- wmp
    source = 'yandex',

    -- Музыка
    musicMin = 0.20,
    musicMax = 1.00,

    -- Двигатель
    engineMin = 0.20,
    engineMax = 1.00,

    -- Влияние газа и скорости
    gasWeight = 0.80,
    speedWeight = 0.20,

    -- Скорость, при которой эффект достигает максимума
    speedFull = 160,

    -- Плавность
    musicSmooth = 3.0,
    engineSmooth = 5.0,

    -- Частота отправки данных Bridge
    bridgeInterval = 0.10
}


------------------------------------------------
-- СОХРАНЕНИЕ НАСТРОЕК
------------------------------------------------

local storage = ac.storage({
    source = CFG.source,

    musicMin = CFG.musicMin,
    musicMax = CFG.musicMax,

    engineMin = CFG.engineMin,
    engineMax = CFG.engineMax,

    gasWeight = CFG.gasWeight,
    speedWeight = CFG.speedWeight,

    speedFull = CFG.speedFull,

    musicSmooth = CFG.musicSmooth,
    engineSmooth = CFG.engineSmooth
})


local function loadSettings()
    CFG.source =
        storage.source or CFG.source

    CFG.musicMin =
        storage.musicMin or CFG.musicMin

    CFG.musicMax =
        storage.musicMax or CFG.musicMax

    CFG.engineMin =
        storage.engineMin or CFG.engineMin

    CFG.engineMax =
        storage.engineMax or CFG.engineMax

    CFG.gasWeight =
        storage.gasWeight or CFG.gasWeight

    CFG.speedWeight =
        storage.speedWeight or CFG.speedWeight

    CFG.speedFull =
        storage.speedFull or CFG.speedFull

    CFG.musicSmooth =
        storage.musicSmooth or CFG.musicSmooth

    CFG.engineSmooth =
        storage.engineSmooth or CFG.engineSmooth
end


loadSettings()


------------------------------------------------
-- СОСТОЯНИЕ
------------------------------------------------

local car = ac.getCar(0)

local musicVolume = CFG.musicMin
local engineVolume = CFG.engineMax

local bridgeTimer = 0
local lastBridgeVolume = -1

local bridgeOK = false
local lastError = ''

local enabled = true


------------------------------------------------
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
------------------------------------------------

local function clamp(value, minValue, maxValue)
    return math.max(
        minValue,
        math.min(maxValue, value)
    )
end


local function lerp(a, b, t)
    return a + (b - a) * t
end


local function smooth(current, target, speed, dt)
    return lerp(
        current,
        target,
        clamp(dt * speed, 0, 1)
    )
end


local function saveSettings()
    storage.source = CFG.source

    storage.musicMin = CFG.musicMin
    storage.musicMax = CFG.musicMax

    storage.engineMin = CFG.engineMin
    storage.engineMax = CFG.engineMax

    storage.gasWeight = CFG.gasWeight
    storage.speedWeight = CFG.speedWeight

    storage.speedFull = CFG.speedFull

    storage.musicSmooth = CFG.musicSmooth
    storage.engineSmooth = CFG.engineSmooth
end


------------------------------------------------
-- ОТПРАВКА ГРОМКОСТИ В WINDOWS BRIDGE
------------------------------------------------

local function sendMusicVolume(volume)

    local url =
        CFG.bridgeURL ..
        '/volume?value=' ..
        string.format('%.3f', volume) ..
        '&source=' ..
        CFG.source

    web.get(url, function(err, response)

        if err then
            bridgeOK = false
            lastError = tostring(err)
        else
            bridgeOK = true
            lastError = ''
        end

    end)
end


------------------------------------------------
-- ОСНОВНОЙ UPDATE
------------------------------------------------

function script.update(dt)

    car = ac.getCar(0)

    if not car then
        return
    end


    if not enabled then

        musicVolume =
            smooth(
                musicVolume,
                CFG.musicMin,
                CFG.musicSmooth,
                dt
            )

        engineVolume =
            smooth(
                engineVolume,
                CFG.engineMax,
                CFG.engineSmooth,
                dt
            )

    else

        ------------------------------------------------
        -- ГАЗ
        ------------------------------------------------

        local gas =
            clamp(
                car.gas or 0,
                0,
                1
            )


        ------------------------------------------------
        -- СКОРОСТЬ
        ------------------------------------------------

        local speed =
            clamp(
                (car.speedKmh or 0) /
                math.max(CFG.speedFull, 1),
                0,
                1
            )


        ------------------------------------------------
        -- ОБЩАЯ ИНТЕНСИВНОСТЬ
        ------------------------------------------------

        local totalWeight =
            math.max(
                CFG.gasWeight +
                CFG.speedWeight,
                0.001
            )


        local intensity =
            (
                gas * CFG.gasWeight +
                speed * CFG.speedWeight
            ) / totalWeight


        intensity =
            clamp(
                intensity,
                0,
                1
            )


        -- Более выразительная кривая
        intensity =
            intensity ^ 0.82


        ------------------------------------------------
        -- ЦЕЛЕВАЯ ГРОМКОСТЬ МУЗЫКИ
        ------------------------------------------------

        local targetMusic =
            lerp(
                CFG.musicMin,
                CFG.musicMax,
                intensity
            )


        ------------------------------------------------
        -- ЦЕЛЕВАЯ ГРОМКОСТЬ ДВИГАТЕЛЯ
        ------------------------------------------------

        local targetEngine =
            lerp(
                CFG.engineMax,
                CFG.engineMin,
                intensity
            )


        ------------------------------------------------
        -- ПЛАВНОЕ ИЗМЕНЕНИЕ
        ------------------------------------------------

        musicVolume =
            smooth(
                musicVolume,
                targetMusic,
                CFG.musicSmooth,
                dt
            )


        engineVolume =
            smooth(
                engineVolume,
                targetEngine,
                CFG.engineSmooth,
                dt
            )
    end


    ------------------------------------------------
    -- ДВИГАТЕЛЬ
    ------------------------------------------------

    ac.setAudioVolume(
        'engine',
        engineVolume,
        0
    )


    ------------------------------------------------
    -- WINDOWS MUSIC
    ------------------------------------------------

    bridgeTimer =
        bridgeTimer - dt


    if bridgeTimer <= 0 then

        bridgeTimer =
            CFG.bridgeInterval


        if math.abs(
            musicVolume -
            lastBridgeVolume
        ) >= 0.008 then

            lastBridgeVolume =
                musicVolume

            sendMusicVolume(
                musicVolume
            )
        end
    end
end


------------------------------------------------
-- RESET
------------------------------------------------

function script.reset()

    musicVolume =
        CFG.musicMin

    engineVolume =
        CFG.engineMax

    lastBridgeVolume =
        -1

    bridgeTimer =
        0

    ac.setAudioVolume(
        'engine',
        CFG.engineMax,
        0
    )

    sendMusicVolume(
        CFG.musicMin
    )
end


------------------------------------------------
-- ВЫБОР ИСТОЧНИКА
------------------------------------------------

local sourceNames = {
    yandex = 'Yandex Music',
    spotify = 'Spotify',
    chrome = 'YouTube — Chrome',
    edge = 'YouTube — Edge',
    firefox = 'YouTube — Firefox',
    wmp = 'Windows Media Player / MP3'
}


local sourceOrder = {
    'yandex',
    'spotify',
    'chrome',
    'edge',
    'firefox',
    'wmp'
}


------------------------------------------------
-- ГЛАВНОЕ ОКНО
------------------------------------------------

function script.windowMain()

    ui.header('Night Runners Audio')

    ------------------------------------------------
    -- ENABLE
    ------------------------------------------------

    if ui.checkbox(
        'Enable',
        enabled
    ) then

        enabled =
            not enabled
    end


    ui.separator()


    ------------------------------------------------
    -- MUSIC SOURCE
    ------------------------------------------------

    ui.text('Music source:')

    ui.setNextItemWidth(
        ui.availableSpaceX()
    )

    ui.combo(
        '##musicSource',
        sourceNames[CFG.source] or 'Unknown',
        function()

            for _, source in ipairs(sourceOrder) do

                if ui.selectable(
                    sourceNames[source],
                    CFG.source == source
                ) then

                    CFG.source =
                        source

                    saveSettings()

                    -- Сразу сообщаем Bridge
                    sendMusicVolume(
                        musicVolume
                    )
                end
            end
        end
    )


    ui.separator()


    ------------------------------------------------
    -- MUSIC
    ------------------------------------------------

    ui.header('Music')

    CFG.musicMin =
        ui.slider(
            '##musicMin',
            CFG.musicMin * 100,
            0,
            100,
            'Minimum: %.0f%%'
        ) / 100


    CFG.musicMax =
        ui.slider(
            '##musicMax',
            CFG.musicMax * 100,
            0,
            100,
            'Maximum: %.0f%%'
        ) / 100


    -- Не позволяем minimum стать выше maximum
    if CFG.musicMin > CFG.musicMax then
        CFG.musicMin =
            CFG.musicMax
    end


    ------------------------------------------------
    -- ENGINE
    ------------------------------------------------

    ui.header('Engine')

    CFG.engineMin =
        ui.slider(
            '##engineMin',
            CFG.engineMin * 100,
            0,
            100,
            'Minimum: %.0f%%'
        ) / 100


    CFG.engineMax =
        ui.slider(
            '##engineMax',
            CFG.engineMax * 100,
            0,
            100,
            'Maximum: %.0f%%'
        ) / 100


    if CFG.engineMin > CFG.engineMax then
        CFG.engineMin =
            CFG.engineMax
    end


    ------------------------------------------------
    -- INPUT MIX
    ------------------------------------------------

    ui.header('Effect')

    CFG.gasWeight =
        ui.slider(
            '##gasWeight',
            CFG.gasWeight * 100,
            0,
            100,
            'Gas influence: %.0f%%'
        ) / 100


    CFG.speedWeight =
        ui.slider(
            '##speedWeight',
            CFG.speedWeight * 100,
            0,
            100,
            'Speed influence: %.0f%%'
        ) / 100


    CFG.speedFull =
        ui.slider(
            '##speedFull',
            CFG.speedFull,
            20,
            400,
            'Maximum effect speed: %.0f km/h'
        )


    ------------------------------------------------
    -- SMOOTHING
    ------------------------------------------------

    ui.header('Smoothness')

    CFG.musicSmooth =
        ui.slider(
            '##musicSmooth',
            CFG.musicSmooth,
            0.5,
            10,
            'Music: %.1f',
            2
        )


    CFG.engineSmooth =
        ui.slider(
            '##engineSmooth',
            CFG.engineSmooth,
            0.5,
            10,
            'Engine: %.1f',
            2
        )


    ------------------------------------------------
    -- SAVE
    ------------------------------------------------

    if ui.button('Save settings') then
        saveSettings()
    end


    ui.separator()


    ------------------------------------------------
    -- STATUS
    ------------------------------------------------

    ui.text(
        string.format(
            'Gas: %3.0f%%',
            (car.gas or 0) * 100
        )
    )

    ui.text(
        string.format(
            'Speed: %3.0f km/h',
            car.speedKmh or 0
        )
    )

    ui.text(
        string.format(
            'Music: %3.0f%%',
            musicVolume * 100
        )
    )

    ui.text(
        string.format(
            'Engine: %3.0f%%',
            engineVolume * 100
        )
    )


    if bridgeOK then
        ui.text('Bridge: CONNECTED')
    else
        ui.text('Bridge: NOT CONNECTED')

        if lastError ~= '' then
            ui.textWrapped(lastError)
        end
    end
end


------------------------------------------------
-- SETTINGS WINDOW
------------------------------------------------

function script.windowSettings()

    ui.header('Night Runners Audio')

    ui.text('External Windows music control')
    ui.separator()

    ui.text('Music minimum:')
    ui.text(
        string.format(
            '%.0f%%',
            CFG.musicMin * 100
        )
    )

    ui.text('Music maximum:')
    ui.text(
        string.format(
            '%.0f%%',
            CFG.musicMax * 100
        )
    )

    ui.text('Engine minimum:')
    ui.text(
        string.format(
            '%.0f%%',
            CFG.engineMin * 100
        )
    )

    ui.text('Engine maximum:')
    ui.text(
        string.format(
            '%.0f%%',
            CFG.engineMax * 100
        )
    )
end