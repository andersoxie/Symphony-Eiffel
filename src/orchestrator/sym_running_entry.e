note
	description: "Orchestrator-owned state for one active worker."

class
	SYM_RUNNING_ENTRY

create
	make

feature {NONE} -- Initialization

	make (a_issue: SYM_ISSUE; a_worker: SYM_AGENT_WORKER; a_retry_attempt: INTEGER;
		a_config: SYM_CONFIG)
		do
			issue := a_issue
			workspace_identifier := a_issue.identifier.twin
			worker := a_worker
			retry_attempt := a_retry_attempt
			config := a_config
			create forced_reason.make_empty
		end

feature -- Access

	issue: SYM_ISSUE

	workspace_identifier: STRING_32
			-- Immutable dispatch-time identity of the workspace owned by this run.

	worker: SYM_AGENT_WORKER

	retry_attempt: INTEGER

	config: SYM_CONFIG
			-- Configuration snapshot used to create this worker and its workspace.

	forced_reason: STRING_32

	forced_retry: BOOLEAN

	forced_terminal: BOOLEAN

	set_issue (a_issue: SYM_ISSUE)
		do
			issue := a_issue
		end

	mark_forced_stop (a_reason: READABLE_STRING_GENERAL; a_retry, a_terminal: BOOLEAN)
		do
			if forced_reason.is_empty or else
				(a_terminal and then not forced_terminal) or else
				(not a_retry and then forced_retry and then not forced_terminal)
			then
				forced_reason := a_reason.to_string_32.twin
				forced_retry := a_retry
				forced_terminal := a_terminal
			end
		end

end
