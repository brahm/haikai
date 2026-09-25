# Plugins (txp_plugin). Code is Ruby, evaluated by Txp::Plugins.
class Plugin < ApplicationRecord
  self.table_name = "txp_plugin"
  self.primary_key = "name"
  self.inheritance_column = :_type_disabled

  TYPES = { 0 => "public", 1 => "public_admin", 2 => "library", 3 => "admin", 4 => "admin_ajax", 5 => "public_admin_ajax" }.freeze

  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/i }

  before_save { self.code_md5 = Digest::MD5.hexdigest(code.to_s) }

  def active?
    status.to_i == 1
  end
end
