#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Christopher Brown (<cb@opscode.com>)
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

require 'chef/log'
require 'chef/config'
require 'chef/api_client'
require 'openssl'
require 'fileutils'

class Chef
  class Certificate
    class << self
  
      # Generates a new CA Certificate and Key, and writes them out to
      # Chef::Config[:signing_ca_cert] and Chef::Config[:signing_ca_key].
      def generate_signing_ca
        ca_cert_file = Chef::Config[:signing_ca_cert]
        ca_keypair_file = Chef::Config[:signing_ca_key] 

        unless File.exists?(ca_cert_file) && File.exists?(ca_keypair_file)
          Chef::Log.info("Creating new signing certificate")
        
          [ ca_cert_file, ca_keypair_file ].each do |f|
            ca_basedir = File.dirname(f)
            FileUtils.mkdir_p ca_basedir
          end

          keypair = OpenSSL::PKey::RSA.generate(1024)

          ca_cert = OpenSSL::X509::Certificate.new
          ca_cert.version = 3
          ca_cert.serial = 1
          info = [
            ["C", Chef::Config[:signing_ca_country]], 
            ["ST", Chef::Config[:signing_ca_state]], 
            ["L", Chef::Config[:signing_ca_location]], 
            ["O", Chef::Config[:signing_ca_org]],
            ["OU", "Certificate Service"], 
            ["CN", "#{Chef::Config[:signing_ca_domain]}/emailAddress=#{Chef::Config[:signing_ca_email]}"]
          ]
          ca_cert.subject = ca_cert.issuer = OpenSSL::X509::Name.new(info)
          ca_cert.not_before = Time.now
          ca_cert.not_after = Time.now + 10 * 365 * 24 * 60 * 60 # 10 years
          ca_cert.public_key = keypair.public_key

          ef = OpenSSL::X509::ExtensionFactory.new
          ef.subject_certificate = ca_cert
          ef.issuer_certificate = ca_cert
          ca_cert.extensions = [
                  ef.create_extension("basicConstraints", "CA:TRUE", true),
                  ef.create_extension("subjectKeyIdentifier", "hash"),
                  ef.create_extension("keyUsage", "cRLSign,keyCertSign", true),
          ]
          ca_cert.add_extension ef.create_extension("authorityKeyIdentifier", "keyid:always,issuer:always")
          ca_cert.sign keypair, OpenSSL::Digest::SHA1.new

          File.open(ca_cert_file, "w") { |f| f.write ca_cert.to_pem }
          File.open(ca_keypair_file, "w") { |f| f.write keypair.to_pem }
        end
        self
      end

      # Creates a new key pair, and signs them with the signing certificate
      # and key generated from generate_signing_ca above.  
      #
      # @param [String] The common name for the key pair.
      # @param [Optional String] The subject alternative name.
      # @return [Object, Object] The public and private key objects.
      def gen_keypair(common_name, subject_alternative_name = nil)

        Chef::Log.info("Creating new key pair for #{common_name}")

        # generate client keypair
        client_keypair = OpenSSL::PKey::RSA.generate(2048)

        client_cert = OpenSSL::X509::Certificate.new

        ca_cert = OpenSSL::X509::Certificate.new(File.read(Chef::Config[:signing_ca_cert]))

        info = [
          ["C", Chef::Config[:signing_ca_country]], 
          ["ST", Chef::Config[:signing_ca_state]], 
          ["L", Chef::Config[:signing_ca_location]], 
          ["O", Chef::Config[:signing_ca_org]],
          ["OU", "Certificate Service"], 
          ["CN", common_name ]
        ]

        client_cert.subject = OpenSSL::X509::Name.new(info)
        client_cert.issuer = ca_cert.subject
        client_cert.not_before = Time.now
        client_cert.not_after = Time.now + 10 * 365 * 24 * 60 * 60 # 10 years
        client_cert.public_key = client_keypair.public_key
        client_cert.serial = 1
        client_cert.version = 3

        ef = OpenSSL::X509::ExtensionFactory.new
        ef.subject_certificate = client_cert
        ef.issuer_certificate = ca_cert

        client_cert.extensions = [
                ef.create_extension("basicConstraints", "CA:FALSE", true),
                ef.create_extension("subjectKeyIdentifier", "hash")
        ]
        client_cert.add_extension ef.create_extension("subjectAltName", subject_alternative_name) if subject_alternative_name

        client_cert.sign(OpenSSL::PKey::RSA.new(File.read(Chef::Config[:signing_ca_key])), OpenSSL::Digest::SHA1.new)

        return client_cert.public_key, client_keypair
      end

      def gen_validation_key(name=Chef::Config[:validation_client_name], key_file=Chef::Config[:validation_key])
        # Create the validation key
        create_key = false 
        begin
          c = Chef::ApiClient.cdb_load(name)
        rescue Chef::Exceptions::CouchDBNotFound
          create_key = true
        end

        if create_key
          Chef::Log.info("Creating validation key...")
          api_client = Chef::ApiClient.new
          api_client.name(name)
          api_client.admin(true)
          api_client.create_keys
          api_client.cdb_save
          key_dir = File.dirname(key_file)
          FileUtils.mkdir_p(key_dir) unless File.directory?(key_dir)
          File.open(key_file, "w") do |f|
            f.print(api_client.private_key)
          end
        end
      end

    end
  end
end
