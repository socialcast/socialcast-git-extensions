require 'rest_client'
require 'json'
require 'socialcast'
require 'highline'

module Socialcast
  module Gitx
    module Github
      private
      # request github authorization token
      # User-Agent is required
      # store the token in ~/.socialcast/credentials.yml for future reuse
      # @see http://developer.github.com/v3/oauth/#scopes
      # @see http://developer.github.com/v3/#user-agent-required
      def authorization_token
        credentials = Socialcast::CommandLine.credentials
        return credentials[:scgitx_token] if credentials[:scgitx_token]

        username = current_user
        raise "Github user not configured.  Run: `git config --global github.user 'me@email.com'`" if username.empty?
        password = HighLine.new.ask("Github password for #{username}: ") { |q| q.echo = false }

        payload = {:scopes => ['repo'], :note => 'Socialcast Git eXtension', :note_url => 'https://github.com/socialcast/socialcast-git-extensions'}.to_json
        response = RestClient::Request.new(:url => "https://api.github.com/authorizations", :method => "POST", :user => username, :password => password, :payload => payload, :headers => {:accept => :json, :content_type => :json, :user_agent => 'socialcast-git-extensions'}).execute
        data = JSON.parse response.body
        token = data['token']
        Socialcast::CommandLine.credentials = credentials.merge(:scgitx_token => token)
        token
      rescue RestClient::Exception => e
        process_error e
        throw e
      end

      # @see http://developer.github.com/v3/pulls/
      def create_pull_request(branch, repo, body)
        payload = {:title => branch, :base => base_branch, :head => branch, :body => body}.to_json
        say "Creating pull request for "
        say "#{branch} ", :green
        say "against "
        say "#{base_branch} ", :green
        say "in "
        say repo, :green
        github_api_request("POST", "repos/#{repo}/pulls", payload)
      end

      # find the PRs matching the given commit hash
      # https://developer.github.com/v3/search/#search-issues
      def pull_requests_for_commit(repo, commit_hash)
        query = "#{commit_hash}+type:pr+repo:#{repo}"
        say "Searching github pull requests for #{commit_hash}"
        github_api_request "GET", "search/issues?q=#{query}"
      end

      # find the PRs for a given branch
      # https://developer.github.com/v3/pulls/#list-pull-requests
      def pull_requests_for_branch(repo, branch)
        head_name = "#{repo.split('/').first}:#{branch}"
        github_api_request "GET", "repos/#{repo}/pulls?head=#{head_name}"
      end

      # find the current PR for a given branch
      def current_pr_for_branch(repo, branch)
        prs = pull_requests_for_branch(repo, branch)
        raise "Multiple (#{prs.size}) open PRs for #{branch} found in #{repo}, unable to proceed" if prs.size > 1
        prs.first
      end

      def assign_pull_request(assignee, issue_url)
        issue_payload = { :assignee => assignee }.to_json
        github_api_request "PATCH", issue_url, issue_payload
      rescue => e
        say "Failed to assign pull request: #{e.message}", :red
      end

      # post a comment on an issue
      # https://developer.github.com/v3/issues/comments/#create-a-comment
      def comment_on_issue(issue_url, comment_body)
        github_api_request 'POST', "#{issue_url}/comments", { :body => comment_body }.to_json
      end

      # @returns [String] socialcast username to assign the review to
      # @returns [nil] when no buddy system configured or user not found
      def socialcast_review_buddy(current_user)
        review_requestor = review_buddies[current_user]

        if review_requestor && review_buddies[review_requestor['buddy']]
          review_buddies[review_requestor['buddy']]['socialcast_username']
        end
      end

      def github_review_buddy(current_user)
        review_requestor = review_buddies[current_user]
        if review_requestor
          review_requestor['buddy']
        end
      end

      # @returns [String] github username responsible for the track
      # @returns [nil] when user not found
      def github_track_reviewer(track)
        github_username_for_socialcast_username(socialcast_track_reviewer(track))
      end

      # @returns [String] Socialcast username responsible for the track
      # @returns [nil] when user not found
      def socialcast_track_reviewer(track)
        specialty_reviewers.values.each do |reviewer_hash|
          return reviewer_hash['socialcast_username'] if reviewer_hash['label'].to_s.downcase == track.downcase
        end
        nil
      end

      # @returns [String] github username corresponding to the Socialcast username
      # @returns [nil] when user not found
      def github_username_for_socialcast_username(socialcast_username)
        return if socialcast_username.nil? || socialcast_username == ""

        review_buddies.each_pair do |github_username, review_buddy_hash|
          return github_username if review_buddy_hash['socialcast_username'] == socialcast_username
        end
      end

      def github_api_request(method, path, payload = nil)
        url = path.include?('http') ? path : "https://api.github.com/#{path}"
        JSON.parse RestClient::Request.new(:url => url, :method => method, :payload => payload, :headers => { :accept => :json, :content_type => :json, 'Authorization' => "token #{authorization_token}", :user_agent => 'socialcast-git-extensions' }).execute
      rescue RestClient::Exception => e
        process_error e
        throw e
      end

      def process_error(e)
        data = JSON.parse e.http_body
        say "GitHub request failed: #{data['message']}", :red
      end
    end
  end
end
