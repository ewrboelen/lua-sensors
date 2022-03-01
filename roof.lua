owpin=3
temps={}--array
servip="edsard.nl" 

payloadFound = false
t = require('ds18b20')
if(mtype == nil)then
    mtype='roof'
end
print(mtype)
local temps = {} 

tmr.create():alarm(20*1000, tmr.ALARM_SINGLE, function() 
  if(t == nil)then
    t = require('ds18b20')
  end
  t:read_temp(function(ltemps)
        temps = ltemps
    end , owpin)
  tmr.create():alarm(1000, tmr.ALARM_SINGLE, function()
    if(temps ~= nil) then
    print("temps:")
    for key, temp in pairs(temps) do
        print("t "..key.."  "..temp)
    end
    else
      print("sens not found")
    end
  
    sendTemp()
  end)
end)

-- every  15 mins
tmr.create():alarm(15*60*1000, tmr.ALARM_AUTO, function() 
    t:read_temp(function(ltemps)
        temps = ltemps
    end , owpin)
    tmr.create():alarm(1000, tmr.ALARM_SINGLE, function()
        sendTemp()
    end)
end)

function sendStatus(mhost,murl)
  if (wifi.sta.getip() == nil) then
    print("no ip")
    wifi.sta.disconnect()
    tmr.delay(1500)
    wifi.sta.connect()
  else
    print("ip "..wifi.sta.getip())
  end
  print("cnct to "..mhost)
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

function sendTemp()
   local i =1
   local query=''
   for addr, temp in pairs(temps) do
    query = query..'&temp'..i..'='..temp
    i=i+1
   end
   if i == 1 then
    print("no temps")
   end
   local mesg = '/api/sens/'..mtype..'?s=1'..query
   sendStatus(servip,mesg)
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
                local coun=1 
                for key, temp in pairs(temps) do
                     buf = buf.."\"temp"..coun.."\":"..temp.."\","
                     coun=coun+1
                end
            end
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.1}"  
           
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
--print("Temps: roof: "..temps[1].." case: "..temps[2])

