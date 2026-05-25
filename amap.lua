-- amap.lua
-- Проверка маппинга и названий объектов | Родина РП | Moonloader
-- Версия 1.0
-- Кодировка файла: Windows-1251

local script_version = "1.2"

-- ============================================================
-- АВТООБНОВЛЕНИЕ
-- Замените на свои данные после публикации на GitHub:
-- GITHUB_USER  = ваш логин GitHub
-- GITHUB_REPO  = название репозитория
-- GITHUB_BRANCH = ветка (обычно "main" или "master")
-- ============================================================
local GITHUB_USER   = "AndreySivokozov"
local GITHUB_REPO   = "ProverkaMappinga"
local GITHUB_BRANCH = "main"
local RAW_BASE      = string.format("https://raw.githubusercontent.com/%s/%s/%s",
                        GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH)
local VERSION_URL   = RAW_BASE .. "/version.txt"
local SCRIPT_URL    = RAW_BASE .. "/amap.luac"
local SCRIPT_PATH   = getWorkingDirectory() .. "\\amap.luac"

require 'moonloader'
local imgui  = require 'mimgui'
local ffi    = require 'ffi'
local samp   = require 'sampfuncs'
local sampev = require 'samp.events'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

-- Хелпер: CP1251 строка ? UTF-8 для ImGui
local function e(s) return encoding.UTF8:encode(s) end

local fa = require 'fAwesome6_solid'

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    imgui.GetIO().MouseDrawCursor = false
    -- Запрещаем ImGui менять системный курсор
    imgui.GetIO().ConfigFlags = imgui.GetIO().ConfigFlags + 32  -- NoMouseCursorChange = 1<<5
    fa.Init(14)
end)

-- ============================================================
-- ЦВЕТОВАЯ ПАЛИТРА
-- ============================================================
local clr = {
    bg          = imgui.ImVec4(0.07, 0.08, 0.10, 0.97),
    bg_child    = imgui.ImVec4(0.10, 0.11, 0.14, 1.00),
    bg_input    = imgui.ImVec4(0.06, 0.07, 0.09, 1.00),
    accent      = imgui.ImVec4(0.29, 0.56, 1.00, 1.00),
    accent_hov  = imgui.ImVec4(0.40, 0.65, 1.00, 1.00),
    accent_act  = imgui.ImVec4(0.20, 0.45, 0.90, 1.00),
    green       = imgui.ImVec4(0.22, 0.78, 0.52, 1.00),
    green_hov   = imgui.ImVec4(0.28, 0.88, 0.60, 1.00),
    green_act   = imgui.ImVec4(0.16, 0.65, 0.42, 1.00),
    danger      = imgui.ImVec4(0.90, 0.28, 0.28, 1.00),
    danger_hov  = imgui.ImVec4(1.00, 0.38, 0.38, 1.00),
    danger_act  = imgui.ImVec4(0.75, 0.20, 0.20, 1.00),
    warn        = imgui.ImVec4(0.95, 0.70, 0.20, 1.00),
    warn_hov    = imgui.ImVec4(1.00, 0.80, 0.30, 1.00),
    warn_act    = imgui.ImVec4(0.80, 0.58, 0.12, 1.00),
    text        = imgui.ImVec4(0.88, 0.90, 0.95, 1.00),
    text_dim    = imgui.ImVec4(0.50, 0.54, 0.62, 1.00),
    separator   = imgui.ImVec4(0.18, 0.20, 0.26, 1.00),
    header      = imgui.ImVec4(0.13, 0.15, 0.20, 1.00),
}

local function toU32(v, a)
    local alpha = a or v.w
    return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(v.x, v.y, v.z, alpha))
end

