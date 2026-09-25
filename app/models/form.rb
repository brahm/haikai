# Form templates (txp_form): reusable template snippets.
class Form < ApplicationRecord
  self.table_name = "txp_form"
  self.primary_key = [ :name, :skin ]
  self.inheritance_column = :_type_disabled

  ESSENTIAL = {
    "comments" => "comment", "comments_display" => "comment", "comment_form" => "comment",
    "default" => "article", "plainlinks" => "link", "files" => "file"
  }.freeze

  validates :name, presence: true, format: { with: /\A[^<>&"'\/]+\z/ }
  validates :name, uniqueness: { scope: :skin }

  before_save { self.lastmod = Time.now.utc }

  def essential?
    ESSENTIAL[name] == type
  end

  # Custom form types from the custom_form_types preference (ini format).
  def self.custom_types(prefs = Pref.site_prefs)
    types = {}
    current = nil
    prefs["custom_form_types"].to_s.each_line do |line|
      line = line.strip
      next if line.empty? || line.start_with?(";")

      if (m = line.match(/\A\[(.+)\]\z/))
        current = m[1]
        types[current] = {}
      elsif current && (m = line.match(/\A(\w+)\s*=\s*"?(.*?)"?\z/))
        types[current][m[1]] = m[2]
      end
    end
    types.select { |_k, v| v["mediatype"].present? }
  end

  def self.types(prefs = Pref.site_prefs)
    Txp::FORM_TYPES + custom_types(prefs).keys
  end
end
