note
	description: "Filesystem workspace assigned to an issue identifier."

class
	SYM_WORKSPACE

create
	make

feature {NONE} -- Initialization

	make (a_path: PATH; a_key: READABLE_STRING_GENERAL; a_created_now: BOOLEAN)
		require
			key_present: not a_key.is_empty
		do
			path := a_path.canonical_path
			workspace_key := a_key.to_string_32.twin
			created_now := a_created_now
		ensure
			path_canonicalized: path.is_equal (a_path.canonical_path)
			key_set: workspace_key.same_string_general (a_key)
			creation_status_set: created_now = a_created_now
		end

feature -- Access

	path: PATH

	workspace_key: STRING_32

	created_now: BOOLEAN

end
