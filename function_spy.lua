-- function_spy.lua
-- Extended function spying module for Luau.
-- The spy hooks functions and executes them in a sandbox
-- while logging global access, calls and basic operations.

local FunctionSpy = {}
FunctionSpy.__index = FunctionSpy

local DEFAULT_SETTINGS = {
    varnames = false,
    usesimplefunctions = false,
    watchoutforloop = false,
    spynilglobals = false,
    hook_op = false,
    hook_op_default_return = nil,
}

local function clone(tbl)
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

-- spy value type used when hook_op is enabled
local SpyValue = {}
SpyValue.__index = SpyValue

local function isSpy(v)
    return getmetatable(v) == SpyValue
end

local function unwrap(v)
    if isSpy(v) then
        return v.value
    end
    return v
end

function SpyValue.new(value, spy)
    return setmetatable({ value = value, spy = spy }, SpyValue)
end

function SpyValue.__tostring(self)
    return tostring(self.value)
end

function SpyValue.__eq(a, b)
    local av, bv = unwrap(a), unwrap(b)
    table.insert(a.spy.ops, { op = "==", a = av, b = bv })
    local res = av == bv
    if a.spy.settings.hook_op_default_return ~= nil then
        return a.spy.settings.hook_op_default_return
    end
    return res
end

local function opWrap(name, func)
    SpyValue[name] = function(a, b)
        local av, bv = unwrap(a), unwrap(b)
        table.insert(a.spy.ops, { op = name, a = av, b = bv })
        local res = func(av, bv)
        if a.spy.settings.hook_op_default_return ~= nil then
            return a.spy.settings.hook_op_default_return
        end
        return SpyValue.new(res, a.spy)
    end
end

opWrap("__add", function(a,b) return a + b end)
opWrap("__sub", function(a,b) return a - b end)
opWrap("__mul", function(a,b) return a * b end)
opWrap("__div", function(a,b) return a / b end)
opWrap("__concat", function(a,b) return a .. b end)

function FunctionSpy.new(settings)
    local self = setmetatable({}, FunctionSpy)
    self.settings = clone(DEFAULT_SETTINGS)
    if settings then
        for k, v in pairs(settings) do
            self.settings[k] = v
        end
    end
    self.calls = {}
    self.globals = {}
    self.ops = {}
    return self
end

local function createEnv(spy)
    local env = {}
    setmetatable(env, {
        __index = function(t, key)
            local val = rawget(t, key)
            if val ~= nil then
                return val
            end
            local g = _G[key]
            if g == nil and spy.settings.spynilglobals then
                spy.globals[key] = true
            end
            return wrapValue(spy, g)
        end,
        __newindex = function(t, key, value)
            spy.globals[key] = true
            rawset(t, key, wrapValue(spy, value))
        end,
    })
    return env
end

local function wrapValue(spy, v)
    if type(v) == "function" then
        return spy:hook(v)
    end
    if spy.settings.hook_op and (type(v) == "number" or type(v) == "string") then
        return SpyValue.new(v, spy)
    end
    return v
end

local function startLoopWatch(spy)
    if not spy.settings.watchoutforloop then
        return nil
    end
    local count = 0
    local function hook()
        count = count + 1
        if count > 1e6 then
            debug.sethook()
            error("infinitelooperror", 2)
        end
    end
    debug.sethook(hook, "", 1)
    return function()
        debug.sethook()
    end
end

local function loopGuard(spy, func)
    return function(...)
        local stopHook = startLoopWatch(spy)
        local results = { func(...) }
        if stopHook then stopHook() end
        return table.unpack(results)
    end
end

function FunctionSpy:hook(func)
    local env = createEnv(self)
    local info = debug.getinfo(func, "u")

    local function wrapper(...)
        table.insert(self.calls, {
            func = info.name or "anonymous",
            args = {...},
            nresults = info.nresults,
        })
        local oldenv = getfenv(func)
        setfenv(func, env)
        local results = { func(...) }
        setfenv(func, oldenv)
        return table.unpack(results)
    end

    local wrapped = loopGuard(self, wrapper)

    if self.settings.usesimplefunctions then
        return wrapped
    end

    local i = 1
    while true do
        local name, up = debug.getupvalue(func, i)
        if not name then break end
        if type(up) == "function" then
            debug.setupvalue(func, i, self:hook(up))
        end
        i = i + 1
    end

    return wrapped
end

function FunctionSpy:getReport()
    local report = {}
    for idx, call in ipairs(self.calls) do
        local args = {}
        for i, v in ipairs(call.args) do
            local name = self.settings.varnames and ("arg" .. i) or nil
            args[i] = name and name .. "=" .. tostring(unwrap(v)) or tostring(unwrap(v))
        end
        local line = string.format("Call %d to %s: (%s)", idx,
            call.func, table.concat(args, ", "))
        table.insert(report, line)
    end

    for g in pairs(self.globals) do
        table.insert(report, "Global accessed: " .. g)
    end

    for _, op in ipairs(self.ops) do
        table.insert(report, string.format("Op %s %s %s", op.op, tostring(op.a), tostring(op.b)))
    end
    return table.concat(report, "\n")
end

function FunctionSpy:loadFile(path)
    path = path or "input.lua"
    local chunk, err = loadfile(path)
    if not chunk then
        return nil, err
    end
    setfenv(chunk, createEnv(self))
    local wrapped = loopGuard(self, chunk)
    return wrapped()
end

-- when executed directly, spy on 'input.lua'
if ... == nil then
    local spy = FunctionSpy.new()
    local ok, err = spy:loadFile("input.lua")
    if not ok and err then
        io.stderr:write(err .. "\n")
    else
        print(spy:getReport())
    end
end

return FunctionSpy
