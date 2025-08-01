# frozen_string_literal: true

require_relative 'spec_helper'

describe WebmentionForwarder::Application do
  def app
    WebmentionForwarder::Application.new
  end

  before do
    # Mock environment variables for testing
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('WEBMENTION_FORWARDER_REPO').and_return('test-owner/test-repo')
    allow(ENV).to receive(:[]).with('GITHUB_CREDENTIALS_PATH').and_return('/tmp/test_github_credentials')
    allow(ENV).to receive(:[]).with('GITHUB_API_URL').and_return(nil)
    
    # Create a temporary credentials file for testing
    File.write('/tmp/test_github_credentials', 'test_github_token')
  end

  after do
    # Clean up test credentials file
    File.delete('/tmp/test_github_credentials') if File.exist?('/tmp/test_github_credentials')
  end

  describe 'GET /' do
    it 'redirects to GitHub PAT creation URL' do
      get '/'
      
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to eq('https://github.com/settings/tokens/new?scopes=repo&description=Webmention%20Forwarder')
    end
  end

  describe 'POST /webmention' do
    context 'with valid parameters' do
      before do
        # Mock the GitHub API endpoint
        stub_request(:post, "https://api.github.com/repos/test-owner/test-repo/pulls")
          .with(
            headers: {
              'Authorization' => 'Bearer test_github_token',
              'Accept' => 'application/vnd.github+json',
              'Content-Type' => 'application/json',
              'User-Agent' => 'webmention-forwarder'
            }
          )
          .to_return(
            status: 201,
            body: JSON.generate({
              'number' => 123,
              'html_url' => 'https://github.com/test-owner/test-repo/pull/123'
            }),
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'creates a GitHub PR and returns success' do
        source = 'https://example.com/source'
        target = 'https://example.com/target'
        
        post '/webmention', source: source, target: target
        
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('Webmention processed successfully')
        
        # Verify the API request was made with correct parameters
        expect(WebMock).to have_requested(:post, "https://api.github.com/repos/test-owner/test-repo/pulls")
          .with { |req|
            body = JSON.parse(req.body)
            expect(body['title']).to match(/^New Webmention Received at \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC$/)
            expect(body['body']).to eq("source: #{source}\ntarget: #{target}")
            expect(body['head']).to match(/^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-new-webmention$/)
            expect(body['base']).to eq('main')
          }
      end

      it 'uses custom GitHub API URL when provided' do
        allow(ENV).to receive(:[]).with('GITHUB_API_URL').and_return('https://custom-github.com/api/v3')
        
        stub_request(:post, "https://custom-github.com/api/v3/repos/test-owner/test-repo/pulls")
          .with(
            headers: {
              'Authorization' => 'Bearer test_github_token',
              'Accept' => 'application/vnd.github+json',
              'Content-Type' => 'application/json',
              'User-Agent' => 'webmention-forwarder'
            }
          )
          .to_return(
            status: 201,
            body: JSON.generate({
              'number' => 456,
              'html_url' => 'https://custom-github.com/test-owner/test-repo/pull/456'
            }),
            headers: { 'Content-Type' => 'application/json' }
          )
        
        post '/webmention', source: 'https://example.com/source', target: 'https://example.com/target'
        
        expect(WebMock).to have_requested(:post, "https://custom-github.com/api/v3/repos/test-owner/test-repo/pulls")
      end
    end

    context 'with missing parameters' do
      it 'returns 400 when source is missing' do
        post '/webmention', target: 'https://example.com/target'
        
        expect(last_response.status).to eq(400)
        expect(last_response.body).to eq('Bad Request: source and target parameters are required')
      end

      it 'returns 400 when target is missing' do
        post '/webmention', source: 'https://example.com/source'
        
        expect(last_response.status).to eq(400)
        expect(last_response.body).to eq('Bad Request: source and target parameters are required')
      end

      it 'returns 400 when both parameters are missing' do
        post '/webmention'
        
        expect(last_response.status).to eq(400)
        expect(last_response.body).to eq('Bad Request: source and target parameters are required')
      end
    end

    context 'with configuration errors' do
      it 'returns 500 when WEBMENTION_FORWARDER_REPO is not set' do
        allow(ENV).to receive(:[]).with('WEBMENTION_FORWARDER_REPO').and_return(nil)
        
        post '/webmention', source: 'https://example.com/source', target: 'https://example.com/target'
        
        expect(last_response.status).to eq(500)
        expect(last_response.body).to eq('Internal Server Error')
      end

      it 'returns 500 when GitHub credentials file does not exist' do
        File.delete('/tmp/test_github_credentials')
        
        post '/webmention', source: 'https://example.com/source', target: 'https://example.com/target'
        
        expect(last_response.status).to eq(500)
        expect(last_response.body).to eq('Internal Server Error')
      end

      it 'returns 500 when GitHub credentials file is empty' do
        File.write('/tmp/test_github_credentials', '')
        
        post '/webmention', source: 'https://example.com/source', target: 'https://example.com/target'
        
        expect(last_response.status).to eq(500)
        expect(last_response.body).to eq('Internal Server Error')
      end
    end

    context 'with GitHub API errors' do
      before do
        # Mock GitHub API to return error
        stub_request(:post, "https://api.github.com/repos/test-owner/test-repo/pulls")
          .with(
            headers: {
              'Authorization' => 'Bearer test_github_token',
              'Accept' => 'application/vnd.github+json',
              'Content-Type' => 'application/json',
              'User-Agent' => 'webmention-forwarder'
            }
          )
          .to_return(
            status: 401,
            body: JSON.generate({
              'message' => 'Bad credentials'
            }),
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns 500 when GitHub API returns an error' do
        post '/webmention', source: 'https://example.com/source', target: 'https://example.com/target'
        
        expect(last_response.status).to eq(500)
        expect(last_response.body).to eq('Internal Server Error')
      end
    end
  end

  describe 'unknown routes' do
    it 'returns 404 for unknown GET routes' do
      get '/unknown'
      
      expect(last_response.status).to eq(404)
      expect(last_response.body).to eq('Not Found')
    end

    it 'returns 404 for unknown POST routes' do
      post '/unknown'
      
      expect(last_response.status).to eq(404)
      expect(last_response.body).to eq('Not Found')
    end

    it 'returns 404 for other HTTP methods' do
      put '/webmention'
      
      expect(last_response.status).to eq(404)
      expect(last_response.body).to eq('Not Found')
    end
  end

  describe 'error handling' do
    it 'returns 500 for unexpected errors' do
      allow_any_instance_of(WebmentionForwarder::Application).to receive(:handle_webmention).and_raise(StandardError.new('Unexpected error'))
      
      post '/webmention', source: 'https://example.com/source', target: 'https://example.com/target'
      
      expect(last_response.status).to eq(500)
      expect(last_response.body).to eq('Internal Server Error')
    end
  end
end