local prototype = ... or _G.prototype

local META = {}
META.ClassName = "base"
	
META.Require = {}
META.Events = {}

prototype.GetSet(META, "Id")
prototype.Delegate(META, "Entity", "GetComponent")
prototype.Delegate(META, "Entity", "AddComponent")
prototype.Delegate(META, "Entity", "RemoveComponent")
prototype.GetSet(META, "Entity", NULL)

function META:OnAdd()

end
	
function META:OnRemove()

end

function META:OnEvent(component, name, ...)

end

function META:GetEntityComponents()
	local out = {}
	
	for name, components in pairs(self:GetEntity():GetComponents()) do
		for id, component in pairs(components) do
			table.insert(out, component)
		end
	end
	
	return out
end

function META:FireEvent(...)
	for i, component in ipairs(self:GetEntityComponents()) do
		component:OnEvent(self, component.Name, ...)
	end
end

local events = {}
local ref_count = {}

function META:AddEvent(event_type)
	ref_count[event_type] = (ref_count[event_type] or 0) + 1
	
	local func_name = "On" .. event_type
	
	events[event_type] = events[event_type] or {}		
	table.insert(events[event_type], self)
	
	event.AddListener(event_type, "metatable_ecs", function(a_, b_, c_) 
		for name, self in ipairs(events[event_type]) do
			if self[func_name] then
				self[func_name](self, a_, b_, c_)
			end
		end
	end)
end

function META:RemoveEvent(event_type)
	ref_count[event_type] = (ref_count[event_type] or 0) - 1

	events[event_type] = events[event_type] or {}
	
	for i, other in pairs(events[event_type]) do
		if other == self then
			events[event_type][i] = nil
			break
		end
	end
	
	table.fixindices(events[event_type])

	for i, self in ipairs(events[event_type]) do
		self[func_name](self)
	end
	
	if ref_count[event_type] <= 0 then
		event.RemoveListener(event_type, "metatable_ecs")
	end
end

function prototype.RegisterComponent(meta)
	meta.TypeBase = "base"
	meta.ClassName = meta.Name
	prototype.Register(meta, "ecs_component")
end

function prototype.CreateComponent(name)		
	return prototype.CreateDerivedObject("ecs_component", name)
end

prototype.Register(META, "ecs_component")