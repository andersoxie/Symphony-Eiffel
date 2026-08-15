note
	description: "Stable SHA-256 identifiers used for collision-resistant workspace keys."

class
	SYM_HASH

feature -- Hashing

	sha_256_hex (a_value: READABLE_STRING_GENERAL): STRING_8
		local
			h: SHA256
			bytes: SPECIAL [NATURAL_8]
			i: INTEGER
			s: STRING_8
		do
			create h.make
			h.sink_string (strings.utf_8 (a_value))
			create bytes.make_filled (0, 32)
			h.do_final (bytes, 0)
			create Result.make (64)
			from i := 0 until i = bytes.count loop
				s := bytes [i].to_hex_string
				Result.append (s.substring (s.count - 1, s.count))
				i := i + 1
			end
			Result.to_lower
		ensure
			length: Result.count = 64
		end

	sha_256_64 (a_value: READABLE_STRING_GENERAL): STRING_8
			-- First 64 bits of SHA-256, encoded as 16 allowed hex characters.
		do
			Result := sha_256_hex (a_value).substring (1, 16)
		ensure
			length: Result.count = 16
		end

feature {NONE} -- Implementation

	strings: SYM_STRINGS
		once
			create Result
		end

end

