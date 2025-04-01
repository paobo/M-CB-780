-- local mqtt_test = {}
-- _G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]] -- _G.sysplus = require("sysplus")
--local reason, slp_state = pm.lastReson()  --获取唤醒原因
--log.info("wakeup state", reason)
adc.open(adc.CH_VBAT)
local mybat = adc.get(adc.CH_VBAT)
adc.close(adc.CH_VBAT)

if fskv.get("bauds") == nil then
    fskv.set("bauds", 9600) ------- 设置默认波特率
    fskv.set("uptime", 60) ------- 设置自动上传周期，默认60分钟【单位分钟】
    fskv.set("surplus",0)  -------- 设置预付费表剩余量
    fskv.set("rebootnum", 3)
end

local dev_data = nil
local meter_data = nil
local rebootnum = fskv.get("rebootnum")
local mqtt_host = "yaoyu.plus"
local mqtt_port = 1883
local mqtt_isssl = false
local client_id = mobile.imei(0)
local user_name = "deviceforyaoyu"
local password = "!@subscribePass$#"
local meterno = nil  -------水表表号
local alldata = nil
--local csq = nil
local metersum = ""        ----水表表头的实际累计数【表头读数】
--local pub_topic = "yomtey/prod/s/" .. mobile.imei(0)  ----mqtt发送主题
--local sub_topic = "yomtey/prod/p/" .. mobile.imei(0)  ----mqtt订阅主题
local pub_topic = "pushinfo/" .. mobile.imei(0)  ----mqtt发送主题
local sub_topic = "getinfo/" .. mobile.imei(0)  ----mqtt订阅主题

local mqttc = nil
local bauds = fskv.get("bauds") --------获得波特率
local uptime = fskv.get("uptime") --------获得自动上传周期
--local uptime = 720 --------获得自动上传周期
local device_id = mobile.imei(0)  ------获得序列号【imei号】
local ccid = mobile.iccid(0)      ------获得iccid号
local table_baud = {9600,4800,2400}   ------波特率范围
local i = 1
gpio.setup(11,0)   ----INA   电机阀控制脚
gpio.setup(8,0) -------INB   电机阀控制脚
-- local wake_delay = 15000
-- if reason == 2 then
--     wake_delay = 25000
-- end
uart.setup(1, bauds, 8, 1, uart.EVEN)

