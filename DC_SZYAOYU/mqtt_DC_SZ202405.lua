--gpio.setup(11,1)   ----INA   电机阀控制脚
--gpio.setup(8,1) -------INB   电机阀控制脚
local lbsLoc2 = require("lbsLoc2")   ------定位库
adc.open(adc.CH_VBAT)
local mybat = adc.get(adc.CH_VBAT)
adc.close(adc.CH_VBAT)

if fskv.get("bauds") == nil then
    fskv.set("bauds", 9600) ------- 设置默认波特率
    fskv.set("uptime", 2) ------- 设置自动上传周期，默认60分钟【单位分钟】
    fskv.set("surplus",0)  -------- 设置预付费表剩余量
    fskv.set("senttime","0600") --------设置自动上传的整点时间，2400为每个整点都上报，其余为指定时间上报
    --fskv.set("valstate",5) -------  设置阀门状态，1开，2关，3卡住
    fskv.set("rebootnum", 3)
end
local lat, lng, t
local senttime = fskv.get("senttime")
local sws = nil
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
local metersum = ""        ----水表表头的实际累计数【表头读数】
local pub_topic = "pushinfo/" .. mobile.imei(0)  ----mqtt发送主题
local sub_topic = "getinfo/" .. mobile.imei(0)  ----mqtt订阅主题

local mqttc = nil
local bauds = fskv.get("bauds") --------获得波特率
local uptime = fskv.get("uptime") --------获得自动上传周期
local device_id = mobile.imei(0)  ------获得序列号【imei号】
local ccid = mobile.iccid(0)      ------获得iccid号
local table_baud = {9600,4800,2400}   ------波特率范围
local i = 1
local uptime1 = nil
local hh_now = nil  -----获得当前整点时间
local mm_now = nil  -----获得当前分钟时间
local ss_now = nil  -----获得当前秒钟时间





gpio.setup(11,0)   ----INA   电机阀控制脚
gpio.setup(8,0) -------INB   电机阀控制脚
uart.setup(1, bauds, 8, 1, uart.EVEN)
---sys.waitUntil("IP_READY", 30000)

