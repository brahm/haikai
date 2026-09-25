# Categories (txp_category), a nested set per type (article, image, file, link).
class Category < ApplicationRecord
  self.table_name = "txp_category"
  self.inheritance_column = :_type_disabled

  TYPES = %w[article image file link].freeze

  validates :name, presence: true, format: { with: /\A[\p{L}\p{N}_\-]+\z/ }
  validates :name, uniqueness: { scope: :type }
  validates :type, inclusion: { in: TYPES }

  scope :of_type, ->(t) { where(type: t) }
  scope :visible, -> { where.not(name: "root") }

  # Rebuilds lft/rgt for a whole type (rebuild_tree_full()).
  def self.rebuild_tree(type)
    transaction do
      root = find_or_create_by!(type: type, name: "root") { |c| c.title = "root" }
      root.update_columns(parent: "")
      where(type: type).update_all(lft: 0, rgt: 0)
      names = where(type: type).pluck(:name)
      where(type: type).where.not(name: "root").where.not(parent: names).update_all(parent: "root")
      where(type: type).where.not(name: "root").where(parent: "").update_all(parent: "root")
      rebuild_node(type, "root", 1, {})
    end
  end

  def self.rebuild_node(type, name, left, seen)
    return left if seen[name]

    seen[name] = true
    right = left + 1
    where(type: type, parent: name).where.not(name: name).order(:name).pluck(:name).each do |child|
      right = rebuild_node(type, child, right, seen)
    end
    where(type: type, name: name).update_all(lft: left, rgt: right)
    right + 1
  end

  # Ordered tree with levels, excluding root.
  def self.tree(type)
    rows = of_type(type).visible.order(:lft).to_a
    stack = []
    rows.map do |c|
      stack.pop while stack.any? && stack.last < c.rgt
      level = stack.length
      stack << c.rgt
      [ c, level ]
    end
  end

  def descendant_names
    Category.of_type(type).where("lft > ? AND rgt < ?", lft, rgt).pluck(:name)
  end
end
