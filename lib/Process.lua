local Process = {
    --// Remote classes
    RemoteClassData = {
        ["RemoteEvent"] = {
            Send = {
                "FireServer",
                "fireServer",
            },
            Receive = {
                "OnClientEvent",
            }
        },
        ["RemoteFunction"] = {
            IsRemoteFunction = true,
            Send = {
                "InvokeServer",
                "invokeServer",
            },
            Receive = {
                "OnClientInvoke",
            }
        },
        ["UnreliableRemoteEvent"] = {
            Send = {
                "FireServer",
                "fireServer",
            },
            Receive = {
                "OnClientEvent",
            }
        },
        ["BindableEvent"] = {
            Send = {
                "Fire",
            },
            Receive = {
                "Event",
            }
        },
        ["BindableFunction"] = {
            IsRemoteFunction = true,
            Send = {
                "Invoke",
            },
            Receive = {
                "OnInvoke",
            }
        }
    },
    RemoteOptions = {}
}

type table = {
	[any]: any
}

--// Modules
local Hook
local Communication
local ReturnSpoofs
local Ui

--// Communication channel
local Channel

local function Merge(Base: table, New: table)
	for Key, Value in next, New do
		Base[Key] = Value
	end
end

--// Communication
function Process:SetChannelId(ChannelId: number)
    Channel = Communication:GetChannel(ChannelId)
end

function Process:Init(Data)
    local Modules = Data.Modules
    Ui = Modules.Ui
    Hook = Modules.Hook
    Communication = Modules.Communication
    ReturnSpoofs = Modules.ReturnSpoofs
end

function Process:PushConfig(Overwrites)
    Merge(self, Overwrites)
end

function Process:FuncExists(Name: string)
	return getfenv(1)[Name]
end

function Process:CheckIsSupported(): boolean
    local CoreFunctions = {
        "create_comm_channel",
        "get_comm_channel",
        "hookmetamethod",
        "getrawmetatable",
        "setreadonly"
    }

    --// Check if the functions exist in the ENV
    for _, Name in CoreFunctions do
        local Func = self:FuncExists(Name)
        if Func then continue end

        --// Function missing!
        Ui:ShowUnsupported(Name)
        return false
    end

    return true
end

function Process:GetClassData(Remote: Instance): table?
    local RemoteClassData = self.RemoteClassData
    local ClassName = Hook:Index(Remote, "ClassName")

    return RemoteClassData[ClassName]
end

function Process:RemoteAllowed(Remote: Instance, TransferType: string, Method: string?): boolean?
    if typeof(Remote) ~= 'Instance' then return end
    
    if Remote == Communication.DebugIdRemote then return end
    if Remote == Channel then return end

    --// Fetch class table
	local ClassData = self:GetClassData(Remote)
	if not ClassData then return end

    --// Check if the transfer type has data
	local Allowed = ClassData[TransferType]
	if not Allowed then return warn("TransferType not Allowed") end

    --// Check if the method is allowed
	if Method then
		return table.find(Allowed, Method) ~= nil
	end

	return true
end

function Process:SetExtraData(Data: table)
    if not Data then return end
    self.ExtraData = Data
end

function Process:GetRemoteSpoof(Remote: Instance, Method: string)
    local Spoof = ReturnSpoofs[Remote]

    if not Spoof then return end
    if Spoof.Method ~= Method then return end

	Communication:Warn("Spoofed", Method)
	return {Spoof.Return}
end

function Process:FindCallingLClosure(Offset: number)
    Offset += 1

    while true do
        Offset += 1

        --// Check if the stack level is valid
        local IsValid = debug.info(Offset, "l") ~= -1
        if not IsValid then continue end

        --// Check if the function is valud
        local Function = debug.info(Offset, "f")
        if not Function then return end

        return Function
    end
end

function Process:ProcessRemote(Data)
    local OriginalFunc = Data.OriginalFunc
    local Remote = Data.Remote
	local Method = Data.Method
    local Args = Data.Args
    local TransferType = Data.TransferType

	--// Check if the transfertype method is allowed
	if TransferType and not self:RemoteAllowed(Remote, TransferType, Method) then return end

    local Id = Communication:GetDebugId(Remote)
    local RemoteData = self:GetRemoteData(Id)
    local ClassData = self:GetClassData(Remote)

    --// Add extra data into the log if needed
    local ExtraData = self.ExtraData
    if ExtraData then
        Merge(Data, ExtraData)
    end

    --// Add to queue
    Merge(Data, {
		CallingScript = getcallingscript(),
		CallingFunction = self:FindCallingLClosure(5),
        Id = Id,
		ClassData = ClassData
    })

    --// Queue log
    Communication:QueueLog(Data)

    --// Blocked
    if RemoteData.Blocked then return {} end

    --// Check for a spoof
	local Spoof = self:GetRemoteSpoof(Remote, Method)
    if Spoof then return Spoof end

    --// Call original function
    if not OriginalFunc then return end

    local ArgsLength = table.maxn(Args)
    local ReturnValues = {OriginalFunc(Remote, unpack(Args, 1, ArgsLength))}

    --// Log return values
    Data.ReturnValues = ReturnValues

    return ReturnValues
end

function Process:UpdateAllRemoteData(Key: string, Value)
    local RemoteOptions = self.RemoteOptions
	for RemoteID, Data in next, RemoteOptions do
		Data[Key] = Value
	end
end

function Process:GetRemoteData(Id: string)
    local RemoteOptions = self.RemoteOptions

    --// Check for existing remote data
	local Existing = RemoteOptions[Id]
	if Existing then return Existing end
	
    --// Base remote data
	local Data = {
		Excluded = false,
		Blocked = false
	}

	RemoteOptions[Id] = Data
	return Data
end

--// The communication creates a different table address
--// Recived tables will not be the same
function Process:SetRemoteData(Id: string, RemoteData: table)
    local RemoteOptions = self.RemoteOptions
    RemoteOptions[Id] = RemoteData
end

function Process:UpdateRemoteData(Id: string, RemoteData: table)
    Communication:Communicate("RemoteData", Id, RemoteData)
end

return Process