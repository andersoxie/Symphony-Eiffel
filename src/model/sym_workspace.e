note
	description: "Filesystem workspace assigned to an issue identifier."

class
	SYM_WORKSPACE

create
	make

feature {NONE} -- Initialization

	make (a_path: PATH; a_key: READABLE_STRING_GENERAL; a_created_now: BOOLEAN)
		do
			path := a_path.canonical_path
			workspace_key := a_key.to_string_32.twin
			created_now := a_created_now
		end

feature -- Access

	path: PATH

	workspace_key: STRING_32

	created_now: BOOLEAN

end