-- ============================================================
-- БАЗЫ ID
-- ============================================================
local BIZ_IDS = {}
for i = 1, 280 do BIZ_IDS[#BIZ_IDS + 1] = i end

local TRAILER_IDS = {}
for i = 1, 371 do TRAILER_IDS[#TRAILER_IDS + 1] = i end

local HOUSE_IDS = {}
local function addRange(t, from, to)
    for i = from, to do t[#t + 1] = i end
end
addRange(HOUSE_IDS, 469,  569)
addRange(HOUSE_IDS, 785,  785)
addRange(HOUSE_IDS, 1001, 1012)
addRange(HOUSE_IDS, 1809, 1930)
HOUSE_IDS[#HOUSE_IDS + 1] = 2664
HOUSE_IDS[#HOUSE_IDS + 1] = 2670
addRange(HOUSE_IDS, 2674, 2868)
addRange(HOUSE_IDS, 2850, 2872)
do
    local seen, clean = {}, {}
    for _, v in ipairs(HOUSE_IDS) do
        if not seen[v] then seen[v] = true; clean[#clean + 1] = v end
    end
    table.sort(clean)
    HOUSE_IDS = clean
end

-- ============================================================
-- СОСТОЯНИЕ
-- ============================================================
local CAT_HOUSE   = 1
local CAT_BIZ     = 2
local CAT_TRAILER = 3

local state = {
    main_open    = false,
    panel_open   = false,
    notify_open  = false,
    main_alpha   = 0.0,
    panel_alpha  = 0.0,
    notify_alpha = 0.0,

    category     = CAT_HOUSE,
    ids          = HOUSE_IDS,
    idx          = 1,
    owner        = "-",
    waiting_info = false,
    info_time    = 0,
    info_timeout = 6.0,
    notify_type  = 1,

    -- Ошибка в главном меню (показывается на экране)
    error_msg    = "",
    error_time   = 0,
    error_dur    = 3.0,  -- секунд показа
}

local start_id_buf   = imgui.new.char[16]()
local mapping_buf    = imgui.new.char[512]()  -- UTF-8 буфер для ввода маппинга
local manual_nick_buf = imgui.new.char[64]()  -- буфер для ручного ввода ника (трейлер)
local prev_dt        = os.clock()

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================
-- Сырые строки (CP1251) для использования в string.format внутри e()
local function catName(cat)
    if cat == CAT_HOUSE   then return "дома" end
    if cat == CAT_BIZ     then return "бизнеса" end
    if cat == CAT_TRAILER then return "трейлера" end
    return "объекта"
end

local function catNameTitle(cat)
    if cat == CAT_HOUSE   then return "Дом" end
    if cat == CAT_BIZ     then return "Бизнес" end
    if cat == CAT_TRAILER then return "Трейлер" end
    return "Объект"
end

local function gotoCmd(cat, id)
    if cat == CAT_HOUSE   then return "/gotohouse " .. id end
    if cat == CAT_BIZ     then return "/gotobiz "   .. id end
    if cat == CAT_TRAILER then return "/gototr "    .. id end
end

local function infoCmd(cat, id)
    if cat == CAT_HOUSE then return "/ahouseinfo " .. id end
    if cat == CAT_BIZ   then return "/abizinfo "   .. id end
    return nil
end

local function currentId()
    return state.ids[state.idx]
end

local function findIdxByValue(ids, val)
    for i, v in ipairs(ids) do
        if v == val then return i end
    end
    return nil
end

local function clampIdx()
    if state.idx < 1 then state.idx = 1 end
    if state.idx > #state.ids then state.idx = #state.ids end
end

local function animAlpha(cur, target, dt, speed)
    speed = speed or 8.0
    if cur < target then return math.min(target, cur + dt * speed)
    else return math.max(target, cur - dt * speed) end
end

-- ============================================================
-- ТЕМА (без PushStyleVar Alpha — используем SetNextWindowBgAlpha)
-- ============================================================
local function pushTheme()
    imgui.PushStyleColor(imgui.Col.WindowBg,             clr.bg)
    imgui.PushStyleColor(imgui.Col.ChildBg,              clr.bg_child)
    imgui.PushStyleColor(imgui.Col.FrameBg,              clr.bg_input)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered,       imgui.ImVec4(0.12, 0.14, 0.18, 1.00))
    imgui.PushStyleColor(imgui.Col.FrameBgActive,        imgui.ImVec4(0.10, 0.12, 0.16, 1.00))
    imgui.PushStyleColor(imgui.Col.Button,               clr.accent)
    imgui.PushStyleColor(imgui.Col.ButtonHovered,        clr.accent_hov)
    imgui.PushStyleColor(imgui.Col.ButtonActive,         clr.accent_act)
    imgui.PushStyleColor(imgui.Col.Header,               clr.header)
    imgui.PushStyleColor(imgui.Col.HeaderHovered,        imgui.ImVec4(0.20, 0.22, 0.30, 1.00))
    imgui.PushStyleColor(imgui.Col.HeaderActive,         imgui.ImVec4(0.16, 0.18, 0.25, 1.00))
    imgui.PushStyleColor(imgui.Col.Text,                 clr.text)
    imgui.PushStyleColor(imgui.Col.TextDisabled,         clr.text_dim)
    imgui.PushStyleColor(imgui.Col.ScrollbarBg,          clr.bg)
    imgui.PushStyleColor(imgui.Col.ScrollbarGrab,        imgui.ImVec4(0.22, 0.25, 0.32, 1.00))
    imgui.PushStyleColor(imgui.Col.ScrollbarGrabHovered, imgui.ImVec4(0.30, 0.34, 0.44, 1.00))
    imgui.PushStyleColor(imgui.Col.ScrollbarGrabActive,  clr.accent)
    imgui.PushStyleColor(imgui.Col.Separator,            clr.separator)
    imgui.PushStyleColor(imgui.Col.TitleBg,              clr.bg)
    imgui.PushStyleColor(imgui.Col.TitleBgActive,        clr.bg)
    imgui.PushStyleColor(imgui.Col.TitleBgCollapsed,     clr.bg)
    imgui.PushStyleColor(imgui.Col.PopupBg,              clr.bg_child)
    imgui.PushStyleColor(imgui.Col.Border,               clr.separator)
    -- 23 цвета
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,    10.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding,      8.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,      6.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.GrabRounding,       6.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.PopupRounding,      8.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarRounding,  6.0)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,       imgui.ImVec2(16, 14))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,        imgui.ImVec2(10, 7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,         imgui.ImVec2(10, 8))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize,   1.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildBorderSize,    1.0)
    -- 11 варов
end

local function popTheme()
    imgui.PopStyleColor(23)
    imgui.PopStyleVar(11)
end

local function colorButton(label, w, h, bg, hov, act)
    imgui.PushStyleColor(imgui.Col.Button,        bg)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, hov)
    imgui.PushStyleColor(imgui.Col.ButtonActive,  act)
    local clicked = imgui.Button(label, imgui.ImVec2(w, h))
    imgui.PopStyleColor(3)
    return clicked
end

local function accentLine(dl, wpos, wsize)
    dl:AddRectFilledMultiColor(
        imgui.ImVec2(wpos.x + 1,           wpos.y + 36),
        imgui.ImVec2(wpos.x + wsize.x - 1, wpos.y + 38),
        toU32(clr.accent, 0.0), toU32(clr.accent, 0.9),
        toU32(clr.accent, 0.9), toU32(clr.accent, 0.0))
end

local function sectionLabel(icon, text)
    imgui.PushStyleColor(imgui.Col.Text, clr.accent)
    imgui.Text(icon)
    imgui.PopStyleColor()
    imgui.SameLine(0, 6)
    imgui.PushStyleColor(imgui.Col.Text, clr.text_dim)
    imgui.Text(text)
    imgui.PopStyleColor()
end

-- Кнопка-переключатель категории/типа
local function toggleBtn(label, active, w, h, bg, hov, act)
    local b  = active and bg  or clr.header
    local bh = active and hov or imgui.ImVec4(0.20, 0.22, 0.30, 1.0)
    local ba = active and act or imgui.ImVec4(0.16, 0.18, 0.25, 1.0)
    return colorButton(label, w, h, b, bh, ba)
end

-- Неактивная (серая) кнопка
local function disabledButton(label, w, h)
    local grey = imgui.ImVec4(0.15, 0.17, 0.22, 1.0)
    imgui.PushStyleColor(imgui.Col.Button,        grey)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, grey)
    imgui.PushStyleColor(imgui.Col.ButtonActive,  grey)
    imgui.Button(label, imgui.ImVec2(w, h))
    imgui.PopStyleColor(3)