sys.taskInit(function()
    gpio.setup(23, nil)
    gpio.close(12)
    gpio.close(13)

    gpio.close(33) --如果功耗偏高，开始尝试关闭WAKEUPPAD1
    gpio.close(32) -- 如果功耗偏高，开始尝试关闭WAKEUPPAD0
    --gpio.setup(32, function() end, gpio.PULLUP)
    gpio.close(35) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要
    log.info("bauds", bauds)
    --uart.setup(1, bauds, 8, 1, uart.EVEN)
    sys.wait(100)
    -- FE FE FE 68 10 AA AA AA AA AA AA AA 01 03 90 1F 01 D2 16------万能读表指令
    uart.write(1,
               string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,
                           0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2,
                           0x16))
    sys.wait(500)

    --uart.close(1)
    --meterno = meterno:match("^[%s]*(.-)[%s]*$")
    log.info("bh", meterno)

    if  meterno == nil then
        log.info("cs", rebootnum)
        if rebootnum <= 3 then
            log.info("reboot", rebootnum)
            uart.rxClear(1)
            rebootnum = rebootnum + 1
            fskv.set("rebootnum", rebootnum)
            if bauds == 9600 then
                bauds = 4800
                fskv.set("bauds", bauds)
                rtos.reboot()
            end
            if bauds == 4800 then
                bauds = 2400
                fskv.set("bauds", bauds)
                rtos.reboot()
            end
            if bauds == 2400 then
                bauds = 9600
                fskv.set("bauds", bauds)
                rtos.reboot()
            end
        end
    end

    

    sys.waitUntil("IP_READY", 30000)
    sys.publish("net_ready", device_id)
    local ret = sys.waitUntil("net_ready")
    local mycsq = mobile.rsrp()

    --local yy = {DEVTYPE = "M2", SN = device_id, INFO = 4}  ---mqtt遗言数据
    --local will_str = json.encode(yy)      ---mqtt遗言json格式
    local will_str = "M2"..device_id.."4"


    if meterno == nil then ----------------------------如果未能获得表号，说明水表接线或水表硬件故障
        if rebootnum > 3 then
            rebootnum = 0
            fskv.set("rebootnum", rebootnum)
        end
        --local kk = {DEVTYPE = "M2", SN = device_id, INFO = 3}
        --dev_data = json.encode(kk)
        dev_data = "M2"..device_id.."3"
        
    else
        local uptime1
        log.info("uptime", uptime)
        if #tostring(uptime) < 4 then    ------自动上传时间补位
            local ggg = 4 - #tostring(uptime)
            uptime1 = string.rep("0", ggg)..uptime
        else
            uptime1 = uptime
        end
        log.info("uptime1", uptime1)
        local yyy = tostring(mycsq)
        local mycsq1 = string.gsub(yyy, "-", "")
        if #yyy < 4 then    ------RSRP值补位
            local fff = 4 - #tostring(mycsq)
            mycsq1 = "-"..string.rep("0", fff)..mycsq1   ----用string.gsub正则表达式去除mycsq前面的"-"
            log.info("yyy",yyy)
            log.info("mycsq1",mycsq1)
        end
        dev_data ="M0"..device_id..ccid..meterno.."CD618010"..uptime1..mybat..bauds..mycsq1.."1"   ---设备状态字符串
        meter_data = "M1"..device_id..metersum.."00000000000000000000".."11"


    end
    log.info("RET",ret)


    if ret then -----------------如果gprs网络已经连上ok
        mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, nil)
        mqttc:auth(client_id, user_name, password)
        mqttc:keepalive(30) ---------- 默认值240s
        mqttc:autoreconn(true, 3000) -- 自动重连机制
        mqttc:will(pub_topic, will_str)
        mqttc:on(
            function(mqtt_client, event, data, payload) -- 用户自定义代码
                if event == "conack" then -- 如果联上了
                    fls(12)
                    mqtt_client:subscribe(sub_topic) -- 单主题订阅
                    -- sys.wait(100)
                    if meterno ~= nil then   ------------如果未取得表数据
                        mqtt_client:publish(pub_topic, dev_data)
                        mqtt_client:publish(pub_topic, meter_data) ------联网成功后，将之前读到的水表数据发送到订阅号
                    else
                        mqtt_client:publish(pub_topic, dev_data) ------上电联网成功后，发一条成功信息到订阅号
                    end
                elseif event == "recv" then
                    sys.publish("mqtt_payload", data, payload)  ------系统通知，收到MQTT下行指令
                end
            end)

    else
        rtos.reboot()  ----如果未连上网络，重启模组
    end
    -- ec618的节能模式，0~3，0完全关闭，1性能优先，2平衡，3极致功耗
-- 详情访问: https://airpsm.cn
-- pm.power(pm.WORK_MODE, 1)

    mqttc:connect()
    sys.waitUntil("mqtt_conack")
    while true do sys.wait(600000) end
    mqttc:close()
    mqttc = nil
end)

sys.taskInit(function()   ------周期上传mqtt数据
	--local data = "123,"
	local qos = 0 -- QOS0不带puback, QOS1是带puback的
    while true do
        sys.wait(uptime * 60 * 1000)
        if mqttc and mqttc:ready() then
            uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
            if metersum ~= nil then
            local pkgid = mqttc:publish(pub_topic, "M1"..device_id..metersum.."00000000000000000000".."11")
            end
        end
    end
end)



