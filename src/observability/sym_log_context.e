note
	description: "Stable issue and session fields attached to structured log events."

class
	SYM_LOG_CONTEXT

create
	make,
	make_with_values

feature {NONE} -- Initialization

	make
			-- Create an empty context.
		do
		ensure
			issue_id_absent: issue_id = Void
			issue_identifier_absent: issue_identifier = Void
			session_id_absent: session_id = Void
		end

	make_with_values (a_issue_id, a_issue_identifier, a_session_id: detachable READABLE_STRING_GENERAL)
		do
			set_issue_id (a_issue_id)
			set_issue_identifier (a_issue_identifier)
			set_session_id (a_session_id)
		ensure
			issue_id_cleared: a_issue_id = Void implies issue_id = Void
			issue_id_set: attached a_issue_id as value implies
				attached issue_id as stored and then stored.same_string_general (value)
			issue_identifier_cleared: a_issue_identifier = Void implies issue_identifier = Void
			issue_identifier_set: attached a_issue_identifier as value implies
				attached issue_identifier as stored and then stored.same_string_general (value)
			session_id_cleared: a_session_id = Void implies session_id = Void
			session_id_set: attached a_session_id as value implies
				attached session_id as stored and then stored.same_string_general (value)
		end

feature -- Access

	issue_id: detachable STRING_32

	issue_identifier: detachable STRING_32

	session_id: detachable STRING_32

	as_json: JSON_OBJECT
			-- Context represented with all stable keys, using JSON null for absent values.
		do
			create Result.make_with_capacity (3)
			put_optional_string (Result, "issue_id", issue_id)
			put_optional_string (Result, "issue_identifier", issue_identifier)
			put_optional_string (Result, "session_id", session_id)
		ensure
			stable_shape: Result.count = 3
			stable_keys: Result.has_key ("issue_id") and then
				Result.has_key ("issue_identifier") and then Result.has_key ("session_id")
		end

feature -- Element change

	set_issue (a_issue_id, a_issue_identifier: detachable READABLE_STRING_GENERAL)
		do
			set_issue_id (a_issue_id)
			set_issue_identifier (a_issue_identifier)
		ensure
			issue_id_cleared: a_issue_id = Void implies issue_id = Void
			issue_id_set: attached a_issue_id as value implies
				attached issue_id as stored and then stored.same_string_general (value)
			issue_identifier_cleared: a_issue_identifier = Void implies issue_identifier = Void
			issue_identifier_set: attached a_issue_identifier as value implies
				attached issue_identifier as stored and then stored.same_string_general (value)
		end

	set_issue_id (a_value: detachable READABLE_STRING_GENERAL)
		do
			if attached a_value as v then
				issue_id := v.to_string_32.twin
			else
				issue_id := Void
			end
		ensure
			cleared: a_value = Void implies issue_id = Void
			set: attached a_value as value implies
				attached issue_id as stored and then stored.same_string_general (value)
		end

	set_issue_identifier (a_value: detachable READABLE_STRING_GENERAL)
		do
			if attached a_value as v then
				issue_identifier := v.to_string_32.twin
			else
				issue_identifier := Void
			end
		ensure
			cleared: a_value = Void implies issue_identifier = Void
			set: attached a_value as value implies
				attached issue_identifier as stored and then stored.same_string_general (value)
		end

	set_session_id (a_value: detachable READABLE_STRING_GENERAL)
		do
			if attached a_value as v then
				session_id := v.to_string_32.twin
			else
				session_id := Void
			end
		ensure
			cleared: a_value = Void implies session_id = Void
			set: attached a_value as value implies
				attached session_id as stored and then stored.same_string_general (value)
		end

	clear_issue
		do
			issue_id := Void
			issue_identifier := Void
		ensure
			issue_id_absent: issue_id = Void
			issue_identifier_absent: issue_identifier = Void
		end

	clear_session
		do
			session_id := Void
		ensure
			session_id_absent: session_id = Void
		end

feature {NONE} -- JSON construction

	put_optional_string (a_object: JSON_OBJECT; a_key: READABLE_STRING_8;
		a_value: detachable READABLE_STRING_GENERAL)
		local
			l_key: JSON_STRING
			l_value: JSON_STRING
		do
			create l_key.make_from_string (a_key)
			if attached a_value as v then
				create l_value.make_from_string_general (v)
				a_object.put (l_value, l_key)
			else
				a_object.put (Void, l_key)
			end
		end

end