end

-- ============================================================
-- ЛОГИКА НАВИГАЦИИ
-- ============================================================
local function requestInfo()
    local id  = currentId()
    local cat = state.category
    if cat == CAT_TRAILER then
        -- Для трейлеров ник вводится вручную в окне уведомления
        state.owner        = "Вручную"
        state.waiting_info = false
    else
        local cmd = infoCmd(cat, id)
        if cmd then
            sampSendChat(cmd)
            state.owner        = "Загрузка..."
            state.waiting_info = true
            state.info_time    = os.clock()
        end
    end
end

local function gotoObject(idx)
    state.idx = idx
    clampIdx()
    sampSendChat(gotoCmd(state.category, currentId()))
    state.owner = "Загрузка..."
    lua_thread.create(function()
        wait(1200)
        requestInfo()
    end)
end

local function goNext()
    if state.idx < #state.ids then gotoObject(state.idx + 1) end
end

local function goPrev()
    if state.idx > 1 then gotoObject(state.idx - 1) end
end

-- ============================================================
-- УВЕДОМЛЕНИЕ
-- ============================================================
local MAX_LINE = 92  -- максимум символов в одной строке /notify

-- Разбивает CP1251 строку на части не длиннее MAX_LINE символов (по словам)
-- Уважает уже существующие переносы \n
local function splitLines(text)
    local lines = {}
    -- Сначала разбиваем по явным \n
    for segment in (text .. "\n"):gmatch("([^\n]*)\n") do
        if segment == "" then
            -- пустой сегмент пропускаем
        else
            -- внутри сегмента режем по словам
            local current = ""
            for word in segment:gmatch("%S+") do
                local sep = current == "" and "" or " "
                if #current + #sep + #word <= MAX_LINE then
                    current = current .. sep .. word
                else
                    if current ~= "" then table.insert(lines, current) end
                    current = word
                end
            end
            if current ~= "" then table.insert(lines, current) end
        end
    end
    if #lines == 0 then lines = {""} end
    return lines
