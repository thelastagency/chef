#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2009 Opscode, Inc.
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

require 'chef/knife'

class Chef
  class Knife
    class Configure < Knife

      banner "Sub-Command: configure (options)"

      option :repository,
        :short => "-r REPO",
        :long => "--repository REPO",
        :description => "The path to your chef-repo"

      def run 
        config[:config_file] ||= ask_question("Where should I put the config file? ") 
        if File.exists?(config[:config_file]) 
          confirm("Overwrite #{config[:config_file]}")
        end

        Chef::Log::Formatter.show_time = false
        Chef::Log.init(STDOUT)
        Chef::Log.level(:info)

        chef_config_path = File.dirname(config[:config_file])
        FileUtils.mkdir_p(File.dirname(config[:config_file]))

        chef_server = config[:chef_server_url] || ask_question("Your chef server URL? ")
        opscode_user = config[:node_name] || ask_question("Your client user name? ")
        opscode_key = config[:client_key] || File.join(chef_config_path, 'key.pem')

        chef_repo = config[:repository] || ask_question("Path to a chef repostiory (or leave blank)? ")

        File.open(config[:config_file], "w") do |f|
          f.puts <<EOH
log_level        :info
log_location     STDOUT
node_name        '#{opscode_user}'
client_key       '#{opscode_key}'
chef_server_url  '#{chef_server}'  
cache_type       'BasicFile'
cache_options( :path => '#{File.join(chef_config_path, "checksums")}' )
EOH
          unless chef_repo == ""
            f.puts "cookbook_path [ '#{chef_repo}/cookbooks', '#{chef_repo}/site-cookbooks' ]"
          end 
        end

        Chef::Log.warn("*****")
        Chef::Log.warn("You must place your client key in:") 
        Chef::Log.warn("  #{opscode_key}")
        Chef::Log.warn("Before running commands with Knife!")
        Chef::Log.warn("*****")
        Chef::Log.warn("")
        Chef::Log.warn("Configuration file written to #{config[:config_file]}")
      end

    end
  end
end







