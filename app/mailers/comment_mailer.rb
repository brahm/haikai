# Notifies an article's author about a new comment (mail_comment()).
class CommentMailer < ApplicationMailer
  def notify(comment, result)
    article = Article.find_by(ID: comment.parentid)
    author = article && User.find_by(name: article.AuthorID)
    return unless author && author.email.present?

    lang = Pref.get("language_ui", nil, user: author.name) || Pref.get("language", "en")
    t = ->(key, atts = {}) { Txp::Textpack.txt(lang, key, atts, "") }
    status = { Txp::VISIBLE => t.call("visible"), Txp::MODERATE => t.call("unmoderated"), Txp::SPAM => t.call("spam") }[result]
    lines = [
      t.call("salutation", "{name}" => author.display_name),
      t.call("comment_recorded", "{title}" => article.Title),
      "",
      "#{t.call('status')}: #{status}",
      "#{t.call('comment_name')}: #{comment.name}",
      "#{t.call('comment_email')}: #{comment.email}",
      "#{t.call('comment_web')}: #{comment.web}",
      "#{t.call('comment_comment')}: #{ActionController::Base.helpers.strip_tags(comment.message)}"
    ]
    subject = t.call("comment_received", "{site}" => Pref.get("sitename").to_s, "{title}" => article.Title)
    mail(to: author.email, from: Pref.get("smtp_from").presence || Pref.get("publisher_email").presence || author.email, subject: subject, reply_to: comment.email.presence) do |format|
      format.text { render plain: lines.join("\n") }
    end
  end
end
