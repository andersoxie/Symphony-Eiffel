note
	description: "Strict, small Liquid-style renderer for Symphony workflow prompts."

class
	SYM_PROMPT_RENDERER

create
	make

feature {NONE} -- Initialization

	make
		do
			create rendered_prompt.make_empty
		ensure
			output_empty: rendered_prompt.is_empty
			idle: not is_success and error = Void
		end

feature -- Result

	rendered_prompt: STRING_32

	error: detachable SYM_ERROR

	is_success: BOOLEAN

feature -- Rendering

	render (
		a_template: READABLE_STRING_GENERAL;
		a_issue: SYM_ISSUE;
		a_attempt: detachable INTEGER_64_REF
	)
			-- Render a_template using the normalized issue and attempt values.
		require
			valid_issue: a_issue.is_core_valid
			valid_attempt: attached a_attempt as attempt implies attempt.item > 0
		local
			template: STRING_32
			environment: HASH_TABLE [JSON_VALUE, STRING_32]
			rendered: STRING_32
			attempt_value: JSON_VALUE
		do
			is_success := False
			error := Void
			create rendered_prompt.make_empty
			template := a_template.to_string_32
			if structure_is_valid (template) then
				create environment.make (3)
				environment.force (a_issue.to_json, "issue")
				if attached a_attempt as v then
					create {JSON_NUMBER} attempt_value.make_integer (v.item)
				else
					create {JSON_NULL} attempt_value
				end
				environment.force (attempt_value, "attempt")
				rendered := rendered_fragment (template, 1, template.count, environment)
				if error = Void then
					rendered_prompt := rendered
					is_success := True
				end
			end
		ensure
			status_consistent: is_success = (error = Void)
			failure_clears_output: not is_success implies rendered_prompt.is_empty
		rescue
			is_success := False
			create rendered_prompt.make_empty
			if error = Void then
				set_error ("template_render_error", "Unexpected failure while rendering the workflow prompt")
			end
		end