end

-- Возвращает CP1251 строку (для отправки и превью)
local function buildNotifyCP()
    local cat   = state.category
    local id    = currentId()
    local obj   = catName(cat)       -- строчный: "дома", "бизнеса", "трейлера"
    local objT  = catNameTitle(cat)  -- с заглавной: "Дом", "Бизнес", "Трейлер"
    if state.notify_type == 1 then
        return string.format(
            "Ув. игрок, название вашего %s №%d нарушает правила проекта. Название будет удалено, а так же вы будете наказаны в соотвествии с правилами.",
            obj, id)
    else
        local what = ffi.string(mapping_buf):gsub("%s*$", "")
        if what == "" then what = "нарушение" end
        -- mapping_buf содержит UTF-8 (ImGui так пишет) — декодируем в CP1251
        what = encoding.UTF8:decode(what)
        if what == "" then what = "нарушение" end
        -- 3 отдельных сообщения через \n — каждое станет отдельным /notify
        return string.format(
            "Ув. игрок, около вашего %s №%d установлен маппинг с нарушением правил проекта.\nА именно установлено: %s. Вам следует его убрать.\nВам дается ровно 72 часа на это, иначе маппинг будет удален без возможности его возврата.",
            obj, id, what)
    end
end

-- Возвращает UTF-8 строку для ImGui превью (с переносами строк)
local function buildNotifyText()
    local cp = buildNotifyCP()
    local lines = splitLines(cp)
    return e(table.concat(lines, "\n"))
end

