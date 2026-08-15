note
	description: "String normalization helpers shared by the scheduler and adapters."

class
	SYM_STRINGS

feature -- Normalization

	normalized (a_value: READABLE_STRING_GENERAL): STRING_32
			-- Trimmed, lowercase comparison form of `a_value'.
		do
			Result := a_value.to_string_32.twin
			Result.left_adjust
			Result.right_adjust
			Result.to_lower
		end

	trimmed (a_value: READABLE_STRING_GENERAL): STRING_32
		do
			Result := a_value.to_string_32.twin
			Result.left_adjust
			Result.right_adjust
		end

	is_blank (a_value: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := trimmed (a_value).is_empty
		end

	normalized_labels (a_labels: ITERABLE [READABLE_STRING_GENERAL]): ARRAYED_LIST [STRING_32]
		local
			l_label: STRING_32
		do
			create Result.make (5)
			Result.compare_objects
			across a_labels as c loop
				l_label := normalized (c.item)
				if not l_label.is_empty and then not Result.has (l_label) then
					Result.extend (l_label)
				end
			end
		end

	has_all_labels (a_labels, a_required: ITERABLE [READABLE_STRING_GENERAL]): BOOLEAN
			-- Does normalized `a_labels' contain every configured required label?
		local
			l_labels: ARRAYED_LIST [STRING_32]
			l_required: STRING_32
		do
			l_labels := normalized_labels (a_labels)
			Result := True
			across a_required as c until not Result loop
				l_required := normalized (c.item)
				Result := not l_required.is_empty and then l_labels.has (l_required)
			end
		end

	utf_8 (a_value: READABLE_STRING_GENERAL): STRING_8
		local
			u: UTF_CONVERTER
		do
			create u
			Result := u.utf_32_string_to_utf_8_string_8 (a_value.as_string_32)
		end

end
