module Txp
  # Handles a public-side request end to end (port of publish.php +
  # textpattern()): resolves the URL, dispatches feeds, comment posts and file
  # downloads, renders the section's page template and error pages.
  class Publisher
    Result = Struct.new(:status, :headers, :body, :file, :cookies, keyword_init: true)

    STATUS_TEXT = {
      200 => "OK", 301 => "Moved Permanently", 302 => "Found", 303 => "See Other", 304 => "Not Modified",
      307 => "Temporary Redirect", 308 => "Permanent Redirect", 401 => "Unauthorized", 403 => "Forbidden",
      404 => "Not Found", 410 => "Gone", 414 => "Request-URI Too Long", 451 => "Unavailable For Legal Reasons",
      500 => "Internal Server Error", 501 => "Not Implemented", 503 => "Service Unavailable"
    }.freeze

    attr_reader :renderer

    def initialize(request, user: nil)
      @request = request
      @user = user
    end

    def call
      Plugins.load!
      @renderer = Renderer.new(request: @request, user: @user)
      trace_queries(@renderer.trace) { dispatch }
    end

    # Feeds the request's SQL queries to the trace (Textpattern's safe_query()
    # logs each one).
    def trace_queries(trace, &)
      callback = lambda do |event|
        next if %w[SCHEMA CACHE TRANSACTION].include?(event.payload[:name])

        trace.query(traced_sql(event.payload), event.duration / 1000.0)
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    end

    # The query with its bound values, without Rails' query log tags.
    def traced_sql(payload)
      sql = payload[:sql].to_s.sub(%r{\s*/\*.*?\*/\s*\z}m, "")
      binds = payload[:type_casted_binds]
      binds = binds.call if binds.respond_to?(:call)
      return sql if binds.blank?

      values = binds.dup
      sql.gsub("?") { values.empty? ? "?" : ActiveRecord::Base.connection.quote(values.shift) }
    end

    # Trace summary (and log in debug mode) appended outside live mode.
    def debug_trailer(r)
      return "" if r.production_status == "live"

      r.trace.summary + (r.production_status == "debug" ? r.trace.result : "")
    end

    def dispatch
      r = @renderer
      r.pretext!
      Callbacks.fire("pretext_end")
      pretext = r.pretext
      # Send 304 Not Modified if appropriate.
      r.handle_lastmod if pretext["feed"].to_s.empty?

      if pretext["status"] == "200" && %w[rss atom].include?(pretext["feed"])
        body = pretext["feed"] == "rss" ? r.render_rss : r.render_atom
        status = r.response_headers.delete("status")&.to_i || 200
        return result(status, body + debug_trailer(r), r.content_type, r)
      end

      if Php.truthy?(r.gps("parentid"))
        if Php.truthy?(r.ps("submit")) || Php.truthy?(r.ps("preview"))
          r.handle_comment_post
        elsif Php.intval(r.get_pref("comments_mode")) == 1
          r.parentid = r.gps("parentid")
          body = Php.str(r.parse_form("popup_comments"))
          return result(200, body, "text/html; charset=utf-8", r)
        end
      end

      if pretext["s"] == "file_download"
        return file_download(r) if Php.truthy?(pretext["filename"]) || r.thisfile

        r.txp_die(r.gTxt("404_not_found"), "404")
      end

      log_hit(pretext["status"].to_i)
      r.txp_die(r.gTxt("404_not_found"), "404") if pretext["status"] == "404"
      r.txp_die(r.gTxt("410_gone"), "410") if pretext["status"] == "410"

      Callbacks.fire("textpattern")
      html = r.parse_page(pretext["page"], pretext["skin"])
      r.txp_die(r.gTxt("unknown_section"), "404") if html == false

      if (download = r.file_to_send)
        return send_file_result(r, download[:file], download[:type])
      end

      body = r.errors.join + Php.str(html).lstrip + debug_trailer(r)
      status = r.response_headers.delete("status")&.to_i || 200
      result(status, body, r.response_headers.delete("content-type") || "text/html; charset=utf-8", r)
    rescue Txp::NotModified
      log_hit(304)
      headers = { "Content-Length" => "0" }
      @renderer.response_headers.each { |k, v| headers[k.split("-").map(&:capitalize).join("-")] = v unless k == "status" }
      Result.new(status: 304, headers: headers, body: "", cookies: @renderer.cookies_to_set)
    rescue Txp::Redirect => e
      Result.new(status: e.status, headers: { "Location" => e.location }, body: "", cookies: @renderer&.cookies_to_set || {})
    rescue Txp::Die => e
      error_page(e)
    end

    def result(status, body, content_type, r)
      headers = { "Content-Type" => content_type || "text/html; charset=utf-8" }
      r.response_headers.each { |k, v| headers[k.split("-").map(&:capitalize).join("-")] = v unless k == "status" }
      Result.new(status: status, headers: headers, body: body, cookies: r.cookies_to_set)
    end

    def error_page(die)
      r = @renderer || Renderer.new(request: @request, user: @user)
      code = die.status.to_i
      code = 503 if code.zero?

      if die.url.present? && [ 301, 302, 303, 307, 308 ].include?(code)
        return Result.new(status: code, headers: { "Location" => die.url }, body: "", cookies: r.cookies_to_set)
      end

      status_line = STATUS_TEXT.key?(code) ? "#{code} #{STATUS_TEXT[code]}" : die.status
      skin = r.pretext["skin"].presence || Section.where(name: "default").pick(:skin)
      out = r.fetch_page("error_#{code}", skin)
      out = r.fetch_page("error_default", skin) if out == false
      if out == false
        out = <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
             <meta charset="utf-8">
             <meta name="robots" content="noindex">
             <title>Textpattern Error: <txp:error_status /></title>
          </head>
          <body>
              <p><txp:error_message /></p>
          </body>
          </html>
        HTML
      end

      # txp_die() takes the trace summary before parsing the error page.
      trailer = debug_trailer(r)
      r.set_error_page(die.message, status_line, code)
      r.txp_atts = nil
      r.pretext["skin"] = skin if r.pretext["skin"].to_s.empty?
      body = begin
        Php.str(r.parse(out))
      rescue Txp::Die, Txp::Redirect
        die.message
      end
      headers = { "Content-Type" => "text/html; charset=utf-8" }
      r.response_headers.each { |k, v| headers[k.split("-").map(&:capitalize).join("-")] = v unless %w[status content-type].include?(k) }
      Result.new(status: code, headers: headers, body: r.errors.join + body + trailer, cookies: r.cookies_to_set)
    end

    # output_file_download()
    def file_download(r)
      r.response_headers.delete("last-modified")
      r.response_headers.delete("etag")
      file = r.thisfile
      return error_page(Die.new(r.gTxt("404_not_found"), "404")) unless file

      send_file_result(r, file, nil)
    end

    def send_file_result(r, file, type)
      rec = TxpFile.find_by(id: file["id"])
      return error_page(Die.new(r.gTxt("404_not_found"), "404")) unless rec&.exists?

      TxpFile.where(id: rec.id).update_all("downloads = downloads + 1")
      log_hit(200)
      # set_headers() keeps a Cache-Control already sent (no-cache outside live mode).
      headers = { "Cache-Control" => r.response_headers["cache-control"] || "private" }
      Result.new(status: 200, headers: headers, body: nil, cookies: r.cookies_to_set,
        file: { path: rec.path.to_s, filename: rec.filename, type: type || "application/octet-stream" })
    end

    def log_hit(status)
      return if status == 404 || @renderer.nil?

      mode = @renderer.get_pref("logging", "none")
      return if mode == "none" || @renderer.instance_variable_get(:@nolog)

      referer = @request.referer.to_s
      host = @request.host.to_s.sub(/\Awww\./, "")
      referer = "" if referer.present? && (URI.parse(referer).host.to_s.sub(/\Awww\./, "") == host rescue true)
      return if mode == "refer" && referer.empty?

      LogEntry.insert({ time: Time.now.utc.change(usec: 0), page: @request.original_fullpath.to_s[0, 255], refer: referer, status: status, method: @request.request_method })
    rescue StandardError => e
      Rails.logger.warn("[txp] log_hit failed: #{e.message}")
    end
  end
end
