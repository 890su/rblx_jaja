--!strict
-- Number formatting for HUD/billboards: 1234 -> "1.23K", 5e6 -> "5M".

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Format.short(value: number): string
	local n = math.floor(value)
	if math.abs(n) < 1000 then
		return tostring(n)
	end
	local tier = math.min(math.floor(math.log10(math.abs(n)) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text = if scaled >= 100
		then string.format("%d", scaled)
		else string.format("%.2f", scaled):gsub("%.?0+$", "")
	return text .. SUFFIXES[tier + 1]
end

-- Preserve fractional rewards from multipliers while keeping big amounts short.
function Format.amount(value: number): string
	if math.abs(value) < 1000 then
		return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
	end
	return Format.short(value)
end

function Format.duration(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	elseif s >= 60 then
		return string.format("%dm %02ds", s // 60, s % 60)
	end
	return `{s}s`
end

return table.freeze(Format)
