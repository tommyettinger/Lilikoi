
-- lilikoi/seed: the core lib used by lilikoi code after translation.
-- Written by Tommy Ettinger. Public Domain.

local seed = {}
local va = require'vararg'
local pp = require'pp'
local glue = require'glue'

seed.__scopes = {{}, {}}

local function lookup(pact)
	local name = pact[1]
	local revi = #seed.__scopes
	local found = 0
	while revi > 0 do
		if seed.__scopes[revi][name] then
			return seed.__scopes[revi][name], name
		end
		revi = revi - 1
	end
	local tgt = seed
	if found > 0 then
		tgt = seed.__scopes[found]
	end
	local ret = tgt[pact[2]]
	if #pact > 2 then
		for i,a in ipairs(pact) do
			if i > 2 then
				if ret[a] == nil then return nil, "nil" end
				if type(ret[a]) == 'function' then
					ret = {
							["\6op"] = ret[a],
							["\6arity"] = -1,
							["\6name"] = name
						}
					seed.__scopes[1][name] = ret
					return ret, name
				else
					ret = ret[a]
				end
			end
		end
	end
	return ret, name
end

-- Look up a string in the defined symbol table.
-- Return a completed partial with all args filled in
-- by the strings given here.
function seed.__(name)
	local p = {name}
	for s in glue.gsplit(name, ".", 1, true) do
		p[#p + 1] = s
	end
	return {
		["\6f"]={
			["\6op"]=lookup,
			["\6arity"]= 1,
			["\6name"]=name
		},
		["\6g"]={p},
		["\6c"]=true
	}
end

local nests = {}

-- runs a partial function once it has been supplied all needed args.
-- returns the function's result, if it has one, followed by another return
-- "\5", or if it has not been supplied enough args, it returns the function
-- with a larger list of supplied args and no extra return. handles grouping.
function seed.__step(partial, arg, terminal)
	local f, given
	-- in the case that we have been given a functor, not a partial
	if partial["\6op"] then
		f = {}
		given = {}
		for k,v in pairs(partial) do f[k] = v end
		partial = {["\6f"]=f, ["\6g"]=given}
	else
		f = partial["\6f"]
		given = partial["\6g"]
	end
	if partial["\6c"] then
		return f["\6op"](unpack(given))
	end
	if arg == nil then
		if f["\6group"] then
			nests[#nests + 1] = f["\6group"]
		end
		if #given == f["\6arity"] or (-1 == f["\6arity"] and terminal) then
			return (f["\6op"](unpack(given))), "\5"
		else
			return partial, nil
		end
	end
	if type(arg) == 'table' and ((arg["\6op"] and nests[#nests] == arg["\6name"])
			or (arg["\6f"] and arg["\6f"]["\6op"]
			and nests[#nests] == arg["\6f"]["\6name"])) then
		table.remove(nests)
		if #nests == 0 then
			return (f["\6op"](seed.__eval(unpack(given)))), "\5"
		else
			given[#given + 1] = arg
		end
	elseif type(arg) == 'table' and ((arg["\6op"] and arg["\6group"])
			or (arg["\6f"] and arg["\6f"]["\6group"])) then
		nests[#nests + 1] = arg["\6group"] or arg["\6f"]["\6group"]
		given[#given + 1] = arg
	elseif f["\6arity"] == -1 or #given < f["\6arity"] then
		given[#given + 1] = arg
	end
	if #given == f["\6arity"] or (-1 == f["\6arity"] and terminal) then
		return (f["\6op"](seed.__eval(unpack(given)))), "\5"
	end
	return partial, nil
end
-- takes a sequence of generated function tables and data, and
-- steps through it until it has exhausted the sequence,
-- returning the final stack (unpacked).
function seed.__eval(...)
	local ahead = glue.reverse({...})
	local stack = {}
	--local sexps = {}
	while #ahead > 0 do
		-- consume any tokens that were used
		local a = table.remove(ahead)
		local ided, nm = nil, nil
		local terminal = #ahead == 0
		if type(a) == 'function' then
			a = {["\6op"] = a,
				["\6arity"] = -1,
				["\6name"] = "__NATIVE"
			}
		end
		
		if type(a) == 'table' and a["\6c"] then
			ided, nm = seed.__step(a, nil, true)
		end
		if type(a) == 'table' and (a["\6group"] or (a["\6f"] and a["\6f"]["\6group"])) then
			ided, nm = a, a["\6name"]
		end
		
		if type(stack[#stack]) == 'table' and ((stack[#stack]["\6op"] and
					stack[#stack]["\6macro"]) or (stack[#stack]["\6f"] and
					stack[#stack]["\6f"]["\6op"] and stack[#stack]["\6f"]["\6macro"])) then
			-- if we are running through a macro, only use names, not values.
			local r, g, q
			if nm then
				q = '\6,' .. nm
			else
				q = a
			end
			r, g = seed.__step(stack[#stack], q, terminal) -- NOTE using nm, not ided
			if(g ~= "\5") then
				stack[#stack] = r
			else
				table.remove(stack)
				table.insert(ahead, r)
			end
		else
		if ided and type(ided) ~= 'table' then a = ided end
		
			if type(ided) == 'table' and (ided["\6op"] or
				(ided["\6f"] and ided["\6f"]["\6op"])) then
			if type(stack[#stack]) == 'table' and ((stack[#stack]["\6op"] and
					stack[#stack]["\6group"]) or (stack[#stack]["\6f"] and
					stack[#stack]["\6f"]["\6op"] and stack[#stack]["\6f"]["\6group"])) then
				-- if we are continuing a function that is on the stack,
				-- and that function is a grouper, disregard starting any
				-- new functions and put the un-evaled args on the stack for
				-- later eval. Do the normal behavior for continuing,
				-- replace the top of the stack with the grouping function
				-- with the latest item received.
				local r, g
				if ided["\6group"] or (ided["\6f"] and ided["\6f"]["\6group"]) then
					r, g = seed.__step(stack[#stack], ided, terminal)
				else
					-- NOTE using a, not ided
					r, g = seed.__step(stack[#stack], a, terminal)
				end
				if(g ~= "\5") then
					stack[#stack] = r
				else
					table.remove(stack)
					table.insert(ahead, r)
				end
			elseif ided["\6group"] or (ided["\6f"] and ided["\6f"]["\6group"]) then
			-- if we have just started executing a grouping function,
			-- ignore the current stack and start the grouping.
				stack[#stack + 1] = seed.__step(ided, nil, terminal)
			else
			-- if we have just started executing a function,
			-- replace the top of the stack with the function called
			-- with the content of the top of the stack.
				local start = #stack
				if start == 0 then start = 1 end
				stack[start] = seed.__step(ided, stack[#stack], terminal)
			end
		elseif type(stack[#stack]) == 'table' and (stack[#stack]["\6op"] or
			(stack[#stack]["\6f"] and stack[#stack]["\6f"]["\6op"])) then
			-- if we are continuing a function that is on the stack,
			-- and we have been given data and not a new function,
			-- replace the top of the stack with the function part-called
			-- with the latest item received.
			stack[#stack] = seed.__step(stack[#stack], a, terminal) -- NOTE using a, again
		else
			-- if we are not continuing or starting a function,
			-- append a piece of data to the stack.
			stack[#stack + 1] = a
		end
		end
	end
	if #stack == 1 then return stack[1] end
	return unpack(stack)
end

-- the entry point for a program. Clears any possible lingering state,
-- then returns any number of args (ideally 1, if the program
-- completed with one return value) based on evaluating a list of
-- code tables and data.
function seed.__run(...)
	nests = {}
	return seed.__eval(...)
end

seed["nil"] = nil

function seed.clean(name)
	if type(name) == 'string' and string.find(name, "^\6,") then
		return string.gsub(name, "^\6,", "", 1)
	else
		return name
	end
end

function seed.unquote(name)
	if type(name) == 'string' and string.find(name, "^\6,") then
		return seed.__(seed.clean(name))
	else
		return name
	end
end

seed.__munge_table = {
["%"]="\6mod",
["\\"]="\6back",
}

function seed.munge(name)
	return name:gsub(
		"^%.", "\6dot"):gsub(
			"%.$", "\6dot"):gsub(
				"[%%\\]", seed.__munge_table);
end

function seed.__def(op, arity, name, group, macro)
	seed[seed.munge(name)] =
	{
		["\6op"] = op,
		["\6arity"] = arity,
		["\6name"] = name,
		["\6group"] = group,
		["\6macro"] = macro
	}
end
local function define(name, ...)
	local val = seed.__eval(va.map(seed.unquote, ...))
	seed.__scopes[#seed.__scopes][seed.munge(seed.clean(name))] = val
	return nil
end
seed.__def(define, -1, "def", nil, true)

local function _fn(...)
	local all = va.pack(...)
	local args, arg_idx = {}, 2
	if arg_idx > all('#') then return nil end
	local a = all(arg_idx)
	while a ~= '\6,]' do
		args[arg_idx - 1] = a
		arg_idx = arg_idx + 1
		if arg_idx > all('#') then return nil end
		a = all(arg_idx)
	end
	
	local my_order = {}
	for i,v in ipairs(args) do
		my_order[i] = seed.clean(v)
	end
	return {
		["\6op"] =
	(function(...)
		local ar = va.pack(...)
		seed.__scopes[#seed.__scopes + 1] = {}
		for i,a in ar do
			seed.__scopes[#seed.__scopes][my_order[i]] = a
		end
		local ret = {seed.__eval(va.map(seed.unquote, all(arg_idx+1, -1)))}
		table.remove(seed.__scopes)
		return unpack(ret)
	end),
		["\6arity"] = #my_order,
		["\6name"] = "anonymous",
	}
end


local function _defn(name, ...)
	local val = _fn(...)
	seed.__scopes[#seed.__scopes][seed.munge(seed.clean(name))] = val
	return nil
end

seed.__def(_fn, -1, "fn", nil, true)
seed.__def(_defn, -1, "defn", nil, true)

function seed.__sequence(...)
	return {...}
end

local function _basic_get(t, idxs)
	local elem = t
	if idxs ~= nil then
		if type(idxs) == 'table' then
			for i,v in ipairs(idxs) do
				elem = elem[v]
			end
		else
			return elem[idxs]
		end
	end
	return elem
end

function seed.format(val)
	local tp = type(val)
	if val == nil then
		return '_'
	elseif tp == 'string' then
		return '"' .. val .. '"'
	elseif tp == 'number' then
		return tostring(val)
	elseif tp == 'table' then
		if val["\6name"] then
			return val["\6name"]
		elseif val["\6g"] and val["\6f"] and val["\6f"]["\6name"] then
			local s = '( ' .. val["\6f"]["\6name"] .. ' '
			for k,v in ipairs(val["\6g"]) do s = s .. seed.format(v) .. ' ' end
			s = s .. ')'
			return s
		else
			local s = '[ '
			for k,v in ipairs(val) do s = s .. seed.format(v) .. ' ' end
			s = s .. ']'
			return s
		end
	end
	return elem
end

seed.__def(glue.pass, -1, "(", ")")

seed.__def(glue.pass, 0, ")")

seed.__def(seed.__sequence, -1, "[", "]")

seed.__def(glue.pass, 0, "]")

seed.__def(_basic_get, 2, "=get")
local function _stringify(v)
	if type(v) == 'string' then
		return v
	else
		return pp.format(v)
	end
end

local function _str(...)
	return table.concat({va.map(_stringify, ...)})
end

seed.__def(_str, -1, "str")
seed.__def(_stringify, 1, "stringify")
seed.__def(pp.print, -1, "pprint")

seed.math = math
seed.io = io
seed.file = file
seed.os = os
seed.string = string
seed.print = print

return glue.autoload(seed,
{
   ["+"] = 'lilikoi.operators',
   ["-"] = 'lilikoi.operators',
   ["*"] = 'lilikoi.operators',
   ["/"] = 'lilikoi.operators',
   ["^"] = 'lilikoi.operators',
   ["\6mod"] = 'lilikoi.operators',
   ["="] = 'lilikoi.operators',
   ["!="] = 'lilikoi.operators',
   ["<"] = 'lilikoi.operators',
   ["<="] = 'lilikoi.operators',
   [">"] = 'lilikoi.operators',
   [">="] = 'lilikoi.operators',
   concat = 'lilikoi.operators',
   transpile = 'lilikoi.transpiler',
   execute = 'lilikoi.transpiler',
   munge = 'lilikoi.transpiler'
})