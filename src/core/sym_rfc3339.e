note
	description: "Strict-enough RFC 3339 instant parser used by tracker adapters."

class
	SYM_RFC3339

feature -- Parsing

	parsed (a_text: READABLE_STRING_GENERAL): detachable DATE_TIME
		local
			s, base, fraction: STRING_32
			y, mo, d, h, mi: INTEGER
			sec: DOUBLE
			zone_index, dot_index, sign, offset_minutes: INTEGER
		do
			s := a_text.to_string_32.twin
			s.left_adjust
			s.right_adjust
			if s.count >= 20 and then s [5] = '-' and then s [8] = '-' and then
				s [11] = 'T' and then s [14] = ':' and then s [17] = ':'
			then
				zone_index := zone_start (s)
				if zone_index > 19 then
					base := s.substring (1, zone_index - 1)
					dot_index := base.index_of ('.', 19)
					if dot_index > 0 then
						fraction := base.substring (dot_index + 1, base.count)
						base := base.substring (1, dot_index - 1)
					else
						create fraction.make_empty
					end
					if valid_digits (base.substring (1, 4)) and valid_digits (base.substring (6, 7)) and
						valid_digits (base.substring (9, 10)) and valid_digits (base.substring (12, 13)) and
						valid_digits (base.substring (15, 16)) and valid_digits (base.substring (18, 19)) and
						(fraction.is_empty or else valid_digits (fraction))
					then
						y := base.substring (1, 4).to_integer
						mo := base.substring (6, 7).to_integer
						d := base.substring (9, 10).to_integer
						h := base.substring (12, 13).to_integer
						mi := base.substring (15, 16).to_integer
						sec := base.substring (18, 19).to_integer.to_double
						if not fraction.is_empty then
							sec := sec + ("0." + fraction.to_string_8).to_double
						end
						if date_time_valid (y, mo, d, h, mi, sec) then
							create Result.make_fine (y, mo, d, h, mi, sec)
							if s [zone_index] /= 'Z' and s [zone_index] /= 'z' and then
								s.count = zone_index + 5 and then s [zone_index + 3] = ':' and then
								valid_digits (s.substring (zone_index + 1, zone_index + 2)) and then
								valid_digits (s.substring (zone_index + 4, zone_index + 5))
							then
								if s [zone_index] = '+' then sign := 1 else sign := -1 end
								offset_minutes := s.substring (zone_index + 1, zone_index + 2).to_integer * 60 +
									s.substring (zone_index + 4, zone_index + 5).to_integer
								if offset_minutes <= 23 * 60 + 59 then
									Result.minute_add (-sign * offset_minutes)
								else
									Result := Void
								end
							elseif s [zone_index] /= 'Z' and s [zone_index] /= 'z' then
								Result := Void
							end
						end
					end
				end
			end
		end

feature {NONE} -- Validation

	zone_start (s: STRING_32): INTEGER
		local
			i: INTEGER
		do
			from i := 20 until i > s.count or Result > 0 loop
				if s [i] = 'Z' or s [i] = 'z' or s [i] = '+' or s [i] = '-' then Result := i end
				i := i + 1
			end
		end

	valid_digits (s: READABLE_STRING_GENERAL): BOOLEAN
		local
			i: INTEGER
		do
			Result := not s.is_empty
			from i := 1 until i > s.count or not Result loop
				Result := s [i] >= '0' and s [i] <= '9'
				i := i + 1
			end
		end

	date_time_valid (y, mo, d, h, mi: INTEGER; sec: DOUBLE): BOOLEAN
		local
			v: DATE_TIME_VALIDITY_CHECKER
		do
			create v
			Result := v.is_correct_date_time (y, mo, d, h, mi, sec, False)
		end

end
