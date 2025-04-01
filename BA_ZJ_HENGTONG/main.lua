PROJECT = "M-CB-780"
VERSION = "1.0.2"
----VERSION = "2.0.0"    ------------------- 深圳测试客户用户 mqtt_DC_SZ
PRODUCT_KEY = "m7dHQUYd4qHO3zD1JgWfjDZr5ToiHQMD" ----------【浙江恒通】光电485电池无阀

-- sys库是标配
_G.sys = require("sys")
fskv.init()
mobile.flymode(0,false)

libnet = require "libnet"
libfota = require "libfota"


function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        rtos.reboot()
    end
end

libfota.request(fota_cb)
sys.timerLoopStart(libfota.request, 3600000, fota_cb)
require("mqtt_BA_HT")     ------【浙江恒通】光电485电池无阀



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!