feature {NONE} -- Template validation

	structure_is_valid (a_template: STRING_32): BOOLEAN
			-- Are all delimiters and control blocks balanced and syntactically valid?
		local
			position, opening, closing, stray_closing, nested_opening: INTEGER
			tag, word, expression: STRING_32
			blocks: ARRAYED_STACK [STRING_32]
			for_parts: detachable TUPLE [variable_name, source: STRING_32]
		do
			create blocks.make (5)
			from
				position := 1
			until
				position > a_template.count or else error /= Void
			loop
				opening := next_opening_index (a_template, position)
				stray_closing := next_closing_index (a_template, position)
				if opening = 0 then
					if stray_closing > 0 then
						set_parse_error ("Closing template delimiter has no matching opening delimiter")
					end
					position := a_template.count + 1
				elseif stray_closing > 0 and then stray_closing < opening then
					set_parse_error ("Closing template delimiter has no matching opening delimiter")
				elseif is_output_opening (a_template, opening) then
					closing := a_template.substring_index (output_close, opening + 2)
					if closing = 0 then
						set_parse_error ("Unclosed output tag")
					else
						nested_opening := next_opening_index (a_template, opening + 2)
						if nested_opening > 0 and then nested_opening < closing then
							set_parse_error ("Nested template opening delimiter in output tag")
						else
							expression := trimmed_slice (a_template, opening + 2, closing - 1)
							if expression.is_empty then
								set_parse_error ("Output tag has no expression")
							else
								validate_pipeline (expression)
							end
							position := closing + 2
						end
					end
				else
					closing := a_template.substring_index (statement_close, opening + 2)
					if closing = 0 then
						set_parse_error ("Unclosed statement tag")
					else
						nested_opening := next_opening_index (a_template, opening + 2)
						if nested_opening > 0 and then nested_opening < closing then
							set_parse_error ("Nested template opening delimiter in statement tag")
						else
							tag := trimmed_slice (a_template, opening + 2, closing - 1)
							word := first_word (tag)
							if word.same_string ("if") then
								expression := after_first_word (tag)
								if expression.is_empty then
									set_parse_error ("if tag has no condition")
								else
									validate_pipeline (expression)
									blocks.extend ("if")
								end
							elseif word.same_string ("for") then
								for_parts := parsed_for_header (tag)
								if attached for_parts as p then
									validate_pipeline (p.source)
									blocks.extend ("for")
								else
									set_parse_error ("Malformed for tag; expected: for name in expression")
								end
							elseif word.same_string ("else") then
								if not after_first_word (tag).is_empty then
									set_parse_error ("else tag must not have an argument")
								elseif blocks.is_empty or else not blocks.item.same_string ("if") then
									set_parse_error ("else tag is not inside an if block")
								else
									blocks.remove
									blocks.extend ("else")
								end
							elseif word.same_string ("endif") then
								if not after_first_word (tag).is_empty then
									set_parse_error ("endif tag must not have an argument")
								elseif blocks.is_empty or else
									not (blocks.item.same_string ("if") or blocks.item.same_string ("else"))
								then
									set_parse_error ("endif tag has no matching if tag")
								else
									blocks.remove
								end
							elseif word.same_string ("endfor") then
								if not after_first_word (tag).is_empty then
									set_parse_error ("endfor tag must not have an argument")
								elseif blocks.is_empty or else not blocks.item.same_string ("for") then
									set_parse_error ("endfor tag has no matching for tag")
								else
									blocks.remove
								end
							else
								set_parse_error ("Unknown or empty statement tag: " + tag)
							end
							position := closing + 2
						end
					end
				end
			end
			if error = Void and then not blocks.is_empty then
				set_parse_error ("Unclosed " + blocks.item + " block")
			end
			Result := error = Void
		end

	validate_pipeline (a_expression: STRING_32)
			-- Validate pipeline punctuation and filter names without evaluating it.
		local
			parts: ARRAYED_LIST [STRING_32]
			filter_text, filter_name, argument: STRING_32
			colon: INTEGER
		do
			parts := split_unquoted (a_expression, '|')
			if parts.is_empty or else parts.first.is_empty or else not base_syntax_is_valid (parts.first) then
				set_parse_error ("Malformed expression: " + a_expression)
			else
				across
					parts as c
				loop
					if c.cursor_index > 1 and then error = Void then
						filter_text := c.item
						colon := unquoted_index_of (filter_text, ':', 1)
						if colon = 0 then
							filter_name := filter_text.twin
							create argument.make_empty
						else
							filter_name := trimmed_slice (filter_text, 1, colon - 1)
							argument := trimmed_slice (filter_text, colon + 1, filter_text.count)
						end
						filter_name.left_adjust
						filter_name.right_adjust
						if filter_name.is_empty or else not is_known_filter (filter_name) then
							set_error ("template_render_error", "Unknown filter: " + filter_name)
						elseif filter_name.same_string ("default") then
							if colon = 0 or else argument.is_empty or else not base_syntax_is_valid (argument) then
								set_parse_error ("default filter requires one valid argument")
							end
						elseif colon > 0 then
							set_parse_error (filter_name + " filter does not accept an argument")
						end
					end
				end
			end
		end

