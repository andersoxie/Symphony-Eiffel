note
	description: "Scheduled retry state for one issue."

class
	SYM_RETRY_ENTRY

create
	make

feature {NONE} -- Initialization

	make (a_issue_id, a_identifier, a_workspace_identifier: READABLE_STRING_GENERAL;
		a_attempt: INTEGER; a_due_at_ms: INTEGER_64; a_error: detachable READABLE_STRING_GENERAL)
		require
			attempt_positive: a_attempt >= 1
		do
			issue_id := a_issue_id.to_string_32.twin
			identifier := a_identifier.to_string_32.twin
			workspace_identifier := a_workspace_identifier.to_string_32.twin
			attempt := a_attempt
			due_at_ms := a_due_at_ms
			if attached a_error as v then error := v.to_string_32.twin end
		end

feature -- Access

	issue_id: STRING_32

	identifier: STRING_32
			-- Best-effort current human identifier for status.

	workspace_identifier: STRING_32
			-- Immutable identifier of the workspace owned by the failed attempt.

	attempt: INTEGER

	due_at_ms: INTEGER_64

	error: detachable STRING_32

end
