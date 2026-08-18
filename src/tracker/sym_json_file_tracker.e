note
	description: "Local JSON-file tracker profile. The file is re-read atomically on every poll/refresh."

class
	SYM_JSON_FILE_TRACKER

inherit
	SYM_TRACKER_ADAPTER

create
	make

feature {NONE} -- Initialization

	make
		do
			create source_path.make_empty
			create last_issues.make (0)
			create codec.make
		ensure
			source_unset: source_path.is_empty
			issues_empty: last_issues.is_empty
			no_error: last_error = Void
		end

feature -- Access

	kind: STRING_32 = "json_file"

	source_path: PATH

	last_issues: ARRAYED_LIST [SYM_ISSUE]

	last_error: detachable SYM_ERROR

feature -- Contract

	validate_config (a_config: SYM_CONFIG)
		local
			p: PATH
			resolved: detachable STRING_32
		do
			last_error := Void
			if not a_config.tracker_kind.is_case_insensitive_equal (kind) then
				create last_error.make ("unsupported_tracker_kind", "Expected tracker.kind=json_file")
			elseif attached json.string (a_config.tracker_provider, "path") as s and then not strings.is_blank (s) then
				resolved := expanded_local_path (s)
				if attached resolved as path_text then
					create p.make_from_string (path_text)
					if p.is_absolute then source_path := p.canonical_path else source_path := p.absolute_path_in (a_config.workflow_path.parent).canonical_path end
				else
					create last_error.make ("invalid_tracker_config", "json_file provider.path references a missing environment variable")
				end
			else
				create last_error.make ("invalid_tracker_config", "json_file provider requires a non-empty path")
			end
		ensure then
			success_has_source: last_error = Void implies not source_path.is_empty
		end

	fetch_issues_by_states (a_states: LIST [STRING_32])
		do
			create last_issues.make (10)
			last_error := Void
			if not a_states.is_empty then
				read_and_filter (a_states, Void)
			end
		ensure then
			successful_items_match: last_error = Void implies
				(across last_issues as issue_cursor all
					normalized_has (a_states, issue_cursor.item.state)
				end)
		end

	fetch_issues_by_ids (a_ids: LIST [STRING_32])
		do
			create last_issues.make (a_ids.count)
			last_error := Void
			if not a_ids.is_empty then
				read_and_filter (Void, a_ids)
			end
		ensure then
			successful_items_match: last_error = Void implies
				(across last_issues as issue_cursor all
					exact_has (a_ids, issue_cursor.item.id)
				end)
		end

feature {NONE} -- Reading

	read_and_filter (a_states, a_ids: detachable LIST [STRING_32])
		local
			f: RAW_FILE
			v: detachable JSON_VALUE
			a: detachable JSON_ARRAY
			seen_ids, seen_identifiers, seen_workspace_keys: HASH_TABLE [BOOLEAN, STRING_32]
			identifier_key, workspace_key: STRING_32
		do
			create f.make_with_path (source_path)
			if not f.exists or else not f.is_plain or else not f.is_readable then
				create last_error.make ("tracker_request", "Cannot read JSON tracker file: " + source_path.name)
			else
				f.open_read
				f.read_stream (f.count)
				v := json.parsed_value (f.last_string)
				f.close
				if attached {JSON_ARRAY} v as root_array then
					a := root_array
				elseif attached {JSON_OBJECT} v as root_object then
					a := json.array (root_object, "issues")
				end
				if attached a as records then
					create seen_ids.make (records.count)
					create seen_identifiers.make (records.count)
					create seen_workspace_keys.make (records.count)
					seen_ids.compare_objects
					seen_identifiers.compare_objects
					seen_workspace_keys.compare_objects
					across records as c until last_error /= Void loop
						if attached {JSON_OBJECT} c.item as o then
							codec.decode (o)
							if attached codec.issue as i then
								identifier_key := filesystem_identifier_key (i.identifier)
								workspace_key := safety.workspace_key (i.identifier)
								if seen_ids.has (i.id) then
									create last_error.make ("tracker_response", "JSON tracker contains a duplicate issue id")
								elseif seen_identifiers.has (identifier_key) then
									create last_error.make ("tracker_response", "JSON tracker contains duplicate or filesystem-equivalent issue identifiers")
								elseif seen_workspace_keys.has (filesystem_identifier_key (workspace_key)) then
									create last_error.make ("tracker_response", "JSON tracker issue identifiers map to the same workspace key")
								else
									seen_ids.force (True, i.id)
									seen_identifiers.force (True, identifier_key)
									seen_workspace_keys.force (True, filesystem_identifier_key (workspace_key))
								end
								if last_error = Void and then attached a_states as states and then normalized_has (states, i.state) then
									last_issues.extend (i)
								elseif last_error = Void and then attached a_ids as ids and then exact_has (ids, i.id) then
									last_issues.extend (i)
								end
							elseif attached codec.error as record_error then
								create last_error.make ("tracker_response", "Malformed JSON tracker issue: " + record_error.message)
							end
						else
							create last_error.make ("tracker_response", "Every JSON tracker issues entry must be an object")
						end
					end
					if last_error /= Void then last_issues.wipe_out end
				else
					create last_error.make ("tracker_response", "JSON tracker root must be an array or an object with an issues array")
				end
			end
		rescue
			if attached f as open_file and then open_file.is_open_read then open_file.close end
			last_issues.wipe_out
			create last_error.make ("tracker_request", "Unexpected error while reading JSON tracker file")
		end

	normalized_has (a_values: LIST [STRING_32]; a_value: READABLE_STRING_GENERAL): BOOLEAN
		local
			v: STRING_32
		do
			v := strings.normalized (a_value)
			across a_values as c until Result loop Result := strings.normalized (c.item).same_string (v) end
		end

	exact_has (a_values: LIST [STRING_32]; a_value: READABLE_STRING_GENERAL): BOOLEAN
		do
			across a_values as c until Result loop Result := c.item.same_string_general (a_value) end
		end

	expanded_local_path (a_raw: READABLE_STRING_GENERAL): detachable STRING_32
			-- Expand the documented local-path forms `~' and leading `$VAR'.
		local
			s, name, rest: STRING_32
			i: INTEGER
		do
			s := strings.trimmed (a_raw)
			if s.starts_with ("~") and then (s.count = 1 or else s [2] = '/' or else s [2] = '\') then
				if attached environment.home_directory_path as home then
					if s.count = 1 then Result := home.name else Result := home.name + s.substring (2, s.count) end
				end
			elseif s.starts_with ("$") then
				from i := 2 until i > s.count or else not is_env_character (s [i]) loop i := i + 1 end
				if i > 2 then
					name := s.substring (2, i - 1)
					if i <= s.count then rest := s.substring (i, s.count) else create rest.make_empty end
					if attached environment.item (name) as value and then not value.is_empty then Result := value + rest end
				end
			else
				Result := s
			end
		end

	is_env_character (c: CHARACTER_32): BOOLEAN
		do
			Result := c.is_alpha_numeric or else c = '_'
		end

	filesystem_identifier_key (a_value: READABLE_STRING_GENERAL): STRING_32
		do
			Result := a_value.to_string_32.twin
			if {PLATFORM}.is_windows or else {PLATFORM}.is_mac then Result.to_lower end
		end

	codec: SYM_ISSUE_CODEC

	json: SYM_JSON once create Result end

	strings: SYM_STRINGS once create Result end

	safety: SYM_PATH_SAFETY once create Result end

	environment: EXECUTION_ENVIRONMENT once create Result end

end
