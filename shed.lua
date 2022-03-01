--shed
scl=2
sda=1

lightpin=6
pumppin=7
doorpin=3

buttonlightpin=0
buttonpumppin=5

gpio.mode(lightpin,gpio.OUTPUT)
gpio.write(lightpin,gpio.HIGH)
gpio.mode(pumppin,gpio.OUTPUT)
gpio.write(pumppin,gpio.HIGH)

gpio.mode(doorpin,gpio.INPUT) 
gpio.mode(buttonlightpin,gpio.INPUT,gpio.PULLUP) 
gpio.mode(buttonpumppin,gpio.INPUT,gpio.PULLUP) 
-- door event will turn light on timer
doorstat = gpio.read(doorpin)
lightstat = gpio.read(buttonlightpin)
lighttimer = 0
--pump is toggle
pumpstat = gpio.read(buttonpumppin)
pumptoggle = 0

i2c.setup(0, sda, scl, i2c.SLOW)
sbme280 = require('bme280').setup(0)
moist = -1
servip="edsard.nl" 

print(mtype)

function checkDoor()
    local newstat = gpio.read(doorpin)
    --print ("d "..newstat.." "..doorstat)
    if(doorstat ~= newstat) then
        print ("door "..lighttimer)
        gpio.write(lightpin,gpio.LOW)
        lighttimer = 60 
        sendStatus(servip,'/api/sens/shed?s=1&e=door&doorstat='..newstat)
    end 
    doorstat = newstat
end

function checkPump()
    local newstat = gpio.read(buttonpumppin)
    --print ("p "..newstat.." "..pumpstat)
    if(newstat == 0 and pumpstat ~= newstat) then
        print ("pump "..pumptoggle)
         if (pumptoggle == 0)then
            gpio.write(pumppin,gpio.LOW)
            pumptoggle = 1
         else
            gpio.write(pumppin,gpio.HIGH)
            pumptoggle = 0
        end
        sendStatus(servip,'/api/sens/shed?s=1&e=pump&pumpstat='..pumptoggle)
    end 
    pumpstat = newstat
end

function checkLight()
    local newstat = gpio.read(buttonlightpin)
    --print ("l "..newstat.." "..lightstat)
    if(newstat == 0 and lightstat ~= newstat) then
       print ("light "..lighttimer)
      if(lighttimer == -1)then
            --turn light off
            gpio.write(lightpin,gpio.HIGH)
            lighttimer = 0
       else
            gpio.write(lightpin,gpio.LOW)
            lighttimer = -1
       end
       sendStatus(servip,'/api/sens/shed?s=1&e=light&lightstat='..lighttimer)
    end 
    lightstat = newstat
end

function checkLightTimer()
    if(lighttimer > 0) then
        lighttimer=lighttimer-1
    end
    if(lighttimer == 1) then
        --light off
        gpio.write(lightpin,gpio.HIGH)
    end
end

function checkTemp()
    if sbme280 ~= nil then
        local T, P, H, QNH = sbme280:read(0)
        if(T == nil or H ==nil) then
            print("temp err")
        else
            humi=string.format("%d", H)
            print("temp: "..T.." h "..humi)
        end
    
        local moist = adc.read(0)
        sendStatus(servip,'/api/sens/shed?s=1&temp='..T..'&hum='..humi..'&moist='..moist..'&doorstat='..doorstat..'&lightstat='..lighttimer..'&pumpstat='..pumptoggle)
   else
     print("no bme")
     sendStatus(servip,'/api/sens/shed?s=1&moist='..moist..'&doorstat='..doorstat..'&lightstat='..lighttimer..'&pumpstat='..pumptoggle)
   end
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
     local auth = file.getcontents('auth.txt')
     conn:send('GET '..murl..' HTTP/1.0\r\n\Host: '..mhost..'\r\naccept: */*\r\nAuthorization: '..auth..'\r\n\r\n')end)
  conn:on("disconnection", function(conn, payload) print('Disconn') end)
  conn:connect(80,mhost)
end

--every 0.5 sec
tmr.create():alarm(600,tmr.ALARM_AUTO,function()
 
    checkDoor()
    checkPump()              
    checkLight()
    checkLightTimer()
    
end)

tmr.create():alarm(20*1000,tmr.ALARM_SINGLE,function()
    checkTemp()
end)

--every 15 minutes
tmr.create():alarm(900*1000,tmr.ALARM_AUTO,function()
    checkTemp()
end)

--for k,v in pairs(_G) do print(k,v) end

print(node.heap())
--small server
srv=net.createServer(net.TCP,10)
srv:listen(80,function(conn)
    
    local function handlePaths(path)
        print(node.heap())
        print("path "..path)
        local buf = ""
        if(path=="/reset")then
            --print(" restarting ")
            node.restart()
        end
        if(path=="/lighton")then
            --print("light on")
            gpio.write(lightpin,gpio.LOW)
            lighttimer = -1
            updateLight=1
        end
        if(path=="/lightoff")then
            --print("light off")
            gpio.write(lightpin,gpio.HIGH)
            lighttimer = 0
            updateLight=1
        end
        if(path=="/pumpon")then
            --print("pump on")
            gpio.write(pumppin,gpio.LOW)
            pumptoggle = 1
            updatepump=1
        end
        if(path=="/pumpoff")then
            --print("pump off")
            gpio.write(pumppin,gpio.HIGH)
            pumptoggle = 0
            updatepump=1
        end

        if(path =="/")then
            local moist = adc.read(0)
            buf="{\"sensorid\":\"shed\","
            if(sbme280 ~= nil) then
              local T, P, H, QNH = sbme280:read(0)
              buf = buf.."\"temp\":"..T.."\",hum:"..string.format("%d", H)
            else
              buf = buf.."\"temp\":n\",hum:n"
            end
            buf = buf.."\",moist:"..moist.."\",".."\"doorstat\":"..doorstat.."\",lightstat:"..lighttimer.."\",pumpstat:"..pumptoggle.."\","
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.1}"  
        end
        return buf
    end
    
    conn:on("receive", function(client,payload)
        --print("received "..payload)
        _, _, method, path = string.find(string.sub(payload,0,128), "([A-Z]+) (.+) HTTP")
        if(path ~= nil and string.sub(path,0,1) == "/") then
            --writingFile=nil status line and header lines
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