sys.subscribe("mqtt_payload",function(topic, payload)
    --log.info("uart", "uart发送数据长度", #payload)
    fls(12)
    if payload ~= nil then
        if string.sub(payload, 1, 2) == "D3" and string.sub(payload, 3, 17) == mobile.imei(0) then
            local bup0 = nil
            if string.sub(payload, 18, 19) == "C4" then  ------设置自动上传周期D3867713070630363C40000000060 D3   869020066349869   C4   60(分钟)
                bup0 = string.sub(payload, 20, #payload)
                --uptime = string.gsub(bup0, "^%z+", "") --- 使用正则表达式将开头连续的零删除
                uptime = bup0:match("^[0]*(.-)[%s]*$")
                if tonumber(uptime) >= 1 then
                fskv.set("uptime", uptime)
                --local upt = fskv.get("uptime")
                mqttc:publish(pub_topic, "M3"..mobile.imei(0).."C4"..bup0)
                end
            end
            if string.sub(payload, 18, 19) == "A2" then  -------查询累计数  D3867713070630363A2----------
                log.info("payload", payload)
                log.info("A2", string.sub(payload, 18, 19))
                uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
                if metersum ~= nil then
                --    log.info("leiji",metersum)
                    mqttc:publish(pub_topic, "M3"..mobile.imei(0).."A2"..metersum)
                end
            end
            if string.sub(payload, 18, 19) == "A3" then --  获取设备参数   D3867713070630363A3  ----------
                local device00 = nil
                local myxh = mobile.rsrp()  --  -91
                local myrsrq = mobile.rsrq()
                local myrssi = mobile.rssi()
                local yyy = tostring(myxh)  --  "-91"
                local myxh1 = string.gsub(yyy, "-", "")  -- "91"
                if #yyy < 4 then    ------RSRP值补位
                    local fff = 4 - #tostring(myxh)
                    myxh1 = "-"..string.rep("0", fff)..myxh1   ----  用string.gsub正则表达式去除mycsq前面的"-"
                end
                local uptime2
                if #tostring(uptime) < 4 then    ------  自动上传时间补位
                    local gggg = 4 - #tostring(uptime)
                    uptime2 = string.rep("0", gggg)..uptime
                else
                    uptime2 = uptime
                end
                device00 ="M0"..device_id..ccid..meterno.."CD618010"..uptime2..mybat..bauds..myxh1.."1"   ---  设备状态字符串
                mqttc:publish(pub_topic, device00)
            end
            if string.sub(payload, 18, 19) == "CS" then --  获取设备信号   D3867713070630363A3  ----------
                local xhz = nil
                local myxh0 = mobile.rsrp()  --  -91
                local myrsrq = mobile.rsrq()
                local myrssi = mobile.rssi()
                local ff = mobile.snr()
                xhz = "RSRP:"..myxh0.."|RSRQ:"..myrsrq.."|RSSI:"..myrssi.."|SNR:"..ff
                mqttc:publish(pub_topic, xhz)
            end
            if string.sub(payload, 18, 19) == "CQ" then --  重启-------
                rtos.reboot()
            end
        end
    end
end)


local function proc_switch(strs)  --------开关阀函数
    if strs == "0000000001" then  -----强制开阀
        gpio.setup(11,1)   ----INA   电机阀控制脚
        gpio.setup(8,0) -------INB   电机阀控制脚
        while gpio.get(3) == 1 do    ---电机开到位  gpio3为 Y

        end

    end
    if strs == "0000000002" then  -----强制关阀

    end

end






local function proc_get_meterno(strs)
    local k1 = string.sub(strs, 5, 18) --------获得水表表号原始数据
    local tmps = ""
    local tmplen = #k1 / 2 -- 获得字符长度
    for i = tmplen, 1, -1 do tmps = tmps .. string.sub(k1, 2 * i - 1, 2 * i) end
    return tmps
    -- local k2 = string.sub(strs,36,43) --------获得水表累计原始数据
end

local function proc_get_metersum(strs)
    local k2 = string.sub(strs, 29, 36) --------获得水表累计原始数据  6810670517240000008116901F01000300002C000300002C0000000000000000FFC316

    local tmps1 = ""
    local tmplen1 = #k2 / 2 -- 获得字符长度
    for i = tmplen1, 1, -1 do
        tmps1 = tmps1 .. string.sub(k2, 2 * i - 1, 2 * i)
    end
    --local str = "00123" -- 要处理的字符串
    --= string.gsub(tmps1, "^%z+", "") --- 使用正则表达式将开头连续的零删除
    local tmps2 = tmps1:match("^[0]*(.-)[%s]*$")
    log.info("tmps1",tmps1)
    log.info("tmps2",tmps2)
    --tmps2 = tonumber(tmps2*10)   -------- DN300特殊表具*100，其他*10
    if #tmps2 < 9 then
        local jjj = 9 - #tmps2
        tmps2 = string.rep("0",jjj) .. tmps2.."0"    ----不足10位的累计，前面补零直到满足10位
    end
    return tmps2
    -- local k2 = string.sub(strs,36,43) -------- 获得水表累计原始数据
end

uart.on(1, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, len)
        alldata = s:toHex()
        if #s > 0 then -- #s 是取字符串的长度
            
            if string.sub(s:toHex(), 1, 4) == "FEFE" then
                local ss = string.gsub(s:toHex(), "FE", "")
                log.info("ss",ss)
                --if string.sub(ss,23,16) == "901F" then
                    meterno = proc_get_meterno(ss)
                    metersum = proc_get_metersum(ss)
                    fls(12)
                --end
            end
        end
        if #s == len then break end
    until s == ""
end)

function fls(ints)
    gpio.setup(ints, 0)
    for i = 1, 1000 do gpio.set(ints, 0) end
    gpio.set(ints, 1)
    gpio.close(ints)
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
