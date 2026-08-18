note
	description: "Parser for the small, data-oriented YAML subset used by WORKFLOW.md front matter."
	license: "Apache-2.0"

class
	SYM_YAML_PARSER

create
	make

feature {NONE} -- Initialization

	make
			-- Create an idle parser.
		do
			create lines.make (16)
			create line_breaks.make (16)
			create flow_text.make_empty
			create error_message.make_empty
		ensure
			idle: not is_valid and root = Void and error_message.is_empty
		end

feature -- Access

	root: detachable JSON_OBJECT
			-- Parsed document root when `is_valid'.

	error_message: STRING_32
			-- Description of the first parse error, if any.

feature -- Status report

	is_valid: BOOLEAN
			-- Did the most recent call to `parse' produce a map document?

feature -- Basic operation

	parse (a_yaml: READABLE_STRING_8)
			-- Parse `a_yaml' into `root'.
			--
			-- This intentionally implements the YAML features used by Symphony workflow
			-- configuration rather than the complete YAML specification: block maps and
			-- sequences, flow collections, strings, booleans, nulls, decimal integers,
			-- comments, and literal/folded block strings.
		local
			l_value: detachable JSON_VALUE
			l_object: JSON_OBJECT
			l_indent: INTEGER
		do
			reset
			split_lines (a_yaml)
			skip_ignorable_lines
			if is_valid and then not after_lines and then is_document_start_line (lines [line_index]) then
				line_index := line_index + 1
				skip_ignorable_lines
			end

			if is_valid then
				if after_lines or else is_current_document_end then
					create l_object.make_empty
					root := l_object
				else
					l_indent := indentation_of (lines [line_index], line_index)
					if is_valid and then l_indent /= 0 then
						fail_at (line_index, "document root must start at indentation zero")
					end
					if is_valid then
						l_value := parse_block (0)
					end
					if is_valid then
						skip_ignorable_lines
						if is_current_document_end then
							line_index := line_index + 1
							skip_ignorable_lines
						end
						if not after_lines then
							fail_at (line_index, "unexpected content after the YAML document")
						elseif attached {JSON_OBJECT} l_value as o then
							root := o
						elseif l_value /= Void then
							fail_at (1, "document root must be a map")
						else
							fail_at (1, "could not parse the YAML document")
						end
					end
				end
			end
			if not is_valid then
				root := Void
			end
		ensure
			valid_exactly_when_root_available: is_valid = (root /= Void)
			valid_has_no_error: is_valid implies error_message.is_empty
			invalid_has_message: not is_valid implies not error_message.is_empty
		end

