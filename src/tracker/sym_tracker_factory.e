note
	description: "Selects an implementation-supported tracker adapter."

class
	SYM_TRACKER_FACTORY

feature -- Result

	last_error: detachable SYM_ERROR

feature -- Factory

	new_adapter (a_config: SYM_CONFIG): detachable SYM_TRACKER_ADAPTER
		local
			memory: SYM_MEMORY_TRACKER
			file_tracker: SYM_JSON_FILE_TRACKER
		do
			last_error := Void
			if a_config.tracker_kind.is_case_insensitive_equal ("memory") then
				create memory.make
				memory.validate_config (a_config)
				if memory.last_call_succeeded then Result := memory else last_error := memory.last_error end
			elseif a_config.tracker_kind.is_case_insensitive_equal ("json_file") then
				create file_tracker.make
				file_tracker.validate_config (a_config)
				if file_tracker.last_call_succeeded then Result := file_tracker else last_error := file_tracker.last_error end
			else
				create last_error.make ("unsupported_tracker_kind", "Unsupported tracker.kind: " + a_config.tracker_kind)
			end
		end

	is_supported (a_kind: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := a_kind.is_case_insensitive_equal ("memory") or else a_kind.is_case_insensitive_equal ("json_file")
		end

end
