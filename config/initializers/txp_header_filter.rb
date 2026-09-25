# Rack middleware giving public-site responses exactly the caching headers
# Textpattern sends: Rails would otherwise add its own Cache-Control
# ("max-age=0, private, must-revalidate" next to an ETag), weak ETags and
# "Vary: Accept".
# PublicController stores Textpattern's headers in env["txp.headers"].
class TxpHeaderFilter
  MANAGED = %w[cache-control vary etag last-modified].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    if (txp = env["txp.headers"])
      txp = txp.transform_keys { |k| k.to_s.downcase }
      MANAGED.each { |name| txp.key?(name) ? headers[name] = txp[name] : headers.delete(name) }
    end
    [ status, headers, body ]
  end
end

Rails.application.config.middleware.insert_before 0, TxpHeaderFilter
