local lbsLoc2 = require("lbsLoc2") ------定位库
---gpio.setup(13,1)
gpio.setup(11, 1) ----INA   电机阀控制脚
gpio.setup(8, 1) -------INB   电机阀控制脚
adc.open(adc.CH_VBAT)
local mybat = adc.get(adc.CH_VBAT)
adc.close(adc.CH_VBAT)
---pm.power(pm.WORK_MODE,1)
local lat, lng, t
if fskv.get("bauds") == nil then
    fskv.set("bauds", 9600) ------- 设置默认波特率
    fskv.set("uptime", 480) ------- 设置自动上传周期，默认60分钟【单位分钟】
    fskv.set("recharsum", 0) -------- + 设置预付费表充值累计数
    fskv.set("alarmint", 1000) ----- + 预警量 ALARMINT
    fskv.set("valstate", 5) -------  设置阀门状态，11开，22关，33卡住
    fskv.set("rebootnum", 4)
    fskv.set("close_num", 0) --------余额用完关阀及提醒次数
    fskv.set("alarmnum", 0) -------- 余额预警次数
    fskv.set("resetcount",0)  ---------初始化次数
    --fskv.set("playmode", 1) --------- 付费方式，1 为后付费，2 为预付费
end

fskv.set("valstate", valstate)
-- pm.power(pm.WORK_MODE,1)
local valstate = fskv.get("valstate") -------阀门状态
local lat, lng, t
---local close_num = fskv.get("close_num")
local close_num = 0
---=local alarmnum = fskv.get("alarmnum")
local resetcount = fskv.get("resetcount")
local alarmnum = 0
local dev_data = nil
local meter_data = nil
local remain = 0 --------预付费剩余值
---local playmode = fskv.get("playmode")
---local alarmint = fskv.get("alarmint")
---local recharsum = fskv.get("recharsum")
local rebootnum = fskv.get("rebootnum")
local mqtt_host = "mqtt.yihuan100.com"
local mqtt_port = 1883
local mqtt_isssl = false
local client_id = "AIR780E-" .. mobile.imei(0)
local user_name = "test001"
local password = "test1234"
local meterno = nil -------水表表号
---local recharsum = fskv.get("recharsum")
local valstate = fskv.get("valstate") -------阀门状态
local alldata = nil
local metersum = "" ----水表表头的实际累计数【表头读数】
local pub_topic = "yomtey/prod/s/" .. mobile.imei(0)  ----mqtt发送主题
local sub_topic = "yomtey/prod/p/" .. mobile.imei(0)  ----mqtt订阅主题
local mqttc = nil
local bauds = fskv.get("bauds") --------获得波特率
local uptime = fskv.get("uptime") --------获得自动上传周期
local device_id = mobile.imei(0) ------获得序列号【imei号】
local ccid = mobile.iccid(0) ------获得iccid号
local table_baud = {9600, 4800, 2400} ------波特率范围
local i = 1
if fskv.get("valstate") == 5 then
    if gpio.get(3) == 1 and gpio.get(6) == 0 then -----阀门开到位gpio指示
        valstate = 11
    end
    if gpio.get(3) == 0 and gpio.get(6) == 1 then -----阀门关到位gpio指示
        valstate = 22
    end
    if gpio.get(3) == 0 and gpio.get(6) == 0 then -----阀门卡住gpio指示
        valstate = 44
    end
end
gpio.setup(11, 0) ----INA   电机阀控制脚
gpio.setup(8, 0) -------INB   电机阀控制脚

uart.setup(1, bauds, 8, 1, uart.EVEN)