feature {NONE} -- Recursive rendering

	rendered_fragment (
		a_template: STRING_32;
		a_start, a_finish: INTEGER;
		a_environment: HASH_TABLE [JSON_VALUE, STRING_32]
	): STRING_32
		local
			position, opening, closing: INTEGER
			tag, word, expression, branch_text: STRING_32
			value: detachable JSON_VALUE
			bounds: detachable TUPLE [else_open, else_after, close_open, after_close: INTEGER]
			for_parts: detachable TUPLE [variable_name, source: STRING_32]
			child_environment: HASH_TABLE [JSON_VALUE, STRING_32]
		do
			create Result.make (a_finish - a_start + 1)
			from
				position := a_start
			until
				position > a_finish or else error /= Void
			loop
				opening := next_opening_index_before (a_template, position, a_finish)
				if opening = 0 then
					if position <= a_finish then
						Result.append (a_template.substring (position, a_finish))
					end
					position := a_finish + 1
				else
					if position < opening then
						Result.append (a_template.substring (position, opening - 1))
					end
					if is_output_opening (a_template, opening) then
						closing := a_template.substring_index (output_close, opening + 2)
						expression := trimmed_slice (a_template, opening + 2, closing - 1)
						value := evaluated_pipeline (expression, a_environment)
						if attached value as v and then error = Void then
							Result.append (display_string (v))
						end
						position := closing + 2
					else
						closing := a_template.substring_index (statement_close, opening + 2)
						tag := trimmed_slice (a_template, opening + 2, closing - 1)
						word := first_word (tag)
						if word.same_string ("if") then
							bounds := matching_block_bounds (a_template, closing + 2, True)
							if attached bounds as b then
								value := evaluated_pipeline (after_first_word (tag), a_environment)
								if attached value as v and then error = Void then
									if is_truthy (v) then
										if b.else_open > 0 then
											branch_text := rendered_fragment (
												a_template, closing + 2, b.else_open - 1, a_environment
											)
										else
											branch_text := rendered_fragment (
												a_template, closing + 2, b.close_open - 1, a_environment
											)
										end
									elseif b.else_open > 0 then
										branch_text := rendered_fragment (
											a_template, b.else_after, b.close_open - 1, a_environment
										)
									else
										create branch_text.make_empty
									end
									Result.append (branch_text)
								end
								position := b.after_close
							else
								set_parse_error ("if block has no matching endif tag")
							end
						elseif word.same_string ("for") then
							bounds := matching_block_bounds (a_template, closing + 2, False)
							for_parts := parsed_for_header (tag)
							if attached bounds as b and attached for_parts as p then
								value := evaluated_pipeline (p.source, a_environment)
								if attached {JSON_ARRAY} value as items and then error = Void then
									across
										items as c
									loop
										if error = Void then
											child_environment := copied_environment (a_environment)
											child_environment.force (c.item, p.variable_name)
											branch_text := rendered_fragment (
												a_template, closing + 2, b.close_open - 1, child_environment
											)
											Result.append (branch_text)
										end
									end
								elseif error = Void then
									set_error ("template_render_error", "for source is not an array: " + p.source)
								end
								position := b.after_close
							else
								set_parse_error ("for block has no matching endfor tag")
							end
						else
							set_parse_error ("Unexpected control tag while rendering: " + tag)
						end
					end
				end
			end
		end

	matching_block_bounds (
		a_template: STRING_32;
		a_body_start: INTEGER;
		a_accept_else: BOOLEAN
	): detachable TUPLE [else_open, else_after, close_open, after_close: INTEGER]
			-- Bounds of the control block whose body begins at a_body_start.
		local
			position, opening, closing, depth, found_else, else_after: INTEGER
			word, tag: STRING_32
		do
			from
				position := a_body_start
				depth := 1
			until
				position > a_template.count or else Result /= Void
			loop
				opening := a_template.substring_index (statement_open, position)
				if opening = 0 then
					position := a_template.count + 1
				else
					closing := a_template.substring_index (statement_close, opening + 2)
					tag := trimmed_slice (a_template, opening + 2, closing - 1)
					word := first_word (tag)
					if word.same_string ("if") or else word.same_string ("for") then
						depth := depth + 1
					elseif word.same_string ("endif") or else word.same_string ("endfor") then
						depth := depth - 1
						if depth = 0 then
							Result := [found_else, else_after, opening, closing + 2]
						end
					elseif word.same_string ("else") and then depth = 1 and then a_accept_else then
						found_else := opening
						else_after := closing + 2
					end
					position := closing + 2
				end
			end
		end

