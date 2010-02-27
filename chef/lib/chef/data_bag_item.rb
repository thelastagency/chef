#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Nuo Yan (<nuo@opscode.com>)
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

require 'chef/config'
require 'chef/mixin/params_validate'
require 'chef/mixin/from_file'
require 'chef/couchdb'
require 'chef/data_bag_item'
require 'extlib'
require 'json'

class Chef
  class DataBagItem
    
    include Chef::Mixin::FromFile
    include Chef::Mixin::ParamsValidate
    include Chef::IndexQueue::Indexable
    
    DESIGN_DOCUMENT = {
      "version" => 1,
      "language" => "javascript",
      "views" => {
        "all" => {
          "map" => <<-EOJS
          function(doc) { 
            if (doc.chef_type == "data_bag_item") {
              emit(doc.name, doc);
            }
          }
          EOJS
        },
        "all_id" => {
          "map" => <<-EOJS
          function(doc) { 
            if (doc.chef_type == "data_bag_item") {
              emit(doc.name, doc.name);
            }
          }
          EOJS
        }
      }
    }

    attr_accessor :couchdb_rev, :raw_data, :couchdb_id, :couchdb
    
    # Create a new Chef::DataBagItem
    def initialize(couchdb=nil)
      @couchdb_rev = nil
      @couchdb_id = nil
      @data_bag = nil
      @raw_data = Mash.new
      @couchdb = couchdb ? couchdb : Chef::CouchDB.new
    end

    def raw_data
      @raw_data
    end

    def raw_data=(new_data)
      unless new_data.kind_of?(Hash) || new_data.kind_of?(Mash)
        raise ArgumentError, "Data Bag Items must contain a Hash or Mash!"
      end
      unless new_data.has_key?("id")
        raise ArgumentError, "Data Bag Items must have an id key in the hash! #{new_data.inspect}"
      end
      unless new_data["id"] =~ /^[\-[:alnum:]_]+$/
        raise ArgumentError, "Data Bag Item id does not match alphanumeric/-/_!"
      end
      @raw_data = new_data
    end

    def data_bag(arg=nil) 
      set_or_return(
        :data_bag,
        arg,
        :regex => /^[\-[:alnum:]_]+$/
      )
    end

    def name
      object_name
    end

    def object_name
      if raw_data.has_key?('id')
        id = raw_data['id']
      else
        raise ArgumentError, "You must have an 'id' or :id key in the raw data"
      end
     
      data_bag_name = self.data_bag
      unless data_bag_name
        raise ArgumentError, "You must have declared what bag this item belongs to!"
      end
      "data_bag_item_#{data_bag_name}_#{id}"
    end

    def self.object_name(data_bag_name, id)
      "data_bag_item_#{data_bag_name}_#{id}"
    end

    def to_hash
      result = self.raw_data
      result["chef_type"] = "data_bag_item"
      result["data_bag"] = self.data_bag
      result["_rev"] = @couchdb_rev if @couchdb_rev
      result
    end

    # Serialize this object as a hash 
    def to_json(*a)
      result = {
        "name" => self.object_name,
        "json_class" => self.class.name,
        "chef_type" => "data_bag_item",
        "data_bag" => self.data_bag,
        "raw_data" => self.raw_data
      }
      result["_rev"] = @couchdb_rev if @couchdb_rev
      result.to_json(*a)
    end
    
    # Create a Chef::DataBagItem from JSON
    def self.json_create(o)
      bag_item = new
      bag_item.data_bag(o["data_bag"])
      o.delete("data_bag")
      o.delete("chef_type")
      o.delete("json_class")
      o.delete("name")
      if o.has_key?("_rev")
        bag_item.couchdb_rev = o["_rev"] 
        o.delete("_rev")
      end
      if o.has_key?("_id")
        bag_item.couchdb_id = o["_id"] 
        o.delete("_id")
      end
      bag_item.raw_data = Mash.new(o["raw_data"])
      bag_item
    end

    # The Data Bag Item behaves like a hash - we pass all that stuff along to @raw_data.
    def method_missing(method_symbol, *args, &block) 
      self.raw_data.send(method_symbol, *args, &block)
    end
    
    # Load a Data Bag Item by name from CouchDB
    def self.cdb_load(data_bag, name, couchdb=nil)
      couchdb = couchdb ? couchdb : Chef::CouchDB.new
      couchdb.load("data_bag_item", object_name(data_bag, name))
    end
    
    # Load a Data Bag Item by name via RESTful API
    def self.load(data_bag, name)
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      r.get_rest("data/#{data_bag}/#{name}")
    end
    
    # Remove this Data Bag Item from CouchDB
    def cdb_destroy
      removed = @couchdb.delete("data_bag_item", object_name, @couchdb_rev)
      removed
    end
    
    def destroy(data_bag=data_bag, databag_item=name)
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      r.delete_rest("data/#{data_bag}/#{databag_item}")
    end
     
    # Save this Data Bag Item to CouchDB
    def cdb_save
      results = @couchdb.store("data_bag_item", object_name, self)
      @couchdb_rev = results["rev"]
    end
    
    # Save this Data Bag Item via RESTful API
    def save(item_id=@raw_data['id'])
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      begin
        r.put_rest("data/#{data_bag}/#{item_id}", @raw_data)
      rescue Net::HTTPServerException => e
        if e.response.code == "404"
          r.post_rest("data/#{data_bag}", @raw_data) 
        else
          raise e
        end
      end
      self
    end
    
    # Create this Data Bag Item via RESTful API
    def create
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      r.post_rest("data/#{data_bag}", @raw_data) 
      self
    end 
    
    # Set up our CouchDB design document
    def self.create_design_document(couchdb=nil)
      couchdb ||= Chef::CouchDB.new
      couchdb.create_design_document("data_bag_items", DESIGN_DOCUMENT)
    end
    
    # As a string
    def to_s
      "data_bag_item[#{@name}]"
    end

  end
end


