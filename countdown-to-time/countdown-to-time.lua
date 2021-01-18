obs           = obslua
source_name   = ""

last_text           = ""
stop_text           = ""
activated           = false

-- DJC Start
remaining_seconds   = 0
target_minute       = 0
target_hour         = 0
RESTART_SECONDS     = -60
DEFAULT_HOUR        = 9
DEFAULT_MINUTES     = 0
-- DJC End

hotkey_id     = obs.OBS_INVALID_HOTKEY_ID



-- DJC Start
function delta_time()
	local now = os.time()
	local year = os.date("%Y", now)
	local month = os.date("%m", now)
	local day = os.date("%d", now)
	local future = os.time{year=year, month=month, day=day, hour=target_hour, min=target_minute}
	local seconds = os.difftime(future, now)

	if (seconds < 0) then
		seconds = seconds + (60*60*24)
	end

	return seconds
end
-- DJC End

-- Function to set the time text
function set_time_text()
	local seconds       = math.floor(remaining_seconds % 60)
	local total_minutes = math.floor(remaining_seconds / 60)
	local minutes       = math.floor(total_minutes % 60)
    local hours         = math.floor(total_minutes / 60)
    local text          = string.format("%02d:%02d:%02d", hours, minutes, seconds)
    -- DJC Start
    if hours == 0 then
        text = string.format("%02d:%02d", minutes, seconds) 
    end
    -- DJC End

	if remaining_seconds < 1 then
		text = stop_text
	end

	if text ~= last_text then
		local source = obs.obs_get_source_by_name(source_name)
		if source ~= nil then
			local settings = obs.obs_data_create()
			obs.obs_data_set_string(settings, "text", text)
			obs.obs_source_update(source, settings)
			obs.obs_data_release(settings)
			obs.obs_source_release(source)
		end
	end

	last_text = text
end

function timer_callback()
    -- DJC Start
	remaining_seconds = remaining_seconds - 1
    if remaining_seconds < RESTART_SECONDS then
        remaining_seconds = delta_time()
    end
    -- DJC End

	set_time_text()
end

function activate(activating)
	if activated == activating then
		return
	end

	activated = activating

    if activating then
        -- DJC Start
		remaining_seconds = delta_time()
        -- DJC End
		set_time_text()
		obs.timer_add(timer_callback, 1000)
	else
		obs.timer_remove(timer_callback)
	end
end

-- Called when a source is activated/deactivated
function activate_signal(cd, activating)
	local source = obs.calldata_source(cd, "source")
	if source ~= nil then
		local name = obs.obs_source_get_name(source)
		if (name == source_name) then
			activate(activating)
		end
	end
end

function source_activated(cd)
	activate_signal(cd, true)
end

function source_deactivated(cd)
	activate_signal(cd, false)
end

function reset(pressed)
	if not pressed then
		return
	end

	activate(false)
	local source = obs.obs_get_source_by_name(source_name)
	if source ~= nil then
		local active = obs.obs_source_active(source)
		obs.obs_source_release(source)
		activate(active)
	end
end

function reset_button_clicked(props, p)
	reset(true)
	return false
end

----------------------------------------------------------

-- A function named script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
	local props = obs.obs_properties_create()
    -- DJC Start
	obs.obs_properties_add_int(props, "hour", "Hour (0-23)", 0, 23, 1)
	obs.obs_properties_add_int(props, "minutes", "Minutes (0-59)", 0, 59, 1)
    -- DJC End

	local p = obs.obs_properties_add_list(props, "source", "Text Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			source_id = obs.obs_source_get_unversioned_id(source)
			if source_id == "text_gdiplus" or source_id == "text_ft2_source" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(p, name, name)
			end
		end
	end
	obs.source_list_release(sources)

	obs.obs_properties_add_text(props, "stop_text", "Final Text", obs.OBS_TEXT_DEFAULT)
	obs.obs_properties_add_button(props, "reset_button", "Reset Timer", reset_button_clicked)

	return props
end

-- A function named script_description returns the description shown to
-- the user
function script_description()
	return "Sets a text source to act as a countdown timer to a specific time when the source is active.\n\nModified by DJC"
end

-- A function named script_update will be called when settings are changed
function script_update(settings)
	activate(false)

    -- DJC Start
    target_hour = obs.obs_data_get_int(settings, "hour")
    target_minute = obs.obs_data_get_int(settings, "minutes") 
    remaining_seconds = delta_time()
    -- DJC End

    source_name = obs.obs_data_get_string(settings, "source")
	stop_text = obs.obs_data_get_string(settings, "stop_text")

	reset(true)
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
    -- DJC Start
	obs.obs_data_set_default_int(settings, "hour", DEFAULT_HOUR)
	obs.obs_data_set_default_int(settings, "minutes", DEFAULT_MINUTES)
    -- DJC End
	obs.obs_data_set_default_string(settings, "stop_text", "Please stand by")
end

-- A function named script_save will be called when the script is saved
--
-- NOTE: This function is usually used for saving extra data (such as in this
-- case, a hotkey's save data).  Settings set via the properties are saved
-- automatically.
function script_save(settings)
	local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
	obs.obs_data_set_array(settings, "reset_hotkey", hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)
end

-- a function named script_load will be called on startup
function script_load(settings)
	-- Connect hotkey and activation/deactivation signal callbacks
	--
	-- NOTE: These particular script callbacks do not necessarily have to
	-- be disconnected, as callbacks will automatically destroy themselves
	-- if the script is unloaded.  So there's no real need to manually
	-- disconnect callbacks that are intended to last until the script is
	-- unloaded.
	local sh = obs.obs_get_signal_handler()
	obs.signal_handler_connect(sh, "source_activate", source_activated)
	obs.signal_handler_connect(sh, "source_deactivate", source_deactivated)

	hotkey_id = obs.obs_hotkey_register_frontend("reset_timer_thingy", "Reset Timer", reset)
	local hotkey_save_array = obs.obs_data_get_array(settings, "reset_hotkey")
	obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)
end
