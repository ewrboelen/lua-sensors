--shutter
upbutton=5 
downbutton=6

lighton=7
lightoff=0

relaypinup=2
relaypindown=3
blinkpin=4

gpio.mode(upbutton,gpio.INPUT) --gpio.INT)
gpio.mode(downbutton,gpio.INPUT)
gpio.mode(lighton,gpio.INPUT)
gpio.mode(lightoff,gpio.INPUT)

gpio.mode(relaypinup,gpio.OUTPUT)
gpio.write(relaypinup,gpio.HIGH)
gpio.mode(relaypindown,gpio.OUTPUT)
gpio.write(relaypindown,gpio.HIGH)

gpio.mode(blinkpin,gpio.OUTPUT)
gpio.write(blinkpin,gpio.HIGH)

relaystat = 0
shutterdelay=0
maxdelay=60
statusIsSent = 0
prevlighton = 1
prevlightoff = 1

servip="edsard.nl" 
lightip="192.168.188.50"
if(mtype == nil)then
    mtype='shutter'
end

function sendStatus(mhost,murl)
  print("to "..mhost)
  conn = nil
  conn = net.createConnection(net.TCP, 0)
  conn:on("receive", function(conn, payloadout)
    if (string.find(payloadout, "200 OK")) then
        print("ok") 
    else
        print(payloadout)
    end
  end)
  conn:on("connection",function(conn, payload)
     local auth = file.getcontents('auth.txt')
     print("sending "..murl);
     conn:send('GET '..murl..' HTTP/1.0\r\n\Host: '..mhost..'\r\naccept: */*\r\nAuthorization: '..auth..'\r\n\r\n')
  end)
  conn:on("disconnection", function(conn, payload) print('Disconn') end)
  conn:connect(80,mhost)
end

function checkShutter()

    relaystat = gpio.read(upbutton)
    if(relaystat == 0) then
        gpio.write(relaypindown,gpio.HIGH)
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(500000)
        gpio.write(relaypinup,gpio.LOW)
        gpio.write(blinkpin,gpio.HIGH)
        shutterdelay = maxdelay
        print ("shutter up e "..shutterdelay)
        shutterstat = "up";
    end

    relaystat = gpio.read(downbutton)
    if(relaystat == 0) then
        gpio.write(relaypinup,gpio.HIGH)
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(500000)
        gpio.write(relaypindown,gpio.LOW)
        gpio.write(blinkpin,gpio.HIGH)
        shutterdelay = maxdelay
        print ("shutter down e "..shutterdelay)
        shutterstat = "down";
    end
    
    if(shutterdelay >= 1) then
        shutterdelay = shutterdelay - 1
        print ("shutter delay"..shutterdelay)
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(10000)
        gpio.write(blinkpin,gpio.HIGH)
        if(shutterdelay ==1) then
          gpio.write(relaypinup,gpio.HIGH)
          gpio.write(relaypindown,gpio.HIGH)
        end
    end

end

function shutterup()
   --make sure down is off
   gpio.write(relaypindown,gpio.HIGH)
   SendHTML(sck, 1) 
   gpio.write(blinkpin,gpio.LOW)
    tmr.delay(400000)
    gpio.write(blinkpin,gpio.HIGH)
   gpio.write(relaypinup,gpio.LOW)
   shutterdelay = maxdelay
   shutterstat= "up";
end

function shutterdown()
    gpio.write(relaypinup,gpio.HIGH)
   SendHTML(sck, 2)
    gpio.write(blinkpin,gpio.LOW)
    tmr.delay(400000)
    gpio.write(blinkpin,gpio.HIGH)
   gpio.write(relaypindown,gpio.LOW)
   shutterdelay = maxdelay
   shutterstat= "down";
end

function checkLight()
    local newlight = gpio.read(lighton)
    if(newlight == 0 and newlight ~= prevlighton)then
        sendStatus(lightip,"/on")
        print ("light on event ")
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(400000)
        gpio.write(blinkpin,gpio.HIGH)
    end
    prevlighton = newlight

    newlight = gpio.read(lightoff)
    if(newlight == 0 and newlight ~= prevlightoff)then
        sendStatus(lightip,"/off")
        print ("light off event ")
        gpio.write(blinkpin,gpio.LOW)
        tmr.delay(400000)
        gpio.write(blinkpin,gpio.HIGH)
    end
    prevlightoff = newlight
end

--every 0.5 sec
tmr.create():alarm(500,tmr.ALARM_AUTO,function()

    checkShutter()

    checkLight()
    
end)

--small server
srv=net.createServer(net.TCP,10)
srv:listen(80,function(conn)
    
    local function handlePaths(path)
        print("path "..path)
        if(path=="/reset")then
            node.restart()
        end
          
        if(path=="/up")then
            shutterup()
        end
          
        if(path=="/down")then
            shutterdown()
        end
        
        if(path =="/")then
            ret="{\"sensorid\":\""..mtype.."\","
            ret = ret.."\"shutter\":\""..shutterstat.."\","
            ret = ret.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.0}"  
        end
        return ret
    end
    
    conn:on("receive", function(client,payload)
        _, _, method, path = string.find(string.sub(payload,0,128), "([A-Z]+) (.+) HTTP")
        if(path ~= nil and string.sub(path,0,1) == "/") then
            local buf="HTTP/1.1 200 OK\r\nConnection: close\r\nAccept: */*\r\n\r\n"
            buf = buf..handlePaths(path)
            client:send(buf,function(sk)
                sk:close()
            end)
            buf = nil
        end
    end)
end)
-- server end 
