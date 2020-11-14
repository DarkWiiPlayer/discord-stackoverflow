local fiber = require 'fiber'
local json = require 'json'
local client = require('http.client').new{}
local uri = require('uri')

local arrr = require 'arrr.arrr'

local options = arrr {
	{ "Discord Webhook URI", "--webhook", "-w", 'url' };
	{ "Polling Interval", "--interval", "-t", 'time', tonumber };
} {...}

options.interval = options.interval or 24*60*60

local function epoch(time)
	return os.difftime(time, os.time{ year=1970, month=1, day=1, hour=1, miunute=1, sec=0 })
end

local function time(time)
	return os.time { year=1970, month=1, day=1, hour=1, minute=1, sec=tonumber(time) }
end

local function addseconds(time, ds)
	local tab = os.date("*t", time)
	tab.sec = tab.sec + ds
	return os.time(tab)
end

local function url()
	local fromdate = epoch(addseconds(os.time(), -(options.interval+60))) -- Overshoot by one minute to avoid missing anything
	local todate = epoch(os.time())
	return uri.format{
		host   = "api.stackexchange.com";
		query  = string.format("fromdate=%i&todate=%i&order=desc&sort=creation&tagged=Lua&site=stackoverflow", fromdate, todate);
		scheme = "https";
		path   = "/2.2/questions";
	}
end

local function newer(a, b)
	if difftime(a, b) > 1 then
		return a
	else
		return b
	end
end

fiber.create(function()
	local known = {}
	while true do
		local new = {}

		local response = client:request("GET", url(), "", {
			accept_encoding="gzip";
		})

		local payload = json.decode(response.body)

		table.sort(payload.items, function(a, b)
			return a.creation_date < b.creation_date
		end)

		print("Quota remaining:", payload.quota_remaining)

		for i, question in ipairs(payload.items) do
			new[question.question_id] = true

			if not known[question.question_id] then
				local body = json.encode{
					embeds = {
						{
							title = question.title:gsub("LUA", "Lua");
							description = string.format("Asked *%s*\nTags: %s",
								os.date("!%A %H:%M:%S UTC", time(question.creation_date)),
								table.concat(question.tags, ", "):gsub("[^,%s]+", "`%0`")
							);
							url = question.link;
							color = '16023588';
						};
					};
					username = question.owner.display_name;
					avatar_url = question.owner.profile_image;
				}
				local response = client:request("POST", options.webhook, body, { headers = { ["Content-Type"]="application/json" } })
			end
		end

		known = new

		fiber.sleep(options.interval)
	end
end)
