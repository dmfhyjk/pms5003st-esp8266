function initWIFI()

	wifi.setmode(wifi.STATION)
	local APConfig={}
	APConfig.ssid="AP-NAME"
	APConfig.pwd="AP-PASSWD"
	wifi.sta.config(APConfig)
	
end --initWIFI

function connectMQTT()

	local tdete = tmr.create()
	tdete:alarm(2 * 1000, tmr.ALARM_AUTO, function ()
		if wifi.sta.getip() then
			tdete:unregister()
			-- print("Config done, IP is ", wifi.sta.getip())
			m:close()
			m:connect('x.x.x.x', 1883, 0) -- mqtt服务器端口
			return nil
		end
	end)
end

function initMQTT()
	
	m = mqtt.Client('PMS5003ST', 80, 'HASS', '123456')  --订阅名称
	m:on('connect', function(client)
		-- print('connected!')
	end)
	m:on('offline', function(client)
		-- print('offline mqtt.')
	end)
	
	connectMQTT()
end

function sendData(t1, t2, t3, t4, t5, t6, t7) --sendData(aqi1,pm25,pm10,pm01,hcho,temp,hum)
	
	if t1 ~= nil then
		m:publish('home/bedroom/aqi1', t1, 0, 0, function(client)
		end)
	end
	if t2 ~= nil then
		m:publish('home/bedroom/pm25', t2, 0, 0, function(client)
		end)
	end
	if t3 ~= nil then
		m:publish('home/bedroom/pm10', t3, 0, 0, function(client)
		end)
	end
	if t4 ~= nil then
		m:publish('home/bedroom/pm01', t4, 0, 0, function(client)
		end)
	end
	if t5 ~= nil then
		m:publish('home/bedroom/hcho', t5, 0, 0, function(client)
		end)
	end
	if t6 ~= nil then
		m:publish('home/bedroom/temp', t6, 0, 0, function(client)
		end)
	end
	if t7 ~= nil then
		m:publish('home/bedroom/hum', t7, 0, 0, function(client)
		end)
	end

end --connect to MQTT server

function decode(data)

	local bs = {}
	-- print('decoding...')
	for i = 1, #data do
		bs[i] = string.byte(data, i)
	end

	if (bs[1] ~= 0x42) or (bs[2] ~= 0x4d) then
		return nil
	end
	
	local d = {}

	d['pm1_0-CF1-ST'] = bs[5] * 256 + bs[6]
	d['pm2_5-CF1-ST'] = bs[7] * 256 + bs[8]
	d['pm10-CF1-ST']  = bs[9] * 256 + bs[10]
	d['pm1_0-AT']     = bs[11] * 256 + bs[12]
	d['pm2_5-AT']     = bs[13] * 256 + bs[14]
	d['pm10-AT']      = bs[15] * 256 + bs[16]
	d['0_3um-count']  = bs[17] * 256 + bs[18]
	d['0_5um-count']  = bs[19] * 256 + bs[20]
	d['1_0um-count']  = bs[21] * 256 + bs[22]
	d['2_5um-count']  = bs[23] * 256 + bs[24]
	d['5_0um-count']  = bs[25] * 256 + bs[26]
	d['10_0um-count']  = bs[27] * 256 + bs[28]
	d['formaldehyde']  = bs[29] * 256 + bs[30]
	d['temperature']  = bs[31] * 256 + bs[32]
	d['humidity']     = bs[33] * 256 + bs[34]
	return d
end --parse

function aqipm25(t)
	if (t <= 12) then return t * 50 / 12
	elseif (t <= 35) then return 50 + (t - 12) * 50 / 23
	elseif (t <= 55) then return 100 + (t - 35) * 5 / 2
	elseif (t <= 150) then return 150 + (t - 55) * 2
	elseif (t <= 350) then return 50 + t
	else return 400 + (t - 350) * 2 / 3
	end
end --aqipm25

function aqipm10(t)
	if (t <= 55) then return t * 50 / 55
	elseif (t <= 355) then return 50 + (t - 55) / 2
	elseif (t <= 425) then return 200 + (t - 355) * 10 / 7
	elseif (t <= 505) then return 300 + (t - 425) * 10 / 8
	else return t - 105
	end
end --aqipm10

function aqi(t25,t10)
	if (t25 > t10) then return math.ceil(t10)
	else return math.ceil(t25)
	end
end --aqi

function initUART()
	
	uart.alt(0)
	uart.setup(0, 9600, 8, 0, uart.STOPBITS_1, 0)
	uart.on('data', 0, function() end, 0)
	uart.write(0, 0x42, 0x4d, 0xe1, 0x00, 0x00, 0x01, 0x70) -- beidongmoshi
	-- print('init uart done.')
end

function main()

	local tmain = tmr.create()
	tmain:alarm(240 * 1000, tmr.ALARM_AUTO, function() -- 240 * 1000
	
		-- print('run...')
	
		if not wifi.sta.getip() then -- wifi state
			initWIFI()
		end
		
		uart.write(0, 0x42, 0x4d, 0xe4, 0x00, 0x01, 0x01, 0x74) -- sensor run
		tmr.delay(500)
		uart.write(0, 0x42, 0x4d, 0xe1, 0x00, 0x00, 0x01, 0x70) -- beidongmoshi
		
		connectMQTT()
		
		local twasd = tmr.create()
		twasd:alarm(50 * 1000, tmr.ALARM_SINGLE, function() -- 50*1000
		
			uart.on('data', 40, function(data)
			
				-- print('getdata...')
			
				uart.write(0, 0x42, 0x4d, 0xe4, 0x00, 0x00, 0x01, 0x73) -- sensor sleep
				uart.on('data', 0, function() end, 0)
				
				mdat = decode(data)
				-- print("Memory Used:"..collectgarbage("count"))
				-- print("Available heap: "..node.heap())
				if (mdat ~= nil) then
					pm01 = mdat['pm1_0-AT']
					pm25 = mdat['pm2_5-AT']
					pm10 = mdat['pm10-AT']
					hcho = mdat['formaldehyde']
					temp = mdat['temperature'] / 10
					hum = mdat['humidity'] / 10
					aqi25 = aqipm25(pm25)
					aqi10 = aqipm10(pm10)
					aqi1  = aqi(aqi25,aqi10)
					sendData(aqi1,pm25,pm10,pm01,hcho,temp,hum)
					-- print('send DATA')
				else
					-- print('UART not get data.')
				end
				
				collectgarbage()

			end, 0)
			uart.write(0, 0x42, 0x4d, 0xe2, 0x00, 0x00, 0x01, 0x71) -- sensor senddata
		end)
	end)
end --main

mdat, pm01, pm25, pm10, hcho, temp, hum, aqi25, aqi10, aqi1 = nil

initWIFI()
initMQTT()
local ttsa = tmr.create()
ttsa:alarm(2 * 1000, tmr.ALARM_AUTO, function ()
	if wifi.sta.getip() then
		ttsa:unregister()
		-- print('runing main...')
		initUART()
		main()
	end
end)

