module Admin
  # The Users panel (event=admin): user accounts and the current user's account.
  class UsersController < BaseController
    self.event_name = "admin"
    self.default_step = :index

    step "author_list", :index
    step "list", :index
    step "author_edit", :edit
    step "author_save", :save, post: true
    step "change_pass", :change_pass, post: true
    step "change_email", :change_email, post: true
    step "admin_multi_edit", :multi_edit, post: true

    SORTS = { "name" => "name", "RealName" => "RealName", "email" => "email", "privs" => "privs", "last_login" => "last_access" }.freeze

    private

    def index
      @page_title = has_privs?("admin.list") ? gTxt("tab_site_admin") : gTxt("tab_site_account")
      if has_privs?("admin.list")
        @state = list_state("admin", SORTS.keys, "name", "asc")
        scope = User.order(Arel.sql("#{SORTS[@state[:sort]]} #{@state[:dir]}, name"))
        crit = params[:crit].to_s.strip
        scope = scope.where("name LIKE :q OR RealName LIKE :q OR email LIKE :q", q: "%#{User.sanitize_sql_like(crit)}%") if crit.present?
        @users = paginate(scope, @state).to_a
        @article_counts = Article.group(:AuthorID).count
      end
      render "admin/users/index"
    end

    def edit
      return require_privs!("admin.edit") unless has_privs?("admin.edit")

      @user = params[:user_id].present? ? User.find_by(user_id: params[:user_id]) : User.new(privs: 4)
      return redirect_with_message(admin_url(event: "admin"), gTxt("not_found"), :error) unless @user

      @page_title = @user.persisted? ? gTxt("edit_author") : gTxt("add_new_author")
      render "admin/users/edit"
    end

    def save
      return require_privs!("admin.edit") unless has_privs?("admin.edit")

      @user = params[:user_id].present? ? User.find_by(user_id: params[:user_id]) : User.new
      return redirect_with_message(admin_url(event: "admin"), gTxt("not_found"), :error) unless @user

      new_record = @user.new_record?
      privs = params[:privs].to_i
      if @user == current_user && privs != current_user.privs
        announce(gTxt("cannot_change_own_role"), :error)
        @page_title = gTxt("edit_author")
        return render("admin/users/edit", status: :unprocessable_entity)
      end

      old_name = @user.name
      @user.assign_attributes(name: params[:name].to_s.strip, RealName: params[:RealName].to_s.strip,
        email: params[:email].to_s.strip, privs: Txp::GROUPS.key?(privs) ? privs : 0)
      password = params[:password].to_s
      activation = new_record && password.empty?
      @user.password = password.presence || SecureRandom.alphanumeric(24) if new_record || password.present?

      unless @user.save
        announce(@user.errors.full_messages.to_sentence, :error)
        @page_title = new_record ? gTxt("add_new_author") : gTxt("edit_author")
        return render("admin/users/edit", status: :unprocessable_entity)
      end

      rename_author(old_name, @user.name) if !new_record && old_name != @user.name
      msg = gTxt(new_record ? "author_created" : "author_saved", "{name}" => @user.name)
      msg += " #{gTxt('account_activation_sent', '{email}' => @user.email)}" if activation && send_activation(@user)
      redirect_with_message(admin_url(event: "admin"), msg)
    end

    def send_activation(user)
      selector = SecureRandom.hex(6)
      secret = SecureRandom.hex(20)
      Token.where(reference_id: user.user_id, type: "account_activation").delete_all
      Token.create!(reference_id: user.user_id, type: "account_activation", selector: selector,
        token: Digest::SHA256.hexdigest(secret), expires: 7.days.from_now.utc.change(usec: 0))
      url = "#{request.base_url}/textpattern/index.php?lang=#{lang_ui}&activate=#{selector}#{secret}"
      AdminMailer.account_activation(user, url).deliver_later
      Rails.logger.info("[txp] activation link for #{user.name}: #{url}") unless Rails.env.production?
      true
    end

    def rename_author(old_name, name)
      Article.where(AuthorID: old_name).update_all(AuthorID: name)
      Article.where(LastModID: old_name).update_all(LastModID: name)
      [ Image, TxpFile, Link ].each { |m| m.where(author: old_name).update_all(author: name) }
      Pref.where(user_name: old_name).update_all(user_name: name)
    end

    def change_pass
      return require_privs!("admin.edit.own") unless has_privs?("admin.edit.own")

      unless current_user.authenticate(params[:current_pass].to_s)
        return redirect_with_message(admin_url(event: "admin"), gTxt("wrong_current_password"), :error)
      end

      current_user.password = params[:new_pass].to_s
      current_user.nonce = SecureRandom.hex(16)
      if current_user.save
        session[:txp_nonce] = current_user.nonce
        redirect_with_message(admin_url(event: "admin"), gTxt("password_changed"))
      else
        redirect_with_message(admin_url(event: "admin"), current_user.errors.full_messages.to_sentence, :error)
      end
    end

    def change_email
      return require_privs!("admin.edit.own") unless has_privs?("admin.edit.own")

      if current_user.update(email: params[:new_email].to_s.strip)
        redirect_with_message(admin_url(event: "admin"), gTxt("email_changed", "{email}" => current_user.email))
      else
        redirect_with_message(admin_url(event: "admin"), current_user.errors.full_messages.to_sentence, :error)
      end
    end

    def multi_edit
      return require_privs!("admin.edit") unless has_privs?("admin.edit")

      users = User.where(name: selected_ids).where.not(user_id: current_user.user_id).to_a
      names = users.map(&:name)
      case params[:edit_method]
      when "delete"
        heir = User.find_by(name: params[:assign_assets].to_s) || current_user
        return redirect_with_message(admin_url(event: "admin"), gTxt("cannot_delete_self"), :error) if names.include?(heir.name)

        User.transaction do
          users.each do |u|
            rename_author(u.name, heir.name)
            u.destroy
          end
        end
        redirect_with_message(admin_url(event: "admin"), gTxt("authors_deleted", "{list}" => names.join(", ")))
      when "changeprivilege"
        privs = params[:privs].to_i
        users.each { |u| u.update(privs: privs) } if Txp::GROUPS.key?(privs)
        redirect_with_message(admin_url(event: "admin"), gTxt("author_saved", "{name}" => names.join(", ")))
      when "resetpassword"
        users.each do |u|
          selector = SecureRandom.hex(6)
          secret = SecureRandom.hex(20)
          Token.where(reference_id: u.user_id, type: "password_reset").delete_all
          Token.create!(reference_id: u.user_id, type: "password_reset", selector: selector, token: Digest::SHA256.hexdigest(secret), expires: 4.hours.from_now.utc.change(usec: 0))
          AdminMailer.password_reset(u, "#{request.base_url}/textpattern/index.php?confirm=#{selector}#{secret}").deliver_later
        end
        redirect_with_message(admin_url(event: "admin"), gTxt("password_reset_sent", "{list}" => names.join(", ")))
      else
        redirect_to admin_url(event: "admin")
      end
    end
  end
end
