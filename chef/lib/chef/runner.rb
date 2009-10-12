#
# Author:: Adam Jacob (<adam@opscode.com>)
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

require 'chef/mixin/params_validate'
require 'chef/node'
require 'chef/resource_collection'
require 'chef/platform'

class Chef
  class Runner
    
    include Chef::Mixin::ParamsValidate
    
    def initialize(node, collection, definitions=nil, cookbook_loader=nil)
      validate(
        {
          :node => node,
          :collection => collection,
        },
        {
          :node => {
            :kind_of => Chef::Node,
          },
          :collection => {
            :kind_of => Chef::ResourceCollection,
          },
        }
      )
      @node = node
      @collection = collection
      @definitions = definitions
      @cookbook_loader = cookbook_loader
    end
    
    def converge
      @delayed_actions = Hash.new
      
      @collection.execute_each_resource do |resource|
        begin
          Chef::Log.debug("Processing #{resource}")
          
          next if only_if?(resource)
          next if not_if?(resource)
          run_actions(resource)
          @delayed_actions.merge!(resource.delayed_actions)
          
        rescue => e
          Chef::Log.error("#{resource} (#{resource.source_line}) had an error:\n#{e}\n#{e.backtrace}")
          raise e unless resource.ignore_failure
        end
      end

      run_delayed_actions
      true
    end
    
    def not_if?(resource)
      if resource.not_if
        unless Chef::Mixin::Command.not_if(resource.not_if)
          Chef::Log.debug("Skipping #{resource} due to not_if")
          true
        end
      end
    end
    
    def only_if?(resource)
      if resource.only_if
        unless Chef::Mixin::Command.only_if(resource.only_if)
          Chef::Log.debug("Skipping #{resource} due to only_if")
          true
        end
      end
    end

    def run_actions(resource)
      action_list = resource.action.kind_of?(Array) ? resource.action : [ resource.action ]
      action_list.each do |action|
        resource.run_action(action)
      end
    end
    
    def run_delayed_actions
      @delayed_actions.each do |resource, actions|
        actions.each do |action, log_messages|
          log_messages.each { |log_message| log_message.call }
          resource.run_action(action)
        end
      end
    end
    
  end
end
