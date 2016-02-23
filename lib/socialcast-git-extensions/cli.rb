require 'thor'
require 'rest_client'
require 'socialcast-git-extensions'
require 'socialcast'
require 'socialcast/command_line/message'
require 'highline/import'
require 'active_support/core_ext'

module Socialcast
  module Gitx
    class CLI < Thor
      include Socialcast::Gitx
      include Socialcast::Gitx::Git
      include Socialcast::Gitx::Github

      PULL_REQUEST_DESCRIPTION = "\n\n" + <<-EOS.dedent
        # Use GitHub flavored Markdown http://github.github.com/github-flavored-markdown/
        # Links to screencasts or screenshots with a desciption of what this is showcasing. For architectual changes please include diagrams that will make it easier for the reviewer to understand the change. Format is ![title](url).
        # Link to ticket describing feature/bug (plantain, JIRA, bugzilla). Format is [title](url).
        # Brief description of the change, and how it accomplishes the task they set out to do.
      EOS

      method_option :quiet, :type => :boolean, :aliases => '-q'
      method_option :trace, :type => :boolean, :aliases => '-v'
      def initialize(*args)
        super(*args)
        RestClient.proxy = ENV['HTTPS_PROXY'] if ENV.has_key?('HTTPS_PROXY')
        RestClient.log = Logger.new(STDOUT) if options[:trace]
      end

      desc "createpr", "Create a pull request on github"
      method_option :description, :type => :string, :aliases => '-d', :desc => 'pull request description'
      # @see http://developer.github.com/v3/pulls/
      def createpr
        update unless @skip_update
        description = options[:description] || editor_input(PULL_REQUEST_DESCRIPTION)
        branch = current_branch
        repo = current_repo
        url = create_pull_request(branch, repo, description)['html_url']
        say "Pull request created: #{url}"
      end

      desc "assignpr", "Assign the pull request on github for review"
      method_option :additional_reviewers, :type => :string, :aliases => '-a', :desc => 'add additional reviewers to mention automatically, and skips the prompt'
      method_option :skip_additional_reviewers, :type => :string, :aliases => '-s', :desc => 'Skips adding additional reviewers'
      # @see http://developer.github.com/v3/pulls/
      def assignpr(*additional_reviewers)
        update unless @skip_update

        primary_mention = if buddy = socialcast_review_buddy(current_user)
          "assigned to @#{buddy}"
        end

        secondary_mention = nil
        if !specialty_reviewers.empty? && !options.key?('skip_additional_reviewers')
          additional_reviewers = options[:additional_reviewers] || additional_reviewers

          if additional_reviewers.empty?
            prompt_text = "#{specialty_reviewers.map { |_,v| v['command'] }.join(", ")} or (or hit enter to continue): "
            additional_reviewers = $terminal.ask("Notify additional people? #{prompt_text} ")
          end

          additional_reviewers = additional_reviewers.is_a?(String) ? additional_reviewers.split(" ") : additional_reviewers

          (specialty_reviewers.keys & additional_reviewers).each do |command|
            reviewer = specialty_reviewers[command]
            secondary_mention ||= ''
            secondary_mention += "\nAssigned additionally to @#{reviewer['socialcast_username']} for #{reviewer['label']} review"
          end
        end

        branch = current_branch
        repo = current_repo
        current_pr = current_pr_for_branch(repo, branch)
        issue_url = current_pr['issue_url']
        url = current_pr['html_url']

        assignee = github_review_buddy(current_user)
        assign_pull_request(assignee, issue_url) if assignee

        if use_pr_comments?
          issue_message = ['#reviewrequest', primary_mention, secondary_mention, "\n/cc @#{developer_group} #scgitx"].compact.join(' ')
          comment_on_issue(issue_url, issue_message)
        else
          review_message = ["#reviewrequest for #{branch} in #{current_repo}", "PR #{url} #{primary_mention}", '', current_pr['body'], '', secondary_mention, "/cc @#{developer_group} #scgitx", '', changelog_summary(branch)].compact.join("\n").gsub(/\n{2,}/, "\n\n")
          post review_message, :message_type => 'review_request'
        end
      end

      desc "reviewrequest", "Create and assign a pull request on github"
      method_option :description, :type => :string, :aliases => '-d', :desc => 'pull request description'
      method_option :additional_reviewers, :type => :string, :aliases => '-a', :desc => 'add additional reviewers to mention automatically, and skips the prompt'
      method_option :skip_additional_reviewers, :type => :string, :aliases => '-s', :desc => 'Skips adding additional reviewers'
      # @see http://developer.github.com/v3/pulls/
      def reviewrequest(*additional_reviewers)
        update
        @skip_update = true
        createpr
        assignpr(*additional_reviewers)
      end

      desc "findpr", "Find pull requests including a given commit"
      def findpr(commit_hash)
        repo = current_repo
        data = pull_requests_for_commit(repo, commit_hash)

        if data['items']
          data['items'].each do |entry|
            say "\n" << [entry['html_url'], entry['title'], "#{entry['user'] && entry['user']['login']} #{entry['created_at']}"].join("\n\t")
          end
        else
          say "No results found", :yellow
        end
      end

      desc "backportpr", "Backport a pull request"
      def backportpr(pull_request_num, maintenance_branch)
        original_base_branch = ENV['BASE_BRANCH']
        ENV['BASE_BRANCH'] = maintenance_branch
        repo = current_repo
        assignee = github_track_reviewer('Backport')
        socialcast_reviewer = socialcast_track_reviewer('Backport')

        pull_request_data = github_api_request('GET', "repos/#{repo}/pulls/#{pull_request_num}")
        commits_data = github_api_request('GET', pull_request_data['commits_url'])

        non_merge_commits_data = commits_data.select { |commit_data| commit_data['parents'].length == 1 }
        shas = non_merge_commits_data.map { |commit| commit['sha'] }

        backport_branch = "backport_#{pull_request_num}_to_#{maintenance_branch}"
        backport_to(backport_branch, shas)

        maintenance_branch_url = "https://github.com/#{repo}/tree/#{maintenance_branch}"
        description = "Backport ##{pull_request_num} to #{maintenance_branch_url}\n***\n#{pull_request_data['body']}"

        pr_hash = create_pull_request(backport_branch, repo, description)
        assign_pull_request(assignee, pr_hash['issue_url']) if assignee

        reviewer_mention = "@#{socialcast_reviewer}" if socialcast_reviewer
        if use_pr_comments?
          issue_message = ['#reviewrequest backport', reviewer_mention, "/cc @#{developer_group} #scgitx"].compact.join(' ')
          comment_on_issue(pr_hash['issue_url'], issue_message)
        else
          review_message = ["#reviewrequest backport ##{pull_request_num} to #{maintenance_branch} in #{current_repo} #scgitx"]
          if socialcast_reviewer
            review_message << "/cc #{reviewer_mention} for #backport track"
          end
          review_message << "/cc @#{developer_group}"
          post review_message.join("\n\n"), :url => pr_hash['html_url'], :message_type => 'review_request'
        end
      ensure
        ENV['BASE_BRANCH'] = original_base_branch
      end

      # TODO: use --no-edit to skip merge messages
      # TODO: use pull --rebase to skip merge commit
      desc 'update', 'Update the current branch with latest changes from the remote feature branch and master'
      def update
        branch = current_branch

        say 'updating '
        say "#{branch} ", :green
        say "to have most recent changes from "
        say base_branch, :green

        run_cmd "git pull origin #{branch}" rescue nil
        run_cmd "git pull origin #{base_branch}"
        run_cmd 'git push origin HEAD'
      end

      desc 'cleanup', 'Cleanup branches that have been merged into master from the repo'
      def cleanup
        run_cmd "git checkout #{base_branch}"
        run_cmd "git pull"
        run_cmd 'git remote prune origin'

        say "Deleting branches that have been merged into "
        say base_branch, :green
        branches(:merged => true, :remote => true).each do |branch|
          run_cmd "git push origin --delete #{branch}" unless reserved_branch?(branch)
        end
        branches(:merged => true).each do |branch|
          run_cmd "git branch -d #{branch}" unless reserved_branch?(branch)
        end
      end

      desc 'track', 'set the current branch to track the remote branch with the same name'
      def track
        track_branch current_branch
      end

      desc 'start', 'start a new git branch with latest changes from master'
      def start(branch_name = nil)
        unless branch_name
          example_branch = %w{ cpr-3922-api-fix-invalid-auth red-212-desktop-cleanup-avatar-markup red-3212-share-form-add-edit-link }.sample
          repo = Rugged::Repository.new(Dir.pwd)
          remote_branches = repo.remotes.collect {|b| b.name.split('/').last }
          ## Explicitly use Highline.ask
          branch_name = $terminal.ask("What would you like to name your branch? (ex: #{example_branch})") do |q|
            q.validate = lambda { |branch| branch =~ /^[A-Za-z0-9\-_]+$/ && !remote_branches.include?(branch) }
            q.responses[:not_valid] = "This branch name is either already taken, or is not a valid branch name"
          end
        end

        run_cmd "git checkout #{base_branch}"
        run_cmd 'git pull'
        run_cmd "git checkout -b #{branch_name}"

        message = <<-EOS.strip_heredoc
          #worklog starting work on #{branch_name} in #{current_repo} #scgitx
          /cc @#{developer_group}
        EOS

        post message.strip
      end

      desc 'share', 'Share the current branch in the remote repository'
      def share
        share_branch current_branch
      end

      desc 'integrate', 'integrate the current branch into one of the aggregate development branches'
      def integrate(target_branch = prototype_branch)
        branch = current_branch

        update
        integrate_branch(branch, target_branch)
        integrate_branch(target_branch, prototype_branch) if target_branch == staging_branch
        run_cmd "git checkout #{branch}"

        current_pr = begin
          current_pr_for_branch(current_repo, current_branch)
        rescue => e
          say e.message.to_s
          nil
        end

        say("WARNING: Unable to find current pull request.  Use `git createpr` to create one.", :red) unless current_pr

        if use_pr_comments? && current_pr
          issue_message = "Integrated into #{target_branch}"
          comment_on_issue(current_pr['issue_url'], issue_message) unless options[:quiet]
        else
          message = <<-EOS.strip_heredoc
            #worklog integrating #{branch} into #{target_branch} in #{current_repo} #scgitx
            /cc @#{developer_group}
          EOS

          post message.strip
        end
      end

      desc 'promote', 'integrate the current branch into staging'
      def promote
        integrate staging_branch
      end

      desc 'nuke', 'nuke the specified aggregate branch and reset it to a known good state'
      method_option :destination, :type => :string, :aliases => '-d', :desc => 'destination branch to reset to'
      def nuke(bad_branch)
        default_good_branch = "last_known_good_#{bad_branch}"
        good_branch = options[:destination] || ask("What branch do you want to reset #{bad_branch} to? (default: #{default_good_branch})")
        good_branch = default_good_branch if good_branch.length == 0
        good_branch = "last_known_good_#{good_branch}" unless good_branch.starts_with?('last_known_good_')

        removed_branches = nuke_branch(bad_branch, good_branch)
        nuke_branch("last_known_good_#{bad_branch}", good_branch)

        message = <<-EOS.strip_heredoc
          #worklog resetting #{bad_branch} branch to #{good_branch} in #{current_repo} #scgitx
          /cc @#{developer_group}
        EOS

        if removed_branches.any?
          message += <<-EOS.strip_heredoc

            The following branches were affected:
          EOS
          message += removed_branches.map{ |b| ['*', b].join(' ') }.join("\n")
        end

        post message.strip
      end

      desc 'branchdiff', 'show branches merged into one remote branch but not merged into another (default = master)'
      def branchdiff(branch = nil, other_branch = 'master')
        branch ||= ask "What remote branch would you like to compare against '#{other_branch}' (ex: staging)?"
        run_cmd "git fetch origin"
        results = branch_difference(branch, other_branch)
        if results.any?
          say "\nBranches in origin/#{branch} and not in origin/#{other_branch}:\n\n#{results.join("\n")}\n\n"
        else
          say "\nNo branches found in origin/#{branch} that are not also in origin/#{other_branch}\n\n"
        end
      end

      desc 'release', 'release the current branch to production'
      def release
        branch = current_branch
        assert_not_protected_branch!(branch, 'release')

        if enforce_staging_before_release?
          assert_in_last_known_good_staging(branch)
        end

        return unless yes?("Release #{branch} to production? (y/n)", :green)

        update
        run_cmd "git checkout #{base_branch}"
        run_cmd "git pull origin #{base_branch}"
        run_cmd "git pull . #{branch}"
        run_cmd "git push origin HEAD"
        integrate_branch(base_branch, staging_branch)
        cleanup

        unless use_pr_comments?
          message = <<-EOS.strip_heredoc
            #worklog releasing #{branch} to #{base_branch} in #{current_repo} #scgitx
            /cc @#{developer_group}
          EOS

          post message.strip
        end
      end

      private

      def developer_group
        config['developer_group'] || 'SocialcastDevelopers'
      end

      def enforce_staging_before_release?
        !!config['enforce_staging_before_release']
      end

      def use_pr_comments?
        config['share_via_pr_comments'] == true
      end

      # post a message in socialcast
      # skip sharing message if CLI quiet option is present
      def post(message, params = {})
        return if options[:quiet]
        ActiveResource::Base.logger = Logger.new(STDOUT) if options[:trace]
        Socialcast::CommandLine::Message.configure_from_credentials
        response = Socialcast::CommandLine::Message.create params.merge(:body => message)
        say "Message has been posted: #{response.permalink_url}"
      end
    end
  end
end
