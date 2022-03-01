--attic
scl=2
sda=1
temp=-100
lcount=3
writingFile=nil

servip="edsard.nl" 

function init_bus() --Set up the u8glib lib
     local sla = 0x3C
     i2c.setup(0, sda, scl, i2c.SLOW)
     bme280.setup()
     if(disp == nil) then
         disp = u8g2.ssd1306_i2c_128x64_noname(0,sla)
        disp:setFlipMode(1);
         --disp:setFont(u8g2.font_10x20_tf)
         print("attic" )
     else
        print("display yet on")
     end
     disp:setFont(u8g2.font_6x10_tf)
     disp:drawStr(0, 16, "welkom1")
     disp:drawStr(0, 32, "welkom2")
     disp:sendBuffer()
     
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
            disp:clearBuffer()
            
              --disp:drawStr(24, 10, "c="..(lcount/2).." H="..(lcount%2))
            if(lcount%4==0)then
                local myip=wifi.sta.getip()
                if(myip==nil)then myip="no ip" end
                disp:drawStr(2, (lcount/2), "ip="..myip)
            else
              -- if(lcount%2==0)then
                  disp:drawStr(24, (10+lcount/2), "T="..temp.." H="..humi)
               -- else
                --  disp:drawStr(50, (10+lcount/2), ".")
                --end
            end
            disp:sendBuffer() 
        end
    end)
end
 
function sendStatus(mhost,murl)
  print("connecting to "..mhost)
  conn = nil
  conn = net.createConnection(net.TCP, 0)
  conn:on("receive", function(conn, payloadout)
    if (string.find(payloadout, "200 OK")) then
        sendsuccess=1 
        local dpos = string.find(payloadout,"Date:")
        --disp:drawStr(2, 15, string.sub(payloadout,dpos+5,20))  
        --disp:sendBuffer()  
    end
    --
    --print("time "..string.sub(payloadout,dpos+5,20)
    print(payloadout)
  end)
  conn:on("connection",
   function(conn, payload)
     print("sending "..murl);
     local auth = file.getcontents('auth.txt')
     conn:send('GET '..murl..' HTTP/1.0\r\n\Host: '..mhost..'\r\naccept: */*\r\nAuthorization: '..auth..'\r\n\r\n')end)
   
  conn:on("disconnection", function(conn, payload) print('Disconnected') end)
  conn:connect(80,mhost)
end



--every 10 seconds
tmr.create():alarm(10000,tmr.ALARM_AUTO,function()
    checkTemp()
    lcount = lcount -1
    if (lcount == 2) then
    --readTempout()
    end
    if (lcount == 0) then
        --sendStatus(servip,'/sens/temp_attic.php?s=0&at='..temp..'&h='..humi)
        sendStatus(servip,'/api/sens/attic?s=1&t1='..temp..'&h='..humi)
        lcount = 90
    end
end)

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
        _, _, method, path = string.find(string.sub(payload,0,128), "([A-Z]+) (.+) HTTP")
        buf="HTTP/1.1 200 OK\r\nConnection: close\r\nAccept: */*\r\n\r\n"
        if(path ~= nil and string.sub(path,0,1) == "/") then
            print("path "..path)
            writingFile=nil
            if(path=="/reset")then
                print(" restarting ")
                node.restart()
            end

            if(path=="/upload")then
                print("got file")
                --print("received "..payload)
                buf="HTTP/1.1 100 Continue\r\nContnue\r\n\r\n"
            end
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

        
        if(path =="/")then
            buf = buf.."{\"sensorid\":\"attic\","   
            buf = buf.."\"temp\":"..temp.."\",humi:"..humi.."\","
            buf = buf.."\"uptime\":"..tmr.time()..",\"id\":"..node.chipid()..",\"version\":1.1}"  
        end

        if(path ~="/reset")then
            client:send(buf,function(sk)
                sk:close()
              end)
        end
    end)
end)
-- server end

init_bus()
