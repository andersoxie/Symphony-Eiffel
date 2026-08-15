note
	description: "Shared conservative predicate for fields that may contain credentials."

class
	SYM_SECRET_KEYS

feature -- Classification

	is_secret_key (a_key: READABLE_STRING_GENERAL): BOOLEAN
		local
			key: STRING_32
			i: INTEGER
			c: CHARACTER_32
		do
			key := a_key.to_string_32.twin
			key.to_lower
			from i := 1 until i > key.count loop
				c := key [i]
				if not c.is_alpha_numeric and then c /= '_' then key.put ('_', i) end
				i := i + 1
			end
			Result :=
				key.same_string ("authorization") or else
				key.same_string ("proxy_authorization") or else
				key.same_string ("api_key") or else
				key.same_string ("apikey") or else
				key.same_string ("password") or else
				key.same_string ("passwd") or else
				key.same_string ("pwd") or else
				key.same_string ("secret") or else
				key.same_string ("client_secret") or else
				key.same_string ("access_token") or else
				key.same_string ("refresh_token") or else
				key.same_string ("id_token") or else
				key.same_string ("bearer_token") or else
				key.same_string ("token") or else
				key.same_string ("private_key") or else
				key.same_string ("signing_key") or else
				key.same_string ("credential") or else
				key.same_string ("credentials") or else
				key.same_string ("cookie") or else
				key.same_string ("set_cookie") or else
				key.ends_with ("_token") or else
				key.ends_with ("_secret") or else
				key.ends_with ("_password") or else
				key.ends_with ("_passwd") or else
				key.ends_with ("_api_key") or else
				key.ends_with ("_private_key") or else
				key.ends_with ("_credential") or else
				key.ends_with ("_credentials")
		end

end
