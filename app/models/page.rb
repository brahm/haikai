# Page templates (txp_page).
class Page < ApplicationRecord
  self.table_name = "txp_page"
  self.primary_key = [ :name, :skin ]

  validates :name, presence: true, format: { with: /\A[^<>&"']+\z/ }
  validates :name, uniqueness: { scope: :skin }

  before_save { self.lastmod = Time.now.utc }

  def in_use?
    Section.where(page: name, skin: skin).exists?
  end
end
