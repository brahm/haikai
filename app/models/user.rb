# Authors / admin users (txp_users).
class User < ApplicationRecord
  self.table_name = "txp_users"
  self.primary_key = "user_id"

  attr_reader :password

  validates :name, presence: true, uniqueness: true, format: { with: /\A[\p{L}\p{N}_\-.@]+\z/ }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :privs, inclusion: { in: Txp::GROUPS.keys }
  validates :password, length: { minimum: 6 }, allow_nil: true

  before_validation { self.nonce = SecureRandom.hex(16) if nonce.blank? }

  def password=(value)
    @password = value
    self.pass = BCrypt::Password.create(value) if value.present?
  end

  # Accepts bcrypt ($2y$ from PHP too) and legacy PHPass/MD5 hashes.
  def authenticate(value)
    hash = pass.to_s
    ok = if hash.start_with?("$2y$", "$2a$", "$2b$")
      BCrypt::Password.new(hash.sub(/\A\$2y\$/, "$2a$")) == value
    elsif hash.start_with?("$P$", "$H$")
      Txp::Phpass.check(value, hash)
    elsif hash.match?(/\A\h{32}\z/)
      ActiveSupport::SecurityUtils.secure_compare(Digest::MD5.hexdigest(value), hash)
    else
      false
    end
    if ok && !hash.start_with?("$2a$", "$2b$")
      self.password = value
      save(validate: false)
    end
    ok ? self : false
  end

  def group
    Txp::GROUPS[privs]
  end

  def display_name
    self.RealName.presence || name
  end

  def can?(resource)
    Txp::Privs.has?(resource, privs)
  end

  def articles_count
    Article.where(AuthorID: name).count
  end
end
