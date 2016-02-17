require 'rugged'
require 'pathname'

module Socialcast
  module Gitx
    module Git
      private
      def assert_not_protected_branch!(branch, action)
        raise "Cannot #{action} reserved branch" if reserved_branch?(branch)
      end

      def assert_in_last_known_good_staging(branch)
        refresh_branch_from_remote last_known_good_staging_branch
        branches_in_last_known_staging = branches(:remote => true, :merged => true)
        unless branches_in_last_known_staging.include? branch
          raise "Cannot release #{branch} unless it has already been promoted separately to #{staging_branch} and the build has passed."
        end
      ensure
        run_cmd "git checkout #{branch}"
      end

      # lookup the current branch of the PWD
      def current_branch
        repo = Rugged::Repository.new(Dir.pwd)
        repo.head.name.split('/').last # refs/heads/<branch-name>
      end

      # lookup the current repository of the PWD
      # ex: git@github.com:socialcast/socialcast-git-extensions.git OR https://github.com/socialcast/socialcast-git-extensions.git
      def current_repo
        repo = `git config -z --get remote.origin.url`.strip
        repo.gsub(/\.git$/,'').split(/[:\/]/).last(2).join('/')
      end

      # @returns [String] github username (ex: 'wireframe') of the current github.user
      # @returns empty [String] when no github.user is set on the system
      def current_user
        `git config -z --global --get github.user`.strip
      end

      def backport_to(branch, shas)
        refresh_branch_from_remote base_branch
        run_cmd "git checkout -b #{branch}"
        begin
          run_cmd "git cherry-pick #{shas.join(' ')}"
        rescue
          while true
            proceed = $terminal.ask "Error during cherry-pick.  You can proceed by resolving the conflicts and using 'git cherry-pick --continue' to finish the cherry-pick in another terminal. Would you like to proceed (y/n)?"
            if proceed.to_s.downcase == 'n'
              run_cmd "git cherry-pick --abort"
              exit 1
            elsif proceed.to_s.downcase == 'y'
              break
            else
              say "Invalid response"
            end
          end
        end
        run_cmd "git push origin HEAD"
      end

      # retrieve a list of branches
      def branches(options = {})
        branches = []
        args = []
        args << '-r' if options[:remote]
        args << "--merged #{options[:merged].is_a?(String) ? options[:merged] : ''}" if options[:merged]
        output = `git branch #{args.join(' ')}`.split("\n")
        output.each do |branch|
          branch = branch.gsub(/\*/, '').strip.split(' ').first
          branch = branch.split('/').last if options[:remote]
          branches << branch unless reserved_branch?(branch)
        end
        branches.uniq
      end

      # retrieve a list of branches merged into one remote branch but not merged into another
      def branch_difference(branch, other_branch)
        branches(:remote => true, :merged => "origin/#{branch}") - branches(:remote => true, :merged => "origin/#{other_branch}")
      end

      # reset the specified branch to the same set of commits as the destination branch
      # reverts commits on aggregate branches back to a known good state
      # returns list of branches that were removed
      def nuke_branch(branch, head_branch)
        return [] if branch == head_branch
        raise "Only aggregate branches are allowed to be reset: #{aggregate_branches}" unless aggregate_branch?(branch)
        say "Resetting "
        say "#{branch} ", :green
        say "branch to "
        say head_branch, :green

        run_cmd "git checkout #{base_branch}"
        refresh_branch_from_remote head_branch
        removed_branches = branch_difference(branch, head_branch)
        run_cmd "git branch -D #{branch}" rescue nil
        run_cmd "git push origin --delete #{branch}" rescue nil
        run_cmd "git checkout -b #{branch}"
        share_branch branch
        run_cmd "git checkout #{base_branch}"

        removed_branches
      end

      # share the local branch in the remote repo
      def share_branch(branch)
        run_cmd "git push origin #{branch}"
        track_branch branch
      end

      def track_branch(branch)
        run_cmd "git branch --set-upstream-to=origin/#{branch} #{branch}"
      end

      # integrate a branch into a destination aggregate branch
      # blow away the local aggregate branch to ensure pulling into most recent "clean" branch
      def integrate_branch(branch, destination_branch)
        assert_not_protected_branch!(branch, 'integrate') unless aggregate_branch?(destination_branch)
        unless aggregate_branch?(destination_branch) || [base_branch, Socialcast::Gitx::DEFAULT_BASE_BRANCH].include?(destination_branch)
          raise "Only aggregate branches are allowed for integration: #{aggregate_branches}"
        end
        say "Integrating "
        say "#{branch} ", :green
        say "into "
        say destination_branch, :green

        refresh_branch_from_remote destination_branch
        run_cmd "git pull . #{branch}"
        run_cmd "git push origin HEAD"
        run_cmd "git checkout #{branch}"
      end

      # nuke local branch and pull fresh version from remote repo
      def refresh_branch_from_remote(destination_branch)
        run_cmd "git branch -D #{destination_branch}" rescue nil
        run_cmd "git fetch origin"
        run_cmd "git checkout #{destination_branch}"
      end

      def aggregate_branch?(branch)
        aggregate_branches.include?(branch) || branch.starts_with?('last_known_good')
      end

      def reserved_branch?(branch)
        aggregate_branch?(branch) || reserved_branches.include?(branch)
      end

      # build a summary of changes
      def changelog_summary(branch)
        changes = `git diff --numstat origin/#{base_branch}...#{branch}`.split("\n")
        stats = `git diff --shortstat origin/#{base_branch}...#{branch}`
        if changes.length > 5
          dirs = changes.map do |file_change|
            filename = "#{file_change.split.last}"
            dir = filename.gsub(/\/[^\/]+$/, '')
            dir
          end
          dir_counts = Hash.new(0)
          dirs.each { |dir| dir_counts[dir] += 1 }
          changes = dir_counts.to_a.sort_by { |k, v| [-v, k] }.first(5).map { |k, v| "#{k} (#{v} file#{'s' if v > 1})" }
        else
          changes = changes.map do |line|
            added, removed, filename = line.split
            "#{filename} | #{added}+ #{removed}-"
          end
        end
        (changes + [stats]).join("\n")
      end

      # launch configured editor to retreive message/string
      def editor_input(initial_text = '')
        require 'tempfile'
        Tempfile.open('reviewrequest.md') do |f|
          f << initial_text
          f.flush

          editor = ENV['EDITOR'] || 'vi'
          flags = case editor
          when 'mate', 'emacs'
            '-w'
          when 'mvim'
            '-f'
          else
            ''
          end
          pid = fork { exec "#{editor} #{flags} #{f.path}" }
          Process.waitpid(pid)
          description = File.read(f.path)
          description.gsub(/^\#.*/, '').chomp.strip
        end
      end

      # load SC Git Extensions Config YAML
      # @returns [Hash] of configuration options from YAML file (if it exists)
      def config
        @config ||= begin
          if config_file.exist?
            YAML.load_file(config_file)
          else
            {}
          end
        end
      end

      # @returns a [Pathname] for the scgitx.yml Config File
      # from either ENV['SCGITX_CONFIG_PATH'] or default $PWD/config/scgitx.yml
      def config_file
        Pathname((ENV['SCGITX_CONFIG_PATH'] || ([Dir.pwd, '/config/scgitx.yml']).join))
      end

      # load Review buddies from the SCGITX Configuration YML
      # @returns [Hash] of review buddy mapping from Config YML (ex: {'wireframe' => {'socialcast_username' => 'RyanSonnek', 'buddy' => 'vanm'}})
      def review_buddies
        config['review_buddies'] || {}
      end

      def specialty_reviewers
        config['specialty_reviewers'] || {}
      end

      def base_branch
        ENV['BASE_BRANCH'] || config['base_branch'] || Socialcast::Gitx::DEFAULT_BASE_BRANCH
      end

      def staging_branch
        config['staging_branch'] || Socialcast::Gitx::DEFAULT_STAGING_BRANCH
      end

      def last_known_good_staging_branch
        config['last_known_good_staging_branch'] || Socialcast::Gitx::DEFAULT_LAST_KNOWN_GOOD_STAGING_BRANCH
      end

      def prototype_branch
        config['prototype_branch'] || Socialcast::Gitx::DEFAULT_PROTOTYPE_BRANCH
      end

      def aggregate_branches
        @aggregate_branches ||= ((config['aggregate_branches'] || []) + [staging_branch, prototype_branch]).uniq
      end

      def reserved_branches
        @reserved_branches ||= %w{ HEAD master next_release } + [base_branch, config['reserved_branches'], config['base_branch']].flatten.compact.uniq + aggregate_branches
      end
    end
  end
end
