note
	description: "Provider-neutral schedulable issue defined by Symphony SPEC section 4.1.1."

class
	SYM_ISSUE

create
	make

feature {NONE} -- Initialization

	make (a_id, a_identifier, a_title, a_state: READABLE_STRING_GENERAL)
		do
			id := a_id.to_string_32.twin
			identifier := a_identifier.to_string_32.twin
			title := a_title.to_string_32.twin
			state := a_state.to_string_32.twin
			create labels.make (0)
			create blocked_by.make (0)
			dispatchable := True
		end

feature -- Required fields

	id: STRING_32

	identifier: STRING_32

	title: STRING_32

	state: STRING_32

	dispatchable: BOOLEAN

feature -- Optional fields

	native_ref: detachable JSON_OBJECT

	description: detachable STRING_32

	priority: detachable INTEGER_64_REF

	branch_name: detachable STRING_32

	url: detachable STRING_32

	assignee_id: detachable STRING_32

	labels: ARRAYED_LIST [STRING_32]

	blocked_by: ARRAYED_LIST [SYM_BLOCKER]

	created_at: detachable DATE_TIME

	updated_at: detachable DATE_TIME

feature -- Status

	is_core_valid: BOOLEAN
		do
			Result := not strings.is_blank (id) and then not strings.is_blank (identifier) and then
				not strings.is_blank (title) and then not strings.is_blank (state)
		end

	normalized_state: STRING_32
		do
			Result := strings.normalized (state)
		end

feature -- Element change

	set_description (a_value: detachable READABLE_STRING_GENERAL)
		do
			if attached a_value as v then description := v.to_string_32.twin else description := Void end
		end

	set_priority (a_value: detachable INTEGER_64_REF)
		do
			if attached a_value as v then priority := v.twin else priority := Void end
		end

	set_state (a_value: READABLE_STRING_GENERAL)
		do
			state := a_value.to_string_32.twin
		end

	set_native_ref (a_value: detachable JSON_OBJECT)
		do
			native_ref := a_value
		end

	set_branch_name (a_value: detachable READABLE_STRING_GENERAL)
		do
			if attached a_value as v then branch_name := v.to_string_32.twin else branch_name := Void end
		end

	set_url (a_value: detachable READABLE_STRING_GENERAL)
		do
			if attached a_value as v then url := v.to_string_32.twin else url := Void end
		end

	set_assignee_id (a_value: detachable READABLE_STRING_GENERAL)
		do
			if attached a_value as v then assignee_id := v.to_string_32.twin else assignee_id := Void end
		end

	set_dispatchable (a_value: BOOLEAN)
		do
			dispatchable := a_value
		end

	set_labels (a_values: ITERABLE [READABLE_STRING_GENERAL])
		do
			labels := strings.normalized_labels (a_values)
		end

	set_blocked_by (a_values: ITERABLE [SYM_BLOCKER])
		do
			create blocked_by.make (3)
			across a_values as c loop blocked_by.extend (c.item) end
		end

	set_created_at (a_value: detachable DATE_TIME)
		do
			created_at := a_value
		end

	set_updated_at (a_value: detachable DATE_TIME)
		do
			updated_at := a_value
		end

feature -- Conversion

	to_json: JSON_OBJECT
		local
			a: JSON_ARRAY
		do
			create Result.make_empty
			Result.put_string (id, "id")
			if attached native_ref as n then Result.put (json.cloned (n), "native_ref") else Result.put (Void, "native_ref") end
			Result.put_string (identifier, "identifier")
			Result.put_string (title, "title")
			if attached description as v then Result.put_string (v, "description") else Result.put (Void, "description") end
			if attached priority as v then Result.put_integer (v.item, "priority") else Result.put (Void, "priority") end
			Result.put_string (state, "state")
			if attached branch_name as v then Result.put_string (v, "branch_name") else Result.put (Void, "branch_name") end
			if attached url as v then Result.put_string (v, "url") else Result.put (Void, "url") end
			if attached assignee_id as v then Result.put_string (v, "assignee_id") else Result.put (Void, "assignee_id") end
			Result.put (json.string_array (labels), "labels")
			create a.make_empty
			across blocked_by as c loop a.extend (c.item.to_json) end
			Result.put (a, "blocked_by")
			Result.put_boolean (dispatchable, "dispatchable")
			if attached created_at as v then Result.put_string (clock.iso_8601 (v), "created_at") else Result.put (Void, "created_at") end
			if attached updated_at as v then Result.put_string (clock.iso_8601 (v), "updated_at") else Result.put (Void, "updated_at") end
		end

feature {NONE} -- Shared helpers

	strings: SYM_STRINGS
		once create Result end

	json: SYM_JSON
		once create Result end

	clock: SYM_CLOCK
		once create Result end

invariant
	labels_attached: labels /= Void
	blocked_by_attached: blocked_by /= Void

end