local function sendNotify(nick, _unused)
    local cp    = buildNotifyCP()
    local lines = splitLines(cp)
    -- Отправляем каждую часть с небольшой задержкой между ними
    lua_thread.create(function()
        for i, line in ipairs(lines) do
            sampSendChat("/notify " .. nick .. " " .. line)
            if i < #lines then wait(600) end
        end
        sampAddChatMessage("{4AFF88}[AMap] Отправлено " .. #lines .. " сообщ. игроку: " .. nick, -1)
    end)
end

-- ============================================================
-- РЕНДЕР
-- ============================================================
local amapFrame  -- объявляем заранее, чтобы замыкание внутри OnFrame могло её видеть
amapFrame = imgui.OnFrame(
    function()
        return state.main_open or state.panel_open or state.notify_open
            or state.main_alpha > 0.01 or state.panel_alpha > 0.01 or state.notify_alpha > 0.01
    end,
    function()
        local now = os.clock()
        local dt  = math.min(now - prev_dt, 0.1)
        prev_dt   = now

        state.main_alpha   = animAlpha(state.main_alpha,   state.main_open   and 1.0 or 0.0, dt)
        state.panel_alpha  = animAlpha(state.panel_alpha,  state.panel_open  and 1.0 or 0.0, dt)
        state.notify_alpha = animAlpha(state.notify_alpha, state.notify_open and 1.0 or 0.0, dt)

        -- Курсор: только при главном меню или окне уведомления
        -- При боковой панели (проверка) — курсор не нужен
        amapFrame.HideCursor = not (state.main_open or state.notify_open)

        -- ESC закрывает только главное меню
        if isKeyJustPressed(0x1B) then  -- VK_ESCAPE
            state.main_open = false
        end

        local display = imgui.GetIO().DisplaySize

        -- --------------------------------------------------------
        -- ГЛАВНОЕ МЕНЮ
        -- --------------------------------------------------------
        if state.main_alpha > 0.01 then
            pushTheme()
            local mw = 440
            local mh = (state.error_msg ~= "" and (os.clock() - state.error_time) < state.error_dur) and 370 or 320
            imgui.SetNextWindowSize(imgui.ImVec2(mw, mh), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2((display.x-mw)/2, (display.y-mh)/2), imgui.Cond.Always)
            imgui.SetNextWindowBgAlpha(clr.bg.w * state.main_alpha)

            local wf = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
            if imgui.Begin(fa.MAP .. e("  AMap — Проверка объектов  v") .. script_version, nil, wf) then
                local dl, wpos, wsize = imgui.GetWindowDrawList(), imgui.GetWindowPos(), imgui.GetWindowSize()
                accentLine(dl, wpos, wsize)
                imgui.Spacing()

                sectionLabel(fa.LAYER_GROUP, e("Категория объекта"))
                imgui.Spacing()

                local bw3 = (imgui.GetContentRegionAvail().x - 20) / 3
                if toggleBtn(fa.HOUSE .. e("  Дома"),     state.category == CAT_HOUSE,   bw3, 38, clr.accent, clr.accent_hov, clr.accent_act) then
                    state.category = CAT_HOUSE; state.ids = HOUSE_IDS; state.idx = 1
                end
                imgui.SameLine()
                if toggleBtn(fa.STORE .. e("  Бизнесы"),  state.category == CAT_BIZ,     bw3, 38, clr.green,  clr.green_hov,  clr.green_act) then
                    state.category = CAT_BIZ; state.ids = BIZ_IDS; state.idx = 1
                end
                imgui.SameLine()
                if toggleBtn(fa.CARAVAN .. e("  Трейлеры"), state.category == CAT_TRAILER, bw3, 38, clr.warn, clr.warn_hov, clr.warn_act) then
                    state.category = CAT_TRAILER; state.ids = TRAILER_IDS; state.idx = 1
                end

                imgui.Spacing(); imgui.Separator(); imgui.Spacing()

                sectionLabel(fa.SLIDERS, e("Начальный ID"))
                imgui.SetNextItemWidth(-1)
                imgui.InputText("##startid", start_id_buf, ffi.sizeof(start_id_buf))
                imgui.Spacing()

                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.13, 0.17, 0.26, 0.55))
                if imgui.BeginChild("##info_hint", imgui.ImVec2(-1, 34), false) then
                    imgui.SetCursorPosY(imgui.GetCursorPosY() + 7)
                    imgui.PushStyleColor(imgui.Col.Text, clr.accent)
                    imgui.Text("  " .. fa.CIRCLE_INFO)
                    imgui.PopStyleColor()
                    imgui.SameLine(0, 6)
                    imgui.PushStyleColor(imgui.Col.Text, clr.text_dim)
                    imgui.Text(e(string.format("Объектов в базе: %d", #state.ids)))
                    imgui.PopStyleColor()
                    imgui.EndChild()
                end
                imgui.PopStyleColor()
                imgui.Spacing()

                if colorButton(fa.CIRCLE_PLAY .. e("  Начать проверку"), -1, 40, clr.accent, clr.accent_hov, clr.accent_act) then
                    local startVal = tonumber(ffi.string(start_id_buf))
                    if startVal then
                        local exact = findIdxByValue(state.ids, startVal)
                        if exact then
                            -- Точное совпадение — запускаем
                            state.idx        = exact
                            state.main_open  = false
                            state.panel_open = true
                            state.owner      = "Загрузка..."
                            state.error_msg  = ""
                            sampSendChat(gotoCmd(state.category, currentId()))
                            lua_thread.create(function() wait(1200); requestInfo() end)
                        else
                            -- ID не существует — показываем ошибку на экране
                            state.error_msg  = string.format(
                                "ID %d не существует для %s. Допустимые: %d — %d",
                                startVal, catName(state.category),
                                state.ids[1], state.ids[#state.ids])
                            state.error_time = os.clock()
                        end
                    else
                        -- Поле пустое — стартуем с первого
                        state.idx        = 1
                        state.main_open  = false
                        state.panel_open = true
                        state.owner      = "Загрузка..."
                        state.error_msg  = ""
                        sampSendChat(gotoCmd(state.category, currentId()))
                        lua_thread.create(function() wait(1200); requestInfo() end)
                    end
                end

                -- Плашка ошибки
                if state.error_msg ~= "" and (os.clock() - state.error_time) < state.error_dur then
                    imgui.Spacing()
                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.55, 0.10, 0.10, 0.85))
                    if imgui.BeginChild("##err_box", imgui.ImVec2(-1, 38), false) then
                        imgui.SetCursorPosY(imgui.GetCursorPosY() + 8)
                        imgui.SetCursorPosX(imgui.GetCursorPosX() + 8)
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.85, 0.85, 1.0))
                        imgui.Text(fa.CIRCLE_EXCLAMATION .. "  " .. e(state.error_msg))
                        imgui.PopStyleColor()
                        imgui.EndChild()
                    end
                    imgui.PopStyleColor()
                elseif state.error_msg ~= "" then
                    state.error_msg = ""
                end
                imgui.End()
            end
            popTheme()
        end

        -- --------------------------------------------------------
        -- БОКОВАЯ ПАНЕЛЬ
        -- --------------------------------------------------------
        if state.panel_alpha > 0.01 then
            pushTheme()
            local pw, ph = 265, 360
            imgui.SetNextWindowSize(imgui.ImVec2(pw, ph), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2(display.x - pw - 16, (display.y - ph) / 2), imgui.Cond.Always)
            imgui.SetNextWindowBgAlpha(clr.bg.w * state.panel_alpha)

            local pf = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize
                     + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoMove
            if imgui.Begin(fa.CIRCLE_INFO .. e("  Объект"), nil, pf) then
                local dl, wpos, wsize = imgui.GetWindowDrawList(), imgui.GetWindowPos(), imgui.GetWindowSize()
                accentLine(dl, wpos, wsize)
                imgui.Spacing()

                local id  = currentId()
                local cat = state.category
                imgui.PushStyleColor(imgui.Col.Text, clr.accent)
                imgui.Text(e(string.format("%s №%d", catNameTitle(cat), id)))
                imgui.PopStyleColor()
                imgui.PushStyleColor(imgui.Col.Text, clr.text_dim)
                imgui.Text(e(string.format("Позиция: %d / %d", state.idx, #state.ids)))
                imgui.PopStyleColor()

                imgui.Spacing(); imgui.Separator(); imgui.Spacing()

                sectionLabel(fa.CIRCLE_USER, e("Владелец"))
                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.13, 0.20, 0.70))
                if imgui.BeginChild("##owner_box", imgui.ImVec2(-1, 38), false) then
                    imgui.SetCursorPosY(imgui.GetCursorPosY() + 8)
                    imgui.SetCursorPosX(imgui.GetCursorPosX() + 8)
                    imgui.Text(e(state.owner))
                    imgui.EndChild()
                end
                imgui.PopStyleColor()

                imgui.Spacing(); imgui.Separator(); imgui.Spacing()

                local nw = (imgui.GetContentRegionAvail().x - 10) / 2
                if state.idx > 1 then
                    if colorButton(fa.CHEVRON_LEFT .. e("  Назад"), nw, 34, clr.header,
                                   imgui.ImVec4(0.20,0.22,0.30,1), imgui.ImVec4(0.16,0.18,0.25,1)) then
                        goPrev()
                    end
                else
                    disabledButton(fa.CHEVRON_LEFT .. e("  Назад"), nw, 34)
                end
                imgui.SameLine()
                if state.idx < #state.ids then
                    if colorButton(e("Вперед  ") .. fa.CHEVRON_RIGHT, nw, 34, clr.header,
                                   imgui.ImVec4(0.20,0.22,0.30,1), imgui.ImVec4(0.16,0.18,0.25,1)) then
                        goNext()
                    end
                else
                    disabledButton(e("Вперед  ") .. fa.CHEVRON_RIGHT, nw, 34)
                end

                imgui.Spacing()
                if colorButton(fa.BELL .. e("  Отправить уведомление"), -1, 36, clr.warn, clr.warn_hov, clr.warn_act) then
                    state.notify_type = 1
                    ffi.fill(mapping_buf, ffi.sizeof(mapping_buf), 0)
                    ffi.fill(manual_nick_buf, ffi.sizeof(manual_nick_buf), 0)
                    state.notify_open = true
                end
                imgui.Spacing()
                if colorButton(fa.XMARK .. e("  Закрыть панель"), -1, 30, clr.danger, clr.danger_hov, clr.danger_act) then
                    state.panel_open = false
                end
                imgui.End()
            end
            popTheme()
        end

        -- --------------------------------------------------------
        -- ОКНО УВЕДОМЛЕНИЯ
        -- --------------------------------------------------------
        if state.notify_alpha > 0.01 then
            pushTheme()
            local nw = 480
            local isTrailer = state.category == CAT_TRAILER
            local nh = state.notify_type == 2 and 410 or 340
            if isTrailer then
                nh = nh + (state.notify_type == 2 and 62 or 72)
            end
            imgui.SetNextWindowSize(imgui.ImVec2(nw, nh), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2((display.x-nw)/2, (display.y-nh)/2), imgui.Cond.Always)
            imgui.SetNextWindowBgAlpha(clr.bg.w * state.notify_alpha)

            local nf = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
            if imgui.Begin(fa.BELL .. e("  Уведомление игрока"), nil, nf) then
                local dl, wpos, wsize = imgui.GetWindowDrawList(), imgui.GetWindowPos(), imgui.GetWindowSize()
                accentLine(dl, wpos, wsize)
                imgui.Spacing()

                imgui.PushStyleColor(imgui.Col.Text, clr.text_dim)
                imgui.Text(e(string.format("%s №%d  •  Владелец: %s",
                    catNameTitle(state.category), currentId(),
                    isTrailer and ffi.string(manual_nick_buf) or state.owner)))
                imgui.PopStyleColor()

                imgui.Spacing(); imgui.Separator(); imgui.Spacing()

                -- Для трейлеров — поле ввода ника
                if isTrailer then
                    sectionLabel(fa.CIRCLE_USER, e("Никнейм владельца"))
                    imgui.SetNextItemWidth(-1)
                    imgui.InputText("##manual_nick", manual_nick_buf, ffi.sizeof(manual_nick_buf))
                    imgui.Spacing()
                end

                sectionLabel(fa.LIST_CHECK, e("Тип нарушения"))
                imgui.Spacing()

                local tw = (imgui.GetContentRegionAvail().x - 10) / 2
                if toggleBtn(fa.TAG .. e("  Название"), state.notify_type == 1, tw, 34,
                             clr.accent, clr.accent_hov, clr.accent_act) then
                    state.notify_type = 1
                end
                imgui.SameLine()
                if toggleBtn(fa.HAMMER .. e("  Маппинг"), state.notify_type == 2, tw, 34,
                             clr.warn, clr.warn_hov, clr.warn_act) then
                    state.notify_type = 2
                end
                imgui.Spacing()

                if state.notify_type == 2 then
                    sectionLabel(fa.PEN, e("Что именно нарушено"))
                    imgui.SetNextItemWidth(-1)
                    imgui.InputText("##mapping_what", mapping_buf, ffi.sizeof(mapping_buf))
                    imgui.Spacing()
                end

                -- Превью
                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.13, 0.20, 0.60))
                if imgui.BeginChild("##preview", imgui.ImVec2(-1, 100), false) then
                    imgui.SetCursorPosY(imgui.GetCursorPosY() + 4)
                    imgui.SetCursorPosX(imgui.GetCursorPosX() + 6)
                    imgui.PushStyleColor(imgui.Col.Text, clr.text_dim)
                    imgui.TextWrapped(buildNotifyText())
                    imgui.PopStyleColor()
                    imgui.EndChild()
                end
                imgui.PopStyleColor()
                imgui.Spacing()

                local bw = (imgui.GetContentRegionAvail().x - 10) / 2
                -- Определяем ник: для трейлера — из поля ввода, иначе из state.owner
                local effectiveNick
                if isTrailer then
                    effectiveNick = ffi.string(manual_nick_buf):gsub("%s*$", "")
                else
                    effectiveNick = state.owner
                end
                local bad_owner = (effectiveNick == "" or effectiveNick == "Загрузка..."
                                or effectiveNick == "Поиск..."  or effectiveNick == "Не найден"
                                or effectiveNick == "-"         or effectiveNick == "Таймаут"
                                or effectiveNick == "Вручную")
                if colorButton(fa.PAPER_PLANE .. e("  Отправить"), bw, 36, clr.green, clr.green_hov, clr.green_act) then
                    if bad_owner then
                        sampAddChatMessage("{FF4444}[AMap] Владелец не определён.", -1)
                    else
                        sendNotify(effectiveNick)
                    end
                    state.notify_open = false
                end
                imgui.SameLine()
                if colorButton(fa.XMARK .. e("  Отмена"), bw, 36, clr.danger, clr.danger_hov, clr.danger_act) then
                    state.notify_open = false
                end
                imgui.End()
            end
            popTheme()
        end

    end -- OnFrame
)

