# Stylesheets (txp_css).
class Style < ApplicationRecord
  self.table_name = "txp_css"
  self.primary_key = [ :name, :skin ]

  validates :name, presence: true, format: { with: /\A[^<>&"'\/]+\z/ }
  validates :name, uniqueness: { scope: :skin }

  before_save { self.lastmod = Time.now.utc }

  def in_use?
    Section.where(css: name, skin: skin).exists?
  end
end
