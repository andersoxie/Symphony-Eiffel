note
	description: "Typed error exposed at Symphony component boundaries."

class
	SYM_ERROR

inherit
	ANY
		redefine
			out
		end

create
	make

feature {NONE} -- Initialization

	make (a_code: READABLE_STRING_GENERAL; a_message: READABLE_STRING_GENERAL)
		require
			code_present: not a_code.is_empty
		do
			code := a_code.to_string_32.twin
			message := a_message.to_string_32.twin
		end

feature -- Access

	code: STRING_32

	message: STRING_32

	out: STRING
		do
			Result := code.to_string_8 + ": " + message.to_string_8
		end

invariant
	code_present: not code.is_empty

end