sys.taskInit(function()
    gpio.setup(23, nil)
    gpio.close(12)
    gpio.close(35) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要
    log.info("bauds", bauds)
    sys.wait(100)
    -- FE FE FE 68 10 AA AA AA AA AA AA AA 01 03 90 1F 01 D2 16------万能读表指令
    uart.write(1,
               string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,
                           0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2,
                           0x16))
    sys.wait(500)

    -- uart.close(1)
    -- meterno = meterno:match("^[%s]*(.-)[%s]*$")----
    log.info("bh", meterno)
    if meterno == nil then
        log.info("cs", rebootnum)
        if rebootnum <= 4 then
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

    local yy = {DEVTYPE = "M2", SN = device_id, INFO = 4} ---mqtt遗言数据
    local will_str = json.encode(yy) ---mqtt遗言json格式
    
    if meterno == nil then ----------------------------如果未能获得表号，说明水表接线或水表硬件故障
        if rebootnum > 3 then
            rebootnum = 0
            fskv.set("rebootnum", rebootnum)
        end
        local kk = {DEVTYPE = "M2", SN = device_id, INFO = 3}
        dev_data = json.encode(kk)
    else
        upCellInfo()
        local dev_data0 = {
            DEVTYPE = "M0",
            SN = device_id,
            ICCID = ccid,
            --ALLDATA = alldata,
            METERNO = meterno,
            VER = "MCD618-20250402",
            UPTIME = uptime,
            REASON = reason,
            VALSTATE = fskv.get("valstate"),
            BATT = mybat,
            LAT = lat,
            LNG = lng,
            BAUD = bauds,
            RSRP = mobile.rsrp(),
            RSRQ = mobile.rsrq(),
            RSSI = mobile.rssi(),
            SINR = mobile.snr(),
            FACT = 2
        }
        dev_data = json.encode(dev_data0)
        local meter_data0 = {
            DEVTYPE = "M1",
            SN = device_id,
            METERSUM = metersum,
            PAYMODE = 1
        }
        meter_data = json.encode(meter_data0)
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
                upCellInfo()
                local dev_data0 = {
                    DEVTYPE = "M0",
                    SN = device_id,
                    ICCID = ccid,
                    --ALLDATA = alldata,
                    METERNO = meterno,
                    VER = "MCD618-20250402",
                    UPTIME = uptime,
                    REASON = reason,
                    VALSTATE = fskv.get("valstate"),
                    BATT = mybat,
                    LAT = lat,
                    LNG = lng,
                    BAUD = bauds,
                    RSRP = mobile.rsrp(),
                    RSRQ = mobile.rsrq(),
                    RSSI = mobile.rssi(),
                    SINR = mobile.snr(),
                    FACT = 2
                }
                dev_data = json.encode(dev_data0)
                local meter_data0 = {
                    DEVTYPE = "M1",
                    SN = device_id,
                    METERSUM = metersum,
                    --VALSTATE = valstate,
                    PAYMODE = 1
                }
                meter_data = json.encode(meter_data0)
            local pkgid = mqttc:publish(pub_topic, meter_data)
            local pkfid = mqttc:publish(pub_topic, dev_data)
            end
        end
    end
end)

--[[ sys.taskInit(function()   ------周期检测充值剩余量
    while true do
        sys.wait(60000)
        if mqttc and mqttc:ready() then
            local pkgid = mqttc:publish(pub_topic, meter_data)
        end
    end

end) ]]



