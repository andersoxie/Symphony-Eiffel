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
		ensure
			trimmed: has_no_outer_whitespace (Result)
			lowercase: Result.same_string (Result.as_lower)
			empty_iff_blank: Result.is_empty = trimmed (a_value).is_empty
		end

	trimmed (a_value: READABLE_STRING_GENERAL): STRING_32
		do
			Result := a_value.to_string_32.twin
			Result.left_adjust
			Result.right_adjust
		ensure
			no_outer_whitespace: has_no_outer_whitespace (Result)
			not_longer: Result.count <= a_value.count
		end

	is_blank (a_value: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := trimmed (a_value).is_empty
		ensure
			definition: Result = trimmed (a_value).is_empty
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
		ensure
			normalized_and_unique: labels_are_normalized_and_unique (Result)
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
		ensure
			empty_finite_requirements:
				attached {FINITE [READABLE_STRING_GENERAL]} a_required as finite_required and then
					finite_required.is_empty implies Result
		end

	utf_8 (a_value: READABLE_STRING_GENERAL): STRING_8
		local
			u: UTF_CONVERTER
		do
			create u
			Result := u.utf_32_string_to_utf_8_string_8 (a_value.as_string_32)
		ensure
			empty_preserved: a_value.is_empty implies Result.is_empty
		end

feature {NONE} -- Contract support

	has_no_outer_whitespace (a_value: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := a_value.is_empty or else
				(not a_value [1].is_space and then not a_value [a_value.count].is_space)
		end

	labels_are_normalized_and_unique (a_labels: ARRAYED_LIST [STRING_32]): BOOLEAN
		local
			i: INTEGER
		do
			Result := a_labels.object_comparison
			from i := 1 until i > a_labels.count or else not Result loop
				Result := not a_labels [i].is_empty and then
					a_labels [i].same_string (a_labels [i].as_lower) and then
					a_labels.occurrences (a_labels [i]) = 1
				i := i + 1
			end
		end

end