feature {NONE} -- Block parsing

	parse_block (a_indent: INTEGER): detachable JSON_VALUE
			-- Parse one block whose first content starts at `a_indent'.
		local
			l_indent, l_line: INTEGER
			l_content: STRING_8
		do
			skip_ignorable_lines
			if after_lines or else is_current_document_end then
				fail_at (line_number_for_end, "expected an indented value")
			else
				l_line := line_index
				l_indent := indentation_of (lines [line_index], line_index)
				if is_valid and then l_indent /= a_indent then
					fail_at (line_index, "inconsistent indentation; expected " + a_indent.out + " spaces")
				elseif is_valid then
					l_content := trim_text (strip_comment (content_after_indent (lines [line_index], a_indent)))
					if is_sequence_marker (l_content) then
						Result := parse_sequence (a_indent)
					elseif mapping_colon_index (l_content, False) > 0 then
						Result := parse_mapping (a_indent)
					else
						line_index := line_index + 1
						Result := parse_inline_value (l_content, l_line)
					end
				end
			end
		end

	parse_mapping (a_indent: INTEGER): detachable JSON_OBJECT
			-- Parse a block mapping at `a_indent'.
		local
			l_result: JSON_OBJECT
			l_indent: INTEGER
			l_content: STRING_8
			l_done: BOOLEAN
		do
			create l_result.make
			from
			until
				l_done or else not is_valid
			loop
				skip_ignorable_lines
				if after_lines or else is_current_document_end then
					l_done := True
				else
					l_indent := indentation_of (lines [line_index], line_index)
					if is_valid then
						if l_indent < a_indent then
							l_done := True
						elseif l_indent > a_indent then
							fail_at (line_index, "unexpected indentation in map; expected " + a_indent.out + " spaces")
						else
							l_content := trim_text (strip_comment (content_after_indent (lines [line_index], a_indent)))
							if is_sequence_marker (l_content) then
								fail_at (line_index, "cannot mix sequence entries with map entries at the same indentation")
							elseif mapping_colon_index (l_content, False) = 0 then
								fail_at (line_index, "expected a map entry of the form 'key: value'")
							else
								parse_mapping_pair (l_content, l_result, a_indent)
							end
						end
					end
				end
			end
			if is_valid then
				Result := l_result
			end
		end

	parse_mapping_pair (a_content: READABLE_STRING_8; a_object: JSON_OBJECT; a_indent: INTEGER)
			-- Parse the map pair in the current physical line.
			-- `a_indent' is the logical indentation of its key. It differs from the
			-- physical indentation for a compact map in a sequence (`- key: value').
		local
			l_colon, l_line, l_next_indent: INTEGER
			l_key_text, l_value_text: STRING_8
			l_key: detachable JSON_STRING
			l_value: detachable JSON_VALUE
		do
			l_line := line_index
			l_colon := mapping_colon_index (a_content, False)
			if l_colon = 0 then
				fail_at (l_line, "expected ':' after map key")
			else
				l_key_text := trim_text (substring_before (a_content, l_colon))
				l_value_text := trim_text (strip_comment (substring_after (a_content, l_colon)))
				l_key := parse_key (l_key_text, l_line)
				if is_valid and then attached l_key as k and then a_object.has_key (k) then
					fail_at (l_line, "duplicate map key '" + printable_key (k) + "'")
				end

				line_index := line_index + 1
				if is_valid then
					if is_block_indicator (l_value_text) then
						l_value := parse_block_scalar (a_indent, l_value_text, l_line)
					elseif l_value_text.is_empty then
						skip_ignorable_lines
						if not after_lines and then not is_current_document_end then
							l_next_indent := indentation_of (lines [line_index], line_index)
							if is_valid and then l_next_indent > a_indent then
								l_value := parse_block (l_next_indent)
							end
						end
						if is_valid and then l_value = Void then
							create {JSON_NULL} l_value
						end
					else
						l_value := parse_inline_value (l_value_text, l_line)
					end
				end

				if is_valid and then attached l_key as k and then attached l_value as v then
					a_object.put (v, k)
				end
			end
		end

	parse_sequence (a_indent: INTEGER): detachable JSON_ARRAY
			-- Parse a block sequence at `a_indent'.
		local
			l_result: JSON_ARRAY
			l_indent, l_line, l_first, l_map_indent: INTEGER
			l_content, l_rest: STRING_8
			l_value: detachable JSON_VALUE
			l_done: BOOLEAN
		do
			create l_result.make (4)
			from
			until
				l_done or else not is_valid
			loop
				skip_ignorable_lines
				if after_lines or else is_current_document_end then
					l_done := True
				else
					l_indent := indentation_of (lines [line_index], line_index)
					if is_valid then
						if l_indent < a_indent then
							l_done := True
						elseif l_indent > a_indent then
							fail_at (line_index, "unexpected indentation in sequence; expected " + a_indent.out + " spaces")
						else
							l_line := line_index
							l_content := content_after_indent (lines [line_index], a_indent)
							if not is_sequence_marker (l_content) then
								l_done := True
							else
								l_first := first_non_space_after_dash (l_content)
								if l_first > l_content.count then
									create l_rest.make_empty
								else
									l_rest := trim_text (strip_comment (l_content.substring (l_first, l_content.count)))
								end

								if l_rest.is_empty then
									line_index := line_index + 1
									skip_ignorable_lines
									if not after_lines and then not is_current_document_end then
										l_indent := indentation_of (lines [line_index], line_index)
										if is_valid and then l_indent > a_indent then
											l_value := parse_block (l_indent)
										end
									end
									if is_valid and then l_value = Void then
										create {JSON_NULL} l_value
									end
								elseif is_block_indicator (l_rest) then
									line_index := line_index + 1
									l_value := parse_block_scalar (a_indent, l_rest, l_line)
								elseif mapping_colon_index (l_rest, False) > 0 then
									l_map_indent := a_indent + l_first - 1
									l_value := parse_sequence_mapping (l_rest, a_indent, l_map_indent)
								else
									line_index := line_index + 1
									l_value := parse_inline_value (l_rest, l_line)
								end

								if is_valid and then attached l_value as v then
									l_result.extend (v)
								end
								l_value := Void
							end
						end
					end
				end
			end
			if is_valid then
				Result := l_result
			end
		end

	parse_sequence_mapping (a_first_pair: READABLE_STRING_8; a_sequence_indent, a_map_indent: INTEGER): detachable JSON_OBJECT
			-- Parse a compact map introduced by `- key: value'.
		local
			l_result: JSON_OBJECT
			l_indent: INTEGER
			l_content: STRING_8
			l_done: BOOLEAN
		do
			create l_result.make
			parse_mapping_pair (a_first_pair, l_result, a_map_indent)
			from
			until
				l_done or else not is_valid
			loop
				skip_ignorable_lines
				if after_lines or else is_current_document_end then
					l_done := True
				else
					l_indent := indentation_of (lines [line_index], line_index)
					if is_valid then
						if l_indent <= a_sequence_indent then
							l_done := True
						elseif l_indent /= a_map_indent then
							fail_at (line_index, "inconsistent indentation in sequence map; expected " + a_map_indent.out + " spaces")
						else
							l_content := trim_text (strip_comment (content_after_indent (lines [line_index], a_map_indent)))
							if is_sequence_marker (l_content) then
								fail_at (line_index, "cannot mix sequence and map entries at the same indentation")
							elseif mapping_colon_index (l_content, False) = 0 then
								fail_at (line_index, "expected a map entry in sequence item")
							else
								parse_mapping_pair (l_content, l_result, a_map_indent)
							end
						end
					end
				end
			end
			if is_valid then
				Result := l_result
			end
		end

