# Themes (txp_skin) group pages, forms and styles.
class Skin < ApplicationRecord
  self.table_name = "txp_skin"
  self.primary_key = "name"

  has_many :pages, foreign_key: "skin", primary_key: "name"
  has_many :forms, foreign_key: "skin", primary_key: "name"
  has_many :styles, foreign_key: "skin", primary_key: "name"

  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_\-.]+\z/ }
  validates :title, presence: true

  def sections_count
    Section.where(skin: name).count
  end

  def in_use?
    Section.where(skin: name).or(Section.where(dev_skin: name)).exists?
  end
end
