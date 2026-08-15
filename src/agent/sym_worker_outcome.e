note
	description: "Observable result of one synchronous per-issue worker attempt."

class
	SYM_WORKER_OUTCOME

create
	make_success,
	make_terminal,
	make_failure

feature {NONE} -- Initialization

	make_success (
		a_message, a_session_id: READABLE_STRING_GENERAL;
		a_turn_count: INTEGER;
		a_latest_issue: detachable SYM_ISSUE
	)
			-- Successful normal worker exit.
		do
			initialize (True, False, False, Void, a_message, a_session_id,
				a_turn_count, a_latest_issue)
		end

	make_terminal (
		a_message, a_session_id: READABLE_STRING_GENERAL;
		a_turn_count: INTEGER;
		a_latest_issue: SYM_ISSUE
	)
			-- Successful exit after observing a terminal tracker state.
		do
			initialize (True, False, True, Void, a_message, a_session_id,
				a_turn_count, a_latest_issue)
		end

	make_failure (
		a_error: SYM_ERROR;
		a_should_retry, a_is_terminal: BOOLEAN;
		a_session_id: READABLE_STRING_GENERAL;
		a_turn_count: INTEGER;
		a_latest_issue: detachable SYM_ISSUE
	)
			-- Failed exit, optionally retryable or terminal.
		do
			initialize (False, a_should_retry, a_is_terminal, a_error,
				a_error.message, a_session_id, a_turn_count, a_latest_issue)
		end

	initialize (
		a_is_success, a_should_retry, a_is_terminal: BOOLEAN;
		a_error: detachable SYM_ERROR;
		a_message, a_session_id: READABLE_STRING_GENERAL;
		a_turn_count: INTEGER;
		a_latest_issue: detachable SYM_ISSUE
	)
		require
			non_negative_turn_count: a_turn_count >= 0
			success_has_no_error: a_is_success implies a_error = Void
			failure_has_error: not a_is_success implies a_error /= Void
			retry_is_failure: a_should_retry implies not a_is_success
			terminal_is_not_retryable: a_is_terminal implies not a_should_retry
		do
			is_success := a_is_success
			should_retry := a_should_retry
			is_terminal := a_is_terminal
			error := a_error
			message := a_message.to_string_32.twin
			session_id := a_session_id.to_string_32.twin
			turn_count := a_turn_count
			latest_issue := a_latest_issue
		end

feature -- Status

	is_success: BOOLEAN

	should_retry: BOOLEAN
			-- Should the orchestrator schedule a failure-driven retry?

	is_terminal: BOOLEAN
			-- Did this attempt observe a terminal tracker state?

	is_failure: BOOLEAN
		do
			Result := not is_success
		end

	is_retry: BOOLEAN
			-- Compatibility query for `should_retry'.
		do
			Result := should_retry
		end

feature -- Details

	error: detachable SYM_ERROR

	message: STRING_32

	session_id: STRING_32
			-- Last observed `<thread_id>-<turn_id>', empty before the first turn starts.

	turn_count: INTEGER

	latest_issue: detachable SYM_ISSUE
			-- Last refreshed snapshot, or Void when the issue disappeared.

invariant
	non_negative_turn_count: turn_count >= 0
	success_has_no_error: is_success implies error = Void
	failure_has_error: not is_success implies error /= Void
	retry_is_failure: should_retry implies not is_success
	terminal_is_not_retryable: is_terminal implies not should_retry

end
