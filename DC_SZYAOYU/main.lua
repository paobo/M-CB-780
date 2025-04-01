PROJECT = "M-CB-780"
VERSION = "2.0.5"
PRODUCT_KEY = "emus4VDXBdNFLPOh9soTnr4mBuI6Z5dc"   --------- 深圳测试客户用2.0.4
---PRODUCT_KEY = "ydFJ6jsLg8HNSPe1CnVWUCjrx87LL0qD"   ---------深圳测试客户【山科表头】2.0.4

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
---require("mqtt_DC_SW_SZ4L")  ------深圳测试客户用
---require("mqtt_DC_SZ202405")  ------深圳测试客户用
---require("mqtt_DC_SZ_shanke")  ------深圳测试客户用
---require("mqtt_DC_SW")   ------【公司演示】光电485有源带阀
---require("mqtt_BA")
---require("mqtt_BA_HT")     ------【浙江恒通】光电485电池无阀
---require("mqtt_DC_SZ")
require("mqtt_DC_SZSW01")
----_G.sysplus = require("sysplus")


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!