feature {NONE} -- Block strings

	parse_block_scalar (a_parent_indent: INTEGER; a_indicator: READABLE_STRING_8; a_line: INTEGER): detachable JSON_STRING
			-- Parse a literal (`|') or folded (`>') scalar after `a_indicator'.
		local
			l_style, l_chomp: CHARACTER_8
			l_scan, l_end, l_indent, l_content_indent, l_last_non_blank, i: INTEGER
			l_line, l_piece, l_next_piece: STRING_8
			l_pieces: ARRAYED_LIST [STRING_8]
			l_indents: ARRAYED_LIST [INTEGER]
			l_breaks: ARRAYED_LIST [BOOLEAN]
			l_text: STRING_8
			l_stop, l_has_non_blank, l_had_trailing_break: BOOLEAN
		do
			if not valid_block_indicator (a_indicator) then
				fail_at (a_line, "invalid block scalar indicator '" + a_indicator.to_string_8 + "'")
			else
				l_style := a_indicator [1]
				if a_indicator.count = 2 then
					l_chomp := a_indicator [2]
				else
					l_chomp := '='
				end

				l_scan := line_index
				l_content_indent := {INTEGER}.max_value
				from
				until
					l_scan > lines.count or else l_stop or else not is_valid
				loop
					l_line := lines [l_scan]
					if is_blank_line (l_line) then
						-- Blank lines belong to a block scalar even when they carry no indentation.
						l_scan := l_scan + 1
					else
						l_indent := indentation_of (l_line, l_scan)
						if is_valid then
							if l_indent <= a_parent_indent then
								l_stop := True
							elseif not l_has_non_blank then
								-- YAML infers block indentation from the first non-blank
								-- content line, not the least-indented later line.
								l_has_non_blank := True
								l_content_indent := l_indent
								l_scan := l_scan + 1
							elseif l_indent < l_content_indent then
								l_stop := True
							else
								l_scan := l_scan + 1
							end
						end
					end
				end
				l_end := l_scan
				if not l_has_non_blank then
					l_content_indent := a_parent_indent + 1
				end

				if is_valid then
					create l_pieces.make ((l_end - line_index).max (0))
					create l_indents.make ((l_end - line_index).max (0))
					create l_breaks.make ((l_end - line_index).max (0))
					from
						i := line_index
					until
						i >= l_end
					loop
						l_line := lines [i]
						if is_blank_line (l_line) then
							create l_piece.make_empty
							l_indent := l_content_indent
						else
							l_indent := indentation_of (l_line, i)
							if l_line.count > l_content_indent then
								l_piece := l_line.substring (l_content_indent + 1, l_line.count)
							else
								create l_piece.make_empty
							end
						end
						l_pieces.extend (l_piece)
						l_indents.extend (l_indent)
						l_breaks.extend (line_breaks [i])
						if not l_piece.is_empty then
							l_last_non_blank := l_pieces.count
						end
						i := i + 1
					end
					line_index := l_end

					create l_text.make (64)
					from
						i := 1
					until
						i > l_pieces.count
					loop
						l_piece := l_pieces [i]
						l_text.append (l_piece)
						if i < l_pieces.count then
							l_next_piece := l_pieces [i + 1]
							if l_style = '|' or else i >= l_last_non_blank then
								l_text.append_character ('%N')
							elseif l_piece.is_empty then
								l_text.append_character ('%N')
							elseif l_next_piece.is_empty then
								if l_indents [i] > l_content_indent then
									l_text.append_character ('%N')
								end
							elseif l_indents [i] > l_content_indent or else l_indents [i + 1] > l_content_indent then
								l_text.append_character ('%N')
							else
								l_text.append_character (' ')
							end
						elseif l_breaks [i] then
							l_text.append_character ('%N')
						end
						i := i + 1
					end

					l_had_trailing_break := not l_text.is_empty and then l_text [l_text.count] = '%N'
					if l_chomp = '-' then
						remove_trailing_newlines (l_text)
					elseif l_chomp = '=' then
						remove_trailing_newlines (l_text)
						if l_has_non_blank and then l_had_trailing_break then
							l_text.append_character ('%N')
						end
					end
					create Result.make_from_string (l_text)
				end
			end
		end

	is_block_indicator (a_text: READABLE_STRING_8): BOOLEAN
			-- Does `a_text' begin like a supported block scalar indicator?
		do
			Result := not a_text.is_empty and then (a_text [1] = '|' or else a_text [1] = '>')
		end

	valid_block_indicator (a_text: READABLE_STRING_8): BOOLEAN
		do
			Result := a_text.count = 1 and then (a_text [1] = '|' or else a_text [1] = '>')
			if not Result and then a_text.count = 2 and then (a_text [1] = '|' or else a_text [1] = '>') then
				Result := a_text [2] = '-' or else a_text [2] = '+'
			end
		end

	remove_trailing_newlines (a_text: STRING_8)
		do
			from
			until
				a_text.is_empty or else a_text [a_text.count] /= '%N'
			loop
				a_text.remove_tail (1)
			end
		end

feature {NONE} -- Flow parsing

	parse_inline_value (a_text: READABLE_STRING_8; a_line: INTEGER): detachable JSON_VALUE
			-- Parse one scalar or flow collection.
		local
			l_clean: STRING_8
		do
			l_clean := trim_text (strip_comment (a_text))
			if l_clean.is_empty then
				create {JSON_NULL} Result
			elseif l_clean [1] /= '[' and then l_clean [1] /= '{' then
				-- Flow punctuation only delimits values inside a flow collection.
				-- A block plain scalar may freely contain commas and brackets.
				Result := scalar_from_token (l_clean, a_line)
			else
				flow_text := l_clean
				flow_index := 1
				flow_line := a_line
				Result := parse_flow_value
				if is_valid then
					skip_flow_spaces
					if is_valid and then flow_index <= flow_text.count then
						fail_at (flow_line, "unexpected trailing characters in value near '" + flow_text.substring (flow_index, flow_text.count) + "'")
					end
				end
			end
		end

	parse_flow_value: detachable JSON_VALUE
		local
			l_start: INTEGER
			l_token: STRING_8
		do
			skip_flow_spaces
			if is_valid then
				if flow_index > flow_text.count then
					fail_at (flow_line, "expected a value")
				else
					inspect flow_text [flow_index]
					when '[' then
						Result := parse_flow_array
					when '{' then
						Result := parse_flow_object
					when '%"', '%'' then
						Result := parse_flow_quoted_string
					else
						l_start := flow_index
						from
						until
							flow_index > flow_text.count or else flow_text [flow_index] = ',' or else flow_text [flow_index] = ']' or else flow_text [flow_index] = '}'
						loop
							flow_index := flow_index + 1
						end
						if flow_index > l_start then
							l_token := trim_text (flow_text.substring (l_start, flow_index - 1))
						else
							create l_token.make_empty
						end
						if l_token.is_empty then
							fail_at (flow_line, "expected a value")
						else
							Result := scalar_from_token (l_token, flow_line)
						end
					end
				end
			end
		end

	parse_flow_array: detachable JSON_ARRAY
		local
			l_result: JSON_ARRAY
			l_value: detachable JSON_VALUE
			l_done: BOOLEAN
		do
			create l_result.make (4)
			flow_index := flow_index + 1
			skip_flow_spaces
			if is_valid and then flow_index <= flow_text.count and then flow_text [flow_index] = ']' then
				flow_index := flow_index + 1
				Result := l_result
			else
				from
				until
					l_done or else not is_valid
				loop
					l_value := parse_flow_value
					if is_valid and then attached l_value as v then
						l_result.extend (v)
					end
					skip_flow_spaces
					if is_valid then
						if flow_index > flow_text.count then
							fail_at (flow_line, "unterminated inline sequence; expected ']'")
						elseif flow_text [flow_index] = ']' then
							flow_index := flow_index + 1
							l_done := True
						elseif flow_text [flow_index] = ',' then
							flow_index := flow_index + 1
							skip_flow_spaces
							if is_valid and then flow_index <= flow_text.count and then flow_text [flow_index] = ']' then
								flow_index := flow_index + 1
								l_done := True
							end
						else
							fail_at (flow_line, "expected ',' or ']' in inline sequence")
						end
					end
				end
				if is_valid then
					Result := l_result
				end
			end
		end

	parse_flow_object: detachable JSON_OBJECT
		local
			l_result: JSON_OBJECT
			l_key: detachable JSON_STRING
			l_value: detachable JSON_VALUE
			l_done: BOOLEAN
		do
			create l_result.make
			flow_index := flow_index + 1
			skip_flow_spaces
			if is_valid and then flow_index <= flow_text.count and then flow_text [flow_index] = '}' then
				flow_index := flow_index + 1
				Result := l_result
			else
				from
				until
					l_done or else not is_valid
				loop
					l_key := parse_flow_key
					skip_flow_spaces
					if is_valid then
						if flow_index > flow_text.count or else flow_text [flow_index] /= ':' then
							fail_at (flow_line, "expected ':' after key in inline map")
						else
							flow_index := flow_index + 1
							skip_flow_spaces
							if is_valid and then flow_index <= flow_text.count and then (flow_text [flow_index] = ',' or else flow_text [flow_index] = '}') then
								create {JSON_NULL} l_value
							else
								l_value := parse_flow_value
							end
						end
					end
					if is_valid and then attached l_key as k and then attached l_value as v then
						if l_result.has_key (k) then
							fail_at (flow_line, "duplicate map key '" + printable_key (k) + "'")
						else
							l_result.put (v, k)
						end
					end
					skip_flow_spaces
					if is_valid then
						if flow_index > flow_text.count then
							fail_at (flow_line, "unterminated inline map; expected '}'")
						elseif flow_text [flow_index] = '}' then
							flow_index := flow_index + 1
							l_done := True
						elseif flow_text [flow_index] = ',' then
							flow_index := flow_index + 1
							skip_flow_spaces
							if is_valid and then flow_index <= flow_text.count and then flow_text [flow_index] = '}' then
								flow_index := flow_index + 1
								l_done := True
							end
						else
							fail_at (flow_line, "expected ',' or '}' in inline map")
						end
					end
					l_key := Void
					l_value := Void
				end
				if is_valid then
					Result := l_result
				end
			end
		end

	parse_flow_key: detachable JSON_STRING
		local
			l_start: INTEGER
			l_text: STRING_8
		do
			skip_flow_spaces
			if is_valid then
				if flow_index > flow_text.count then
					fail_at (flow_line, "expected a key in inline map")
				elseif flow_text [flow_index] = '%"' or else flow_text [flow_index] = '%'' then
					Result := parse_flow_quoted_string
				else
					l_start := flow_index
					from
					until
						flow_index > flow_text.count or else flow_text [flow_index] = ':' or else flow_text [flow_index] = ',' or else flow_text [flow_index] = '}'
					loop
						flow_index := flow_index + 1
					end
					if flow_index > l_start then
						l_text := trim_text (flow_text.substring (l_start, flow_index - 1))
					else
						create l_text.make_empty
					end
					if l_text.is_empty then
						fail_at (flow_line, "empty key in inline map")
					else
						create Result.make_from_string_32 ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (l_text))
					end
				end
			end
		end

	parse_flow_quoted_string: detachable JSON_STRING
		local
			l_quote: CHARACTER_8
			l_start, i: INTEGER
			l_closed: BOOLEAN
			l_token: STRING_8
		do
			l_start := flow_index
			l_quote := flow_text [flow_index]
			from
				i := flow_index + 1
			until
				i > flow_text.count or else l_closed
			loop
				if l_quote = '%"' and then flow_text [i] = '\' then
					i := i + 2
				elseif flow_text [i] = l_quote then
					if l_quote = '%'' and then i < flow_text.count and then flow_text [i + 1] = '%'' then
						i := i + 2
					else
						l_closed := True
					end
				else
					i := i + 1
				end
			end
			if not l_closed then
				fail_at (flow_line, "unterminated quoted string")
			else
				l_token := flow_text.substring (l_start, i)
				flow_index := i + 1
				Result := decoded_quoted_string (l_token, flow_line)
			end
		end

	scalar_from_token (a_token: STRING_8; a_line: INTEGER): detachable JSON_VALUE
		local
			l_boolean: JSON_BOOLEAN
			l_number: JSON_NUMBER
			l_string: JSON_STRING
		do
			if a_token.is_case_insensitive_equal ("true") then
				create l_boolean.make_true
				Result := l_boolean
			elseif a_token.is_case_insensitive_equal ("false") then
				create l_boolean.make_false
				Result := l_boolean
			elseif a_token.is_case_insensitive_equal ("null") or else a_token.same_string ("~") then
				create {JSON_NULL} Result
			elseif is_decimal_integer (a_token) then
				if a_token.is_integer_64 then
					create l_number.make_integer (a_token.to_integer_64)
					Result := l_number
				else
					fail_at (a_line, "integer is outside the signed 64-bit range")
				end
			elseif a_token [1] = '%"' or else a_token [1] = '%'' then
				flow_text := a_token
				flow_index := 1
				flow_line := a_line
				Result := parse_flow_quoted_string
				if is_valid and then flow_index <= flow_text.count then
					fail_at (a_line, "unexpected text after quoted scalar")
				end
			else
				create l_string.make_from_string_32 ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_token))
				Result := l_string
			end
		end

	decoded_quoted_string (a_token: READABLE_STRING_8; a_line: INTEGER): detachable JSON_STRING
			-- Decode one complete single- or double-quoted YAML token.
		local
			l_inner: STRING_32
			l_output: STRING_32
			l_quote, c: CHARACTER_32
			i, l_digits: INTEGER
			l_code: NATURAL_32
		do
			if a_token.count < 2 then
				fail_at (a_line, "invalid quoted scalar")
			else
				l_quote := a_token [1]
				l_inner := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_token.substring (2, a_token.count - 1))
				create l_output.make (l_inner.count)
				from
					i := 1
				until
					i > l_inner.count or else not is_valid
				loop
					c := l_inner [i]
					if l_quote = '%'' then
						if c = '%'' and then i < l_inner.count and then l_inner [i + 1] = '%'' then
							l_output.append_character ('%'')
							i := i + 2
						else
							l_output.append_character (c)
							i := i + 1
						end
					elseif c /= '\' then
						l_output.append_character (c)
						i := i + 1
					elseif i = l_inner.count then
						fail_at (a_line, "quoted scalar ends with an incomplete escape")
					else
						i := i + 1
						inspect l_inner [i]
						when '0' then l_output.append_code (0); i := i + 1
						when 'a' then l_output.append_code (7); i := i + 1
						when 'b' then l_output.append_character ('%B'); i := i + 1
						when 't' then l_output.append_character ('%T'); i := i + 1
						when 'n' then l_output.append_character ('%N'); i := i + 1
						when 'v' then l_output.append_code (11); i := i + 1
						when 'f' then l_output.append_character ('%F'); i := i + 1
						when 'r' then l_output.append_character ('%R'); i := i + 1
						when 'e' then l_output.append_code (27); i := i + 1
						when ' ', '%"', '/', '\' then l_output.append_character (l_inner [i]); i := i + 1
						when '_' then l_output.append_code (160); i := i + 1
						when 'N' then l_output.append_code (133); i := i + 1
						when 'L' then l_output.append_code (8232); i := i + 1
						when 'P' then l_output.append_code (8233); i := i + 1
						when 'x' then l_digits := 2
						when 'u' then l_digits := 4
						when 'U' then l_digits := 8
						else
							fail_at (a_line, "unsupported escape in double-quoted scalar")
						end
						if is_valid and then l_digits > 0 then
							if i + l_digits > l_inner.count or else not is_hex_sequence (l_inner, i + 1, l_digits) then
								fail_at (a_line, "invalid hexadecimal escape in quoted scalar")
							else
								l_code := hexadecimal_value (l_inner, i + 1, l_digits)
								if l_code > 0x10FFFF or else (l_code >= 0xD800 and then l_code <= 0xDFFF) then
									fail_at (a_line, "invalid Unicode code point in quoted scalar")
								else
									l_output.append_code (l_code)
									i := i + l_digits + 1
								end
							end
							l_digits := 0
						end
					end
				end
				if is_valid then
					create Result.make_from_string_32 (l_output)
				end
			end
		end

feature {NONE} -- Key and token helpers

	parse_key (a_text: STRING_8; a_line: INTEGER): detachable JSON_STRING
		do
			if a_text.is_empty then
				fail_at (a_line, "map key must not be empty")
			elseif a_text [1] = '%"' or else a_text [1] = '%'' then
				flow_text := a_text
				flow_index := 1
				flow_line := a_line
				Result := parse_flow_quoted_string
				if is_valid and then flow_index <= flow_text.count then
					fail_at (a_line, "unexpected text after quoted map key")
				end
			else
				create Result.make_from_string_32 ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_text))
			end
		end

	is_decimal_integer (a_text: READABLE_STRING_8): BOOLEAN
		local
			i: INTEGER
		do
			if not a_text.is_empty then
				i := 1
				if a_text [1] = '+' or else a_text [1] = '-' then
					i := 2
				end
				Result := i <= a_text.count
				from
				until
					i > a_text.count or else not Result
				loop
					Result := a_text [i] >= '0' and then a_text [i] <= '9'
					i := i + 1
				end
			end
		end

	is_hex_sequence (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): BOOLEAN
		local
			i: INTEGER
		do
			Result := a_start >= 1 and then a_count >= 0 and then a_start + a_count - 1 <= a_text.count
			from
				i := a_start
			until
				i >= a_start + a_count or else not Result
			loop
				Result := is_hex_character (a_text [i])
				i := i + 1
			end
		end

	hexadecimal_value (a_text: READABLE_STRING_32; a_start, a_count: INTEGER): NATURAL_32
		local
			i: INTEGER
		do
			from
				i := a_start
			until
				i >= a_start + a_count
			loop
				Result := Result * 16 + hex_character_value (a_text [i])
				i := i + 1
			end
		end

	is_hex_character (c: CHARACTER_32): BOOLEAN
		do
			Result := (c >= '0' and then c <= '9') or else (c >= 'a' and then c <= 'f') or else (c >= 'A' and then c <= 'F')
		end

	hex_character_value (c: CHARACTER_32): NATURAL_32
		do
			if c >= '0' and then c <= '9' then
				Result := (c.code - ('0').code).to_natural_32
			elseif c >= 'a' and then c <= 'f' then
				Result := (c.code - ('a').code + 10).to_natural_32
			else
				Result := (c.code - ('A').code + 10).to_natural_32
			end
		end

feature {NONE} -- Line handling

	reset
		do
			root := Void
			is_valid := True
			error_message.wipe_out
			lines.wipe_out
			line_breaks.wipe_out
			flow_text.wipe_out
			flow_index := 1
			flow_line := 1
			line_index := 1
		end

	split_lines (a_yaml: READABLE_STRING_8)
		local
			i, l_start: INTEGER
			l_line: STRING_8
		do
			from
				i := 1
				l_start := 1
			until
				i > a_yaml.count
			loop
				if a_yaml [i] = '%N' then
					if i > l_start then
						l_line := a_yaml.substring (l_start, i - 1)
					else
						create l_line.make_empty
					end
					remove_terminal_carriage_return (l_line)
					lines.extend (l_line)
					line_breaks.extend (True)
					l_start := i + 1
				end
				i := i + 1
			end
			if l_start <= a_yaml.count then
				l_line := a_yaml.substring (l_start, a_yaml.count)
				remove_terminal_carriage_return (l_line)
				lines.extend (l_line)
				line_breaks.extend (False)
			end
		end

	remove_terminal_carriage_return (a_line: STRING_8)
		do
			if not a_line.is_empty and then a_line [a_line.count] = '%R' then
				a_line.remove_tail (1)
			end
		end

	skip_ignorable_lines
		local
			l_indent: INTEGER
			l_done: BOOLEAN
		do
			from
			until
				l_done or else after_lines or else not is_valid
			loop
				l_indent := indentation_of (lines [line_index], line_index)
				if is_valid and then (l_indent = lines [line_index].count or else lines [line_index] [l_indent + 1] = '#') then
					line_index := line_index + 1
				else
					l_done := True
				end
			end
		end

	indentation_of (a_line: READABLE_STRING_8; a_line_number: INTEGER): INTEGER
		local
			i: INTEGER
			l_done: BOOLEAN
		do
			from
				i := 1
			until
				i > a_line.count or else l_done
			loop
				if a_line [i] = ' ' then
					Result := Result + 1
					i := i + 1
				elseif a_line [i] = '%T' then
					fail_at (a_line_number, "tabs are not allowed for YAML indentation")
					l_done := True
				else
					l_done := True
				end
			end
		end

	is_blank_line (a_line: READABLE_STRING_8): BOOLEAN
		local
			i: INTEGER
		do
			Result := True
			from
				i := 1
			until
				i > a_line.count or else not Result
			loop
				Result := a_line [i] = ' '
				i := i + 1
			end
		end

	content_after_indent (a_line: READABLE_STRING_8; a_indent: INTEGER): STRING_8
		do
			if a_indent < a_line.count then
				Result := a_line.substring (a_indent + 1, a_line.count)
			else
				create Result.make_empty
			end
		end

	strip_comment (a_text: READABLE_STRING_8): STRING_8
			-- Remove an unquoted YAML comment. `#' starts a comment only at the
			-- beginning of a value or when preceded by whitespace.
		local
			i: INTEGER
			l_in_single, l_in_double: BOOLEAN
			c: CHARACTER_8
			l_done: BOOLEAN
		do
			from
				i := 1
			until
				i > a_text.count or else l_done
			loop
				c := a_text [i]
				if l_in_double then
					if c = '\' then
						i := i + 2
					elseif c = '%"' then
						l_in_double := False
						i := i + 1
					else
						i := i + 1
					end
				elseif l_in_single then
					if c = '%'' and then i < a_text.count and then a_text [i + 1] = '%'' then
						i := i + 2
					elseif c = '%'' then
						l_in_single := False
						i := i + 1
					else
						i := i + 1
					end
				elseif c = '%"' then
					l_in_double := True
					i := i + 1
				elseif c = '%'' then
					l_in_single := True
					i := i + 1
				elseif c = '#' and then (i = 1 or else a_text [i - 1] = ' ' or else a_text [i - 1] = '%T') then
					l_done := True
				else
					i := i + 1
				end
			end
			if l_done then
				if i > 1 then
					Result := a_text.substring (1, i - 1)
				else
					create Result.make_empty
				end
			else
				Result := a_text.to_string_8.twin
			end
		end

	mapping_colon_index (a_text: READABLE_STRING_8; a_allow_compact: BOOLEAN): INTEGER
			-- Index of a map-delimiting colon outside quotes/flow collections.
		local
			i, l_square_depth, l_curly_depth: INTEGER
			l_in_single, l_in_double: BOOLEAN
			c: CHARACTER_8
		do
			from
				i := 1
			until
				i > a_text.count or else Result > 0
			loop
				c := a_text [i]
				if l_in_double then
					if c = '\' then
						i := i + 2
					else
						if c = '%"' then
							l_in_double := False
						end
						i := i + 1
					end
				elseif l_in_single then
					if c = '%'' and then i < a_text.count and then a_text [i + 1] = '%'' then
						i := i + 2
					else
						if c = '%'' then
							l_in_single := False
						end
						i := i + 1
					end
				else
					inspect c
					when '%"' then l_in_double := True
					when '%'' then l_in_single := True
					when '[' then l_square_depth := l_square_depth + 1
					when ']' then l_square_depth := l_square_depth - 1
					when '{' then l_curly_depth := l_curly_depth + 1
					when '}' then l_curly_depth := l_curly_depth - 1
					when ':' then
						if l_square_depth = 0 and then l_curly_depth = 0 and then (a_allow_compact or else i = a_text.count or else a_text [i + 1] = ' ' or else a_text [i + 1] = '%T') then
							Result := i
						end
					else
					end
					i := i + 1
				end
			end
		end

	is_sequence_marker (a_content: READABLE_STRING_8): BOOLEAN
		do
			Result := not a_content.is_empty and then a_content [1] = '-' and then (a_content.count = 1 or else a_content [2] = ' ' or else a_content [2] = '%T' or else a_content [2] = '#')
		end

	first_non_space_after_dash (a_content: READABLE_STRING_8): INTEGER
		do
			from
				Result := 2
			until
				Result > a_content.count or else (a_content [Result] /= ' ' and then a_content [Result] /= '%T')
			loop
				if a_content [Result] = '%T' then
					fail_at (line_index, "tabs are not allowed after a sequence marker")
				end
				Result := Result + 1
			end
		end

	trim_text (a_text: READABLE_STRING_8): STRING_8
		do
			Result := a_text.to_string_8.twin
			Result.left_adjust
			Result.right_adjust
		end

	substring_before (a_text: READABLE_STRING_8; a_index: INTEGER): STRING_8
		do
			if a_index > 1 then
				Result := a_text.substring (1, a_index - 1)
			else
				create Result.make_empty
			end
		end

	substring_after (a_text: READABLE_STRING_8; a_index: INTEGER): STRING_8
		do
			if a_index < a_text.count then
				Result := a_text.substring (a_index + 1, a_text.count)
			else
				create Result.make_empty
			end
		end

	printable_key (a_key: JSON_STRING): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_key.unescaped_string_32)
		end

	skip_flow_spaces
		do
			from
			until
				flow_index > flow_text.count or else (flow_text [flow_index] /= ' ' and then flow_text [flow_index] /= '%T') or else not is_valid
			loop
				if flow_text [flow_index] = '%T' then
					fail_at (flow_line, "tabs are not allowed in YAML flow indentation")
				else
					flow_index := flow_index + 1
				end
			end
		end

	is_document_start_line (a_line: READABLE_STRING_8): BOOLEAN
		do
			Result := trim_text (strip_comment (a_line)).same_string ("---")
		end

	is_current_document_end: BOOLEAN
		do
			Result := not after_lines and then trim_text (strip_comment (lines [line_index])).same_string ("...")
		end

	after_lines: BOOLEAN
		do
			Result := line_index > lines.count
		end

	line_number_for_end: INTEGER
		do
			Result := line_index.min (lines.count.max (1))
		end

feature {NONE} -- Error handling

	fail_at (a_line: INTEGER; a_message: READABLE_STRING_GENERAL)
			-- Record the first error.
		do
			if is_valid then
				is_valid := False
				error_message.wipe_out
				error_message.append ("line ")
				error_message.append (a_line.max (1).out)
				error_message.append (": ")
				error_message.append (a_message.as_string_32)
			end
		end

feature {NONE} -- Parser state

	lines: ARRAYED_LIST [STRING_8]

	line_breaks: ARRAYED_LIST [BOOLEAN]

	line_index: INTEGER

	flow_text: STRING_8

	flow_index: INTEGER

	flow_line: INTEGER

invariant
	line_metadata_aligned: line_breaks.count = lines.count
	valid_root_consistent: is_valid implies root /= Void
	error_state_consistent: not error_message.is_empty implies not is_valid

end
