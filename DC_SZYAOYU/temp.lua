function
    local str0 = ...
    if #str0 > 0 then
        if string.sub(str0:toHex(), 1, 4) == "FEFE" then   ----FE FE FE 68 10 18 00 00 40 40 92 00 81 16 90 1F 00 29 00 00 00 2C 29 00 00 00 2C 00 00 00 00 00 00 00 00 23 B5 16
            local ss = string.gsub(str0:toHex(), "FE", "")  ---- 68 10 18 00 00 40 40 92 00 81 16 90 1F 00 29 00 00 00 2C 29 00 00 00 2C 00 00 00 00 00 00 00 00 23 B5 16
            local kk0 = string.sub(ss, 5, 18) 
            local tmps0 = ""
            local tmplen0 = #kk0 / 2
            for i = tmplen0, 1, -1 do
                tmps0 = tmps0 .. string.sub(kk0, 2 * i - 1, 2 * i)
            end
            local meterno = tmps0
            local k1 = string.sub(ss, 29, 36)
            local tmps1 = ""
            local tmplen1 = #k1 / 2
            for i = tmplen1, 1, -1 do
                tmps1 = tmps1 .. string.sub(k1, 2 * i - 1, 2 * i)
            end
            local sn = misc.getImei()
            local tmps2 = string.gsub(tmps1, "^%z+", "")
            local tmps3 = tonumber(tmps2) * 10
            local meter_data = {
                DEVTYPE = "M3",
                GATEWAY = 1,
                SN = sn,
                METERNO = meterno,
                UPDATA = tmps3,
                FUNCCODE ="A2",
                PAYMODE = 1
            }
            str = json.encode(meter_data)
            return str, 1
        else
            return str0
        end
    end
end





function
    local str=...
    if string.sub(str,1,2) =="D3"  then     -----------D313000040409200A2
        if string.sub(str, 17, 18)=="A2" then
            local ttt = string.sub(str, 3,16)   -------13000040409200   下一步需要转成  
            local tmpdata = "6810"..ttt.."0103901F00"
            local tmps0=0x00
            local tmplen0 = #tmpdata/2
            for i=1,tmplen0 do
                tmps0=tmps0+tonumber(string.sub(tmpdata,2*i-1,2*i),16)
            end
            local vcode=pack.pack("b",tmps0)
            local str1=("FEFEFE"):fromHex()..(tmpdata):fromHex()..vcode..("16"):fromHex()
            return str1,1
        end
    else
    return str,1
    end
end