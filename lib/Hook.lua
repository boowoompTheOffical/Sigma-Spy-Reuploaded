local Hook = {
	OrignalNamecall = nil,
	OrignalIndex = nil,
}

type table = {
	[any]: any
}

type MetaCallback = (Instance, ...any)->...any

--// Modules
local Process

--// This is a custom hookmetamethod function, feel free to replace with your own
--// The callback is expected to return a nil value sometimes which should be ingored
--[[
local function HookMetaMethod(self, Call: string, Callback: MetaCallback): MetaCallback
	local OriginalFunc
	OriginalFunc = hookmetamethod(self, Call, function(...)
		--// Invoke callback and check for a reponce otherwise ignored
		local ReturnValues = Callback(...)
		if ReturnValues then
			local Length = table.maxn(ReturnValues)
			return unpack(ReturnValues, 1, Length)
		end

		--// Invoke orignal function
		return OriginalFunc(...)
	end)
	return OriginalFunc
end
--]]

--// Replace metatable function method, this can be a workaround on some games if hookmetamethod is detected
local function HookMetaMethod(self, Call: string, Callback: MetaCallback): MetaCallback
	local Metatable = getrawmetatable(self)
	local OriginalFunc = rawget(Metatable, Call)
	
	--// Replace function
	setreadonly(Metatable, false)
	rawset(Metatable, Call, function(...)
		--// Invoke callback and check for a reponce otherwise ignored
		local ReturnValues = Callback(...)
		if ReturnValues then
			local Length = table.maxn(ReturnValues)
			return unpack(ReturnValues, 1, Length)
		end

		return OriginalFunc(...)
	end)
	setreadonly(Metatable, true)

	return OriginalFunc
end


local function Merge(Base: table, New: table)
	for Key, Value in next, New do
		Base[Key] = Value
	end
end

function Hook:RunOnActors(Code: string, ChannelId: number)
	if not getactors then return end
	for _, Actor in getactors() do 
		run_on_actor(Actor, Code, ChannelId)
	end
end

local function ProcessRemote(OriginalFunc, MetaMethod: string, self, Method: string, ...)
	return Process:ProcessRemote({
		Remote = self,
		Method = Method,
		OriginalFunc = OriginalFunc,
		MetaMethod = MetaMethod,
		TransferType = "Send",
		Args = {...}
	})
end

local function __IndexCallback(OriginalIndex, self, Method: string)
	--// Check if the orignal value is a function
	local OriginalFunc = OriginalIndex(self, Method)
	if typeof(OriginalFunc) ~= "function" then return end

	--// Check if the Object is allowed 
	if not Process:RemoteAllowed(self, "Send", Method) then return end

	--// Process the remote data
	return {function(self, ...) -- Possible detection?
		return ProcessRemote(OriginalFunc, "__index", self, Method, ...)
	end}
end

function Hook:HookMeta()
	--// Namecall hook
	local On; On = HookMetaMethod(game, "__namecall", function(self, ...)
		local Method = getnamecallmethod()
		return ProcessRemote(On, "__namecall", self, Method, ...)
	end)
	--// Index call hook
	local Oi; Oi = HookMetaMethod(game, "__index", function(...)
		return __IndexCallback(Oi, ...)
	end)

	Merge(self, {
		OrignalNamecall = On,
		OrignalIndex = Oi,
	})
end

function Hook:Index(Object: Instance, Key: string)
	local OrignalIndex = self.OrignalIndex
	if OrignalIndex then
		return OrignalIndex(Object, Key)
	end

	return Object[Key]
end

function Hook:Init(Data)
    local Modules = Data.Modules
	Process = Modules.Process
end

function Hook:PushConfig(Overwrites)
    Merge(self, Overwrites)
end

function Hook:HookClientInvoke(Remote, Method, Callback): ((...any) -> ...any)?
	local PreviousFunction = getcallbackvalue(Remote, Method)
	Remote[Method] = Callback

	return PreviousFunction
end

function Hook:MultiConnect(Remotes)
	for _, Remote in next, Remotes do
		Hook:ConnectClientRecive(Remote)
	end
end

function Hook:ConnectClientRecive(Remote)
	--// Check if the Remote class is allowed for receiving
	local Allowed = Process:RemoteAllowed(Remote, "Receive")
	if not Allowed then return end

	--// Check if the Object has Remote class data
    local ClassData = Process:GetClassData(Remote)
    if not ClassData then return end

    local IsRemoteFunction = ClassData.IsRemoteFunction
    local Method = ClassData.Receive[1]
	local PreviousFunction = nil

	--// New callback function
	local function Callback(...)
        return Process:ProcessRemote({
            Remote = Remote,
            Method = Method,
            OriginalFunc = PreviousFunction,
            IsReceive = true,
            MetaMethod = "Connect",
            Args = {...}
        })
	end

	--// Connect remote
	if not IsRemoteFunction then
   		Remote[Method]:Connect(Callback)
	else -- Remote functions
		pcall(function()
			self:HookClientInvoke(Remote, Method, Callback)
		end)
	end
end

function Hook:BeginService(Libraries, ExtraData, ChannelId: number)
	local ReturnSpoofs = Libraries.ReturnSpoofs
	local ProcessLib = Libraries.Process
	local Communication = Libraries.Communication

	local InitData = {
		Modules = {
			ReturnSpoofs = ReturnSpoofs,
			Communication = Communication,
			Process = ProcessLib,
			Hook = self
		}
	}
	
	--// Communication configuration
	local Channel = Communication:GetChannel(ChannelId)
	Communication:Init(InitData)
	Communication:SetChannel(Channel)
	Communication:AddConnection(function(Type: string, Id: string, RemoteData)
		if Type ~= "RemoteData" then return end
		ProcessLib:SetRemoteData(Id, RemoteData)
	end)
	
	--// Process configuration
	ProcessLib:Init(InitData)
	ProcessLib:SetChannelId(ChannelId)
	ProcessLib:SetExtraData(ExtraData)

	--// Hook configuration
	self:Init(InitData)
	self:HookMeta()
end

return Hook