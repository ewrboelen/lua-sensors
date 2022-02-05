relaypin=3
gpio.mode(relaypin,gpio.OUTPUT)
--dhtpin = 7 i2c is used
owpin=7

tempup=5
tempdown=0
gpio.mode(tempup,gpio.INPUT) --gpio.INT)
gpio.mode(tempdown,gpio.INPUT)
t = require('ds18b20')
if(mtype == nil)then
    mtype='living'
end
xpos=2
servip="edsard.nl" 
tempupstat = gpio.read(tempup)
tempdownstat = gpio.read(tempdown)
temp=0
temp1=0
humi=-1
tempsetting=file.getcontents('settemp.dat')
tempsetting=tonumber(tempsetting)
relaycount=0
relaytime=0
--writingFile=nil

--every  sec
tmr.create():alarm(1000,tmr.ALARM_AUTO,function()
    checkButtons()
end)

--20 sec after boot
tmr.create():alarm(20*1000,tmr.ALARM_SINGLE,function()
    checkTemp()
    sendTemp()
end)

--every minute
tmr.create():alarm(60*1000,tmr.ALARM_AUTO,function()
    checkTemp()
    checkRelay()
end) 

--every 15 minutes
tmr.create():alarm(15*60*1000,tmr.ALARM_AUTO,function()
    sendTemp()
end)

function checkButtons()
    local newtemp = gpio.read(tempup)
    local showSetting = false
    if(newtemp ~= tempupstat)then
        tempsetting=tempsetting+0.25
        print ("t up ev "..tempsetting)
        showSetting = true
    end
    tempupstat = newtemp

    newtemp = gpio.read(tempdown)
    if(newtemp ~= tempdownstat)then
        print ("t down e "..tempsetting)
        tempsetting=tempsetting-0.25
        showSetting = true
    end
    tempdownstat = newtemp
    
    if(showSetting == true) then
        disp:clearBuffer()
        disp:setFont(u8g2.font_9x15_tr)
        disp:drawStr(2, 15, string.sub(temp1,0 , 4))--..'r'..resultcount )
        disp:setFont(u8g2.font_fub20_tn)
        disp:drawStr(2, 50,"set "..tempsetting  )
        disp:sendBuffer() 
        file.putcontents('settemp.dat',tempsetting)
    end
end

function checkTemp()
    if(disp == nil) then
      local scl=1
      local sda=2
      local sla = 0x3C
      i2c.setup(0, sda, scl, i2c.SLOW)
      disp = u8g2.ssd1306_i2c_128x64_noname(0,sla) --ssd1306_i2c_128x64_noname(0,sla)
      disp:setFlipMode(1)
      am2320.setup()
    end
    --ow
    t:read_temp(function(ltemp)
         for addr, ltemp in pairs(ltemp) do
            temp1 = ltemp
         end
    end , owpin,t.C)
    -- ow end
    local rh =0
    local t=0 
    rh, t = am2320.read()
    temp = t/10
    humi= math.floor(rh/10)
    print(temp..' '..temp1..' '..humi..'% '..tempsetting)
    displayTemp()
end

function checkRelay()
    if(relaycount > 0)then
        gpio.write(relaypin,gpio.HIGH)
        relaytime = relaytime +1
        relaycount = relaycount -1
        print ("t relay ON "..relaycount)
    else
        gpio.write(relaypin,gpio.LOW)
        if(temp1 > 5 and temp1 < tempsetting) then
            relaycount = math.floor((tempsetting - temp1) * 5)
            print ("t relay ev "..tempsetting.." cnt "..relaycount)
        end
    end
end

function displayTemp()
    disp:clearBuffer()
    disp:setFont(u8g2.font_6x10_tr)
    disp:drawStr(xpos+60, 7,"rt ".. relaytime)
    disp:setFont(u8g2.font_9x15_tr)
    disp:drawStr(xpos, 10, "s "..tempsetting)
    disp:drawStr(xpos+2, 60, string.sub(temp,0,4).."c")
    disp:drawStr(xpos+60, 60, humi.."%")
    disp:setFont(u8g2.font_fub20_tn)
    disp:drawStr(xpos+2, 40, string.sub(temp1,0 , 4))
    disp:sendBuffer() 
    xpos=xpos + 1
    if(xpos==40)then
        xpos=2
    end
end

function sendTemp()
    if (wifi.sta.getip() == nil) then
            print("no ip")
            wifi.sta.disconnect()
            tmr.delay(1500)
            wifi.sta.connect()
    end
    sendStatus(servip,'/api/sens/'..mtype..'?s=1&temp1='..temp..'&temp2='..temp1..'&hum='..humi..'&tempsetting='..tempsetting..'&relaytime='..relaytime)
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

--small server 
srv=net.createServer(net.TCP,10)
srv:listen(80,function(conn)
    
    local function handlePaths(path)
        print("path "..path)
        if(path=="/reset")then
            node.restart()
        end
        local i=1
        local buf = ''
        if(path =="/")then
            buf="HTTP/1.1 200 OK\r\nConnection: close\r\nAccept: */*\r\n\r\n"
            buf = buf.."{\"sensorid\":\""..mtype.."\",\"location1\":\"in\","
            buf = buf.."\",temp"..i..":"..temp1..",temp2:"..temp..",\"humidity\":"..humi..","
            buf = buf.."\"tempsetting\":"..tempsetting..",\"relaytime\":"..relaycount..","
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.0}"  
        end
        --if(path=="/upload")then
        --    print("got f")
            --print("received "..payload)
        --    buf="HTTP/1.1 100 Continue\r\nContnue\r\n\r\n"
        --end
        return buf
    end

    local function handleVars(vars)
        --print("vars"..vars)
        local _GET = {}
        for k, v in string.gmatch(vars, "(%w+)=(%w+)&*") do
            _GET[k] = v
        end
        if(_GET.temp ~= nil and tonumber(_GET.temp) >= 0)then
            tempsetting = tonumber(_GET.temp)
            if(tempsetting > 100) then
                tempsetting = tempsetting/10
            end
            print("new t: "..tempsetting)
            file.putcontents('settemp.dat',tempsetting)
        end
    end
    
    conn:on("receive", function(client,payload)
        --print("received "..payload)
        local _, _, method, path, vars = string.find(payload, "([A-Z]+) (.+)?(.+) HTTP");
        if(method == nil)then
                _, _, method, path = string.find(payload, "([A-Z]+) (.+) HTTP");
        end
        if (vars ~= nil)then
            handleVars(vars)
            local buf="HTTP/1.1 200 OK\r\nConnection: close"
            client:send(buf,function(sk)
                sk:close()
            end)
        end
        if(path ~= nil and string.sub(path,0,1) == "/") then
            --local buf = handlePaths(path)
            --print(buf)
            client:send(handlePaths(path),function(sk)
                sk:close()
            end)
            --buf = nil
        --    writingFile = nil
        --else
           --if(writingFile == nil) then
           --     print("got "..string.sub(payload,0,128))
           --     local point=string.find(payload, "filename=[^C]+")
           --     local pend=string.find(payload, "Type",point)
           --     local filename = string.sub(payload,point+10,pend-12)
           --     print("wfile "..filename)
           --     writefile("_"..filename,"w+",string.sub(payload, pend+30))
           --     writingFile=true
           --     print("done "..tostring(writingFile))
                --dofile(filename)
           --else
           --     writefile(filename,"a+",payload)
           --end
        end
    end)
end)
-- server end 

print(mtype) 
checkTemp()
