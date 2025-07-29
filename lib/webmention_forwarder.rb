# frozen_string_literal: true

require 'rack'
require 'net/http'
require 'json'
require 'logger'
require 'time'
require 'uri'

module WebmentionForwarder
  class Application
    def initialize
      @logger = Logger.new($stdout)
      @logger.level = Logger::INFO
    end

    def call(env)
      request = Rack::Request.new(env)
      
      case [request.request_method, request.path_info]
      when ['POST', '/webmention']
        handle_webmention(request)
      when ['GET', '/']
        redirect_to_github_pat_creation
      else
        [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
      end
    rescue => e
      @logger.error "Unexpected error: #{e.message}"
      @logger.error e.backtrace.join("\n")
      [500, { 'Content-Type' => 'text/plain' }, ['Internal Server Error']]
    end

    private

    def handle_webmention(request)
      source = request.params['source']
      target = request.params['target']

      if source.nil? || target.nil?
        @logger.warn "Invalid webmention: missing source or target. Source: #{source}, Target: #{target}"
        return [400, { 'Content-Type' => 'text/plain' }, ['Bad Request: source and target parameters are required']]
      end

      begin
        create_github_pr(source, target)
        [200, { 'Content-Type' => 'text/plain' }, ['Webmention processed successfully']]
      rescue => e
        @logger.error "Failed to create GitHub PR: #{e.message}"
        [500, { 'Content-Type' => 'text/plain' }, ['Internal Server Error']]
      end
    end

    def create_github_pr(source, target)
      repo = ENV['WEBMENTION_FORWARDER_REPO']
      if repo.nil? || repo.empty?
        raise "WEBMENTION_FORWARDER_REPO environment variable is not set. Please set it to OWNER/REPO format."
      end

      github_token = read_github_token
      github_api_url = ENV['GITHUB_API_URL'] || 'https://api.github.com'

      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S UTC')
      title = "New Webmention Received at #{timestamp}"
      body = "source: #{source}\ntarget: #{target}"
      
      # Create timestamped branch name for the head
      branch_timestamp = Time.now.strftime('%Y-%m-%dT%H-%M-%S')
      head_branch = "#{branch_timestamp}-new-webmention"

      @logger.info "Creating PR in #{repo} with title: #{title}"

      pr_response = create_pull_request_via_api(
        github_api_url,
        github_token,
        repo,
        title,
        body,
        head_branch,
        'main'
      )

      @logger.info "Successfully created PR ##{pr_response['number']}: #{pr_response['html_url']}"
    rescue => e
      @logger.error "GitHub API error: #{e.message}"
      raise "GitHub API error: #{e.message}"
    end

    def create_pull_request_via_api(api_url, token, repo, title, body, head, base)
      uri = URI("#{api_url}/repos/#{repo}/pulls")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == 'https'
      
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{token}"
      request['Accept'] = 'application/vnd.github+json'
      request['Content-Type'] = 'application/json'
      request['User-Agent'] = 'webmention-forwarder'
      
      request_body = {
        title: title,
        body: body,
        head: head,
        base: base
      }
      
      request.body = JSON.generate(request_body)
      
      response = http.request(request)
      
      unless response.is_a?(Net::HTTPSuccess)
        error_body = response.body
        @logger.error "GitHub API request failed with status #{response.code}: #{error_body}"
        raise "GitHub API request failed with status #{response.code}: #{error_body}"
      end
      
      JSON.parse(response.body)
    end

    def read_github_token
      credentials_path = ENV['GITHUB_CREDENTIALS_PATH'] || File.expand_path('~/.github_credentials')
      
      unless File.exist?(credentials_path)
        raise "GitHub credentials file not found at #{credentials_path}. Please create this file with your GitHub Personal Access Token."
      end

      token = File.read(credentials_path).strip
      if token.empty?
        raise "GitHub credentials file is empty. Please add your GitHub Personal Access Token to #{credentials_path}."
      end

      token
    rescue => e
      @logger.error "Failed to read GitHub credentials: #{e.message}"
      raise "Failed to read GitHub credentials: #{e.message}"
    end

    def redirect_to_github_pat_creation
      # GitHub URL to create a PAT with the necessary scopes for creating pull requests
      github_url = 'https://github.com/settings/tokens/new?scopes=repo&description=Webmention%20Forwarder'
      
      [302, { 'Location' => github_url }, []]
    end
  end
end