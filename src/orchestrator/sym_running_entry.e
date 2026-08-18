note
	description: "Orchestrator-owned state for one active worker."

class
	SYM_RUNNING_ENTRY

create
	make

feature {NONE} -- Initialization

	make (a_issue: SYM_ISSUE; a_worker: SYM_AGENT_WORKER; a_retry_attempt: INTEGER;
		a_config: SYM_CONFIG)
		require
			retry_attempt_non_negative: a_retry_attempt >= 0
		do
			issue := a_issue
			workspace_identifier := a_issue.identifier.twin
			worker := a_worker
			retry_attempt := a_retry_attempt
			config := a_config
			create forced_reason.make_empty
		ensure
			issue_set: issue = a_issue
			workspace_identity_captured: workspace_identifier.same_string (a_issue.identifier)
			worker_set: worker = a_worker
			retry_attempt_set: retry_attempt = a_retry_attempt
			config_set: config = a_config
			no_forced_stop: forced_reason.is_empty and not forced_retry and not forced_terminal
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
		require
			same_dispatch_id: a_issue.id.same_string (issue.id)
		do
			issue := a_issue
		ensure
			issue_set: issue = a_issue
			workspace_identity_unchanged: workspace_identifier ~ old workspace_identifier.twin
		end

	mark_forced_stop (a_reason: READABLE_STRING_GENERAL; a_retry, a_terminal: BOOLEAN)
		require
			reason_present: not a_reason.is_empty
			terminal_not_retryable: not (a_retry and a_terminal)
		do
			if forced_reason.is_empty or else
				(a_terminal and then not forced_terminal) or else
				(not a_retry and then forced_retry and then not forced_terminal)
			then
				forced_reason := a_reason.to_string_32.twin
				forced_retry := a_retry
				forced_terminal := a_terminal
			end
		ensure
			reason_recorded: not forced_reason.is_empty
			terminal_not_retryable: forced_terminal implies not forced_retry
		end

invariant
	retry_attempt_non_negative: retry_attempt >= 0
	workspace_identifier_present: not workspace_identifier.is_empty
	terminal_not_retryable: forced_terminal implies not forced_retry

end