sys.taskInit(function()
    gpio.setup(23, nil)
    gpio.close(12)
    gpio.close(13)

    gpio.close(33) --如果功耗偏高，开始尝试关闭WAKEUPPAD1
    gpio.close(32) -- 如果功耗偏高，开始尝试关闭WAKEUPPAD0
    --gpio.setup(32, function() end, gpio.PULLUP)
    gpio.close(35) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要
    local sjbd = os.date("%H:%M:%S",os.time()+28800)
    local sj = os.date("%H:%M:%S",os.time()+28800)
    log.info("sjbd",sjbd)
    log.info("sj",sj)
    ----log.info("bauds", bauds)
    --uart.setup(1, bauds, 8, 1, uart.EVEN)
    sys.wait(100)
    -- FE FE FE 68 10 AA AA AA AA AA AA AA 01 03 90 1F 01 D2 16------万能读表指令
    uart.write(1,
               string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,
                           0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2,
                           0x16))
    sys.wait(500)

    --uart.close(1)
    --meterno = meterno:match("^[%s]*(.-)[%s]*$")----
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
    local myrsrq = mobile.rsrq()
    local myrssi = mobile.rssi()
    local mysinr = mobile.snr()
    local yy = {DEVTYPE = "M2", SN = device_id, INFO = 4}  ---mqtt遗言数据
    local will_str = json.encode(yy)      ---mqtt遗言json格式

    upCellInfo()
    if meterno == nil then ----------------------------如果未能获得表号，说明水表接线或水表硬件故障
        if rebootnum > 3 then
            rebootnum = 0
            fskv.set("rebootnum", rebootnum)
        end
        local kk = {DEVTYPE = "M2", SN = device_id, INFO = 3}
        dev_data = json.encode(kk)

        
    else
        ---upCellInfo()
        local dev_data0 = {
            DEVTYPE = "M0",
            SN = device_id,
            ICCID = ccid,
            --ALLDATA = alldata,
            METERNO = meterno,
            VER = "MCD618-20240403",
            UPTIME = uptime,
            SENTTIME = senttime,
            REASON = reason,
            --VALSTATE = valstate,
            BATT = mybat,
            BAUD = bauds,
            LAT = lat,
            LNG = lng,
            RSRP = mycsq,
            RSRQ = myrsrq,
            RSSI = myrssi,
            SINR = mysinr,
            METERSUM = metersum,
            PAYMODE = 1,
            FACT = 1
        }
        dev_data = json.encode(dev_data0)
        -- local meter_data0 = {
        --     DEVTYPE = "M1",
        --     SN = device_id,
        --     METERSUM = metersum,
        --     PAYMODE = 1
        -- }
        -- meter_data = json.encode(meter_data0)
    end
    log.info("RET",ret)
    if ret then -----------------如果gprs网络已经连上ok
        hh_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),1,2)  -----获得当前整点时间
        mm_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),4,5)  -----获得当前分钟时间
        --ss_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),7,8)  -----获得当前秒钟时间
        if senttime == 2400 then  -------如果设置为每个整点都上报
            if tonumber(mm_now)==0 then
                uptime = 60
            else
                uptime = 60 - tonumber(mm_now)
            end
        else
            log.info("now",os.date("!%H:%M:%S",os.time()+28800))
            log.info("tonumber(hh_now)",hh_now)
            uptime = time_difference(hh_now, mm_now, string.sub(senttime,1,2), string.sub(senttime,3,4))
            uptime1 = uptime
        end
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
                    --if meterno ~= nil then   ------------如果取得表数据
                    --    mqtt_client:publish(pub_topic, dev_data)
                    --    mqtt_client:publish(pub_topic, meter_data) ------联网成功后，将之前读到的水表数据发送到订阅号
                    --else
                        mqtt_client:publish(pub_topic, dev_data) ------上电联网成功后，发一条成功信息到订阅号
                    --end
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
        ----sys.waitUntil("IP_READY", 30000)
        if mqttc and mqttc:ready() then
            --adc.open(adc.CH_VBAT)
            --mybat = adc.get(adc.CH_VBAT)
            --dc.close(adc.CH_VBAT)
            hh_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),1,2)  -----获得当前整点时间
            mm_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),4,5)  -----获得当前分钟时间
            local nowbd = os.date("!%H:%M:%S",os.time()+28800)
            local nowbd1 = os.date("!%H:%M:%S",os.time())
            ----ss_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),7,8)  -----获得当前秒钟时间
            if senttime == 2400 then  -------如果设置为每个整点都上报
                if tonumber(mm_now) == 0 then
                    uptime1 = 60
                else
                    uptime1 = 60 - tonumber(mm_now)
                end
            else
                log.info("now1",os.date("!%H:%M:%S",os.time()+28800))
                log.info("nowbd",nowbd)
                log.info("nowbd1",nowbd1)
                log.info("hh_now1",hh_now)
                uptime1 = time_difference(hh_now, mm_now, string.sub(senttime,1,2), string.sub(senttime,3,4))
                if uptime1 <= 0 then
                    uptime1 = 24*60
                end
                
            end
            if uptime1 == nil then
                uptime = 2
            else
                uptime = uptime1
            end
            log.info("uptime",uptime)
            upCellInfo()
            uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
            if metersum ~= nil then
                local meter_data0 = {
                    DEVTYPE = "M1",
                    SN = device_id,
                    ICCID = ccid,
                    --ALLDATA = alldata,
                    METERNO = meterno,
                    VER = "MCD618-20240403",
                    UPTIME = uptime,
                    SENTTIME = senttime,
                    REASON = reason,
                    --VALSTATE = valstate,
                    --BATT = mybat,
                    BAUD = bauds,
                    LAT = lat,
                    LNG = lng,
                    RSRP = mobile.rsrp(),
                    RSRQ = mobile.rsrq(),
                    RSSI = mobile.rssi(),
                    SINR = mobile.snr(),
                    METERSUM = metersum,
                    PAYMODE = 1,
                    FACT = 1
                }
                meter_data = json.encode(meter_data0)
                local pkgid = mqttc:publish(pub_topic, meter_data)
            end
        end
        local randomNum = GetRandomNumber()  --------产生随即秒（0-60）
        sys.wait((uptime * 60 + randomNum) * 1000)
        ---sys.wait(uptime * 60 * 1000)
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
                bup0 = string.sub(payload, 20, #payload)
                --uptime = string.gsub(bup0, "^%z+", "") --- 使用正则表达式将开头连续的零删除
                uptime = bup0:match("^[0]*(.-)[%s]*$")
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
            if string.sub(payload, 18, 19) == "A3" then  -------查询累计数和设备参数  D3867713070630363A2----------
                adc.open(adc.CH_VBAT)
                mybat = adc.get(adc.CH_VBAT)
                adc.close(adc.CH_VBAT)
                uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
                if metersum ~= nil then
                    local dev_data0 = {
                        DEVTYPE = "M3",
                        SN = device_id,
                        ICCID = ccid,
                        --ALLDATA = alldata,
                        METERNO = meterno,
                        VER = "MCD618-20240403",
                        UPTIME = uptime,
                        SENTTIME = senttime,
                        --REASON = reason,
                        VALSTATE = valstate,
                        BATT = mybat,
                        BAUD = bauds,
                        RSRP = mobile.rsrp(),
                        RSRQ = mobile.rsrq(),
                        RSSI = mobile.rssi(),
                        SINR = mobile.snr(),
                        METERSUM = metersum,
                        FACT = 1,
                        PAYMODE = 1,
                        FUNCCODE = "A3"
                    }
                    dev_data = json.encode(dev_data0)
                    log.info("dev_data",dev_data)
                    mqttc:publish(pub_topic, dev_data)
                end
            end

            if string.sub(payload, 18, 19) == "T4" then  --------设置定点或整点上传时间 格式"小时分钟"---"2315"，如为2400，则每个整点上传一次
                local re0 = nil
                local re1 = nil
                local temphm = string.sub(payload, 20, #payload)
                if is_valid_time_format(temphm) then
                    senttime = tostring(temphm)
                    fskv.set("senttime",senttime)
                    getuptime(temphm)
                    re0 = {
                        DEVTYPE = "M3",
                        SN = device_id,
                        FUNCCODE = "T4",
                        UPDATA = senttime
                    }
                    local re00 = json.encode(re0)
                    mqttc:publish(pub_topic, re00)
                    sys.wait("100")
                    ---rtos.reboot()
                    pm.reboot()
                else
                    re1 = {
                        DEVTYPE = "M3",
                        SN = device_id,
                        FUNCCODE = "T4",
                        UPDATA = "error"
                    }
                    local re11 = json.encode(re1)
                    mqttc:publish(pub_topic, re11)
                end
            end

            if string.sub(payload, 18, 20) == "RST" then  -------重启  D3867713070630363A2----------
                local jjjj = {
                    DEVTYPE = "M3",
                    SN = device_id,
                    FUNCCODE = "RST",
                }
                rtos.reboot()
            end
            -- if string.sub(payload, 18, 19) == "A3" then --  获取设备参数   D3867713070630363A3  ----------
            --     adc.open(adc.CH_VBAT)
            --     mybat = adc.get(adc.CH_VBAT)
            --     adc.close(adc.CH_VBAT)
            --     --log.info("valstate",valstate)
            --     local dev_data0 = {
            --         DEVTYPE = "M3",
            --         SN = device_id,
            --         ICCID = ccid,
            --         --ALLDATA = alldata,
            --         METERNO = meterno,
            --         VER = "MCD618-20240403",
            --         UPTIME = uptime,
            --         --REASON = reason,
            --         VALSTATE = valstate,
            --         BATT = mybat,
            --         BAUD = bauds,
            --         RSRP = mobile.rsrp(),
            --         RSRQ = mobile.rsrq(),
            --         RSSI = mobile.rssi(),
            --         SINR = mobile.snr(),
            --         METERSUM = metersum,
            --         FACT = 1,
            --         PAYMODE = 1,
            --         FUNCCODE = "A3"
            --     }
            --     dev_data = json.encode(dev_data0)
            --     log.info("dev_data",dev_data)
            --     mqttc:publish(pub_topic, dev_data)
            -- end
        end
    end
end)

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


function upCellInfo()   -------基站定位函数
    ----log.info('请求基站查询')
    mobile.reqCellInfo(15)
    ----log.info('开始查询基站定位信息')
    sys.waitUntil("CELL_INFO_UPDATE", 10000)
    lat, lng, t = lbsLoc2.request(5000,nil,nil,true)
    if lat ~= nil then
    -- 这里的时间戳需要减 28800 北京时间 
        --log.info("定位成功",lat, lng, os.time(t),(json.encode(t or {})))
        return lat,lng
    else
        --log.info("基站定位失败")
        return nil
    end
end 

local function GetRandomNumber()
    math.randomseed(os.time())
    return math.random(0, 60)
end

function getuptime(sentstr)
    hh_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),1,2)  -----获得当前整点时间
    mm_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),4,5)  -----获得当前分钟时间
    if sentstr == 2400 then  -------如果设置为每个整点都上报
        if tonumber(mm_now) == 0 then
            uptime1 = 60
        else
            uptime1 = 60 - tonumber(mm_now)
        end
    else
        uptime1 = time_difference(hh_now, mm_now, string.sub(sentstr,1,2), string.sub(sentstr,3,4))
        if uptime1 <= 0 then
            uptime1 = 24*60
        end
    end
    if uptime1 == nil then
        uptime = 2
    else
        uptime = uptime1
    end
---    return uptime
end



function time_difference(hh1, mm1, hh2, mm2)   -----获得时间差值
    -- Helper function to convert time components to total minutes
    local function to_minutes(hours, minutes)
        return hours * 60 + minutes
    end

    -- Convert both times to minutes
    local minutes1 = to_minutes(hh1, mm1)
    local minutes2 = to_minutes(hh2, mm2)

    -- Calculate the difference
    local difference = minutes2 - minutes1

    -- If the difference is negative, it means t2 is on the next day
    if difference < 0 then
        difference = difference + 24 * 60 -- Add 24 hours worth of minutes
    end

    return difference
end

function is_valid_time_format(time_str)
    -- Check if the input is a string and has a length of 4
    if type(time_str) ~= "string" or #time_str ~= 4 then
        return false
    end

    -- Check if all characters in the string are digits
    if not time_str:match("^%d%d%d%d$") then
        return false
    end

    -- Extract hours and minutes from the string
    local hh = tonumber(time_str:sub(1, 2))
    local mm = tonumber(time_str:sub(3, 4))

    -- Validate the hours and minutes
    if hh < 0 or hh > 23 or mm < 0 or mm > 59 then
        return false
    end

    return true
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
