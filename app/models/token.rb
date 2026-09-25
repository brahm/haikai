# Tokens (txp_token) used for password resets and account activation.
class Token < ApplicationRecord
  self.table_name = "txp_token"
  self.inheritance_column = :_type_disabled
end
