note
	description: "Best-effort normalized blocker reference."

class
	SYM_BLOCKER

create
	make

feature {NONE} -- Initialization

	make (a_id, a_identifier, a_state: detachable READABLE_STRING_GENERAL)
		do
			if attached a_id as v then id := v.to_string_32.twin end
			if attached a_identifier as v then identifier := v.to_string_32.twin end
			if attached a_state as v then state := v.to_string_32.twin end
		ensure
			id_set:
				(attached a_id as source and then attached id as stored and then stored.same_string_general (source)) or else
				(a_id = Void and then id = Void)
			identifier_set:
				(attached a_identifier as source and then attached identifier as stored and then stored.same_string_general (source)) or else
				(a_identifier = Void and then identifier = Void)
			state_set:
				(attached a_state as source and then attached state as stored and then stored.same_string_general (source)) or else
				(a_state = Void and then state = Void)
		end

feature -- Access

	id: detachable STRING_32

	identifier: detachable STRING_32

	state: detachable STRING_32

	to_json: JSON_OBJECT
		do
			create Result.make_empty
			if attached id as v then Result.put_string (v, "id") else Result.put (Void, "id") end
			if attached identifier as v then Result.put_string (v, "identifier") else Result.put (Void, "identifier") end
			if attached state as v then Result.put_string (v, "state") else Result.put (Void, "state") end
		ensure
			stable_shape: Result.count = 3
		end

end
