
-- lilikoi/seed: the core lib used by lilikoi code after translation.
-- Written by Tommy Ettinger. Public Domain.

local seed = {}
local pp = require'pp'
local glue = require'glue'

seed.__scopes = {{}, {}}
seed.__namespace = nil

local function _directcall(fun, ...)
	return rawget(fun, "\6op")(...)
end

local function _givencall(fun, ...)
	if #rawget(fun, "\6g") == 0 then return rawget(rawget(fun, "\6f"), "\6op")(...)
	else return rawget(rawget(fun, "\6f"), "\6op")(unpack(rawget(fun, "\6g")), ...)
	end
end
local _directmeta = {__call = _directcall}
local _givenmeta = {__call = _givencall}
function _functor(op, arity, name, group, macro)
	return setmetatable({
		["\6op"] = op,
		["\6arity"] = arity,
		["\6name"] = name,
		["\6group"] = group,
		["\6macro"] = macro
	}, _directmeta)
end

local function _partial(fun, given, quote, complete)
	return setmetatable({
		["\6f"] = fun,
		["\6g"] = given or {},
		["\6q"] = quote,
		["\6c"] = complete
	}, _givenmeta)
end

local function lookup_helper(name, pact, tgt)
	local ret = tgt[pact[2]]
	if #pact > 2 then
		for i,a in ipairs(pact) do
			if i > 2 then
				if ret[a] == nil then return nil, nil end
				if type(ret[a]) == 'function' then
					ret = _functor(ret[a], -1, name)
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
local function lookup(pact)
	local name = pact[1]
	local revi = #seed.__scopes

	while revi > 0 do
		if seed.__scopes[revi][name] then
			return seed.__scopes[revi][name], name
		end
		revi = revi - 1
	end
	local lookups
	if seed.__namespace then
		lookups = {seed.__namespace, seed}
	else
		lookups = {seed}
	end
	local res, nm
	for t,ns in ipairs(lookups) do
		res, nm = lookup_helper(name, pact, ns)
		if res then
			return res, nm
		end
	end
	return nil, name
end

