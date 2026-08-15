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
		end

feature -- Contract

	kind: STRING_32
		deferred
		end

	validate_config (a_config: SYM_CONFIG)
		deferred
		end

	fetch_issues_by_states (a_states: LIST [STRING_32])
		deferred
		ensure
			empty_short_circuit: a_states.is_empty implies last_issues.is_empty
		end

	fetch_issues_by_ids (a_ids: LIST [STRING_32])
		deferred
		ensure
			empty_short_circuit: a_ids.is_empty implies last_issues.is_empty
		end

	secret_environment_names: ARRAYED_LIST [STRING_32]
		do
			create Result.make (0)
		end

end

