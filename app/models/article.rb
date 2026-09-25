# Articles (the "textpattern" table). Column names follow Textpattern.
class Article < ApplicationRecord
  self.table_name = "textpattern"
  self.primary_key = "ID"

  alias_attribute :title, :Title
  alias_attribute :body, :Body
  alias_attribute :excerpt, :Excerpt
  alias_attribute :status, :Status
  alias_attribute :section, :Section
  alias_attribute :posted, :Posted
  alias_attribute :expires, :Expires
  alias_attribute :author_id, :AuthorID
  alias_attribute :category1, :Category1
  alias_attribute :category2, :Category2
  alias_attribute :keywords, :Keywords
  alias_attribute :image, :Image
  alias_attribute :annotate, :Annotate
  alias_attribute :annotate_invite, :AnnotateInvite
  alias_attribute :last_mod, :LastMod
  alias_attribute :last_mod_id, :LastModID

  has_many :comments, foreign_key: "parentid", primary_key: "ID", dependent: :delete_all
  belongs_to :author, class_name: "User", foreign_key: "AuthorID", primary_key: "name", optional: true

  validates :Title, length: { maximum: 255 }
  validates :Status, inclusion: { in: Txp::STATUSES.keys }

  before_validation :apply_defaults
  before_save :render_markup

  scope :live, -> { where(Status: [ Txp::STATUS_LIVE, Txp::STATUS_STICKY ]) }

  def self.update_comments_count(id)
    count = Comment.where(parentid: id, visible: Txp::VISIBLE).count
    where(ID: id).update_all(comments_count: count)
  end

  def status_name
    Txp::STATUSES[self.Status]
  end

  def live?
    [ Txp::STATUS_LIVE, Txp::STATUS_STICKY ].include?(self.Status)
  end

  def custom_field(num)
    self["custom_#{num}"]
  end

  private

  def apply_defaults
    now = Time.now.utc.change(usec: 0)
    self.Posted ||= now
    self.LastMod = now
    self.uid = SecureRandom.hex(16) if uid.blank?
    self.feed_time ||= self.Posted.to_date
    self.url_title = Txp::Text.strip_space(self.Title, Pref.site_prefs, force: true) if url_title.blank? && self.Title.present?
  end

  def render_markup
    self.Title_html = self.Title.to_s
    self.Body_html = Txp::TextFilter.apply(self.Body.to_s, textile_body)
    self.Excerpt_html = Txp::TextFilter.apply(self.Excerpt.to_s, textile_excerpt)
  end
end