-- Look up a string in the defined symbol table.
-- Return a completed partial with all args filled in
-- by the strings given here.
function seed.__(name)
	local p = {name}
	for s in glue.gsplit(name, ".", 1, true) do
		p[#p + 1] = s
	end
	return _partial(_functor(lookup, 1, name), {p}, nil, true)
end

local nests = {}

-- runs a partial function once it has been supplied all needed args.
-- returns the function's result, if it has one, followed by another return
-- "\5", or if it has not been supplied enough args, it returns the function
-- with a larger list of supplied args and no extra return. handles grouping.
function seed.__step(fun, arg, terminal)
	local f, given, partial
	-- in the case that we have been given a functor, not a partial
	if fun["\6op"] then
		f = fun
		given = {}
		partial = _partial(fun, given)
	else
		f = fun["\6f"]
		given = fun["\6g"]
		partial = fun
	end
	if partial["\6c"] then
		return f["\6op"](unpack(given))
	end
	if arg == nil then
		if f["\6group"] then
			nests[#nests + 1] = f["\6group"]
		end
		
		if #given == f["\6arity"] then
			local t = {f["\6op"](unpack(seed.__eval(given)))}
			t["\5"]=true
			return t
		elseif f["\6macro"] and terminal then
			local t = {f["\6op"](given)}
			t["\5"]=true
			return t
		elseif -1 == f["\6arity"] and terminal then
			local t = {f["\6op"](unpack(seed.__eval(given)))}
			t["\5"]=true
			return t
		else
			return partial
		end
	end
	if type(arg) == 'table' and ((arg["\6op"] and nests[#nests] == arg["\6name"])
			or (arg["\6f"] and arg["\6f"]["\6op"]
			and nests[#nests] == arg["\6f"]["\6name"])) then
		table.remove(nests)
		if #nests == 0 then
			local t = {f["\6op"](unpack(seed.__eval(given)))}
			t["\5"]=true
			return t
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
	if #given == f["\6arity"] then
		local t = {f["\6op"](unpack(seed.__eval(given)))}
		t["\5"]=true
		return t
	elseif f["\6macro"] and terminal then
		local t = {f["\6op"](given)}
		t["\5"]=true
		return t
	elseif -1 == f["\6arity"] and terminal then
		local t = {f["\6op"](unpack(seed.__eval(given)))}
		t["\5"]=true
		return t
	end
	return partial
end
-- takes a sequence of generated function tables and data, and
-- steps through it until it has exhausted the sequence,
-- returning the final stack (unpacked).
function seed.__eval(upcoming)
	local ahead = glue.reverse(upcoming)
	local stack = {}
	--local sexps = {}
	while #ahead > 0 do
		-- consume any tokens that were used
		local a = table.remove(ahead)
		local ided, nm = nil, nil
		local terminal = #ahead == 0
		if type(a) == 'function' then
			a = _functor(a, -1, "__NATIVE")
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
			r = seed.__step(stack[#stack], q, terminal) -- NOTE using nm, not ided
			if(r["\5"]) then
				table.remove(stack)
				glue.reverse(r)
				for i,v in ipairs(r) do
					table.insert(ahead, v)
				end
			else
				stack[#stack] = r
			end
		else
			-- we are not running through a macro
			if ided and (type(ided) ~= 'table') then -- or ided["\6q"]
				-- we have looked up a value and it is not a functor or table
				a = ided
			elseif type(a) == 'table' and a["\6op"] and a["\6name"] and not a["\6q"] then
				ided, nm = a, a["\6name"]
			end
		
			if type(ided) == 'table' and (ided["\6op"] or
				(ided["\6f"] and ided["\6f"]["\6op"])) and not ided["\6q"] then
				
				if type(stack[#stack]) == 'table' and ((stack[#stack]["\6op"] and
						stack[#stack]["\6group"]) or (stack[#stack]["\6f"] and
						stack[#stack]["\6f"]["\6op"] and stack[#stack]["\6f"]["\6group"])) then
					-- if we are continuing a function that is on the stack,
					-- and that function is a grouper, disregard starting any
					-- new functions and put the un-evaled args on the stack for
					-- later eval. Do the normal behavior for continuing,
					-- replace the top of the stack with the grouping function
					-- with the latest item received.
					local r
					if ided["\6group"] or (ided["\6f"] and ided["\6f"]["\6group"]) then
						r = seed.__step(stack[#stack], ided, terminal)
					else
						-- NOTE using a, not ided
						r = seed.__step(stack[#stack], a, terminal)
					end
					if(r["\5"]) then
						table.remove(stack)
						glue.reverse(r)
						for i,v in ipairs(r) do
							if type(v) == 'table' and v["\6op"] then
								table.insert(ahead, _partial(v, {}, true))
							elseif type(v) == 'table' and v["\6f"] then
								v["\6q"] = true
								table.insert(ahead, v)
							else
								table.insert(ahead, v)
							end
						end
					else
						stack[#stack] = r
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
					local r = seed.__step(ided, stack[#stack], terminal)
					if(r["\5"]) then
						table.remove(stack)
						glue.reverse(r)
						for i,v in ipairs(r) do
							table.insert(ahead, v)
						end
					else
						stack[start] = r
					end
				end
			elseif type(stack[#stack]) == 'table' and (stack[#stack]["\6op"] or
				(stack[#stack]["\6f"] and stack[#stack]["\6f"]["\6op"]))
				and not stack[#stack]["\6q"] then
				-- if we are continuing a function that is on the stack,
				-- and we have been given data and not a new function,
				-- replace the top of the stack with the function part-called
				-- with the latest item received.
				
				local r = seed.__step(stack[#stack], a, terminal) -- NOTE using a, again
				if(r["\5"]) then
					table.remove(stack)
					glue.reverse(r)
					for i,v in ipairs(r) do
						table.insert(ahead, v)
					end
				else
					stack[#stack] = r
				end
			else
				-- if we are not continuing or starting a function,
				-- append a piece of data to the stack.
				stack[#stack + 1] = a
			end
		end
	end
	return stack
end

-- the entry point for a program. Clears any possible lingering state,
-- then returns any number of args (ideally 1, if the program
-- completed with one return value) based on evaluating a list of
-- code tables and data.
function seed.__run(program)
	nests = {}
	seed.__scopes = {{},{}}
	seed.__namespace = nil
	
	return unpack(seed.__eval(program))
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
		if string.find(name, "^\6,~") then
			return seed.__(string.sub(name, 4))
		end
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
	seed[seed.munge(name)] = _functor(op, arity, name, group, macro)
end

local function _length(t)
	if type(t) == 'table' then
		return #t
	else
		return 0
	end
end

local function _defunctor(f)
	if type(f) == 'table' then
		if f["\6op"] then return f["\6op"]
		elseif f["\6f"] and f["\6f"]["\6op"] and f["\6g"] and #f["\6g"] > 0 then
			return function(...)
				return f["\6f"]["\6op"](unpack(f["\6g"]), ...)
			end
		elseif f["\6f"] and f["\6f"]["\6op"] then
			return function(...)
				return f["\6f"]["\6op"](...)
			end
		end
	end
	return f
end

local function _call(fun, ...)
	return fun(...)
end

local function _map(f, coll, offset)
	--local f = _defunctor(fun)
	local coll2 = {}
	offset = offset or 0
	for i,v in ipairs(coll) do
		if i > offset then
			rawset(coll2, #coll2 + 1, f(v))
		end
	end
	return coll2
end

local function _apply(f, t)
	--local f = _defunctor(fun)
	return f(unpack(t))
end

local function _pack(...)
	return {...}
end

local function _reduce(f, coll, initial)
	--local f = _defunctor(fun)
	local ret = initial or coll[1]
	for i,v in ipairs(coll) do
		if initial or i > 1 then
			ret = f(ret, v)
		end
	end
	return ret
end

local function _multiget(t, i)
	local ret = {}
	for c,v in ipairs(t) do
		rawset(ret, c, rawget(v, i))
	end
	return ret
end

local function _vmap(f, ...)
	if (...) == nil then return nil end
	--local f = _defunctor(fun)
	local ret = {}
	local colls = {...}
	local minlength = math.min(unpack(_map(_length, colls)))
	for i,v in ipairs(rawget(colls, 1)) do
		if i <= minlength then
			rawset(ret, #ret + 1, f(unpack(_multiget(colls, i))))
		else
			return ret
		end
	end
	return ret
end

seed.__def(_call, -1, "call")
seed.__def(_call, -1, "@")
seed.__def(_map, 2, "map")
seed.__def(_map, 3, "off-map")
seed.__def(_vmap, -1, "vmap")

seed.__def(_apply, 2, "apply")
seed.__def(unpack, 1, "unpack")
seed.__def(_pack, -1, "pack")
seed.__def(_reduce, 2, "reduce")
seed.__def(_reduce, 3, "reduce-with")

local function _lucompose(ftable)
	--local ftable = _map(_defunctor, fs)
	return function(...)
		local ff = table.remove(ftable, 1)
		local ret = {ff(...)}
		for i,v in ipairs(ftable) do
			ret = v(unpack(ret))
		end
		return ret
	end
end

local function _compose(...)
	return _functor(_lucompose({...}), -1, "anonymous")
end

seed.__def(_compose, -1, "compose")

local function define(args)
	local name = table.remove(args, 1)
	local val = seed.__eval(_map(seed.unquote, args))[1]
	if type(val) == 'table' and val["\6q"] then val["\6q"] = nil end
	local scp = seed.__scopes[2]
	if seed.__namespace and scp[seed.__namespace] then scp = scp[seed.__namespace] end
	for s in glue.gsplit(seed.munge(seed.clean(name)), ".", 1, true) do
		local munged = seed.munge(s)
		local n, nm = lookup({munged, munged}) 
		if type(n) == 'table' and not (n["\6f"] or n["\6op"]) then
			scp = n
		else
			scp[munged] = val
			return nil
		end
	end
	scp = val
	return nil
--	seed.__scopes[#seed.__scopes][seed.munge(seed.clean(name))] = val
end
seed.__def(define, -1, "def", nil, true)

local function _fn(args)
	local varargs
	local argseq, arg_idx = {}, 2
	if arg_idx > #args then return nil end
	local a = args[arg_idx]
	while a ~= '\6,]' do
		if varargs == nil then
			argseq[arg_idx - 1] = a
		end
		arg_idx = arg_idx + 1
		if arg_idx > #args then return nil end
		if a == "\6,\6dot.\6dot" then
			varargs = -1
		end
		a = args[arg_idx]
	end
	local my_order = {}
	for i,v in ipairs(argseq) do
		my_order[i] = seed.clean(v)
	end
	return _functor(
	(function(...)
		local ar = {...}
		seed.__scopes[#seed.__scopes + 1] = {}
		seed.__scopes[#seed.__scopes]["\6dot.\6dot"] = {}
		local i2 = 1
		for i,a in ipairs(ar) do
			if my_order[i2] == "\6dot.\6dot" then
				table.insert(seed.__scopes[#seed.__scopes]["\6dot.\6dot"], a)
			else
				seed.__scopes[#seed.__scopes][my_order[i2]] = a
				i2 = i + 1
			end
		end
		local tmp = _map(seed.unquote, args, arg_idx)
		local ret = seed.__eval(tmp)
		table.remove(seed.__scopes)
		return unpack(ret)
	end),
	varargs or #my_order,
	"anonymous")
end


local function _defn(args)
	local name = table.remove(args, 1)
	local val = _fn(args)
	val["\6name"] = seed.munge(seed.clean(name))
	define({name, val})
	return nil
end


local function _defmacro(args)
	local name = table.remove(args, 1)
	local varargs
	local argseq, arg_idx = {}, 2
	if arg_idx > #args then return nil end
	local a = args[arg_idx]
	while a ~= '\6,]' do
		if varargs == nil then
			argseq[arg_idx - 1] = a
		end
		arg_idx = arg_idx + 1
		if arg_idx > #args then return nil end
		if a == "\6,\6dot.\6dot" then
			varargs = -1
		end
		a = args[arg_idx]
	end
	local my_order = {}
	for i,v in ipairs(argseq) do
		my_order[i] = seed.clean(v)
	end
	return _functor(
	(function(...)
		local ar = {...}
		seed.__scopes[#seed.__scopes + 1] = {}
		seed.__scopes[#seed.__scopes]["\6dot.\6dot"] = {}
		local i2 = 1
		for i,a in ipairs(ar) do
			-- scope at element 'arg1' has value '\6,val1'
			if my_order[i2] == "\6dot.\6dot" then
				table.insert(seed.__scopes[#seed.__scopes]["\6dot.\6dot"], a)
			else
				seed.__scopes[#seed.__scopes][my_order[i2]] = a
				i2 = i + 1
			end
		end
		local tmp = _map(seed.unquote, args, arg_idx)
		local ret = seed.__eval(tmp)
		table.remove(seed.__scopes)
		return unpack(ret)
	end),
	varargs or  #my_order,
	seed.munge(seed.clean(name)),
	nil,
	true
	)
end

local function _ns(name)
	local s = seed.munge(seed.clean(name))
	local scp = seed.__scopes[2]
	if scp[s] == nil then scp[s] = {} end
	seed.__namespace = s
	return nil
--	if seed.__namespace and scp[seed.__namespace] then scp = scp[seed.__namespace] end
	
	--[[
	local s2
	for s in glue.gsplit(seed.munge(seed.clean(name)), ".", 1, true) do
		s2 = seed.munge(s)
		local n = scp[s2]
		if type(n) == 'table' then
			if n["\6f"] or n["\6op"] then
				scp[s2] = {}
			end
			seed.__namespace = scp[s2]
		else
			scp[s2] = {}
			seed.__namespace = scp[s2]
		end
	end--]]
end

seed.__def(_fn, -1, "fn", nil, true)
seed.__def(_defn, -1, "defn", nil, true)
seed.__def(_defmacro, -1, "defmacro", nil, true)
seed.__def(_ns, -1, "ns", nil, true)

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
	return nil
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
	return table.concat(_map(_stringify, {...}))
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