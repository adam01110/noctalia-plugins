--!nonstrict

noctalia.setUpdateInterval(1000)

-- Helpers
local function cfg(key)
	return noctalia.getConfig(key)
end

local function getState(key)
	return noctalia.state.get(key)
end

local function setState(key, value)
	noctalia.state.set(key, value)
end

local function watchState(key, cb)
	noctalia.state.watch(key, cb)
end

local function killWithPidFile(file)
	if noctalia.fileExists(file) then
		local content = noctalia.readFile(file) or ""
		local pid = noctalia.string.trim(content)

		if type(pid) == "string" and pid ~= "" then
			noctalia.runAsync(`pkill -9 -P {pid} && kill -9 {pid}`)
		end
		noctalia.removeFile(file)
	end
end

-- Vars
local generationsCheckInterval = cfg("generation_check_interval")
local systemStatsCheckInterval = cfg("system_stats_check_interval")
local systemStatsCheckDurationThreshold = cfg("system_stats_check_duration_threshold")
local stateDir = noctalia.pluginDataDir() or "/tmp/nix-monitor"
local storeSizeFile = stateDir .. "/storeSize"
local closureSizeFile = stateDir .. "/closureSize"
local storePidFile = stateDir .. "/storeSize.pid"
local closurePidFile = stateDir .. "/closureSize.pid"

local nixosGenerationsCmd = "nixos-rebuild list-generations | tail -n +2 | wc -l"
local nixosCurrentGenCmd = "nixos-rebuild list-generations | grep True | awk '{print $1}'"
local hmGenerationsCmd = "home-manager generations | wc -l"
local hmCurrentGenCmd = "home-manager generations | grep '(current)' | awk '{print $5}'"
local storeSizeCmd = "du -s --block-size=1 /nix/store | awk '{printf \"%.2f GiB\", $1/1073741824}'"
local closureSizeCmd = "nix path-info --closure-size --human-readable /run/current-system | awk '{print $2, $3}'"

-- State inits
setState("lastGenerationsCheckTime", 0)
setState("isSystemStatsCheckRunning", false)
setState("systemStatsCheckHasBeenPerformed", false)
setState("lastSystemStatsCheckTime", os.time())
setState("lastSystemStatsCheckRunTime", os.time())
setState("hasHomeManager", noctalia.commandExists("home-manager"))
setState("nixosGenerations", "•••")
setState("nixosCurrentGen", "•••")
setState("hmGenerations", "•••")
setState("hmCurrentGen", "•••")
setState("storeSize", "•••")
setState("closureSize", "•••")

noctalia.mkdirAll(stateDir)

-- Generation check
function checkGenerations()
	setState("lastGenerationsCheckTime", os.time())

	noctalia.runAsync(nixosGenerationsCmd, function(result)
		setState("nixosGenerations", noctalia.string.trim(result.stdout))
	end)

	noctalia.runAsync(nixosCurrentGenCmd, function(result)
		setState("nixosCurrentGen", noctalia.string.trim(result.stdout))
	end)

	if getState("hasHomeManager") then
		noctalia.runAsync(hmGenerationsCmd, function(result)
			setState("hmGenerations", noctalia.string.trim(result.stdout))
		end)

		noctalia.runAsync(hmCurrentGenCmd, function(result)
			setState("hmCurrentGen", noctalia.string.trim(result.stdout))
		end)
	end
end

-- System stats check
function checkSystemStats(force)
	if getState("isSystemStatsCheckRunning") then
		return
	end

	if cfg("system_stats_check_mode") == "off" then
		return
	end

	if cfg("system_stats_check_mode") == "on_start" and getState("systemStatsCheckHasBeenPerformed") and not force then
		return
	end

	setState("storeSize", "•••")
	setState("closureSize", "•••")
	setState("systemStatsCheckHasBeenPerformed", true)
	setState("isSystemStatsCheckRunning", true)
	setState("lastSystemStatsCheckRunTime", os.time())

	-- Sleep 0 to trigger noctalia calling /bin/sh.
	noctalia.runAsync(`sleep 0 && {storeSizeCmd} > {storeSizeFile} & echo $! > {storePidFile}`)
	noctalia.runAsync(`sleep 0 && {closureSizeCmd} > {closureSizeFile} & echo $! > {closurePidFile}`)
end

function checkSystemStatsFile()
	local storeSizeFileContent = noctalia.readFile(storeSizeFile) or ""
	local storeSize = noctalia.string.trim(storeSizeFileContent)
	local closureSizeFileContent = noctalia.readFile(closureSizeFile) or ""
	local closureSize = noctalia.string.trim(closureSizeFileContent)

	if typeof(storeSize) == "string" and storeSize ~= "" then
		setState("storeSize", storeSize)
	end

	if typeof(closureSize) == "string" and closureSize ~= "" then
		setState("closureSize", closureSize)
	end

	local success = typeof(storeSize) == "string"
		and storeSize ~= ""
		and typeof(closureSize) == "string"
		and closureSize ~= ""

	if success then
		setState("isSystemStatsCheckRunning", false)
		setState("lastSystemStatsCheckTime", os.time())
		noctalia.removeFile(storePidFile)
		noctalia.removeFile(closurePidFile)
	end
end

function cancelSystemCheck()
	setState("isSystemStatsCheckRunning", false)
	killWithPidFile(storePidFile)
	killWithPidFile(closurePidFile)
end

-- Init
if cfg("system_stats_check_mode") ~= "off" then
	checkSystemStats()
else
	setState("storeSize", "n/a")
	setState("closureSize", "n/a")
end

-- Command watcher
watchState("command", function(command)
	if command == "refresh" then
		checkGenerations()
		checkSystemStats(true)
	end
end)

-- Hooks
function update()
	-- Generations check
	if (os.time() - getState("lastGenerationsCheckTime")) >= 60 * generationsCheckInterval then
		checkGenerations()
	end

	-- System stats check
	if (os.time() - getState("lastSystemStatsCheckTime")) >= 60 * systemStatsCheckInterval then
		checkSystemStats()
	end

	if getState("isSystemStatsCheckRunning") then
		checkSystemStatsFile()

		-- System stats check timeout
		if (os.time() - getState("lastSystemStatsCheckRunTime")) >= 60 * systemStatsCheckDurationThreshold then
			cancelSystemCheck()
		end
	end
end

function onExit(_signal)
	cancelSystemCheck()
end
