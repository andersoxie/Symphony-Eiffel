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
		end

end
