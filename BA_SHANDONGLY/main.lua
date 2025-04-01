PROJECT = "M-CB-780"
VERSION = "1.0.0"    ------------6系列代表用粤镁特的项目标识烧录恒通的代码
PRODUCT_KEY = "Uyo5f9zQwIOQHEoexg0oqP5Y7ySbHHBr"   --------- 山东临沂铭信485后付费电池水表
-- sys库是标配
_G.sys = require("sys")
fskv.init()
mobile.flymode(0,false)

libnet = require "libnet"
libfota = require "libfota"


--[[ sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("fota","VER",VERSION)
        log.info("hello world!",VERSION)
    end
end) ]]

function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        rtos.reboot()
    end
end

libfota.request(fota_cb)
sys.timerLoopStart(libfota.request, 3600000, fota_cb)
require("mqtt_DC_SW")
---require("mqtt_sw_4L")

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!