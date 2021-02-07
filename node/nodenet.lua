require("protocol")
local storage = require("storage")
local napi = require("netcraftAPI")
local component = require("component")
local serial = require("serialization")
local modem = component.modem
require("common")

local nodenet = {}

function nodenet.sendClient(c,p,msg)
    modem.send(c,p,cache.myPort,msg)
end

function nodenet.sync()
    -- Update node list
    for _,client in pairs(cache.nodes) do
        nodenet.sendClient(client.ip, client.port, "GETNODES")
        local _,_,msg = napi.listentoclient(modem, cache.myPort, client.ip, 2)
        if msg~="NOT_IMPLEMENTED" and msg~=nil then
            local parse = explode("####",msg)
            cache[parse[1]] = {}
            cache[parse[1]].ip = node
            cache[parse[1]].port = parsed[2]
            cache[parse[1]].miner = parsed[3]
        end
    end
    -- Get last block
    for _,client in pairs(cache.nodes) do
        nodenet.sendClient(client.ip, client.port, "GET_LAST_BLOCK")
        local _,_,msg = napi.listentoclient(modem, cache.myPort, client.ip, 2)
        if msg~="NOT_IMPLEMENTED" and msg~=nil then
            local block = serial.unserialize(msg)
            local result = nodenet.newBlock(client.ip,client.port, block)
        end
    end
end

function nodenet.dispatchNetwork()
    local clientIP,clientPort,msg = napi.listen(modem, cache.myPort)
    local parsed = explode("####",msg)
    
    if parsed[1]=="GETBLOCK" then
        local req = parsed[2]
        local block = storage.loadBlock(req)
        if block==nil then nodenet.sendClient(clientIP,clientPort,"ERR_BLOCK_NOT_FOUND")
        else nodenet.sendClient(clientIP,clientPort,"OK####"..serial.serialize(block)) end
        
    elseif parsed[1]=="GETNODES" then
        for _,client in ipairs(cache.nodes) do
                nodenet.sendClient(clientIP,clientPort,client.ip .. "####" .. client.port .. "####" .. client.node)
            end
        nodenet.sendClient(clientIP,clientPort,"END")
    elseif parsed[1]=="NEWBLOCK" then
        local block = serial.unserialize(parsed[2])
        local result = nodenet.newBlock(clientIP,clientPort,block)
        if result==true then
            for _,client in pairs(cache.nodes) do
                nodenet.sendClient(client.ip, client.port, parsed[2])
            end
        end
    elseif parsed[1]=="NEWNODE" then
        local node = parsed[2]
        if cache[node]~=nil then
            for k,client in pairs(cache.nodes) do
                nodenet.sendClient(client.ip, client.port, "NEWNODE####" .. parsed[2] .. "####" .. parsed[3] .. "####" .. parsed[4])
            end
            cache[node] = {}
            cache[node].ip = node
            cache[node].port = parsed[3]
            cache[node].miner = parsed[4]
        end
    elseif parsed[1]=="GET_LAST_BLOCK" then
        nodenet.sendClient(clientIP,clientPort,serial.serialize(storage.loadBlock(cache.getlastBlock())))
    elseif parsed[1]=="NEWTRANSACT" then
        for k,v in pairs(cache.nodes) do
            if v.miner==true then
                nodenet.sendClient(v.ip, v.port, "NEWTRANSACT####" .. parsed[2])
            end
        end
    end
end

function nodenet.newBlock(clientIP,clientPort,block)
    if not block or not block.height then return false end
    if cache.getlastBlock()~="error" and block.height <= storage.loadBlock(cache.getlastBlock()).height then nodenet.sendClient(clientIP,clientPort,"NOT_ENOUGH_HEIGHT")
    elseif block.previous==nil then nodenet.sendClient(clientIP,clientPort,"INVALID_BLOCK")
    elseif cache.getlastBlock()~="error" and block.previous ~= cache.getlastBlock() then -- We need more blocks!
        local result = nodenet.newUnknownBlock(clientIP,clientPort,block)
        if result==false then nodenet.sendClient(clientIP,clientPort,"ERR_BLOCKS_REJECTED") end
    elseif not verifyBlock(block) then nodenet.sendClient(clientIP,clientPort,"INVALID_BLOCK")
    else
        consolidateBlock(block)
        nodenet.sendClient(clientIP,clientPort,"BLOCK_ACCEPTED")
        return true
    end
    return false
end

function nodenet.newUnknownBlock(clientIP,clientPort,block)
    local lb = storage.loadBlock(cache.getlastBlock())
            local chain = lb
            local recv = {block}
            while chain.uuid ~= recv[#recv].uuid and recv[#recv].height~=0 do
                local msg
                local tries = 0
                repeat
                    nodenet.sendClient(clientIP,clientPort,"GETBLOCK####"..(recv[#recv].previous))
                    _,_,msg = napi.listentoclient(modem,cache.myPort,clientIP,2)
                    if msg~=nil then msg = explode("####",msg) 
                    else return false
                    end
                    tries = tries + 1
                until msg[1] == "OK" or tries >= 5
                if tries >= 5 then return false end
                local recvb = serial.unserialize(msg[2])
                if recvb.uuid ~= recv[#recv].previous then return false end
                recv[#recv+1] = recvb
                chain = storage.loadBlock(chain.previous)
            end
            if ((lb.height - lb.height%10) ~= (chain.height - chain.height%10)) or recv[#recv].height==0 then
                local result = reconstructUTXOFromZero(recv, block)
                if (not result) then nodenet.sendClient(clientIP,clientPort,"INVALID_BLOCKS")
                else nodenet.sendClient(clientIP,clientPort,"BLOCK_ACCEPTED") return true end
            else
                local result = reconstructUTXOFromCache(recv, block)
                if (not result) then nodenet.sendClient(clientIP,clientPort,"INVALID_CHAIN")
                else nodenet.sendClient(clientIP,clientPort,"BLOCK_ACCEPTED") return true end
            end
    return false
end

return nodenet