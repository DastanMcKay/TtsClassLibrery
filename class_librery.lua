---comment
---@param t table
---@return table
local function const(t)
    local proxy = {}
    local mt = {
        __index = t,
        __newindex = function(_, _, _)
            error("attempt to update a read-only table", 2)
        end
    }
    setmetatable(proxy, mt)
    return proxy
end

---comment
---@param orig any
---@return any
function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function NewDownloadable()
    local this = {
        value = "",
    }
    local _value = function()
        return this.value
    end
    local _download = function(url)
        if (url == "") then
            return
        end
        WebRequest.get(url, function(request)
            if (request.is_error) then
                warn("Unable to load download url:\n" .. url)
            end
            this.value = request.text
        end)
    end
    return {
        value = _value,
        download = _download
    }
end

---comment
---@param name string
---@return table
local function NewClass(name)
    local this = {
        _name = name,
        _version = 0,
        _script = NewDownloadable(),
        _xml = NewDownloadable(),
        _assets = {},
        _objectGuids = {},
    }
    local _name = function()
        return this._name
    end
    local _version = function()
        return this._version
    end
    local _loadAssets = function(data)
        this._assets = deepcopy(data)
    end
    local _inject = function(obj)
        local guid = obj.getGUID()
        obj.setLuaScript(this._script.value())
        obj.UI.setXml(this._xml.value(), this._assets)
        table.insert(this._objectGuids, guid)
    end
    local _update = function(updateInfo)
        this._version = updateInfo.version
        this._script.download(updateInfo.scriptUrl)
        this._xml.download(updateInfo.xmlUrl)
        _loadAssets(updateInfo.assetData)
    end
    local _saveState = function()
        return JSON.encode(this)
    end
    local _loadState = function(savedState)
        if (savedState == "") then
            return
        end
        this = JSON.decode(savedState)
    end

    return const({
        name = _name,
        version = _version,
        saveState = _saveState,
        loadState = _loadState,
        update = _update,
        inject = _inject,
    })
end

Settings = {
    checkForUpdates = true,
    installUpdates = true
}

Classes = {}

UpdateInfo = {}

function onSave()
    local state = {
        settings = deepcopy(Settings),
        classes = {}
    }
    for className, class in pairs(Classes) do
        state.classes[className] = class.savedState()
    end
    return JSON.encode(state)
end

function onLoad(saveState)
    if (saveState ~= "") then
        local state = JSON.decode(saveState)
        Settings = deepcopy(state.settings)
        for className, classState in pairs(state.classes) do
            Classes[className] = NewClass(className)
            Classes[className].loadState(classState)
        end
    end
    if (Settings.checkForUpdates) then
        checkForUpdates()
    end
end

function checkForUpdates()
    local url = self.getDescription()
    if (url == "") then
        print("Set class librery description to url of version.json of your librery")
        return
    end
    WebRequest.get(url, function(request)
        if (request.is_error) then
            print("Failed to get version info.\n" .. request.error)
            return
        end

        print("Received:\n" .. request.text)

        local latestVersion = JSON.decode(request.text)
        self.setName(latestVersion.name)
        UpdateInfo = {}

        for _, class in ipairs(latestVersion) do
            if (Classes[class.name] == nil) then
                Classes[class.name] = NewClass(class.name)
            end
            if (Classes[class.name].version() < class.version) then
                UpdateInfo[class.name] = deepcopy(class)
            end
        end
        if (next(UpdateInfo) == nil) then
            return
        end
        if (Settings.installUpdates) then
            getLatestUpdates()
        else
            broadcastToAll("Custom RPG system update avaliable")
        end
    end)
end

function getLatestUpdates()
    while (next(UpdateInfo) ~= nil) do
        local updateInfo = table.remove(UpdateInfo)
        Classes[updateInfo.name].update(updateInfo)
    end

    print("^^^^^^^^^^^^^^^^^^^^^^^^^^^^")
    for _, class in pairs(Classes) do
        print("Class \"" .. class.name() .. "\" version " .. class.version())
    end
end
