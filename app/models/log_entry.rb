# Visitor logs (txp_log).
class LogEntry < ApplicationRecord
  self.table_name = "txp_log"

  def request_method
    self[:method]
  end
end
