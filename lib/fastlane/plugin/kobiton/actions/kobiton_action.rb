require 'fastlane/action'
require_relative '../helper/kobiton_helper'

module Fastlane
  module Actions
    class KobitonAction < Action
      def self.run(params)
        require "base64"

        host = params[:host] || "api.kobiton.com"
        username = params[:username]
        api_key = params[:api_key]
        param_verify_ssl = params[:verify_ssl] || 'true'
        verify_ssl = param_verify_ssl.to_bol

        # Must use strict encoding because encode64() will insert
        # a new line every 60 characters and at the end of the
        # encoded string...
        base64_authorization = Base64.strict_encode64("#{username}:#{api_key}")
        authorization = "Basic #{base64_authorization}"

        filepath = params[:file]
        app_id = params[:app_id]

        filename = File.basename(filepath)

        UI.message("Getting upload URL...")

        kobiton_upload_pair = self.get_upload_url(host, verify_ssl, filename, app_id, authorization)

        UI.message("Got upload URL.")

        app_path = kobiton_upload_pair["appPath"]
        upload_url = kobiton_upload_pair["url"]

        UI.message("Uploading the build to storage...")

        upload_success = self.upload_file(upload_url, verify_ssl, filepath)

        if upload_success
          UI.message("Successfully uploaded the build to storage.")
        else
          UI.user_error!("Failed to upload the build to storage.")
        end

        self.notify_kobiton_after_file_upload(host, verify_ssl, app_path, filename, authorization)

        UI.message("Successfully uploaded the build to Kobiton!")
      end

      def self.description
        "Upload build to Kobiton"
      end

      def self.authors
        ["Vlad Rusu"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "A Fastlane plugin which allows you to upload the iOS and Android builds to Kobiton"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :host,
            env_name: "FL_KOBITON_HOST",
            description: "Kobiton host server",
            verify_block: proc do |value|
              UI.user_error!("No Host for KobitonUpload given, pass using `host: 'ipaddress/domain'`") unless value && !value.empty?
            end,
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :verify_ssl,
            env_name: "FL_KOBITON_VERIFY_SSL",
            description: "Flag to bypass ssl cert to Kobiton",
            verify_block: proc do |value|
              UI.user_error!("No flag for KobitonUpload given, pass using `verify_ssl: 'true/false'`") unless value && !value.empty?
            end,
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :api_key,
            env_name: "FL_KOBITON_API_KEY",
            description: "API key from Kobiton",
            verify_block: proc do |value|
              UI.user_error!("No API key for KobitonUpload given, pass using `api_key: 'token'`") unless value && !value.empty?
            end,
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :username,
            env_name: "FL_KOBITON_USERNAME",
            description: "The username or email of your Kobiton account",
            verify_block: proc do |value|
              UI.user_error!("No username/email for KobitonUpload given, pass using `username: 'username/email'`") unless value && !value.empty?
            end,
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :file,
            env_name: "FL_KOBITON_FILE",
            description: "The build file to upload to Kobiton",
            verify_block: proc do |value|
              UI.user_error!("No build file for KobitonUpload given, pass using `file: 'file_path'`") unless value && !value.empty?
            end,
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_id,
            env_name: "FL_KOBITON_APP_ID",
            description: "The Kobiton app ID of the application",
            verify_block: proc do |value|
              UI.user_error!("No app ID or value 0 for KobitonUpload given, pass using `app_id: <app_id>`") unless value && value != 0
            end,
            optional: true,
            type: Integer
          )
        ]
      end

      def self.is_supported?(platform)
        [:ios, :android].include?(platform)
      end

      def self.get_upload_url(host, verify_ssl, filename, app_id, authorization)
        require "rest-client"
        require "json"

        headers = {
          "Authorization" => authorization,
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }

        begin
          # response = RestClient.post("https://#{host}/v1/apps/uploadUrl", {
          #   "filename" => filename,
          #   "appId" => app_id,
          # }, headers, :verify_ssl => verify_ssl)

          # response = RestClient::Request.execute(
          #   :method => :post, 
          #   :url => "https://#{host}/v1/apps/uploadUrl", 
          #   :body => , 
          #   :headers => headers, 
          #   :verify_ssl => verify_ssl)

          restClient = RestClient::Request.new(
            :url => "https://#{host}/v1/apps/uploadUrl",
            :headers => headers,
            :verify_ssl => verify_ssl
          )

          if app_id 
            response = restClient.post({
              "filename" => filename,
              "appId" => app_id,
            })
          else
            response = restClient.post({
              "filename" => filename
            }.to_json)
          end
          

        rescue RestClient::Exception => e
          UI.user_error!("URL retrieval failed status code #{e.response.code}, message from server:  #{e.response.body}")
        end

        return JSON.parse(response)
      end

      def self.upload_file(url, verify_ssl, filepath)
        require "rest-client"

        headers = {
          "Content-Type" => "application/octet-stream",
          "x-amz-tagging" => "unsaved=true"
        }

        begin
          #response = RestClient.put(url, File.read(filepath), headers, {:verify_ssl => verify_ssl})
          restClient = RestClient::Request.new(
            :url => url,
            :headers => headers,
            :verify_ssl => verify_ssl
          )

          response = restClient.put(File.read(filepath))
          
        rescue RestClient::Exception => e
          UI.user_error!("Uploading the binary to repo failed with status code #{e.response.code}, message: #{e.response.body}")
        end

        return response.code == 200
      end

      def self.notify_kobiton_after_file_upload(host, verify_ssl, app_path, filename, authorization)
        require "rest-client"

        headers = {
          "Authorization" => authorization,
          "Content-Type" => "application/json"
        }

        begin
          # RestClient.post("https://#{host}v1/apps", {
          #   "filename" => filename,
          #   "appPath" => app_path
          # }, headers, {:verify_ssl => verify_ssl})

          restClient = RestClient::Request.new(
            :url => "https://#{host}v1/apps",
            :headers => headers,
            :verify_ssl => verify_ssl
          )

          response = restClient.post({
            "filename" => filename,
            "appPath" => app_path
          }.to_json)

        rescue RestClient::Exception => e
          UI.user_error!("Kobiton could not be notified, status code: #{e.response.code}, message: #{e.response.body}")
        end
      end
    end
  end
end
