# Webmention GitHub PR Forwarder

A Ruby Rack service that receives webmentions and creates GitHub pull requests.

## Features

- Listens for webmentions on `/webmention` endpoint
- Creates GitHub PRs when webmentions are received
- Redirects GET requests to GitHub PAT creation page
- Configurable via environment variables

## Setup

1. Install dependencies:
   ```bash
   bundle install
   ```

2. Set up environment variables:
   ```bash
   export WEBMENTION_FORWARDER_REPO="owner/repo"
   export GITHUB_CREDENTIALS_PATH="~/.github_credentials"  # Optional, defaults to ~/.github_credentials
   export GITHUB_API_URL="https://api.github.com"  # Optional, defaults to GitHub API
   ```

3. Create GitHub credentials file:
   ```bash
   echo "your_github_token_here" > ~/.github_credentials
   ```

4. Run the server:
   ```bash
   bundle exec puma config.ru -p 9292
   ```

## Usage

### Receive Webmentions

POST to `/webmention` with `source` and `target` parameters:

```bash
curl -X POST http://localhost:9292/webmention \
  -d "source=https://example.com/source&target=https://example.com/target"
```

### Get GitHub PAT Setup URL

Visit the root URL to be redirected to GitHub's PAT creation page:

```bash
curl http://localhost:9292/
```

## Environment Variables

- `WEBMENTION_FORWARDER_REPO`: GitHub repository in "owner/repo" format (required)
- `GITHUB_CREDENTIALS_PATH`: Path to GitHub token file (optional, defaults to `~/.github_credentials`)
- `GITHUB_API_URL`: GitHub API URL (optional, defaults to `https://api.github.com`)