-- ============================================================
-- ПАРСИНГ ДИАЛОГОВ
-- ============================================================
function sampev.onShowDialog(id, style, title, btn1, btn2, text)
    if not state.waiting_info then return end
    if state.category == CAT_TRAILER then return end

    local t   = title or ""
    local txt = text  or ""

    -- Заголовок "ИНФОРМАЦИЯ О ДОМЕ" / "ИНФОРМАЦИЯ О БИЗНЕСЕ"
    -- CP1251 байты слова "ИНФОРМАЦИЯ": \xC8\xCD\xD4\xCE\xD0\xCC\xC0\xD6\xC8\xDF
    -- Также проверяем строчный вариант "Информация": \xC8\xED\xF4\xEE\xF0\xEC\xE0\xF6\xE8\xFF
    local isInfoDialog = t:find('\xC8\xCD\xD4\xCE\xD0\xCC\xC0\xD6\xC8\xDF') ~= nil
                      or t:find('\xC8\xED\xF4\xEE\xF0\xEC\xE0\xF6\xE8\xFF') ~= nil

    if not isInfoDialog then return end  -- не наш диалог, не трогаем

    local owner = nil

    -- "ВЛАДЕЛЕЦ:" CP1251 заглавными: \xC2\xCB\xC0\xC4\xC5\xCB\xC5\xD6
    owner = txt:match('\xC2\xCB\xC0\xC4\xC5\xCB\xC5\xD6:%s*([^\n\r\t]+)')

    -- Строчный вариант "Владелец:" CP1251: \xC2\xEB\xE0\xE4\xE5\xEB\xE5\xF6
    if not owner or owner == "" then
        owner = txt:match('\xC2\xEB\xE0\xE4\xE5\xEB\xE5\xF6:%s*([^\n\r\t]+)')
    end

    -- Fallback: никнейм латиницей Имя_Фамилия
    if not owner or owner == "" then
        owner = txt:match('([A-Z][a-zA-Z]+_[A-Z][a-zA-Z]+)')
    end
    if not owner or owner == "" then
        owner = txt:match('([A-Z][A-Z_]+_[A-Z][A-Z_]+)')
    end

    if owner then
        owner = owner:gsub("{%x%x%x%x%x%x}", ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    state.owner        = (owner and owner ~= "") and owner or "Не найден"
    state.waiting_info = false
    sampSendDialogResponse(id, 1, 0, '')
    return false
end

-- ============================================================
-- MAIN
-- ============================================================
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    -- Проверка обновлений через downloadUrlToFile (как в AdminScript)
    local dlstatus = require('moonloader').download_status
    local ver_tmp = getWorkingDirectory() .. "\\amap_ver.tmp"
    downloadUrlToFile(VERSION_URL, ver_tmp, function(id, status)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            local f = io.open(ver_tmp, "r")
            if not f then return end
            local remote_ver = f:read("*a"):match("^%s*([%d%.]+)%s*$")
            f:close()
            os.remove(ver_tmp)

            if not remote_ver or remote_ver == script_version then return end

            sampAddChatMessage(string.format(
                "{FFAA00}[AMap] Доступна новая версия: v%s (текущая: v%s). Обновление...",
                remote_ver, script_version), -1)

            -- Скачиваем новый скрипт прямо поверх текущего
            downloadUrlToFile(SCRIPT_URL, SCRIPT_PATH, function(id2, status2)
                if status2 == dlstatus.STATUSEX_ENDDOWNLOAD then
                    sampAddChatMessage("{4AFF88}[AMap] Обновление установлено! Перезагрузка...", -1)
                    lua_thread.create(function()
                        wait(1500)
                        thisScript():reload()
                    end)
                else
                    sampAddChatMessage("{FF4444}[AMap] Ошибка загрузки обновления.", -1)
                end
            end)
        end
    end)

    sampRegisterChatCommand("amap", function()
        if state.panel_open then
            state.panel_open  = false
            state.notify_open = false
        else
            state.main_open = not state.main_open
        end
    end)

    sampAddChatMessage("{4A8FFF}[AMap] {FFFFFF}Скрипт для отдела проверки маппинга загружен v" .. script_version
        .. ". Команда: {4A8FFF}/amap", 0xFFFFFF)

    while true do
        wait(0)
        if state.waiting_info then
            local elapsed = os.clock() - state.info_time
            if elapsed >= state.info_timeout then
                state.owner        = "Таймаут"
                state.waiting_info = false
            end
        end
    end
end
