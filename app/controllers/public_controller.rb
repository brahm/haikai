# Public site: every URL not handled elsewhere is resolved by the Textpattern
# router and rendered from the section's page template.
class PublicController < ApplicationController
  skip_forgery_protection

  def show
    # With Textpattern's .htaccess, Apache answers a missing file inside an
    # existing directory (themes/, images/, ...) itself instead of index.php.
    first, rest = request.path.delete_prefix("/").split("/", 2)
    if rest.present? && first.present? && !first.start_with?(".") && File.directory?(Rails.public_path.join(first))
      return head(:not_found)
    end

    result = Txp::Publisher.new(request, user: current_user).call
    request.env["txp.headers"] = result.headers
    apply_cookies(result.cookies)

    if result.file
      send_file result.file[:path], filename: result.file[:filename], type: result.file[:type], disposition: "attachment"
      return
    end

    result.headers.each { |k, v| response.headers[k] = v unless k == "Content-Type" }
    if result.headers["Location"]
      redirect_to result.headers["Location"], status: result.status, allow_other_host: true
    else
      render body: result.body, status: result.status, content_type: result.headers["Content-Type"] || "text/html; charset=utf-8"
    end
  end

  # /css.php?n=name&t=theme (or ?s=section) -- Textpattern stylesheet URLs.
  def css
    prefs = Pref.site_prefs
    names = Txp::Php.do_list_unique(params[:n])
    theme = params[:t].to_s

    if names.empty? && params[:s].present?
      section = Section.find_by(name: params[:s])
      names = [ section&.css ].compact
      theme = section&.skin.to_s if theme.empty?
    end

    theme = Section.where(name: "default").pick(:skin).to_s if theme.empty?
    css = names.filter_map { |n| Style.where(name: n, skin: theme).pick(:css) }.join("\n")
    expires_in 1.hour, public: true if prefs["production_status"] == "live"
    render plain: css, content_type: "text/css; charset=utf-8"
  end

  # /images/thumb/<params>/<id><ext> -- automatic thumbnails.
  def thumbnail
    prefs = Pref.site_prefs
    paramlist = params[:params].to_s
    file = params[:file].to_s
    id = file[/\A\d+/]
    head(:not_found) and return unless id

    token = params[:token].to_s
    unless ActiveSupport::SecurityUtils.secure_compare(token, Txp::Thumbnails.token(id, paramlist, prefs))
      head(:forbidden) and return
    end

    image = Image.find_by(id: id)
    head(:not_found) and return unless image && File.exist?(image.path)

    opts = Txp::Thumbnails.decode(paramlist)
    ext = File.extname(file)
    dest = Txp::Images.dir(prefs).join("thumb", paramlist, "#{id}#{ext}")
    unless File.exist?(dest)
      dims = Txp::Images.resize(image.path, dest, width: opts["w"], height: opts["h"], crop: opts["c"], quality: opts["q"])
      unless dims
        send_file image.path, type: Txp::Images.mime_for(image.ext), disposition: "inline"
        return
      end
    end

    send_file dest, type: Txp::Images.mime_for(ext), disposition: "inline"
  end

  private

  def apply_cookies(list)
    (list || {}).each do |name, c|
      if c[:expires] && c[:expires] < Time.now
        cookies.delete(name, path: c[:path])
      else
        cookies[name] = { value: c[:value], expires: c[:expires], path: c[:path] }
      end
    end
  end
end
