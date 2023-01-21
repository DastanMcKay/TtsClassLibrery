--Class librery

Settings = {
    active = false,
    checkForUpdates = true,
    installUpdates = true
}

Classes = {}

UpdateInfo = {}

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

---comment
---@param val string
---@return table
local function NewDownloadable(val)
    local this = {
        value = val,
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
---@param className string
---@return table
local function NewClass(className)
    local this = {
        name = className,
        version = 0,
        script = NewDownloadable(""),
        xml = NewDownloadable(""),
        assets = {},
        objectGuids = {},
    }
    local _name = function()
        return this.name
    end
    local _version = function()
        return this.version
    end
    local _loadAssets = function(data)
        this.assets = deepcopy(data)
    end
    local _inject = function(obj)
        local guid = obj.getGUID()
        obj.setLuaScript(this.script.value())
        obj.UI.setXml(this.xml.value(), this.assets)
        table.insert(this.objectGuids, guid)
    end
    local _update = function(updateInfo)
        this.version = updateInfo.version
        this.script.download(updateInfo.scriptUrl)
        this.xml.download(updateInfo.xmlUrl)
        _loadAssets(updateInfo.assetData)
    end
    local _saveState = function()
        return JSON.encode({
            name = this.name,
            version = this.version,
            script = this.script.value(),
            xml = this.xml.value(),
            assets = deepcopy(this.assets),
            objectGuids = deepcopy(this.objectGuids)
        })
    end
    local _loadState = function(savedState)
        if (savedState == "") then
            return
        end
        local state = JSON.decode(savedState)
        this.name = state.name
        this.version = state.version
        this.script = NewDownloadable(state.script)
        this.xml = NewDownloadable(state.xml)
        this.assets = deepcopy(state.assets)
        this.objectGuids = deepcopy(state.objectGuids)
    end

    return {
        name = _name,
        version = _version,
        saveState = _saveState,
        loadState = _loadState,
        update = _update,
        inject = _inject,
    }
end

function onSave()
    local state = {
        settings = deepcopy(Settings),
        classes = {}
    }
    for className, class in pairs(Classes) do
        state.classes[className] = class.saveState()
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
    setupUi()
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

        local latestVersion = JSON.decode(request.text)
        self.setName(latestVersion.name)
        UpdateInfo = {}

        for _, class in ipairs(latestVersion.classes) do
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
            broadcastToAll(latestVersion.name .. " update avaliable", { r = 1, g = 1, b = 0 })
        end
    end)
end

function getLatestUpdates()
    for className, info in pairs(UpdateInfo) do
        Classes[className].update(info)
    end
    Classes = {}
end

function showActivationPanel()
    self.UI.setAttribute("WorkModePanel", "active", false)
    self.UI.setAttribute("ActivationPanel", "active", true)
end

function showWorkModePanel()
    self.UI.setAttribute("ActivationPanel", "active", false)
    self.UI.setAttribute("WorkModePanel", "active", true)

    broadcastToAll("Activate class librery", { r = 1, g = 1, b = 1 })
end

function enterWorkMode()
    self.setLock(true)
    self.interactable = false
    Settings.active = true
    showWorkModePanel()
    if (Settings.checkForUpdates) then
        checkForUpdates()
    end
end

function exitWorkMode()
    self.interactable = true
    self.setLock(false)
    Settings.active = false
    showActivationPanel()
end

function toggleAutoUpdate()
    Settings.checkForUpdates = not Settings.checkForUpdates
    self.UI.setAttribute("AutoCheckForUpdates", "isOn", Settings.checkForUpdates)
    print("Toggle auto-update")
end

function toggleAutoInstall()
    Settings.installUpdates = not Settings.installUpdates
    self.UI.setAttribute("AutoInstallUpdates", "isOn", Settings.installUpdates)
    print("Toggle auto-install")
end

function setupUi()
    self.UI.setAttribute("ActivationPanel", "active", not Settings.active)
    self.UI.setAttribute("WorkModePanel", "active", Settings.active)
    self.UI.setAttribute("AutoCheckForUpdates", "isOn", Settings.checkForUpdates)
    self.UI.setAttribute("AutoInstallUpdates", "isOn", Settings.installUpdates)
end
