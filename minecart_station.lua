local defaultConfig = {
    stationName = "Station Name",
    stationColor = colors.blue,
    detector1 = "redstone_integrator_0",
    direction1 = "east",
    control1 = "redstone_integrator_0",
    control1Invert = false,
    indicator1 = "redstone_integrator_0",
    detector2 = "redstone_integrator_0",
    direction2 = "west",
    control2 = "redstone_integrator_0",
    control2Invert = false,
    indicator2 = "redstone_integrator_0",
    stationProtocal = "minecraft_station",
    playerTimeout = 23 -- in-game hours TODO: fix this, purge doesnt work
}

-- check if basalt is installed, if not install it
if not fs.exists("basalt") then
    shell.run("wget", "run", "https://basalt.madefor.cc/install.lua", "release", "latest.lua")
end

local basalt = require("basalt")

-- check for config file
local config = defaultConfig
if fs.exists("config") then
    local file = fs.open("config", "r")
    config = textutils.unserialize(file.readAll())
    file.close()
else
    local file = fs.open("config", "w")
    file.write(textutils.serialize(config))
    file.close()

    print("Config file created")
    -- exit to allow user to edit config file
    return
end

local detector1 = peripheral.wrap(config.detector1)
local detector2 = peripheral.wrap(config.detector2)

if not detector1 then
    error(config.detector1 .. "not found", 0)
elseif not detector2 then
    error(config.detector2 .. "not found", 0)
end

local Control = { invert = false, integrator = nil }
function Control:new(integrator, direction, invert)
    if not integrator then
        error(integrator .. "not found", 0)
    end
    local o = { integrator = integrator, direction = direction, invert = invert }
    setmetatable(o, self)
    self.__index = self
    return o
end
function Control:setOutput(value)
    if self.invert then
        value = not value
    end
    self.integrator.setOutput(self.direction, value)
end

local control1 = Control:new(peripheral.wrap(config.control1), config.direction1, config.control1Invert)
local control2 = Control:new(peripheral.wrap(config.control2), config.direction2, config.control2Invert)

-- Setup entity detector module
local modules = peripheral.find("manipulator")
if not modules then
    error("Cannot find manipulator", 0)
end
if not modules.hasModule("plethora:sensor") then
    error("Sensor module not found", 0)
end

-- Setup rednet connection
local modem = peripheral.find("modem", function(name, object) return object.isWireless() end)
if not modem then
    error("Wireless modem not found", 0)
end
if not rednet.isOpen() then
    peripheral.find("modem", rednet.open)
end
rednet.host(config.stationProtocal, tostring(os.computerID()))

local playerList = {}

local function checkForPlayer(control)
    -- sense for players
    local entities = modules.sense()
    local foundPlayer = false
    for _, entity in ipairs(entities) do
        if entity.key == "minecraft:player" then
            if playerList[entity.name] then
                foundPlayer = true
                -- remove player from list
                playerList[entity.name] = nil
                break
            end
        end
    end

    if foundPlayer then
        control:setOutput(true)
        sleep(0.5)
        control:setOutput(false)
    end
end

-- Function to handle detector input
local function handleDetectorInput(detector, direction, control)
    control:setOutput(false)
    while true do
        if detector.getInput(direction) then
            checkForPlayer(control)
        end
        sleep(0.1)
    end
end

-- Function to purge old player entries
local function purgePlayerEntries()
    while true do
        for player, timestamp in pairs(playerList) do
            if os.time() - timestamp > config.playerTimeout then
                playerList[player] = nil
            end 
        end
        sleep(60)
    end
end

local function sendTicket(stopId, playerName)
    rednet.send(stopId, playerName, config.stationProtocal)
end

local function selectStop(stopId)
    -- sense for players
    local entities = modules.sense()
    local players = {}
    for _, entity in ipairs(entities) do
        if entity.key == "minecraft:player" then
            table.insert(players, entity.name)
        end
    end

    if #players > 1 then
        -- TODO: handle multiple players
    elseif #players == 1 then
        sendTicket(stopId, players[1])
    end
end

local TicketStation = { monitor = nil, mainFrame = nil, ticketList = nil, stationList = nil }
function TicketStation:new(monitor)
    local mainFrame = basalt.addMonitor():setBackground(colors.black)
    mainFrame:setMonitor(monitor)
    -- station name with color background
    mainFrame:addLabel()
        :setText(config.stationName)
        :setPosition(1, 1)
        :setSize("parent.w", 1)
        :setTextAlign("center")
        :setForeground(colors.white)
        :setBackground(config.stationColor)
    -- incoming tickets
    mainFrame:addLabel()
        :setText("Incoming")
        :setPosition(1, 2)
        :setSize("parent.w", 1)
        :setForeground(colors.black)
        :setBackground(colors.gray)
    local ticketWrapper = mainFrame:addScrollableFrame()
        :setPosition(1, 3)
        :setSize("parent.w", "parent.h - 4")
    local ticketList = ticketWrapper:addList()
        :setPosition(1, 1)
        :setSize("parent.w", "parent.h")
    -- station list
    mainFrame:addLabel()
        :setText("Stations")
        :setPosition(1, "parent.h - 1")
        :setSize("parent.w", 1)
        :setForeground(colors.black)
        :setBackground(colors.gray)
    local stationWrapper = mainFrame:addScrollableFrame()
        :setPosition(1, "parent.h - 4")
        :setSize("parent.w", "parent.h - 5")
    local stationList = stationWrapper:addList()
        :setPosition(1, 1)
        :setSize("parent.w", "parent.h")

    local o = { monitor = monitor, mainFrame = mainFrame, ticketList = ticketList, stationList = stationList }
    setmetatable(o, self)
    self.__index = self
    return o
end
function TicketStation:updateTickets()
    self.ticketList:clear()
    for player, timestamp in pairs(playerList) do
        self.ticketList:addItem(player .. " | " .. textutils.formatTime(timestamp))
    end
end
function TicketStation:updateStations(stations)
    self.stationList:clear()
    for _, station in ipairs(stations) do
        self.stationList:addItem(station)
    end
end

-- get monitors, there must be 2
local monitors = peripheral.find("monitor")

if not monitors or #monitors < 2 then
    error("Two monitors required", 0)
end

local ticketStation1 = TicketStation:new(monitors[1])
local ticketStation2 = TicketStation:new(monitors[2])

-- Function to handle rednet messages
local function handleRednet()
    while true do
        -- Listen for rednet messages
        local senderId, playerName, protocol = rednet.receive()
        if protocol == config.stationProtocal then
            playerList[playerName] = os.time()
            print("Ticket: " .. playerName .. " | " .. textutils.formatTime(playerList[playerName]))

            -- update ticket stations
            ticketStation1:updateTickets()
            ticketStation2:updateTickets()
        end
    end
end

-- Start the async functions
parallel.waitForAny(basalt.autoUpdate, function() handleDetectorInput(detector1, config.direction1, control1) end, function() handleDetectorInput(detector2, config.direction2, control2) end, purgePlayerEntries, handleRednet)
