module Admin
  # The Visitor logs panel (event=log).
  class LogsController < BaseController
    self.event_name = "log"
    self.event_priv = "log"
    self.default_step = :index

    step "log_list", :index
    step "list", :index
    step "log_multi_edit", :multi_edit, post: true

    SORTS = { "time" => "time", "page" => "page", "refer" => "refer", "method" => "method", "status" => "status" }.freeze

    private

    def index
      expire_old
      @page_title = gTxt("tab_logs")
      @state = list_state("log", SORTS.keys, "time")
      scope = LogEntry.order(Arel.sql("#{SORTS[@state[:sort]]} #{@state[:dir]}, id #{@state[:dir]}"))
      crit = params[:crit].to_s.strip
      if crit.present?
        like = "%#{LogEntry.sanitize_sql_like(crit)}%"
        scope = case params[:search_method]
        when "refer" then scope.where("refer LIKE ?", like)
        when "status" then scope.where(status: crit.to_i)
        else scope.where("page LIKE ?", like)
        end
      end
      @logs = paginate(scope, @state).to_a
      render "admin/logs/index"
    end

    def expire_old
      days = @prefs["expire_logs_after"].to_i
      LogEntry.where("time < ?", days.days.ago.utc).delete_all if days.positive?
    end

    def multi_edit
      ids = selected_ids.map(&:to_i)
      LogEntry.where(id: ids).delete_all if params[:edit_method] == "delete"
      redirect_with_message(admin_url(event: "log"), gTxt("logs_deleted", "{list}" => ids.join(", ")))
    end
  end
end
