#
# Author:: Nuo Yan (<nuo@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef'/'webui_user'
require 'uri'

class ChefServerWebui::Users < ChefServerWebui::Application

  provides :html
  before :login_required, :exclude => [:login, :login_exec, :complete]
    
  # List users, only if the user is admin.
  def index
    begin
      authorized_user
      @users = Chef::WebUIUser.list 
      render
    rescue
      set_user_and_redirect
    end 
  end
  
  # Edit user. Admin can edit everyone, non-admin user can only edit itself.
  def edit
    begin
      raise Forbidden, "The current user is not an Administrator, you can only Show and Edit the user itself. To control other users, login as an Administrator." unless params[:user_id] == session[:user] unless session[:level] == :admin
      @user = Chef::WebUIUser.load(params[:user_id])
      render
    rescue
      set_user_and_redirect
    end 
  end 
  
  # Show the details of a user. If the user is not admin, only able to show itself; otherwise able to show everyone
  def show
    begin
      raise Forbidden, "The current user is not an Administrator, you can only Show and Edit the user itself. To control other users, login as an Administrator." unless params[:user_id] == session[:user] unless session[:level] == :admin
      begin
        @user = Chef::WebUIUser.load(params[:user_id])
      rescue Net::HTTPServerException => e
        raise NotFound, "Cannot find user #{params[:user_id]}"
      end
      render
    rescue 
      set_user_and_redirect
    end 
  end 
  
  # PUT to /users/:user_id/update
  def update
    begin
      begin
        @user = Chef::WebUIUser.load(params[:user_id])
      rescue Net::HTTPServerException => e
        raise NotFound, "Cannot find user #{params[:user_id]}"
      end
      @user.admin = str_to_bool(params[:admin]) if ['true','false'].include?params[:admin]
      session[:level] = :user if params[:user_id] == session[:user] && params[:admin] == 'false'
      @user.set_password(params[:new_password], params[:confirm_new_password]) unless (params[:new_password].nil? || params[:new_password].length == 0)      
      (params[:openid].length == 0 || params[:openid].nil?) ? @user.set_openid(nil) : @user.set_openid(URI.parse(params[:openid]).normalize.to_s)
      @user.save
      @_message = { :notice => "Updated User #{@user.name}" }       
      render :show
    rescue   
      @_message = { :error => $! }
      render :edit
    end 
  end 
  
  def new
    begin
      authorized_user
      @user = Chef::WebUIUser.new
      render
    rescue
      set_user_and_redirect
    end 
  end 

  def create
    begin
      authorized_user
      @user = Chef::WebUIUser.new
      @user.name = params[:name]
      @user.set_password(params[:password], params[:password2])
      @user.admin = true if params[:admin]
      (params[:openid].length == 0 || params[:openid].nil?) ? @user.set_openid(nil) : @user.set_openid(URI.parse(params[:openid]).normalize.to_s)
      begin
        @user.create
      rescue Net::HTTPServerException => e
        if e.message =~ /403/ 
          raise ArgumentError, "User already exists" 
        else 
          raise e
        end 
      end
      redirect(slice_url(:users), :message => { :notice => "Created User #{params[:name]}" })
    rescue
      @_message = { :error => $! }
      session[:level] != :admin ? set_user_and_redirect : (render :new)
    end
  end 

  def login
    @user = Chef::WebUIUser.new
    session[:user] ? redirect(slice_url(:nodes), :message => { :warning => "You've already logged in with user #{session[:user]}"  }) : (render :layout => 'login') 
  end 
  
  def login_exec
    begin
      begin
        @user = Chef::WebUIUser.load(params[:name])
      rescue Net::HTTPServerException => e
        raise NotFound, "Cannot find user #{params[:name]}"
      end 
      raise(Unauthorized, "Wrong username or password.") unless @user.verify_password(params[:password])
      complete
    rescue
      @user = Chef::WebUIUser.new
      @_message = { :error => $! }
      render :login
    end   
  end

  def complete    
    session[:user] = params[:name]
    session[:level] = (@user.admin == true ? :admin : :user)
    (@user.name == Chef::Config[:web_ui_admin_user_name] && @user.verify_password(Chef::Config[:web_ui_admin_default_password])) ? redirect(slice_url(:users_edit, :user_id => @user.name), :message => { :warning => "Please change default password!!!" }) : redirect_back_or_default(absolute_slice_url(:nodes))
  end

  def logout
    cleanup_session
    redirect slice_url(:top)
  end
  
  def destroy
    begin
      raise Forbidden, "The last admin user cannot be deleted" if (is_admin(params[:user_id]) && is_last_admin)
      raise Forbidden, "A non-admin user can only delete itself" if (params[:user_id] != session[:user] && session[:level] != :admin)
      @user = Chef::WebUIUser.load(params[:user_id])
      @user.destroy
      logout if params[:user_id] == session[:user]
      redirect(absolute_slice_url(:users), {:message => { :notice => "User #{params[:user_id]} deleted successfully" }, :permanent => true})
    rescue
      session[:level] != :admin ? set_user_and_redirect : redirect_to_list_users({ :error => $! })
    end 
  end 
  
  private
  
    def set_user_and_redirect
      begin
        @user = Chef::WebUIUser.load(session[:user]) rescue (raise NotFound, "Cannot find User #{session[:user]}, maybe it got deleted by an Administrator.")
      rescue
        logout_and_redirect_to_login
      else  
        redirect(slice_url(:users_show, :user_id => session[:user]), {:message => { :error => $! }, :permanent => true})
      end 
    end 
  
    def redirect_to_list_users(message)
      @_message = message
      @users = Chef::WebUIUser.list 
      render :index
    end 

end
