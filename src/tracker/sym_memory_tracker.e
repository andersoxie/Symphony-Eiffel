note
	description: "Deterministic in-memory tracker adapter for tests and local Eiffel development."

class
	SYM_MEMORY_TRACKER

inherit
	SYM_TRACKER_ADAPTER

create
	make

feature {NONE} -- Initialization

	make
		do
			create issues.make (10)
			create last_issues.make (0)
		end

feature -- Access

	kind: STRING_32 = "memory"

	issues: ARRAYED_LIST [SYM_ISSUE]

	last_issues: ARRAYED_LIST [SYM_ISSUE]

	last_error: detachable SYM_ERROR

feature -- Mutation

	put (a_issue: SYM_ISSUE)
		local
			replaced: BOOLEAN
		do
			across issues as c until replaced loop
				if c.item.id.same_string (a_issue.id) then issues [c.cursor_index] := a_issue; replaced := True end
			end
			if not replaced then issues.extend (a_issue) end
		end

	remove (a_id: READABLE_STRING_GENERAL)
		do
			from issues.start until issues.after loop
				if issues.item.id.same_string_general (a_id) then issues.remove else issues.forth end
			end
		end

feature -- Contract

	validate_config (a_config: SYM_CONFIG)
		do
			last_error := Void
			if not a_config.tracker_kind.is_case_insensitive_equal (kind) then
				create last_error.make ("unsupported_tracker_kind", "Expected tracker.kind=memory")
			end
		end

	fetch_issues_by_states (a_states: LIST [STRING_32])
		do
			create last_issues.make (issues.count)
			last_error := Void
			if not a_states.is_empty and then has_unique_identities then
				across issues as c loop
					if normalized_has (a_states, c.item.state) then last_issues.extend (c.item) end
				end
			end
		end

	fetch_issues_by_ids (a_ids: LIST [STRING_32])
		do
			create last_issues.make (a_ids.count)
			last_error := Void
			if not a_ids.is_empty and then has_unique_identities then
				across issues as c loop
					if exact_has (a_ids, c.item.id) then last_issues.extend (c.item) end
				end
			end
		end

feature {NONE} -- Helpers

	has_unique_identities: BOOLEAN
		local
			seen_ids, seen_identifiers, seen_keys: HASH_TABLE [BOOLEAN, STRING_32]
			identifier_key, workspace_key: STRING_32
		do
			Result := True
			create seen_ids.make (issues.count)
			create seen_identifiers.make (issues.count)
			create seen_keys.make (issues.count)
			seen_ids.compare_objects
			seen_identifiers.compare_objects
			seen_keys.compare_objects
			across issues as cursor until not Result loop
				identifier_key := filesystem_key (cursor.item.identifier)
				workspace_key := filesystem_key (safety.workspace_key (cursor.item.identifier))
				if seen_ids.has (cursor.item.id) or else seen_identifiers.has (identifier_key) or else seen_keys.has (workspace_key) then
					Result := False
					create last_error.make ("tracker_response", "Memory tracker contains duplicate issue or workspace identities")
				else
					seen_ids.force (True, cursor.item.id)
					seen_identifiers.force (True, identifier_key)
					seen_keys.force (True, workspace_key)
				end
			end
		end

	filesystem_key (a_value: READABLE_STRING_GENERAL): STRING_32
		do
			Result := a_value.to_string_32.twin
			if {PLATFORM}.is_windows or else {PLATFORM}.is_mac then Result.to_lower end
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

	strings: SYM_STRINGS once create Result end

	safety: SYM_PATH_SAFETY once create Result end

end
