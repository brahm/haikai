# Comments (txp_discuss).
class Comment < ApplicationRecord
  self.table_name = "txp_discuss"
  self.primary_key = "discussid"

  belongs_to :article, foreign_key: "parentid", primary_key: "ID", optional: true

  validates :message, presence: true

  after_save :refresh_count
  after_destroy :refresh_count

  scope :visible, -> { where(visible: Txp::VISIBLE) }
  scope :moderated, -> { where(visible: Txp::MODERATE) }
  scope :spam, -> { where(visible: Txp::SPAM) }

  def visibility_name
    { Txp::VISIBLE => "visible", Txp::MODERATE => "unmoderated", Txp::SPAM => "spam" }[visible]
  end

  private

  def refresh_count
    Article.update_comments_count(parentid)
  end
end
