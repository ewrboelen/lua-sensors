--sleeping room control
scl=2
sda=1

shutterup=5
shutterdown=0
lighton=6 
lightoff=7

blinkpin=4

gpio.mode(shutterup,gpio.INPUT) --gpio.INT)
gpio.mode(shutterdown,gpio.INPUT)
gpio.mode(lighton,gpio.INPUT)
gpio.mode(lightoff,gpio.INPUT)

gpio.mode(blinkpin,gpio.OUTPUT)
gpio.write(blinkpin,gpio.HIGH)

lcount=3
sendsuccess=0
temp=0
humi=0
prevlighton=0
prevlightoff=0
prevshutup=0
prevshutdown=0
brightness=1

lightip="192.168.178.35"
shutterip="192.168.178.36"
servip="edsard.nl" 
if(mtype == nil)then
    mtype='sleeping'
end

function init_bus() --Set up the u8glib lib
     local sla = 0x3C
     i2c.setup(0, sda, scl, i2c.SLOW)
     bme280.setup()
     if(disp == nil) then
         disp = u8g2.ssd1306_i2c_128x32_univision(0,sla)
         disp:setFlipMode(1);
         --disp:setFont(u8g2.font_10x20_tf)
         disp:setFont(u8g2.font_6x10_tf)
         disp:drawStr(0, 16, "welkom1")
         disp:drawStr(0, 32, "welkom2")
         disp:sendBuffer()  
         print(mtype.." welcome" )
     else
        print(mtype.." display already on")
     end
     --disp:drawStr(10, 30, "welkom3")
     --disp:drawStr(10, 40, "welkom4")
     --disp:drawStr(10, 50, "welkom5")
     
     
end

function write_OLED(lbrightness) -- Write Display
    local myip=wifi.sta.getip()
    if(myip==nil)then myip="no ip" end
    print("T="..temp.." H="..humi.." C="..lcount.." B="..lbrightness)
    print("ip:"..myip.." stat:"..sendsuccess)
    --disp:firstPage()
    --repeat
    disp:clearBuffer()
    if(lbrightness==1) then
        -- disp:setFont(u8g2.font_6x10_tf)
         disp:drawStr(24, 12, "T="..temp.." H="..humi)
         if(lcount%2==0)then
             disp:drawStr(1, 30, "out temp "..lcount)
    --       disp:drawStr(1, 54, "del:"..doordelay.." "..pumpdelay.." s:"..sendsuccess.." c:"..lcount)
         else
           disp:drawStr(1, 30, "ip:"..myip)
         end
    end
    disp:sendBuffer()  
    brightness=0
end

function sendStatus(mhost,murl)
  print("connecting to "..mhost)
  conn = nil
  conn = net.createConnection(net.TCP, 0)
  conn:on("receive", function(conn, payloadout)
    if (string.find(payloadout, "200 OK")) then
        sendsuccess=1    
    end
    --local dpos = string.find(payloadout,"Date:")
    --print("time "..string.sub(payloadout,dpos+5,20)
    print(payloadout)
  end)
  conn:on("connection",
   function(conn, payload)
     local auth = file.getcontents('auth.txt')
     print("sending "..murl);
     conn:send('GET '..murl..' HTTP/1.0\r\n\Host: '..mhost..'\r\naccept: */*\r\nAuthorization: '..auth..'\r\n\r\n')end)
   
  conn:on("disconnection", function(conn, payload) print('Disconnected') end)
  conn:connect(80,mhost)
end

function checkLight()

    local newlight = gpio.read(lighton)
    if(newlight == 0 and newlight ~= prevlighton)then
        write_OLED(1)
        sendStatus(lightip,"/on")
        print ("light on event ")
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(400000)
        gpio.write(blinkpin,gpio.HIGH)
    end
    prevlighton = newlight

    newlight = gpio.read(lightoff)
    if(newlight == 0 and newlight ~= prevlightoff)then
        write_OLED(1)
        sendStatus(lightip,"/off")
        print ("light off event ")
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(400000)
        gpio.write(blinkpin,gpio.HIGH)
    end
    prevlightoff = newlight
end

function checkShutter()

    local newshut = gpio.read(shutterup)
    if(newshut == 0 and newshut ~= prevshutup)then
        write_OLED(1)
        sendStatus(shutterip,"/up")
        print ("shutter up event ")
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(400000)
        gpio.write(blinkpin,gpio.HIGH)
    end
    prevshutup = newshut

    newshut = gpio.read(shutterdown)
    if(newshut == 0 and newshut ~= prevshutdown)then
        write_OLED(1)
        sendStatus(shutterip,"/down")
        print ("shutter down event ")
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(400000)
        gpio.write(blinkpin,gpio.HIGH)
    end
    prevshutdown = newshut
end




function checkTemp()
    bme280.startreadout(0, function ()
        local T, P, H = bme280.read()
        if(T == nil or H ==nil) then
            print("temp read error")
            humi="ee" 
        else
            local Tsgn = (T < 0 and -1 or 1); T = Tsgn*T
            temp=string.format("%s%d.%02d", Tsgn<0 and "-" or "", T/100, T%100)
--            humi=string.format("%d.%03d%%", H/1000, H%1000)
            humi=string.format("%d", H/1000)
            print("temp: "..temp)
        end
    end)
end

--every 0.5 sec
tmr.create():alarm(200,tmr.ALARM_AUTO,function()

    checkShutter()

    checkLight()
    
end)


--every 10 seconds
tmr.create():alarm(10000,tmr.ALARM_AUTO,function()
    checkTemp()
    write_OLED(0)
    brightness=0
    lcount = lcount -1
    if (lcount == 2) then
    --readTempout()
    end
    if (lcount == 0) then
        sendStatus(servip,'/api/sens/sleeping?s=1&t='..temp..'&h='..humi)
        lcount = 90
    end
end)

--small server
srv=net.createServer(net.TCP,10)
srv:listen(80,function(conn)
    
    local function handlePaths(path)
        print(node.heap())
        print("path "..path)
        if(path=="/reset")then
            --print(" restarting ")
            node.restart()
        end
        
        if(path =="/")then
            buf="{\"sensorid\":\""..mtype.."\","
            if(bme280 ~= nil) then
              local T, P, H, QNH = bme280:read(0)
              buf = buf.."\"temp\":"..T.."\",hum:"..string.format("%d", H)
            else
              buf = buf.."\"temp\":n\",hum:n"
            end
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.0}"  
        end
        return buf
    end
    
    conn:on("receive", function(client,payload)
        _, _, method, path = string.find(string.sub(payload,0,128), "([A-Z]+) (.+) HTTP")
        if(path ~= nil and string.sub(path,0,1) == "/") then
            local buf="HTTP/1.1 200 OK\r\nConnection: close\r\nAccept: */*\r\n\r\n"
            buf = buf..handlePaths(path)
            --if(buf == nil)then
            -- end
            --print(buf)
            client:send(buf,function(sk)
                sk:close()
            end)
            buf = nil
        end
    end)
end)
-- server end 

init_bus()
