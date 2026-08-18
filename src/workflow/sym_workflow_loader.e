note
	description: "WORKFLOW.md discovery and YAML-front-matter loader."

class
	SYM_WORKFLOW_LOADER

create
	make

feature {NONE} -- Initialization

	make
		do
			create yaml.make
		ensure
			idle: not is_success and workflow = Void and error = Void
		end

feature -- Result

	workflow: detachable SYM_WORKFLOW

	error: detachable SYM_ERROR

	is_success: BOOLEAN
		do
			Result := workflow /= Void and error = Void
		ensure
			definition: Result = (workflow /= Void and error = Void)
		end

feature -- Loading

	load (a_path: PATH)
		local
			f: RAW_FILE
			content, yaml_text, prompt_8: STRING_8
			config: JSON_OBJECT
			closing_start, body_start: INTEGER
			prompt_32: STRING_32
		do
			workflow := Void
			error := Void
			create f.make_with_path (a_path)
			if not f.exists or else not f.is_plain then
				set_error ("missing_workflow_file", "Cannot read workflow file: " + a_path.name)
			elseif not f.is_readable then
				set_error ("missing_workflow_file", "Workflow file is not readable: " + a_path.name)
			else
				f.open_read
				f.read_stream (f.count)
				content := f.last_string
				f.close
				if starts_with_front_matter (content) then
					closing_start := closing_marker_start (content)
					if closing_start = 0 then
						set_error ("workflow_parse_error", "YAML front matter is missing its closing --- marker")
					else
						yaml_text := content.substring (first_line_end (content) + 1, closing_start - 1)
						yaml.parse (yaml_text)
						if not yaml.is_valid or else not attached yaml.root as r then
							if yaml.error_message.has_substring ("document root must be a map") then
								set_error ("workflow_front_matter_not_a_map", yaml.error_message)
							else
								set_error ("workflow_parse_error", yaml.error_message)
							end
						else
							config := r
							body_start := line_end_after (content, closing_start)
							if body_start <= content.count then prompt_8 := content.substring (body_start, content.count) else create prompt_8.make_empty end
							prompt_32 := decoded_utf_8 (prompt_8)
							prompt_32.left_adjust
							prompt_32.right_adjust
							create workflow.make (config, prompt_32, a_path, hash.sha_256_hex (content))
						end
					end
				else
					create config.make_empty
					prompt_32 := decoded_utf_8 (content)
					prompt_32.left_adjust
					prompt_32.right_adjust
					create workflow.make (config, prompt_32, a_path, hash.sha_256_hex (content))
				end
			end
		ensure
			complete_result: (workflow /= Void) /= (error /= Void)
			loaded_path_preserved: attached workflow as loaded implies
				loaded.path.is_equal (a_path.canonical_path)
		rescue
			if attached f as open_file and then open_file.is_open_read then open_file.close end
			workflow := Void
			set_error ("missing_workflow_file", "Unexpected I/O error while reading WORKFLOW.md")
		end

feature {NONE} -- Front matter splitting

	starts_with_front_matter (s: STRING_8): BOOLEAN
		do
			Result := s.count >= 3 and then s.substring (1, 3).same_string ("---") and then
				(s.count = 3 or else s [4] = '%N' or else s [4] = '%R')
		end

	first_line_end (s: STRING_8): INTEGER
		do
			Result := s.index_of ('%N', 1)
			if Result = 0 then Result := s.count end
		end

	closing_marker_start (s: STRING_8): INTEGER
		local
			i, start, stop: INTEGER
			line: STRING_8
		do
			from i := first_line_end (s) + 1 until i > s.count or Result > 0 loop
				start := i
				stop := s.index_of ('%N', start)
				if stop = 0 then stop := s.count + 1 end
				line := s.substring (start, stop - 1)
				if line.ends_with ("%R") then line.remove_tail (1) end
				if line.same_string ("---") then Result := start else i := stop + 1 end
			end
		end

	line_end_after (s: STRING_8; a_start: INTEGER): INTEGER
		local
			i: INTEGER
		do
			i := s.index_of ('%N', a_start)
			if i = 0 then Result := s.count + 1 else Result := i + 1 end
		end

	decoded_utf_8 (s: STRING_8): STRING_32
		local
			u: UTF_CONVERTER
		do
			create u
			if u.is_valid_utf_8_string_8 (s) then
				Result := u.utf_8_string_8_to_string_32 (s)
			else
				Result := s.to_string_32
			end
		end

	set_error (a_code, a_message: READABLE_STRING_GENERAL)
		do
			if error = Void then create error.make (a_code, a_message) end
		end

	yaml: SYM_YAML_PARSER

	hash: SYM_HASH once create Result end

end
