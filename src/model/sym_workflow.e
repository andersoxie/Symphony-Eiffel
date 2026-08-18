note
	description: "Parsed WORKFLOW.md definition and its source identity."

class
	SYM_WORKFLOW

create
	make

feature {NONE} -- Initialization

	make (a_config: JSON_OBJECT; a_prompt: READABLE_STRING_GENERAL; a_path: PATH; a_signature: READABLE_STRING_GENERAL)
		require
			path_present: not a_path.name.is_empty
			signature_present: not a_signature.is_empty
		do
			config := a_config
			prompt_template := a_prompt.to_string_32.twin
			path := a_path.canonical_path
			signature := a_signature.to_string_32.twin
		ensure
			config_set: config = a_config
			prompt_set: prompt_template.same_string_general (a_prompt)
			path_canonicalized: path.is_equal (a_path.canonical_path)
			signature_set: signature.same_string_general (a_signature)
		end

feature -- Access

	config: JSON_OBJECT

	prompt_template: STRING_32

	path: PATH

	signature: STRING_32

end
