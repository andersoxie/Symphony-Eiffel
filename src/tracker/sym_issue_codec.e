note
	description: "JSON codec for normalized Symphony issues."

class
	SYM_ISSUE_CODEC

create
	make

feature {NONE} -- Initialization

	make
		do
		end

feature -- Result

	issue: detachable SYM_ISSUE

	error: detachable SYM_ERROR

	decode (a_object: JSON_OBJECT)
		local
			i: SYM_ISSUE
			labels: ARRAYED_LIST [STRING_32]
			blockers: ARRAYED_LIST [SYM_BLOCKER]
			b: SYM_BLOCKER
		do
			issue := Void
			error := Void
			if attached json.string (a_object, "id") as id and then not strings.is_blank (id) and then
				attached json.string (a_object, "identifier") as identifier and then not strings.is_blank (identifier) and then
				attached json.string (a_object, "title") as title and then not strings.is_blank (title) and then
				attached json.string (a_object, "state") as state and then not strings.is_blank (state) and then
				attached {JSON_BOOLEAN} a_object.item ("dispatchable") as dispatch
			then
				create i.make (id, identifier, title, state)
				i.set_description (nullable_string (a_object, "description"))
				i.set_priority (json.integer_64 (a_object, "priority"))
				i.set_branch_name (nullable_string (a_object, "branch_name"))
				i.set_url (nullable_string (a_object, "url"))
				i.set_assignee_id (nullable_string (a_object, "assignee_id"))
				i.set_dispatchable (dispatch.item)
				if attached json.object (a_object, "native_ref") as n and then not contains_secret_key (n) then
					i.set_native_ref (n)
				end
				labels := json.string_list (a_object, "labels")
				i.set_labels (labels)
				create blockers.make (3)
				if attached json.array (a_object, "blocked_by") as a then
					across a as c loop
						if attached {JSON_OBJECT} c.item as o then
							create b.make (nullable_string (o, "id"), nullable_string (o, "identifier"), nullable_string (o, "state"))
							blockers.extend (b)
						end
					end
				end
				i.set_blocked_by (blockers)
				if attached nullable_string (a_object, "created_at") as created then i.set_created_at (dates.parsed (created)) end
				if attached nullable_string (a_object, "updated_at") as updated then i.set_updated_at (dates.parsed (updated)) end
				issue := i
			else
				create error.make ("tracker_response", "Issue record is missing id, identifier, title, state, or boolean dispatchable")
			end
		end

feature {NONE} -- Helpers

	nullable_string (a_object: JSON_OBJECT; a_key: READABLE_STRING_8): detachable STRING_32
		do
			Result := json.string (a_object, a_key)
		end

	contains_secret_key (a_value: detachable JSON_VALUE): BOOLEAN
			-- Does a provider-native value contain a conventionally secret field?
			-- Unsafe `native_ref' values normalize to null instead of entering prompts.
		do
			if attached {JSON_OBJECT} a_value as object then
				across object as cursor until Result loop
					Result := is_secret_key (cursor.key.unescaped_string_32) or else contains_secret_key (cursor.item)
				end
			elseif attached {JSON_ARRAY} a_value as array then
				across array as cursor until Result loop
					Result := contains_secret_key (cursor.item)
				end
			end
		end

	is_secret_key (a_key: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := secret_keys.is_secret_key (a_key)
		end

	json: SYM_JSON once create Result end

	strings: SYM_STRINGS once create Result end

	dates: SYM_RFC3339 once create Result end

	secret_keys: SYM_SECRET_KEYS once create Result end

end
