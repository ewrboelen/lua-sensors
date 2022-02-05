owpin=7
doorpin=5
ow.setup(owpin)
xpos=0
temp='n'
servip="edsard.nl" 
--resultcount=0
gpio.mode(doorpin,gpio.INPUT) 
doorstat=gpio.read(doorpin)

p = require('p1')
t = require('ds18b20')
if(mtype == nil)then
    mtype='power'
end

--uart
tmr.create():alarm(5*1000, tmr.ALARM_SINGLE, function() 
    displayTemp()
    tmr.create():alarm(10*1000, tmr.ALARM_SINGLE, function() 
        --print(temp.."s uart "..node.heap())
        uart.setup(0, 115200, 8, uart.PARITY_NONE, uart.STOPBITS_1, 1)
    end)
end) 

uart.on("data", '\r',function(data)
        --print(data)
        p:convert(data)
        if(p:isComplete()) then
            --resultcount=resultcount+1
            displaypow()
            readTemp(owpin)
        end
end, 0)

--door every 6 sec
tmr.create():alarm(6*1000,tmr.ALARM_AUTO,function()
    checkDoor()
end)

function checkDoor()
    local newstat = gpio.read(doorpin)
    if(doorstat ~= newstat) then
        local query = '/api/sens/'..mtype..'?s=1&e=door&doorstat='..newstat
        sendStatus(servip,query)
    end 
    doorstat = newstat
end

--temp
function readTemp(owpin)
    t:read_temp(function(ltemp)
         for addr, ltemp in pairs(ltemp) do
            temp = ltemp
         end
    end , owpin,t.C)
end

function displayTemp()
    if(disp == nil) then
      local scl=3
      local sda=2
      local sla = 0x3C
      i2c.setup(0, sda, scl, i2c.SLOW)
      disp = u8g2.ssd1306_i2c_128x64_noname(0,sla) --ssd1306_i2c_128x64_noname(0,sla)
      disp:setFlipMode(1);
    end
    disp:setFont(u8g2.font_fub20_tn)
    disp:drawStr(2, 50, string.sub(temp,0 , 4))
    disp:sendBuffer() 
end

--power
function displaypow()
    disp:clearBuffer()
    disp:setFont(u8g2.font_6x10_tr)
    disp:drawStr(2, 10,p:getTijd())--..'r'..resultcount )
    disp:drawStr(2, 20,"p "..p:getHuidig() )
    displayTemp() 
    xpos = xpos + 1
    if xpos == 50 then
        xpos = 2
    end
end

--send
--every 5 min, only if no result has been sent
tmr.create():alarm(5*60*1000, tmr.ALARM_AUTO, function() 
    sendPow()
end)

function sendPow()
    if (wifi.sta.getip() == nil) then
            print("no ip")
            wifi.sta.disconnect()
            tmr.delay(1500)
            wifi.sta.connect()
    end
    readTemp(owpin)
    -- oo calling wait 5sec before sending
    tmr.create():alarm(5*1000, tmr.ALARM_SINGLE, function() 
        local query = '/api/sens/'..mtype..'?s=1&temp='..temp
        query = query..p:getQuery()
        sendStatus(servip,query)
    end)

end

function sendStatus(mhost,murl)
    --print("cnct to "..mhost)
    conn = net.createConnection(net.TCP, 0)
    conn:on("receive", function(conn, payloadout)
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
            buf = buf.."\",temp"..i..":"..temp..","
            buf = buf.."\"doorstat\":"..doorstat..","
            buf = buf..p:getJson()
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.1}"  
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
readTemp(owpin)