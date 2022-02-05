--basement
doorpin=3
waterpin=4 --also status led...
lightpin=5

ledpin=6
pumppin=7

doordelay=0
pumpdelay=0

gpio.mode(doorpin,gpio.INPUT) --gpio.INT)
gpio.mode(waterpin,gpio.INPUT)
gpio.mode(lightpin,gpio.INPUT)

gpio.mode(ledpin,gpio.OUTPUT)
gpio.write(ledpin,gpio.LOW)
gpio.mode(pumppin,gpio.OUTPUT)
gpio.write(pumppin,gpio.LOW)

doorstat = gpio.read(doorpin)
waterstat = gpio.read(waterpin)
lightstat = gpio.read(lightpin)

humi=""
temp=""
lcount=5
sendsuccess=0

if(mtype == nil)then
    mtype='basement'
end

function init_bus() --Set up the u8glib lib
     bme280.setup()
     if(disp ~= nil) then
         local scl=1
         local sda=2
         local sla = 0x3C
         i2c.setup(0, sda, scl, i2c.SLOW)
         disp = u8g2.ssd1306_i2c_128x64_noname(0,sla)
     end
     disp:setFont(u8g2.font_6x10_tr)
     disp:drawStr(10, 30, "welkom")
     disp:sendBuffer()  
end

--temp
function checkTemp()
    bme280.startreadout(0, function ()
        local T, P, H = bme280.read()
        if(T == nil) then
            print("temp read error")
            humi="ee" 
        else
            local Tsgn =  (T < 0 and -1 or 1); T = Tsgn*T
            temp=string.format("%s%d.%02d", Tsgn<0 and "-" or "", T/100, T%100)
            humi=string.format("%d", H/1000)
        end
    end)
end

function displayStatus() 
    local myip=wifi.sta.getip()
    if(myip==nil)then myip="no ip" end
    --print("T="..temp.." H="..humi.." C="..lcount)
    --print("door:"..doorstat.." water:"..waterstat.." light"..lightstat.."delay:"..doordelay..pumpdelay)
    --print("ip:"..myip.." stat:"..sendsuccess)
     disp:clearBuffer()
     disp:setFont(u8g2.font_9x15_tr)
     disp:drawStr(1, 20, "T="..temp.." H="..humi)
     disp:setFont(u8g2.font_6x10_tr)
     disp:drawStr(1, 39, "door "..doorstat.." water "..waterstat.." li "..lightstat)
     if(lcount%2==0)then
       disp:drawStr(1, 54, "del:"..doordelay.." "..pumpdelay.." s:"..sendsuccess.." c:"..lcount)
     else
       disp:drawStr(1, 54, "ip:"..myip)
     end
     disp:sendBuffer()  
end

--send
tmr.create():alarm(15*60*1000, tmr.ALARM_AUTO, function() 
    sendBasement()
end)

function sendBasement()
    if (wifi.sta.getip() == nil) then
            print("no ip")
            wifi.sta.disconnect()
            tmr.delay(1500)
            wifi.sta.connect()
    end
    checkTemp()
    -- oo calling wait 5sec before sending
    tmr.create():alarm(5*1000, tmr.ALARM_SINGLE, function() 
        local query = '/api/sens/'..mtype..'?s=1&temp='..temp..'&humi='..humi
        query = query..'&door='..doorstat..'&water='..waterstat..'&light='..lightstat
        sendStatus(servip,query)
    end)

end

function sendStatus(mhost,murl)
  print("cnct to "..mhost)
  conn = nil
  conn = net.createConnection(net.TCP, 0)
  conn:on("receive", function(conn, payloadout)
    --local dpos = string.find(payloadout,"Date:")
    --print("time "..dpos.." "..string.sub(payloadout,dpos+5,dpos+27))
    print(payloadout)
  end)
  conn:on("connection",
   function(conn, payload)
     print("s "..murl);
     local auth = file.getcontents('token.txt')
     conn:send('GET '..murl..' HTTP/1.0\r\n\Host: '..mhost..'\r\naccept: */*\r\nAuthorization: '..auth..'\r\n\r\n')end)
  conn:on("disconnection", function(conn, payload) print('Disconn') end)
  conn:connect(80,mhost)
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
            buf="{\"sensorid\":\""..mtype.."\",\"location1\":\"out\","
            buf = buf.."\",temp"..i..":"..temp.."\",\"humidity\":"..humi
            buf = buf.."\"doorstat\":"..doorstat.."\","
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.0}"  
        end
        return buf
    end
    
    conn:on("receive", function(client,payload)
        --print("received "..payload)
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
