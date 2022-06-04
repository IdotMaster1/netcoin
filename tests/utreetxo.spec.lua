package.path = "./tests/lib/?.lua;./usr/lib/?.lua;" .. package.path

local lu = require("luaunit")

local hashService = require("math.hashService")
local sha = require("sha2")
local sha256 = function(str)
    return sha.sha256(str)
end
hashService.constructor(sha256)

local utxoProvider = require("utreetxo.utxoProviderInMemory")

local updater = require("utreetxo.updater")
updater.constructor(utxoProvider.iterator)

local acc = {}

function Dump(o)
    if type(o) == "table" then
        local s = "{ "
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = '"' .. k .. '"'
            end
            s = s .. "[" .. k .. "] = " .. Dump(v) .. ","
        end
        return s .. "} "
    else
        return tostring(o)
    end
end

function Test01_simpleadd()
    local myutxo = {
        id = "hey!",
        from = "test",
        to = "test2",
        qty = 1,
        rem = 0,
        sources = {"utxo1", "utxo2"},
        sig = "blablabla"
    }
    utxoProvider.addNormalUtxo(myutxo, 0)
    acc = updater.saveutxo(acc, myutxo)
    lu.assertEquals(acc[0], "335d712f953d70aed03692a14eb4fcf6945be69e208a2a96b983f3ff14d5163f")
    lu.assertEquals(acc[1], nil)

    local proof = utxoProvider.getUtxos()[1]
    lu.assertNotEquals(proof, nil)
    lu.assertEquals(#proof.hashes, 0)
end

function Test02_Delete()
    local proof = utxoProvider.getUtxos()[1]
    local res = updater.deleteutxo(acc, proof)
    lu.assertNotEquals(res, nil)
    lu.assertNotEquals(res, false)
    utxoProvider.deleteUtxo(proof)
    lu.assertEquals(utxoProvider.getUtxos()[1], nil)
end

function Test03_ComplexDelete()
    local acc = {}
    for k = 1, 50 do
        local utxo = {
            id = tostring(k),
            from = tostring(-k),
            to = tostring(-k),
            qty = k * 134315141 % 400,
            rem = k * 549625732 % 842,
            sources = {tostring(2 * k), tostring(2 * k + 1)},
            sig = tostring(k * 4310573825438 % 124942)
        }
        utxoProvider.addNormalUtxo(utxo, 0)
        acc = updater.saveutxo(acc, utxo)
    end

    for k = 1, 50 do
        local toDelete = utxoProvider.getUtxos()[k]
        acc = updater.deleteutxo(acc, toDelete)
        lu.assertNotEquals(acc, false)
    end
end

function Test04_deletetwice()
    -- clean
    utxoProvider.setUtxos({})
    acc = {}
    local myutxo = {
        id = "hey!",
        from = "test",
        to = "test2",
        qty = 1,
        rem = 0,
        sources = {"utxo1", "utxo2"},
        sig = "blablabla"
    }

    -- act
    utxoProvider.addNormalUtxo(myutxo, 0)
    acc = updater.saveutxo(acc, myutxo)
    local proof = utxoProvider.getUtxos()[1]
    acc = updater.deleteutxo(acc, proof)
    lu.assertNotEquals(acc, false)
    acc = updater.deleteutxo(acc, proof)
    lu.assertEquals(acc, false)
end

os.exit(lu.LuaUnit.run())
