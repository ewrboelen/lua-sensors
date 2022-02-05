owpin=3
temps={}--array
payloadFound = false
t = require('ds18b20')
if(mtype == nil)then
    mtype='roof'
end

tmr.create():alarm(20*1000, tmr.ALARM_SINGLE, function() 
    
  readTemp(owpin)
  
  tmr.create():alarm(1000, tmr.ALARM_SINGLE, function()
    if(temps ~= nil) then
    print("temps:")
    for key, temp in pairs(temps) do
        print("t "..key.."  "..temp)
    end
    else
      print(" sensor not found ")
    end
  
    sendStatus(temps)
  end)
end)

-- every  15 mins
tmr.create():alarm(15*60*1000, tmr.ALARM_AUTO, function() 
    temps = readTemp(owpin)
    sendStatus(temps)
end)
 
function sendStatus(temps)
  if (wifi.sta.getip() == nil) then
    print("no ip")
    wifi.sta.disconnect()
    tmr.delay(1500)
    wifi.sta.connect()
  else
    print("ip "..wifi.sta.getip())
  end
    strTemp = ""
    for key, temp in pairs(temps) do
        strTemp = strTemp.."&t"..key.."="..temp
    end
 
  conn = nil
  conn = net.createConnection(net.TCP, 0)
  conn:on("receive", function(conn, payload) print(payload)end)
  conn:on("connection", function(conn, payload)
   local mesg = 'GET /api/sens/'..mtype..'?s=1'..strTemp..' HTTP/1.0\r\n\Host: edsard.nl\r\naccept: */*\r\n'
   local auth = file.getcontents('auth.txt')
   mesg = mesg..'Authorization: '..auth..'\r\n\r\n'
   print("s "..mesg)
   conn:send(mesg)
  end)
  conn:on("disconnection", function(conn, payload) print('Disconn') end)
  conn:connect(80,'edsard.nl')
end

function readTemp(pin)
    t:read_temp(function(ltemp)
        local coun=1
         for addr, mtemp in pairs(ltemp) do
            print(mtemp) 
            temps[coun]=mtemp
            coun=coun+1
         end
    end , pin,t.C)
end



--small server
srv=net.createServer(net.TCP,10)
srv:listen(80,function(conn)
    local function writefile(name, mode, data)
        if (file.open("" .. name, mode) == nil) then
            return -1
        end
        file.write(data)
        file.close()
    end
        
    conn:on("receive", function(client,payload)
        --print("received "..payload)
        _, _, method, path = string.find(payload, "([A-Z]+) (.+) HTTP")
        --print("m "..method)
        if(path ~= nil) then
            print("path "..path)
            if(path=="/reset")then
                print(" restarting ")
                node.restart()
            end

            if(path=="/upload")then
                print("got file ")
            end
        else
            point=string.find(payload, "filename=[^C]+")
            pend=string.find(payload, "Type",point)
            filename = string.sub(payload,point+10,pend-12)
            print("write to file "..filename)
            writefile(filename,"w+",string.sub(payload, pend+20))
            if(string.find(filename,".lua") ~= nil)then
                --dofile(filename)
            end
        end

        buf="HTTP/1.1 200 OK\r\nConnection: close\r\nAccept: */*\r\n\r\n"

        if(path =="/")then 

            -- return json
            buf=buf.."{\"sensorid\":\""..mtype.."\"," 
            if(temps ~= nil) then  
                for key, temp in pairs(temps) do
                     buf = buf.."\"temp"..key.."\":"..temp.."\","
                end
            end
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.0}"  
           
         end

        if(path ~="/reset")then
            client:send(buf,function(sk)
                sk:close()
              end)
        end
    end)
end)
--end
    

ow.setup(owpin)
readTemp(owpin)
--print("Temps: roof: "..temps[1].." case: "..temps[2])

