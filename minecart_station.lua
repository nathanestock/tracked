local defaultConfig = {
    stationName = "Station Name",
    stationColor = colors.blue,
    stationIndex = 1,
    detector1 = "redstone_integrator_9",
    direction1 = "west",
    control1 = "redstone_integrator_8",
    control1Invert = false,
    indicator1 = "redstone_integrator_10",
    detector2 = "redstone_integrator_7",
    direction2 = "east",
    control2 = "redstone_integrator_6",
    control2Invert = true,
    indicator2 = "redstone_integrator_11",
    stationProtocal = "minecraft_station",
    stationListProtocal = "minecraft_station_list",
    playerTimeout = 300 -- 5 minutes
}

-- check if basalt is installed, if not install it
if not fs.exists("basalt.lua") then
    shell.run("wget", "https://github.com/Pyroxenium/Basalt/releases/download/v1.7/basalt.lua")
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

local function sendTicket(station, playerName)
    print("Sent: " .. playerName .. " | " .. station.id .. " | " .. textutils.formatTime(os.time()))
    rednet.send(station.id, playerName, config.stationProtocal)

    -- if this index is greater then station index, indicate 1
    if station.index > config.stationIndex then
        os.queueEvent("indicator1")
    else
        os.queueEvent("indicator2")
    end
end

local function selectStation(station)
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
        sendTicket(station, players[1])
    end
end

local TicketStation = { monitor = nil, mainFrame = nil, ticketList = nil, stationList = nil, indicator = nil, eventQueue = {} }
function TicketStation:new(monitor, indicator)
    local mainFrame = basalt.addMonitor()
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
        :setText("Inbound")
        :setPosition(1, 2)
        :setSize("parent.w", 1)
        :setForeground(colors.lightGray)
        :setBackground(colors.black)
    local ticketWrapper = mainFrame:addScrollableFrame()
        :setPosition(1, 3)
        :setSize("parent.w", "parent.h/3 - 2")
    local ticketList = ticketWrapper:addList()
        :setPosition(1, 1)
        :setSize("parent.w", "parent.h")
        :setForeground(colors.lightGray)
        :setBackground(colors.gray)
        :setSelectionColor(colors.gray)
    -- station list
    mainFrame:addLabel()
        :setText("Stations")
        :setPosition(1, "parent.h/3 + 1")
        :setSize("parent.w", 1)
        :setForeground(colors.lightGray)
        :setBackground(colors.black)
    local stationWrapper = mainFrame:addScrollableFrame()
        :setPosition(1, "parent.h/3 + 2")
        :setSize("parent.w", "parent.h/3 * 2 - 1")

    local o = {
        monitor = monitor,
        mainFrame = mainFrame,
        ticketList = ticketList,
        stationList = stationWrapper,
        indicator =
    indicator }
    setmetatable(o, self)
    self.__index = self
    return o
end

function TicketStation:updateTickets()
    self.ticketList:clear()
    for player, timestamp in pairs(playerList) do
        self.ticketList:addItem(player)
    end
end

function TicketStation:updateStations(stations)
    self.stationList:removeChildren()

    -- sort stations by index
    table.sort(stations, function(a, b) return a.index > b.index end)

    for _, station in ipairs(stations) do
        if station.id == os.getComputerID() then
            self.stationList:addLabel()
                :setText("* " .. station.name .. " *")
                :setSize("parent.w", 1)
                :setPosition(1, _)
                :setTextAlign("center")
                :setBackground(colors.gray)
                :setForeground(colors.lightGray)
        else
            self.stationList:addButton()
                :setText(station.name)
                :setSize("parent.w", 1)
                :setPosition(1, _)
                :setBackground(colors.gray)
                :setForeground(colors.white)
                :onClick(function() selectStation(station) end)
        end
    end
end

-- get monitors, there must be 2
local monitors = { peripheral.find("monitor") }

if #monitors < 2 then
    error("Two monitors required", 0)
end

local ticketStation1 = TicketStation:new(monitors[1], config.indicator1)
local ticketStation2 = TicketStation:new(monitors[2], config.indicator2)

-- broadcast station information to other stations
local stationInfo = { name = config.stationName, id = os.getComputerID(), index = config.stationIndex }
rednet.broadcast(textutils.serialize(stationInfo), config.stationListProtocal)

-- fetch station list
local stations = {}
local stationIds = { rednet.lookup(config.stationProtocal) }
for _, stationId in pairs(stationIds) do
    if stationId == os.getComputerID() then
        table.insert(stations, stationInfo)
    else
        print("Requesting station info from: " .. stationId)
        -- send station list requests
        rednet.send(stationId, "get_info", config.stationListProtocal)
        local senderId, message, protocol = rednet.receive(config.stationListProtocal, 5)
        if senderId == stationId and protocol == config.stationListProtocal then
            local station = textutils.unserialize(message)
            if station.id == nil or station.index == nil or station.name == nil then
                print("Unknown: " .. message)
            else
                print("Recieved: " .. station.name)
                table.insert(stations, station)
            end
        end
    end
end

local function updateTickets()
    ticketStation1:updateTickets()
    ticketStation2:updateTickets()
end

local function updateStations()
    ticketStation1:updateStations(stations)
    ticketStation2:updateStations(stations)
end

-- init stations
updateStations()

-- Function to handle rednet messages
local function handleRednet()
    while true do
        -- Listen for rednet messages
        local senderId, message, protocol = rednet.receive()
        if protocol == config.stationProtocal then
            local playerName = message
            playerList[playerName] = os.epoch("utc") / 1000
            print("Recieved: " .. playerName .. " | " .. textutils.formatTime(playerList[playerName]))

            updateTickets()
        elseif protocol == config.stationListProtocal then
            if message == "get_info" then
                -- sent station information
                rednet.send(senderId,
                textutils.serialize(stationInfo),
                    config.stationListProtocal)
            else
                local station = textutils.unserialize(message)
                if station.id == nil or station.index == nil or station.name == nil then
                    print("Unknown: " .. message)
                else
                    print("Recieved: " .. station.name)
                    
                    -- if station already exists, update it
                    local found = false
                    for _, s in ipairs(stations) do
                        if s.id == station.id then
                            s.index = station.index
                            s.name = station.name
                            found = true
                            break
                        end
                    end

                    if not found then
                        table.insert(stations, station)
                    end

                    updateStations()
                end
            end
        end
    end
end

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

                updateTickets()
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
            if (os.epoch("utc") / 1000) - timestamp > config.playerTimeout then
                playerList[player] = nil

                updateTickets()
            end
        end
        sleep(60)
    end
end

local indicator1 = peripheral.wrap(config.indicator1)
local indicator2 = peripheral.wrap(config.indicator2)

local function handleIndicator(indicator, name)
    if not indicator then
        error(name .. "not found", 0)
    end
    while true do
        local event = os.pullEvent(name)
        indicator.setOutput("bottom", true)
        sleep(3)
        indicator.setOutput("bottom", false)
    end
end

-- Start the async functions
parallel.waitForAny(basalt.autoUpdate, function() handleDetectorInput(detector1, config.direction1, control1) end,
    function() handleDetectorInput(detector2, config.direction2, control2) end,
    function() handleIndicator(indicator1, "indicator1") end,
    function() handleIndicator(indicator2, "indicator2") end
, purgePlayerEntries, handleRednet)
