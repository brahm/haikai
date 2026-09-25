# Sections (txp_section).
class Section < ApplicationRecord
  self.table_name = "txp_section"
  self.primary_key = "name"

  belongs_to :skin_record, class_name: "Skin", foreign_key: "skin", primary_key: "name", optional: true

  validates :name, presence: true, uniqueness: true, format: { with: /\A[\p{L}\p{N}_\-]+\z/ }

  def self.index_by_name
    connection.select_all("SELECT * FROM txp_section").to_a.index_by { |r| r["name"] }
  end

  def articles_count
    Article.where(Section: name).count
  end
end
