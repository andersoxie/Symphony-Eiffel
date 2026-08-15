note
	description: "Small typed facade over Eiffel JSON values."

class
	SYM_JSON

feature -- Parsing

	parsed_value (a_text: READABLE_STRING_8): detachable JSON_VALUE
		local
			p: JSON_PARSER
		do
			create p.make_with_string (a_text.to_string_8)
			p.parse_content
			if p.is_valid then
				Result := p.parsed_json_value
			end
		end

	parsed_object (a_text: READABLE_STRING_8): detachable JSON_OBJECT
		do
			if attached {JSON_OBJECT} parsed_value (a_text) as o then
				Result := o
			end
		end

	cloned (a_value: JSON_VALUE): JSON_VALUE
			-- Structurally independent JSON value.
		local
			object_copy: JSON_OBJECT
			array_copy: JSON_ARRAY
		do
			if attached {JSON_OBJECT} a_value as object_value then
				create object_copy.make_empty
				across object_value as cursor loop
					object_copy.put (cloned (cursor.item), create {JSON_STRING}.make_from_string_32 (cursor.key.unescaped_string_32))
				end
				Result := object_copy
			elseif attached {JSON_ARRAY} a_value as array_value then
				create array_copy.make_empty
				across array_value as cursor loop array_copy.extend (cloned (cursor.item)) end
				Result := array_copy
			elseif attached {JSON_STRING} a_value as string_value then
				create {JSON_STRING} Result.make_from_string_32 (string_value.unescaped_string_32)
			elseif attached {JSON_NUMBER} a_value as number_value then
				if number_value.is_integer then
					create {JSON_NUMBER} Result.make_integer (number_value.integer_64_item)
				elseif number_value.is_natural then
					create {JSON_NUMBER} Result.make_natural (number_value.natural_64_item)
				else
					create {JSON_NUMBER} Result.make_real (number_value.real_64_item)
				end
			elseif attached {JSON_BOOLEAN} a_value as boolean_value then
				create {JSON_BOOLEAN} Result.make (boolean_value.item)
			else
				create {JSON_NULL} Result
			end
		end

feature -- Typed access

	string (a_object: JSON_OBJECT; a_key: READABLE_STRING_8): detachable STRING_32
		do
			if attached {JSON_STRING} a_object.item (a_key) as v then
				Result := v.unescaped_string_32
			end
		end

	integer_64 (a_object: JSON_OBJECT; a_key: READABLE_STRING_8): detachable INTEGER_64_REF
		local
			s: STRING_8
		do
			if attached {JSON_NUMBER} a_object.item (a_key) as v then
				s := v.item
				if s.is_integer_64 then
					create Result
					Result.set_item (s.to_integer_64)
				end
			end
		end

	boolean (a_object: JSON_OBJECT; a_key: READABLE_STRING_8; a_default: BOOLEAN): BOOLEAN
		do
			if attached {JSON_BOOLEAN} a_object.item (a_key) as v then
				Result := v.item
			else
				Result := a_default
			end
		end

	object (a_object: JSON_OBJECT; a_key: READABLE_STRING_8): detachable JSON_OBJECT
		do
			if attached {JSON_OBJECT} a_object.item (a_key) as v then
				Result := v
			end
		end

	array (a_object: JSON_OBJECT; a_key: READABLE_STRING_8): detachable JSON_ARRAY
		do
			if attached {JSON_ARRAY} a_object.item (a_key) as v then
				Result := v
			end
		end

	string_list (a_object: JSON_OBJECT; a_key: READABLE_STRING_8): ARRAYED_LIST [STRING_32]
		do
			create Result.make (5)
			if attached array (a_object, a_key) as a then
				across a as c loop
					if attached {JSON_STRING} c.item as s then
						Result.extend (s.unescaped_string_32)
					end
				end
			end
		end

feature -- Construction

	string_array (a_values: ITERABLE [READABLE_STRING_GENERAL]): JSON_ARRAY
		do
			create Result.make_empty
			across a_values as c loop
				Result.extend (create {JSON_STRING}.make_from_string_general (c.item))
			end
		end

end
