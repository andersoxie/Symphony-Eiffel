note
	description: "Workspace-key derivation and path-boundary checks."

class
	SYM_PATH_SAFETY

feature -- Workspace keys

	workspace_key (a_identifier: READABLE_STRING_GENERAL): STRING_32
		require
			identifier_present: not a_identifier.is_empty
		local
			i: INTEGER
			c: CHARACTER_32
			changed: BOOLEAN
		do
			create Result.make (a_identifier.count + 17)
			from i := 1 until i > a_identifier.count loop
				c := a_identifier [i]
				if is_allowed_key_character (c) then
					Result.extend (c)
				else
					Result.extend ('_')
					changed := True
				end
				i := i + 1
			end
			if Result.same_string (".") or else Result.same_string ("..") or else
				({PLATFORM}.is_windows and then is_windows_ambiguous_name (Result))
			then
				-- Keep the key a direct child on every supported filesystem.
				-- Win32 strips trailing dots and reserves device-name stems.
				changed := True
			end
			if changed then
				Result.extend ('-')
				Result.append_string_general (hash.sha_256_64 (a_identifier))
			end
		ensure
			not_empty: not Result.is_empty
			allowed: is_safe_key (Result)
			unchanged_when_already_portable:
				(is_safe_key (a_identifier) and then
					(not {PLATFORM}.is_windows or else not is_windows_ambiguous_name (a_identifier))) implies
					Result.same_string_general (a_identifier)
		end

	is_safe_key (a_key: READABLE_STRING_GENERAL): BOOLEAN
		local
			i: INTEGER
		do
			Result := not a_key.is_empty and then not a_key.same_string (".") and then not a_key.same_string ("..")
			from i := 1 until i > a_key.count or not Result loop
				Result := is_allowed_key_character (a_key [i])
				i := i + 1
			end
		ensure
			safe_is_nonempty: Result implies not a_key.is_empty
			dot_not_safe: a_key.same_string (".") implies not Result
			dot_dot_not_safe: a_key.same_string ("..") implies not Result
		end

	is_within (a_root, a_child: PATH): BOOLEAN
			-- Is canonical `a_child' equal to or under canonical `a_root' at a directory boundary?
		local
			r, c: STRING_32
			separator: CHARACTER_32
		do
			r := a_root.canonical_path.name
			c := a_child.canonical_path.name
			if {PLATFORM}.is_windows then
				r.to_lower
				c.to_lower
				separator := '\'
			else
				separator := '/'
			end
			if c.same_string (r) then
				Result := True
			elseif c.count > r.count and then c.substring (1, r.count).same_string (r) then
				Result := r [r.count] = separator or else c [r.count + 1] = separator
			end
		ensure
			root_contains_itself:
				a_child.canonical_path.is_equal (a_root.canonical_path) implies Result
		end

	is_existing_workspace_directory (a_root, a_child: PATH): BOOLEAN
			-- Is `a_child' an existing, non-link directory directly below the
			-- configured root at both the lexical and filesystem-identity levels?
			-- Rejecting a link at the issue path prevents hooks, Codex, and recursive
			-- cleanup from following a symlink or Windows reparse point out of root.
		local
			root_directory, child_directory: DIRECTORY
			child_file: RAW_FILE
		do
			create root_directory.make_with_path (a_root)
			create child_directory.make_with_path (a_child)
			create child_file.make_with_path (a_child)
			if root_directory.exists and then child_directory.exists and then
				child_file.path_exists and then not child_file.is_symlink and then
				is_within (a_root, a_child) and then
				not a_child.canonical_path.is_equal (a_root.canonical_path)
			then
				-- The workspace contract always uses one direct child of the root.
				-- The child itself is checked without following links above; the root
				-- may intentionally be mounted or linked by the operator.
				Result := a_child.parent.canonical_path.is_equal (a_root.canonical_path)
			end
		ensure
			accepted_path_is_contained: Result implies is_within (a_root, a_child)
			accepted_path_is_not_root:
				Result implies not a_child.canonical_path.is_equal (a_root.canonical_path)
		rescue
			Result := False
		end

	workspace_path (a_root: PATH; a_identifier: READABLE_STRING_GENERAL): detachable PATH
		require
			identifier_present: not a_identifier.is_empty
		local
			p: PATH
		do
			p := a_root.canonical_path.extended (workspace_key (a_identifier))
			if is_within (a_root, p) and then not p.canonical_path.is_equal (a_root.canonical_path) then
				Result := p
			end
		ensure
			attached_path_is_contained:
				attached Result as path implies is_within (a_root, path)
			attached_path_is_not_root:
				attached Result as path implies not path.canonical_path.is_equal (a_root.canonical_path)
		end

feature {NONE} -- Implementation

	is_windows_ambiguous_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
		local
			stem: STRING_32
			dot: INTEGER
		do
			Result := a_name.ends_with (".")
			stem := a_name.to_string_32.twin
			dot := stem.index_of ('.', 1)
			if dot > 0 then stem.keep_head (dot - 1) end
			stem.to_lower
			Result := Result or else stem.same_string ("con") or else stem.same_string ("prn") or else
				stem.same_string ("aux") or else stem.same_string ("nul") or else
				is_numbered_windows_device (stem, "com") or else is_numbered_windows_device (stem, "lpt")
		end

	is_numbered_windows_device (a_stem, a_prefix: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := a_stem.count = 4 and then a_stem.substring (1, 3).same_string (a_prefix) and then
				a_stem [4] >= '1' and then a_stem [4] <= '9'
		end

	is_allowed_key_character (c: CHARACTER_32): BOOLEAN
		do
			Result := (c >= 'A' and c <= 'Z') or else (c >= 'a' and c <= 'z') or else
				(c >= '0' and c <= '9') or else c = '.' or else c = '_' or else c = '-'
		end

	hash: SYM_HASH
		once
			create Result
		end

end