sys.subscribe("mqtt_payload",function(topic, payload)
    --log.info("uart", "uart发送数据长度", #payload)
    fls(12)
    if payload ~= nil then
        if string.sub(payload, 1, 2) == "D3" and string.sub(payload, 3, 17) == mobile.imei(0) then
            local bup0 = nil
            if string.sub(payload, 18, 19) == "C4" then  ------ 设置自动上传周期D3867713070630363C40000000060 D3   869020066349869   C4   60(分钟)
                --bup0 = string.sub(payload, 20, #payload)
                uptime = string.gsub(bup0, "^%z+", "") --- 使用正则表达式将开头连续的零删除
                if tonumber(uptime) >= 1 then
                fskv.set("uptime", uptime)
                local upt = fskv.get("uptime")
                local re = {
                            DEVTYPE = "M3",
                            SN = device_id,
                            FUNCCODE = "C4",
                            UPDATA = upt
                            }
                local REDATA = json.encode(re)
                mqtt_client:publish(pub_topic, REDATA)
                --local upt = fskv.get("uptime")
                --mqttc:publish(pub_topic, "M3"..mobile.imei(0).."C4"..bup0)
                end
            end
            if string.sub(payload, 18, 19) == "A2" then  -------查询累计数  D3867713070630363A2----------
                log.info("payload", payload)
                log.info("A2", string.sub(payload, 18, 19))
                uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
                if metersum ~= nil then
                --    log.info("leiji",metersum)
                local lj0 = {
                    DEVTYPE = "M3",
                    SN = device_id,
                    METERSUM = metersum,
                    FUNCCODE = "A2",
                    UPDATA = metersum
                    }
                local lj = json.encode(lj0)
                    mqttc:publish(pub_topic, lj)
                end
            end
--[[             if string.sub(payload, 18, 19) == "A3" then --  获取设备参数   D3867713070630363A3  ----------
                adc.open(adc.CH_VBAT)
                mybat = adc.get(adc.CH_VBAT)
                adc.close(adc.CH_VBAT)
                log.info("valstate",valstate)
                local dev_data0 = {
                    DEVTYPE = "M3",
                    SN = device_id,
                    ICCID = ccid,
                    --ALLDATA = alldata,
                    METERNO = meterno,
                    VER = "CD780-20240320",
                    UPTIME = uptime,
                    REASON = reason,
                    VALSTATE = valstate,
                    BATT = mybat,
                    BAUD = bauds,
                    RSRP = mobile.rsrp(),
                    RSRQ = mobile.rsrq(),
                    RSSI = mobile.rssi(),
                    SINR = mobile.snr(),
                    FACT = 1,
                    FUNCCODE = "A3"
                }
                dev_data = json.encode(dev_data0)
                log.info("dev_data",dev_data)
                mqttc:publish(pub_topic, dev_data)
            end ]]
            if string.sub(payload, 18, 19) == "C5" then --  开阀或关阀   D3867713070630363C50000000001  ----------
                bup0 = string.sub(payload, 20, #payload)
                if bup0 == "11" then ------强制开阀
                    if fskv.get("valstate") ~= 33 then ------如果不是欠费关阀
                        Switch_proc("open")
                    end
                end
                if bup0 == "22" then ------强制关阀
                    Switch_proc("close")
                end
            end
        end
    end
end)
-----gpio去抖动



sys.subscribe("do_switch", function(sws) ----------捕获开关阀是否成功

    local moto_status0 = nil
    log.info("sws", sws)
    if sws == "k0" or sws == "ak0" then -------最终电机已开到位
        valstate = 11
    end
    if sws == "k1" or sws == "ak1" then -------最终电机未开到位
        valstate = 44
    end
    if sws == "g0" then -------最终电机已关到位
        valstate = 22
    end
    if sws == "ag0" then -------最终电机已关到位
        valstate = 33
    end
    if sws == "g1" or sws == "ag1" then -------最终电机未关到位
        valstate = 44
    end
    fskv.set("valstate", valstate)
    valstate = fskv.get("valstate")
    log.info("vvv", valstate)
    moto_status0 = {
        DEVTYPE = "M3",
        SN = device_id,
        FUNCCODE = "C5",
        SWITCH = valstate
        --UPDATA = valstate
    }
    local moto_status = json.encode(moto_status0)
    mqttc:publish(pub_topic, moto_status) ------发送到MQTT
end)

function Switch_proc(strs) ------开关阀函数
    sys.taskInit(function()
        local sws = nil
        local timeout = 180
        ---local startTime = os.clock()
        local startTime = os.time()
        if strs == "open" then
            gpio.setup(11, 1) ----INA   电机阀控制脚
            gpio.setup(8, 0) -------INB   电机阀控制脚
            gpio.setup(12, 0) ------------电机动作指示灯亮
            while gpio.get(3) == 0 do --- 如果电机未开到位  gpio3为行程开关到位指示 Y
                if os.time() - startTime > timeout then -----超时退出
                    break
                end
                sys.wait(100)
            end
            if gpio.get(3) == 0 then
                sws = "k1" -------最终电机未开到位
            else
                sws = "k0" -------最终电机已开到位
            end
            gpio.setup(8, 1) -------INB   电机阀控制脚
            gpio.setup(12, 1) ------------电机动作指示灯灭
        end
        if strs == "autoopen" then
            gpio.setup(11, 1) ----INA   电机阀控制脚
            gpio.setup(8, 0) -------INB   电机阀控制脚
            gpio.setup(12, 0) ------------电机动作指示灯亮
            while gpio.get(3) == 0 do ---电机未开到位  gpio3为行程开关到位指示 Y
                if os.time() - startTime > timeout then -----超时退出
                    break
                end
                sys.wait(100)
            end
            if gpio.get(3) == 0 then
                sws = "ak1" -------最终电机未开到位
            else
                sws = "ak0" -------最终电机已开到位
            end
            gpio.setup(8, 1) -------INB   电机阀控制脚
            gpio.setup(12, 1) ------------电机动作指示灯灭
        end
        if strs == "close" then
            gpio.setup(11, 0) ----INA   电机阀控制脚
            gpio.setup(8, 1) -------INB   电机阀控制脚
            gpio.setup(12, 0) ------------ 电机动作指示灯亮
            while gpio.get(6) == 0 do ---电机未关到位  gpio6为 B
                if os.time() - startTime > timeout then -----超时退出
                    break
                end
                sys.wait(100)
            end
            if gpio.get(6) == 0 then
                sws = "g1" -------最终电机未关到位
            else
                sws = "g0" -------最终电机已关到位
            end
            gpio.setup(11, 1) -------INA   电机阀控制脚
            gpio.setup(12, 1) ------------电机动作指示灯灭
        end
        if strs == "autoclose" then
            gpio.setup(11, 0) ----INA   电机阀控制脚
            gpio.setup(8, 1) -------INB   电机阀控制脚
            gpio.setup(12, 0) ------------ 电机动作指示灯亮
            while gpio.get(6) == 0 do ---电机未关到位  gpio6为 B
                if os.time() - startTime > timeout then -----超时退出
                    break
                end
                sys.wait(100)
            end
            if gpio.get(6) == 0 then
                sws = "ag1" -------最终电机未关到位
            else
                sws = "ag0" -------最终电机已关到位
            end
            gpio.setup(11, 1) -------INA   电机阀控制脚
            gpio.setup(12, 1) ------------电机动作指示灯灭
        end
        ---pm.power(pm.WORK_MODE,1)
        sys.publish("do_switch", sws)
    end)
end






--[[ local function Get_device_info(strss)    -----------获取设备信息或水表流量信息函数
    local deviceinfo = nil
    if strss == "device" then
        adc.open(adc.CH_VBAT)
        mybat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        local dev_data0 = {
            DEVTYPE = "M0",
            SN = device_id,
            ICCID = ccid,
            --ALLDATA = alldata,
            METERNO = meterno,
            VER = "CB108-20240105",
            UPTIME = uptime,
            REASON = reason,
            BATT = mybat,
            BAUD = bauds,
            RSRP = mobile.rsrp(),
            FACT = 1
        }
        deviceinfo = json.encode(dev_data0)
    end
    if strss == "meters" then
        uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
        local meter_data0 = {
            DEVTYPE = "M1",
            SN = device_id,
            METERSUM = metersum,
            PAYMODE = 1
        }
        deviceinfo = json.encode(meter_data0)
    end

end ]]



local function proc_get_meterno(strs)
    local k1 = string.sub(strs, 5, 18) --------获得水表表号原始数据6810891070800000008116901F01000000002C000000002C0000000000000000FF9F16
    local tmps = ""
    local tmplen = #k1 / 2 -- 获得字符长度
    for i = tmplen, 1, -1 do tmps = tmps .. string.sub(k1, 2 * i - 1, 2 * i) end
    return tmps
    -- local k2 = string.sub(strs,36,43) --------获得水表累计原始数据
    -- log.info("meterno",tmps)
end

local function proc_get_metersum(strs)
    local k2 = string.sub(strs, 29, 36) --------获得水表累计原始数据  6810670517240000008116901F01000300002C000300002C0000000000000000FFC316
    local tmps1 = ""
    local tmps2 = ""
    local tmplen1 = #k2 / 2 -- 获得字符长度
    for i = tmplen1, 1, -1 do
        tmps1 = tmps1 .. string.sub(k2, 2 * i - 1, 2 * i)
    end
    -- local str = "00123" -- 要处理的字符串
    -- = string.gsub(tmps1, "^%z+", "") --- 使用正则表达式将开头连续的零删除
    if tonumber(tmps1) ~= 0 then
        tmps2 = tmps1:match("^[0]*(.-)[%s]*$") --- 使用正则表达式将开头连续的零删除
    else
        tmps2 = tmps1
    end

    log.info("tmps1", tmps1)
    log.info("tmps2", tmps2)
    ---- tmps2 = tonumber(tmps2)*10   -------- DN300特殊表具*100，其他*10
    if #tmps2 < 9 then
        local jjj = 9 - #tmps2
        tmps2 = string.rep("0", jjj) .. tmps2 .. "0" ----不足10位的累计，前面补零直到满足10位
    end
    return tmps2
    -- local k2 = string.sub(strs,36,43) -------- 获得水表累计原始数据
end

function upCellInfo() -------基站定位函数
    mobile.reqCellInfo(15)
    sys.waitUntil("CELL_INFO_UPDATE", 10000)
    lat, lng, t = lbsLoc2.request(5000, nil, nil, true)
    if lat ~= nil then
        return lat, lng
    else
        return nil
    end
end

uart.on(1, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, len)
        alldata = s:toHex()
        if #s > 0 then -- #s 是取字符串的长度

            if string.sub(s:toHex(), 1, 4) == "FEFE" then
                local ss = string.gsub(s:toHex(), "FE", "")
                log.info("ss", ss)
                if string.sub(ss, 23, 26) == "901F" then -- 6810891070800000008116901F01000000002C000000002C0000000000000000FF9F16
                    meterno = proc_get_meterno(ss)
                    metersum = proc_get_metersum(ss)
                    fls(12)
                end
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
