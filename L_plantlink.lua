	local PLUGIN_VERSION = "1.72"
	PL = {}
	PL.jsonlua = "dkjson.lua"

	Creds = nil
	function GetPlants(Creds) 
		local SVCID = "urn:airedalez-net:serviceId:PlantLink"
		local respbody = {}
		local ltn12 = require("ltn12")
		local https = require("ssl.https")
		local ui7Check = luup.variable_get(SVCID, "UI7Check", lul_device) or ""
		if ui7Check == "false" then
			luup.log("Using net json parser")
			json = require("json")
		elseif ui7Check == "true" then
			luup.log("Using built in json parser")
			json = require("dkjson")
		end
		myheaders={
		["Authorization"]=Creds,
		["X-Mashape-Key"]="Fk7DqcJC0qmshmBnc27cqkiA4netp1YTZ80jsnn6inwQ5Sgo2A",
		["Accept"]="application/json"
		}

		local body, code, headers, status = https.request{
		url="https://plantlink.p.mashape.com/plants",
		headers=myheaders,sink = ltn12.sink.table(respbody)}

		respbody = table.concat(respbody)
		myPlants = json.decode(respbody)
		return myPlants	
	end

	function lug_startup(lul_device)
	luup.log("plugin version " .. PLUGIN_VERSION .. " starting up...", 50)
		local SVCID = "urn:airedalez-net:serviceId:PlantLink"
		Creds = luup.variable_get(SVCID,"Credential", lul_device)
		luup.log("checking version")
		versionCheck(SVCID,lul_device)
		if Creds ~= nil then
			plants = GetPlants(Creds)
			child_devices = luup.chdev.start(lul_device);
			TotalPlants = table.getn(plants)
		
			if TotalPlants > 1 then
				luup.log("Total Plants: " .. TotalPlants)
    			for i = 2,TotalPlants do
      				s = string.format("%02d", i)
        			luup.log("Adding Plant " .. s)
        			luup.chdev.append(lul_device, child_devices, s, myPlants[i].name, "urn:schemas-airedalez-net:device:PlantLink:1","D_PlantLink.xml", "", "", false)
    			end
    			luup.chdev.sync(lul_device, child_devices)
    		end
    		luup.log("Filling Data")
		FillData()
		luup.log("Data Filled")
		end
	end
	
	function writetofile (filename,package)
	  local f = assert(io.open(filename, "w"))
	  local t = f:write(package)
	  f:close()
	  return t    
	end	
	
	function getfile(filename,url)
		package.loaded.http = nil
    		local http = require("socket.http")
    		http.TIMEOUT = 30
    		local page, code = http.request(url)
    		package.loaded.http = nil
    		if (code == 200) then
      			local _ = writetofile(filename,page)
      			return true
    		else
      			return false
    		end
	end

	
	function FillData()
		local DayOWeek = {"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"}
		local Months = {"January","February","March","April","May","June","July","August","September","October","November","December"}
		myPlants = GetPlants(Creds)
		luup.log("Setting Data")
		local SVCID = "urn:airedalez-net:serviceId:PlantLink"
		local i = 0
		for k, v in pairs(luup.devices) do
			if v.device_type == "urn:schemas-airedalez-net:device:PlantLink:1" then
				i = i + 1
				luup.attr_set("name",myPlants[i].name,k)
				if myPlants[i].plant_type.key == 999999 then
					luup.variable_set(SVCID,"PlantName", "Repeater",k)
					luup.variable_set(SVCID,"MaxMoisture", myPlants[i].upper_moisture_threshold,k)
					luup.variable_set(SVCID,"MinMoisture", myPlants[i].lower_moisture_threshold,k)
					s = "No Data"
					luup.variable_set(SVCID,"Moisture",0,k)
					luup.variable_set(SVCID,"MoisturePercent", s .. "%",k)
					luup.variable_set(SVCID,"WaterDay",s,k)
					luup.variable_set(SVCID,"last_updated",myPlants[i].updated, k)
					luup.variable_set(SVCID,"Status",s,k)
					luup.variable_set(SVCID,"PLIcon","50",k)
				else
					local t = os.date("*t", myPlants[i].last_measurements[1].predicted_water_needed)
					local ct = os.date("*t", os.time())
					if t.wday == ct.wday then
						WaterDay = "Today"
					else
						WaterDay = DayOWeek[t.wday] .. " - " .. Months[t.month] .. " " .. t.day
					end
					luup.log("The Time: " .. myPlants[i].last_measurements[1].predicted_water_needed)
					luup.log("Setting: " .. k)
					luup.variable_set(SVCID,"PlantName", myPlants[i].plant_type.name,k)
					luup.variable_set(SVCID,"MaxMoisture", myPlants[i].upper_moisture_threshold,k)
					luup.variable_set(SVCID,"MinMoisture", myPlants[i].lower_moisture_threshold,k)
					if myPlants[i].last_measurements[1].moisture ~= nil then
				 	 percent = 100 * myPlants[i].last_measurements[1].moisture
				 	 s = string.format("%.2f", percent)
					else
				 	 s = "No Data"
					end
					luup.variable_set(SVCID,"Moisture",myPlants[i].last_measurements[1].moisture,k)
					luup.variable_set(SVCID,"MoisturePercent", s .. "%",k)
					luup.variable_set(SVCID,"WaterDay", WaterDay,k)
					local updt = os.date("%c",myPlants[i].last_measurements[1].updated)
					luup.variable_set(SVCID,"last_updated",updt,k)
					if myPlants[i].last_measurements[1].battery_voltage ~= nil then
				 	 battery = round(100*myPlants[i].last_measurements[1].battery,0)
                                         
					else
				 	 battery = 0
					end
					luup.variable_set("urn:micasaverde-com:serviceId:HaDevice1","BatteryLevel",battery, k)
					DetermineWaterStatus(myPlants[i].upper_moisture_threshold,myPlants[i].lower_moisture_threshold,myPlants[i].last_measurements[1].moisture,SVCID,k)
				end
			end
		end
		luup.log("Filling Up Plants")
		luup.call_timer("FillData",1,"15m","","")
	end
	
	function DetermineWaterStatus(upper,lower,current,SVCID,k)
		if (upper ~= nil) and (lower ~= nil) and (current ~= nil) then
		luup.log(upper .. " " .. lower .. " " .. current)
		if (current &lt; upper) and (current &gt; lower) then
			luup.variable_set(SVCID,"Status","Just Right",k)
			luup.variable_set(SVCID,"PLIcon","50",k)
		elseif (current &gt; upper) then
			luup.variable_set(SVCID,"Status","Too Wet",k)
			luup.variable_set(SVCID,"PLIcon","0",k)		
		elseif (current &lt; lower) then
			luup.variable_set(SVCID,"Status","Too Dry",k)
			luup.variable_set(SVCID,"PLIcon","100",k)
		else
			luup.variable_set(SVCID,"Status","Not Sure",k)
			luup.variable_set(SVCID,"PLIcon","50",k)
		end
		else
		luup.variable_set(SVCID,"Status","No Data",k)
		end
	end
	
	function versionCheck(SVCID,lul_device)
		local ui7Check = luup.variable_get(SVCID, "UI7Check", lul_device) or ""
		if ui7Check == "" then
			luup.variable_set(SVCID, "UI7Check", "false", lul_device)
			ui7Check = "false"
		end
		if ui7Check == "false" then
			CheckForJSONParser()
		end
		if( luup.version_branch == 1 and luup.version_major == 7) then
			luup.variable_set(SVCID, "UI7Check", "true", lul_device)
			luup.attr_set("device_json", "D_PlantLink_UI7.json", lul_device)
			return
		end
	end

	function round(num, n)
  		local mult = 10^(n or 0)
  		return math.floor(num*mult+0.5)/mult
	end
