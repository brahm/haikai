# Links (txp_link).
class Link < ApplicationRecord
  self.table_name = "txp_link"

  validates :linkname, :url, presence: true

  before_validation do
    self.date ||= Time.now.utc.change(usec: 0)
    self.linksort = linkname if linksort.blank?
  end
end
