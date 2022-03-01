lnet = {}
local lstatus=-1
function lnet.sendstatus(conn,mhost,murl)
if (wifi.sta.getip() == nil) then
 print("no ip")
 wifi.sta.disconnect()
 tmr.delay(1500)
 wifi.sta.connect()
else print(wifi.sta.getip())end

print("cnct to "..mhost)
conn:on("receive", function(sock, payloadout) print("r "..payloadout);lstatus=1 end)
conn:on("connection", function(sock, payload)
 print(conn:getpeer())
 print(murl)
 local auth = file.getcontents('auth.txt')
 sock:send('GET '..murl..' HTTP/1.0\r\n\Host: '..mhost..'\r\nConnection: close\r\nAccept: */*\r\nAuthorization: '..auth..'\r\n\r\n')
end)
conn:on("disconnection", function(conn, payload) print('Disconn');lstatus=0 end)
conn:connect(80,mhost)
end
function getstatus() return lstatus end
return lnet
