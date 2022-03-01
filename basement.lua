--basement
doorpin=3
waterpin=4 --status led
lightpin=5

ledpin=6
pumppin=7

gpio.mode(doorpin,gpio.INPUT)
gpio.mode(waterpin,gpio.INPUT)
gpio.mode(lightpin,gpio.INPUT)

gpio.mode(ledpin,gpio.OUTPUT)
gpio.write(ledpin,gpio.LOW)
gpio.mode(pumppin,gpio.OUTPUT)
gpio.write(pumppin,gpio.LOW)

local base = {
humi=-1,
temp=-1,
lcount=0,
doorstat=1,
waterstat=1,
lightstat=1,
pumpdelay=0,
doordelay=0  
}
disp=nil
base.doorstat = gpio.read(doorpin)
base.waterstat = gpio.read(waterpin)
base.lightstat = gpio.read(lightpin)


if(mtype == nil)then
    mtype='basement'
end

function init_bus() --Set up the u8glib lib
     if(disp == nil) then
         local scl=1
         local sda=2
         local sla = 0x3C
         i2c.setup(0, sda, scl, i2c.SLOW)
         disp = u8g2.ssd1306_i2c_128x64_noname(0,sla)
         --s = require('bme280').setup(0)
     end
     disp:setFont(u8g2.font_6x10_tr)
     disp:drawStr(10, 30, "welkom")
     disp:sendBuffer()  
end

function checkDoor()

    base.doorstat = gpio.read(doorpin)
    if(base.doorstat == 0) then
        gpio.write(ledpin,gpio.HIGH)
        base.doordelay = 300
    else
        --grace time
        if(base.doordelay >= 1) then
            base.doordelay = base.doordelay - 1
            print ("door delay"..base.doordelay)
            if(base.doordelay ==1) then
              gpio.write(ledpin,gpio.LOW)
            end
        end
    end

end

function checkWater()

    base.waterstat = gpio.read(waterpin)
    if(base.waterstat == 0) then
        gpio.write(pumppin,gpio.HIGH)
        if(statusIsSent == 0) then
              conn = net.createConnection(net.TCP, 0)
              local query = '/api/sens/'..mtype..'?s=1&e=water'
              local s = require('lnet').sendstatus(conn,'edsard.nl',query)
              statusIsSent=1
        end
        base.pumpdelay = 150
        print ("Water event "..base.pumpdelay)
    else
        if(base.pumpdelay >= 1) then
            base.pumpdelay = base.pumpdelay - 1
            print ("pump delay"..base.pumpdelay)
            if(base.pumpdelay ==1) then
              statusIsSent=0
              gpio.write(pumppin,gpio.LOW)
            end
        end
    end

end

function checkTemp()
    local s = require('bme280').setup(0)
    if(s == nil) then
        print("temp r error")
        base.temp="ee"
        base.humi="ee" 
    else
        local T, P, H = s:read()
        if T ~= nil then
          base.temp=T
          base.humi=H
          print(base.temp)
       else
          base.temp=-1
       end
    end
end

function displayStatus() 
    local myip=wifi.sta.getip()
    if(myip==nil)then myip="no ip" end
    disp:clearBuffer()
     disp:setFont(u8g2.font_9x15_tr)
     disp:drawStr(2, 20, "T="..base.temp.." H="..base.humi)
     disp:setFont(u8g2.font_6x10_tr)
     disp:drawStr(2, 39, "door "..base.doorstat.." water "..base.waterstat.." li "..base.lightstat)
     if(base.lcount%2==0)then
       disp:drawStr(2, 54, "del:"..base.doordelay.." "..base.pumpdelay.." c:"..base.lcount)
     else
       disp:drawStr(2, 54, "ip:"..myip)
     end
     disp:sendBuffer()  
end

--0.5 sec
tmr.create():alarm(500,tmr.ALARM_AUTO,function()
    checkDoor()
    checkWater()
end)

tmr.create():alarm(15*1000, tmr.ALARM_AUTO, function() 
    displayStatus()
    if(base.lcount==0)then
    sendBasement()
    base.lcount=60
    end
    base.lcount=base.lcount-1
end)

function sendBasement()
    checkTemp()
    local ln = require('lnet')
    tmr.create():alarm(5*1000, tmr.ALARM_SINGLE, function() 
        conn = net.createConnection(net.TCP, 0)
        local query = '/api/sens/'..mtype..'?s=1&temp='..base.temp..'&humi='..base.humi
        query=query..'&door='..base.doorstat..'&water='..base.waterstat..'&light='..base.lightstat
        ln.sendstatus(conn,'edsard.nl',query)
    end)
end

--small server 
srv=net.createServer(net.TCP,10)
srv:listen(80,function(conn)
    
    local function handlePaths(path)
        print("path "..path)
        if(path=="/reset")then
            node.restart()
        end
        local i=1
        if(path =="/")then
            buf="{\"sensorid\":\""..mtype.."\",temp"..i..":"..base.temp.."\",\"humidity\":"..base.humi
            buf = buf.."\"doorstat\":"..base.doorstat.."\"water\":"..base.waterstat.."\","
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.0}"  
        end
        return buf
    end
    
    conn:on("receive", function(client,payload)
        _, _, method, path = string.find(string.sub(payload,0,128), "([A-Z]+) (.+) HTTP")
        if(path ~= nil and string.sub(path,0,1) == "/") then
            buf="HTTP/1.1 200 OK\r\nConnection: close\r\nAccept: */*\r\n\r\n"
            buf = buf..handlePaths(path)
            --print(buf)
            client:send(buf,function(sk)
                sk:close()
            end)
            buf = nil
        end
    end)
end)
-- server end 

print(mtype) 
init_bus()
checkTemp()