feature {NONE} -- Expression evaluation

	evaluated_pipeline (
		a_expression: STRING_32;
		a_environment: HASH_TABLE [JSON_VALUE, STRING_32]
	): detachable JSON_VALUE
		local
			parts: ARRAYED_LIST [STRING_32]
			current_value: detachable JSON_VALUE
			filter_text, filter_name, argument: STRING_32
			colon: INTEGER
		do
			parts := split_unquoted (a_expression, '|')
			if not parts.is_empty then
				current_value := evaluated_base (parts.first, a_environment)
				across
					parts as c
				loop
					if c.cursor_index > 1 and then attached current_value as v and then error = Void then
						filter_text := c.item
						colon := unquoted_index_of (filter_text, ':', 1)
						if colon = 0 then
							filter_name := filter_text.twin
							create argument.make_empty
						else
							filter_name := trimmed_slice (filter_text, 1, colon - 1)
							argument := trimmed_slice (filter_text, colon + 1, filter_text.count)
						end
						filter_name.left_adjust
						filter_name.right_adjust
						current_value := filtered_value (v, filter_name, argument, a_environment)
					end
				end
				Result := current_value
			end
		end

	evaluated_base (
		a_expression: STRING_32;
		a_environment: HASH_TABLE [JSON_VALUE, STRING_32]
	): detachable JSON_VALUE
		local
			expression, content: STRING_32
			number: INTEGER_64
		do
			expression := a_expression.twin
			expression.left_adjust
			expression.right_adjust
			if is_quoted (expression) then
				content := unquoted (expression)
				create {JSON_STRING} Result.make_from_string_32 (content)
			elseif expression.same_string ("true") then
				create {JSON_BOOLEAN} Result.make_true
			elseif expression.same_string ("false") then
				create {JSON_BOOLEAN} Result.make_false
			elseif expression.same_string ("nil") or else expression.same_string ("null") then
				create {JSON_NULL} Result
			elseif expression.is_integer_64 then
				number := expression.to_integer_64
				create {JSON_NUMBER} Result.make_integer (number)
			else
				Result := resolved_path (expression, a_environment)
			end
		end

	resolved_path (
		a_path: STRING_32;
		a_environment: HASH_TABLE [JSON_VALUE, STRING_32]
	): detachable JSON_VALUE
			-- Resolve dotted object fields and zero-based array indices.
		local
			position, start, closing, index: INTEGER
			name, token: STRING_32
			current_value: detachable JSON_VALUE
		do
			from
				position := 1
			until
				position > a_path.count or else a_path [position] = '.' or else a_path [position] = '['
			loop
				position := position + 1
			end
			if position = 1 then
				set_error ("template_render_error", "Invalid variable path: " + a_path)
			else
				name := a_path.substring (1, position - 1)
				if a_environment.has_key (name) then
					current_value := a_environment.item (name)
				else
					set_error ("template_render_error", "Unknown variable: " + name)
				end
			end
			from
			until
				position > a_path.count or else error /= Void
			loop
				if a_path [position] = '.' then
					start := position + 1
					position := start
					from
					until
						position > a_path.count or else a_path [position] = '.' or else a_path [position] = '['
					loop
						position := position + 1
					end
					if start = position then
						set_error ("template_render_error", "Invalid member in variable path: " + a_path)
					else
						name := a_path.substring (start, position - 1)
						if attached {JSON_OBJECT} current_value as object_value then
							if object_value.has_key (name) then
								current_value := object_value.item (name)
							else
								set_error ("template_render_error", "Unknown variable: " + a_path.substring (1, position - 1))
							end
						else
							set_error ("template_render_error", "Cannot access member " + name + " on a non-object value")
						end
					end
				elseif a_path [position] = '[' then
					closing := a_path.index_of (']', position + 1)
					if closing = 0 then
						set_error ("template_render_error", "Unclosed array index in variable path: " + a_path)
					else
						token := trimmed_slice (a_path, position + 1, closing - 1)
						if not token.is_integer then
							set_error ("template_render_error", "Array index is not an integer: " + token)
						else
							index := token.to_integer
							if attached {JSON_ARRAY} current_value as array_value then
								if index >= 0 and then array_value.valid_index (index + 1) then
									current_value := array_value.i_th (index + 1)
								else
									set_error ("template_render_error", "Array index is out of bounds: " + token)
								end
							else
								set_error ("template_render_error", "Cannot index a non-array value")
							end
						end
						position := closing + 1
					end
				else
					set_error ("template_render_error", "Invalid variable path: " + a_path)
				end
			end
			if error = Void then
				Result := current_value
			end
		end

	filtered_value (
		a_value: JSON_VALUE;
		a_filter_name, a_argument: STRING_32;
		a_environment: HASH_TABLE [JSON_VALUE, STRING_32]
	): detachable JSON_VALUE
		local
			text: STRING_32
		do
			if a_filter_name.same_string ("default") then
				if is_defaultable (a_value) then
					Result := evaluated_base (a_argument, a_environment)
				else
					Result := a_value
				end
			elseif a_filter_name.same_string ("strip") then
				text := display_string (a_value)
				text.left_adjust
				text.right_adjust
				create {JSON_STRING} Result.make_from_string_32 (text)
			elseif a_filter_name.same_string ("downcase") then
				text := display_string (a_value).as_lower
				create {JSON_STRING} Result.make_from_string_32 (text)
			elseif a_filter_name.same_string ("upcase") then
				text := display_string (a_value).as_upper
				create {JSON_STRING} Result.make_from_string_32 (text)
			elseif a_filter_name.same_string ("json") then
				text := decoded_utf_8 (a_value.representation)
				create {JSON_STRING} Result.make_from_string_32 (text)
			else
				set_error ("template_render_error", "Unknown filter: " + a_filter_name)
			end
		end

