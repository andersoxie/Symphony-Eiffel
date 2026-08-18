note
	description: "Provider-neutral tracker read contract. Core orchestration never inspects provider payloads."

deferred class
	SYM_TRACKER_ADAPTER

feature -- Result

	last_issues: ARRAYED_LIST [SYM_ISSUE]
		deferred
		end

	last_error: detachable SYM_ERROR
		deferred
		end

	last_call_succeeded: BOOLEAN
		do
			Result := last_error = Void
		ensure
			definition: Result = (last_error = Void)
		end

feature -- Contract

	kind: STRING_32
		deferred
		ensure
			present: not Result.is_empty
		end

	validate_config (a_config: SYM_CONFIG)
		deferred
		ensure
			kind_mismatch_rejected:
				not a_config.tracker_kind.is_case_insensitive_equal (kind) implies last_error /= Void
		end

	fetch_issues_by_states (a_states: LIST [STRING_32])
		deferred
		ensure
			empty_short_circuit: a_states.is_empty implies last_issues.is_empty
			failure_has_no_issues: last_error /= Void implies last_issues.is_empty
		end

	fetch_issues_by_ids (a_ids: LIST [STRING_32])
		deferred
		ensure
			empty_short_circuit: a_ids.is_empty implies last_issues.is_empty
			failure_has_no_issues: last_error /= Void implies last_issues.is_empty
		end

	secret_environment_names: ARRAYED_LIST [STRING_32]
		do
			create Result.make (0)
		ensure
			all_names_present: across Result as name_cursor all
				not name_cursor.item.is_empty
			end
		end

end
