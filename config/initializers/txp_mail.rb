Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method :textpattern, Txp::MailDelivery
end

# Mail jobs carry password reset and account activation links: keep them out
# of the logs.
ActiveSupport.on_load(:action_mailer) do
  ActionMailer::MailDeliveryJob.log_arguments = false
end