feature {NONE} -- Value semantics

	display_string (a_value: JSON_VALUE): STRING_32
		do
			if attached {JSON_STRING} a_value as s then
				Result := s.unescaped_string_32
			elseif attached {JSON_NULL} a_value then
				create Result.make_empty
			else
				Result := decoded_utf_8 (a_value.representation)
			end
		end

	is_truthy (a_value: JSON_VALUE): BOOLEAN
			-- Liquid considers only false and null falsey.
		do
			Result := not attached {JSON_NULL} a_value and then
				not (attached {JSON_BOOLEAN} a_value as b and then not b.item)
		end

	is_defaultable (a_value: JSON_VALUE): BOOLEAN
		do
			Result :=
				attached {JSON_NULL} a_value or else
				(attached {JSON_BOOLEAN} a_value as b and then not b.item) or else
				(attached {JSON_STRING} a_value as s and then s.unescaped_string_32.is_empty) or else
				(attached {JSON_ARRAY} a_value as a and then a.is_empty) or else
				(attached {JSON_OBJECT} a_value as o and then o.is_empty)
		end

feature {NONE} -- Lexical helpers

	parsed_for_header (a_tag: STRING_32): detachable TUPLE [variable_name, source: STRING_32]
		local
			rest, variable_name, separator, source: STRING_32
			position, start: INTEGER
		do
			rest := after_first_word (a_tag)
			from position := 1 until position > rest.count or else not is_space (rest [position]) loop
				position := position + 1
			end
			start := position
			from until position > rest.count or else is_space (rest [position]) loop
				position := position + 1
			end
			if start <= rest.count then
				variable_name := rest.substring (start, position - 1)
			else
				create variable_name.make_empty
			end
			from until position > rest.count or else not is_space (rest [position]) loop
				position := position + 1
			end
			start := position
			from until position > rest.count or else is_space (rest [position]) loop
				position := position + 1
			end
			if start <= rest.count then
				separator := rest.substring (start, position - 1)
			else
				create separator.make_empty
			end
			from until position > rest.count or else not is_space (rest [position]) loop
				position := position + 1
			end
			if position <= rest.count then
				source := rest.substring (position, rest.count)
				source.right_adjust
			else
				create source.make_empty
			end
			if is_identifier (variable_name) and then separator.same_string ("in") and then not source.is_empty then
				Result := [variable_name, source]
			end
		end

	first_word (a_text: STRING_32): STRING_32
		local
			text: STRING_32
			position: INTEGER
		do
			text := a_text.twin
			text.left_adjust
			text.right_adjust
			position := text.index_of (' ', 1)
			if position = 0 then
				position := text.index_of ('%T', 1)
			end
			if position = 0 then
				Result := text
			else
				Result := text.substring (1, position - 1)
			end
		end

	after_first_word (a_text: STRING_32): STRING_32
		local
			position: INTEGER
		do
			from position := 1 until position > a_text.count or else is_space (a_text [position]) loop
				position := position + 1
			end
			from until position > a_text.count or else not is_space (a_text [position]) loop
				position := position + 1
			end
			if position <= a_text.count then
				Result := a_text.substring (position, a_text.count)
				Result.right_adjust
			else
				create Result.make_empty
			end
		end

	split_unquoted (a_text: STRING_32; a_separator: CHARACTER_32): ARRAYED_LIST [STRING_32]
		local
			position, start: INTEGER
			quote: CHARACTER_32
			escaped: BOOLEAN
			piece: STRING_32
		do
			create Result.make (3)
			from
				position := 1
				start := 1
			until
				position > a_text.count
			loop
				if escaped then
					escaped := False
				elseif quote /= '%U' and then a_text [position] = '\' then
					escaped := True
				elseif quote = '%U' and then (a_text [position] = '"' or else a_text [position] = '%'' ) then
					quote := a_text [position]
				elseif quote /= '%U' and then a_text [position] = quote then
					quote := '%U'
				elseif quote = '%U' and then a_text [position] = a_separator then
					piece := trimmed_slice (a_text, start, position - 1)
					Result.extend (piece)
					start := position + 1
				end
				position := position + 1
			end
			piece := trimmed_slice (a_text, start, a_text.count)
			Result.extend (piece)
		end

	unquoted_index_of (a_text: STRING_32; a_character: CHARACTER_32; a_start: INTEGER): INTEGER
		local
			position: INTEGER
			quote: CHARACTER_32
			escaped: BOOLEAN
		do
			from position := a_start until position > a_text.count or else Result > 0 loop
				if escaped then
					escaped := False
				elseif quote /= '%U' and then a_text [position] = '\' then
					escaped := True
				elseif quote = '%U' and then (a_text [position] = '"' or else a_text [position] = '%'' ) then
					quote := a_text [position]
				elseif quote /= '%U' and then a_text [position] = quote then
					quote := '%U'
				elseif quote = '%U' and then a_text [position] = a_character then
					Result := position
				end
				position := position + 1
			end
		end

	base_syntax_is_valid (a_expression: STRING_32): BOOLEAN
		local
			expression: STRING_32
		do
			expression := a_expression.twin
			expression.left_adjust
			expression.right_adjust
			Result := not expression.is_empty and then (
				is_quoted (expression) or else
				expression.same_string ("true") or else expression.same_string ("false") or else
				expression.same_string ("nil") or else expression.same_string ("null") or else
				expression.is_integer_64 or else path_syntax_is_valid (expression)
			)
		end

	path_syntax_is_valid (a_path: STRING_32): BOOLEAN
		local
			position, start, closing: INTEGER
			token: STRING_32
		do
			from position := 1 until position > a_path.count or else a_path [position] = '.' or else a_path [position] = '[' loop
				position := position + 1
			end
			Result := position > 1 and then is_identifier (a_path.substring (1, position - 1))
			from until position > a_path.count or else not Result loop
				if a_path [position] = '.' then
					start := position + 1
					position := start
					from until position > a_path.count or else a_path [position] = '.' or else a_path [position] = '[' loop
						position := position + 1
					end
					Result := start < position and then is_identifier (a_path.substring (start, position - 1))
				elseif a_path [position] = '[' then
					closing := a_path.index_of (']', position + 1)
					if closing = 0 then
						Result := False
					else
						token := trimmed_slice (a_path, position + 1, closing - 1)
						Result := token.is_integer and then token.to_integer >= 0
						position := closing + 1
					end
				else
					Result := False
				end
			end
		end

	is_quoted (a_text: STRING_32): BOOLEAN
		do
			Result := a_text.count >= 2 and then
				((a_text [1] = '"' and then a_text [a_text.count] = '"') or else
				(a_text [1] = '%'' and then a_text [a_text.count] = '%''))
		end

	unquoted (a_text: STRING_32): STRING_32
			-- Remove matching quotes and the common backslash escapes.
		local
			position: INTEGER
			escaped: BOOLEAN
		do
			create Result.make (a_text.count - 2)
			from position := 2 until position >= a_text.count loop
				if escaped then
					inspect a_text [position]
					when 'n' then Result.extend ('%N')
					when 'r' then Result.extend ('%R')
					when 't' then Result.extend ('%T')
					else Result.extend (a_text [position])
					end
					escaped := False
				elseif a_text [position] = '\' then
					escaped := True
				else
					Result.extend (a_text [position])
				end
				position := position + 1
			end
			if escaped then
				Result.extend ('\')
			end
		end

	is_identifier (a_text: STRING_32): BOOLEAN
		local
			position: INTEGER
			character: CHARACTER_32
		do
			Result := not a_text.is_empty
			from position := 1 until position > a_text.count or else not Result loop
				character := a_text [position]
				if position = 1 then
					Result := character = '_' or else character.is_alpha
				else
					Result := character = '_' or else character.is_alpha or else character.is_digit
				end
				position := position + 1
			end
		end

	is_known_filter (a_name: STRING_32): BOOLEAN
		do
			Result :=
				a_name.same_string ("default") or else
				a_name.same_string ("strip") or else
				a_name.same_string ("downcase") or else
				a_name.same_string ("upcase") or else
				a_name.same_string ("json")
		end

	is_space (a_character: CHARACTER_32): BOOLEAN
		do
			Result := a_character = ' ' or else a_character = '%T' or else
				a_character = '%N' or else a_character = '%R'
		end

	next_opening_index (a_template: STRING_32; a_start: INTEGER): INTEGER
		local
			output_index, statement_index: INTEGER
		do
			output_index := a_template.substring_index (output_open, a_start)
			statement_index := a_template.substring_index (statement_open, a_start)
			Result := earlier_positive (output_index, statement_index)
		end

	next_opening_index_before (a_template: STRING_32; a_start, a_finish: INTEGER): INTEGER
		do
			Result := next_opening_index (a_template, a_start)
			if Result > a_finish then
				Result := 0
			end
		end

	next_closing_index (a_template: STRING_32; a_start: INTEGER): INTEGER
		local
			output_index, statement_index: INTEGER
		do
			output_index := a_template.substring_index (output_close, a_start)
			statement_index := a_template.substring_index (statement_close, a_start)
			Result := earlier_positive (output_index, statement_index)
		end

	earlier_positive (a_first, a_second: INTEGER): INTEGER
		do
			if a_first = 0 then
				Result := a_second
			elseif a_second = 0 then
				Result := a_first
			else
				Result := a_first.min (a_second)
			end
		end

	is_output_opening (a_template: STRING_32; a_position: INTEGER): BOOLEAN
		do
			Result := a_position + 1 <= a_template.count and then
				a_template [a_position] = '{' and then a_template [a_position + 1] = '{'
		end

	trimmed_slice (a_text: STRING_32; a_start, a_finish: INTEGER): STRING_32
		do
			if a_start <= a_finish and then a_start >= 1 and then a_finish <= a_text.count then
				Result := a_text.substring (a_start, a_finish)
				Result.left_adjust
				Result.right_adjust
			else
				create Result.make_empty
			end
		end

	copied_environment (
		a_environment: HASH_TABLE [JSON_VALUE, STRING_32]
	): HASH_TABLE [JSON_VALUE, STRING_32]
		do
			create Result.make (a_environment.count + 1)
			across a_environment as c loop
				Result.force (c.item, c.key)
			end
		end

	decoded_utf_8 (a_text: READABLE_STRING_8): STRING_32
		local
			converter: UTF_CONVERTER
		do
			create converter
			if converter.is_valid_utf_8_string_8 (a_text) then
				Result := converter.utf_8_string_8_to_string_32 (a_text)
			else
				Result := a_text.to_string_32
			end
		end

	set_parse_error (a_message: READABLE_STRING_GENERAL)
		do
			set_error ("template_parse_error", a_message)
		end

	set_error (a_code, a_message: READABLE_STRING_GENERAL)
		do
			if error = Void then
				create error.make (a_code, a_message)
			end
		end

feature {NONE} -- Delimiters

	output_open: STRING_32
		once
			Result := "{{"
		end

	output_close: STRING_32
		once
			Result := "}}"
		end

	statement_open: STRING_32
		once
			Result := "{%%"
		end

	statement_close: STRING_32
		once
			Result := "%%}"
		end

invariant
	success_has_no_error: is_success implies error = Void
	error_clears_output: error /= Void implies not is_success and rendered_prompt.is_empty

end
