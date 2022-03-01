--kitchen 1.1
local t = require('ds18b20')
scl=2
sda=1
owpin=3
doorpin=5
gpio.mode(doorpin,gpio.INPUT) 

servip="edsard.nl" 
doorstat=gpio.read(doorpin)
dispNr=1 -- which temp to display
xpos=0
writingFile=nil
if(mtype == nil)then
    mtype='kitchen'
end
local temps = {}  

function init_bus() --Set up the u8glib lib
     local sla = 0x3C
     i2c.setup(0, sda, scl, i2c.SLOW)
     --bme280.setup()
     if(disp == nil) then
         disp = u8g2.ssd1306_i2c_128x64_noname(0,sla)
         --disp:setFlipMode(1);
         --disp:setFont(u8g2.font_10x20_tf)
         print(mtype)
     else
        print("display yet on")
     end
     disp:setFont(u8g2.font_9x15_tr)
     disp:drawStr(10, 10, mtype)
     disp:drawStr(10, 32, "welkom1")
     disp:sendBuffer()

     t:read_temp(function(ltemps) 
     temps = ltemps
        end , owpin)
end

function createTempQuery(query)
  local i =1
  for addr, temp in pairs(temps) do
    --print(string.format("Sensor %s: %s °C", ('%02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X'):format(addr:byte(1,8)), temp))
    query = query..'&temp'..i..'='..temp
    i=i+1
  end
  if i == 1 then
    print("no temps")
  end
  return query
end

function sendTemp()
  local query = '/api/sens/kitchen?s=1&doorstat='..doorstat
  query = createTempQuery(query)
  sendStatus(servip,query)
  -- Module can be released when it is no longer needed
  --t = nil
  --package.loaded["ds18b20"]=nil
end

function showtemp()
  local i=1
  local t1='n   '
  local t2='n   '
  
  for addr, temp in pairs(temps) do
     if i==1 then
        t1 = temp
     end
     if i==2 then
        t2 = temp
     end
     print(i..' '..temp)
     i=i+1
  end

  disp:clearBuffer()
  disp:setFont(u8g2.font_9x15_tr)
  disp:drawStr(xpos, 15, "in "..string.sub(t2,0 , 4)) 
  disp:setFont(u8g2.font_fub14_tr)
  disp:drawStr(xpos, 40, "out ")     
  disp:setFont(u8g2.font_fub20_tn)
  disp:drawStr(xpos+36, 50, string.sub(t1,0 , 4)) 
  disp:sendBuffer()
  
  xpos=xpos+1
  if(xpos == 15)then
    xpos = 0
  end
end

function checkDoor()
    local newstat = gpio.read(doorpin)
    if(doorstat ~= newstat) then
        print ("door")
        disp:setFont(u8g2.font_fub14_tr)
        disp:drawStr(xpos+50, 15, " door "..newstat) 
        disp:sendBuffer()
        local query = '/api/sens/kitchen?s=1&e=door&doorstat='..newstat
        query = createTempQuery(query)
        sendStatus(servip,query)
    end 
    doorstat = newstat
end

function sendStatus(mhost,murl)
  print("cnct to "..mhost)
  conn = nil
  conn = net.createConnection(net.TCP, 0)
  conn:on("receive", function(conn, payloadout)
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

tmr.create():alarm(15*1000,tmr.ALARM_SINGLE,function()
    sendTemp()
end)

--every 15 minutes send to server
tmr.create():alarm(900*1000,tmr.ALARM_AUTO,function()
    sendTemp()
end)

--every 30 sec show temp
tmr.create():alarm(30*1000,tmr.ALARM_AUTO,function()
    t:read_temp(function(ltemps)
        temps = ltemps
    end , owpin)
    showtemp()
end)

--every 3 sec
tmr.create():alarm(5*1000,tmr.ALARM_AUTO,function()
    showtemp()
    checkDoor()
end)

--small server 
srv=net.createServer(net.TCP,10)
srv:listen(80,function(conn)
    
    local function handlePaths(path)
        print("path "..path)
        if(path=="/reset")then
            --print(" restarting ")
            node.restart()
        end

        if(path =="/")then
            buf="HTTP/1.1 200 OK\r\nConnection: close\r\nAccept: */*\r\n\r\n"
            buf=buf.."{\"sensorid\":\""..mtype.."\",\"location1\":\"out\",\"location2\":\"in\","
            local i=1
            for addr,temp in pairs(temps) do
                buf = buf.."\",temp"..i..":"..temp.."\","
                buf = buf.."\",addr"..i..":"..string.format("%s",('%02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X '):format(addr:byte(1,8))).."\","
                i=i+1
            end
            buf = buf.."\"doorstat\":"..doorstat.."\","
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.1}"  
        end
          
        if(path=="/upload")then
            print("got file")
            --print("received "..payload)
            buf="HTTP/1.1 100 Continue\r\nContnue\r\n\r\n"
        end
        return buf
    end
    
    conn:on("receive", function(client,payload)
        --print("received "..payload)
        _, _, method, path = string.find(string.sub(payload,0,128), "([A-Z]+) (.+) HTTP")
        if(path ~= nil and string.sub(path,0,1) == "/") then
            --writingFile=nil
            local buf = handlePaths(path)
            --if(buf == nil)then
            -- end
            --print(buf)
            client:send(buf,function(sk)
                sk:close()
            end)
           else
           --curl -i -H "Expect:" -F "file=@/home/ed/hobby/roof.lua" 192.168.178.69/upload
            print("_file "..tostring(writingFile))
            if (writingFile ~= nil) then
                writefile(filename,"a+",payload)
            else
                print("got "..string.sub(payload,0,128))
                local point=string.find(payload, "filename=[^C]+")
                pend=string.find(payload, "Type",point)
                filename = string.sub(payload,point+10,pend-12)
                if(string.find(filename,".lua") ~= nil)then
                    print("begin write to file "..filename)
                    writefile("_"..filename,"w+",string.sub(payload, pend+30))
                    writingFile=true
                    print("done "..tostring(writingFile))
                    --dofile(filename)
                end
            end
        end
    end)
end)
-- server end 

init_bus()
