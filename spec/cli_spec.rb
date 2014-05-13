require 'spec_helper'

describe Socialcast::Gitx::CLI do
  # stub methods on cli
  class Socialcast::Gitx::CLI
    class << self
      attr_accessor :stubbed_executed_commands
    end
    private
    # stub out command execution and record commands for test inspection
    def run_cmd(cmd)
      self.class.stubbed_executed_commands << cmd
    end
  end

  def stub_message(message_body, params = {})
    json_body = { :message => params.merge!(:body => message_body) }

    stub_request(:post, "https://testuser:testpassword@testdomain/api/messages.json")
      .with(:body => json_body.to_json)
      .to_return(:status => 200, :body => '', :headers => {})
  end

  before do
    Socialcast::Gitx::CLI.instance_eval do # to supress warning from stubbing ldap_config
      @no_tasks = @no_commands = true
    end

    Socialcast::Gitx::CLI.stubbed_executed_commands = []
    Socialcast::Gitx::CLI.any_instance.stub(:current_branch).and_return('FOO')
    Socialcast::Gitx::CLI.any_instance.stub(:current_user).and_return('wireframe')
    Socialcast::CommandLine.stub(:credentials).and_return(:domain => 'testdomain', :user => 'testuser', :password => 'testpassword', :scgitx_token => 'faketoken')
  end

  describe '#update' do
    before do
      Socialcast::Gitx::CLI.any_instance.should_not_receive(:post)
      Socialcast::Gitx::CLI.start ['update']
    end
    it 'should not post message to socialcast' do end # see expectations
    it 'should run expected commands' do
      Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
        'git pull origin FOO',
        'git pull origin master',
        'git push origin HEAD'
      ]
    end
  end

  describe '#integrate' do
    context 'when target branch is ommitted' do
      before do
        stub_message "#worklog integrating FOO into prototype #scgitx"

        Socialcast::Gitx::CLI.start ['integrate']
      end
      it 'should post message to socialcast' do end # see expectations
      it 'should default to prototype' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git pull origin FOO",
          "git pull origin master",
          "git push origin HEAD",
          "git branch -D prototype",
          "git fetch origin",
          "git checkout prototype",
          "git pull . FOO",
          "git push origin HEAD",
          "git checkout FOO",
          "git checkout FOO"
        ]
      end
    end
    context 'when target branch is ommitted with custom prototype branch' do
      before do
        Socialcast::Gitx::CLI.any_instance.stub(:prototype_branch).and_return('special-prototype')

        stub_message "#worklog integrating FOO into special-prototype #scgitx"

        Socialcast::Gitx::CLI.start ['integrate']
      end
      it 'should post message to socialcast' do end # see expectations
      it 'should default to prototype' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git pull origin FOO",
          "git pull origin master",
          "git push origin HEAD",
          "git branch -D special-prototype",
          "git fetch origin",
          "git checkout special-prototype",
          "git pull . FOO",
          "git push origin HEAD",
          "git checkout FOO",
          "git checkout FOO"
        ]
      end
    end
    context 'when target branch == prototype' do
      before do
        stub_message "#worklog integrating FOO into prototype #scgitx"

        Socialcast::Gitx::CLI.start ['integrate', 'prototype']
      end
      it 'should post message to socialcast' do end # see expectations
      it 'should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git pull origin FOO",
          "git pull origin master",
          "git push origin HEAD",
          "git branch -D prototype",
          "git fetch origin",
          "git checkout prototype",
          "git pull . FOO",
          "git push origin HEAD",
          "git checkout FOO",
          "git checkout FOO"
        ]
      end
    end
    context 'when target branch == staging' do
      before do
        stub_message "#worklog integrating FOO into staging #scgitx"

        Socialcast::Gitx::CLI.start ['integrate', 'staging']
      end
      it 'should post message to socialcast' do end # see expectations
      it 'should also integrate into prototype and run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git pull origin FOO",
          "git pull origin master",
          "git push origin HEAD",
          "git branch -D staging",
          "git fetch origin",
          "git checkout staging",
          "git pull . FOO",
          "git push origin HEAD",
          "git checkout FOO",
          "git branch -D prototype",
          "git fetch origin",
          "git checkout prototype",
          "git pull . staging",
          "git push origin HEAD",
          "git checkout staging",
          "git checkout FOO"
        ]
      end
    end
    context 'when target branch != staging || prototype' do
      it 'should raise an error' do
        lambda {
          Socialcast::Gitx::CLI.start ['integrate', 'asdfasdfasdf']
        }.should raise_error(/Only aggregate branches are allowed for integration/)
      end
    end
  end

  describe '#release' do
    context 'when user rejects release' do
      before do
        Socialcast::Gitx::CLI.any_instance.should_receive(:yes?).and_return(false)
        Socialcast::Gitx::CLI.start ['release']
      end
      it 'should run no commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == []
      end
    end
    context 'when user confirms release' do
      before do
        stub_message "#worklog releasing FOO to master #scgitx"

        Socialcast::Gitx::CLI.any_instance.should_receive(:yes?).and_return(true)
        Socialcast::Gitx::CLI.any_instance.should_receive(:cleanup)
        Socialcast::Gitx::CLI.start ['release']
      end
      it 'should post message to socialcast' do end # see expectations
      it 'should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git pull origin FOO",
          "git pull origin master",
          "git push origin HEAD",
          "git checkout master",
          "git pull origin master",
          "git pull . FOO",
          "git push origin HEAD",
          "git branch -D staging",
          "git fetch origin",
          "git checkout staging",
          "git pull . master",
          "git push origin HEAD",
          "git checkout master"
        ]
      end
    end

    context 'with reserved_branches via config file' do
      before do
        stub_message "#worklog releasing FOO to master #scgitx"
        Socialcast::Gitx::CLI.any_instance.should_receive(:yes?).and_return(true)
        Socialcast::Gitx::CLI.any_instance.stub(:config).and_return( { 'reserved_branches' => ['dont-del-me','dont-del-me-2'] })
        Socialcast::Gitx::CLI.start ['release']
      end
      it "treats the alternative base branch as reserved" do
        Socialcast::Gitx::CLI.new.send(:reserved_branches).should include 'dont-del-me'
        Socialcast::Gitx::CLI.new.send(:reserved_branches).should include 'dont-del-me-2'
      end
    end

    context 'with alternative base branch via config file' do
      before do
        stub_message "#worklog releasing FOO to special-master #scgitx"

        Socialcast::Gitx::CLI.any_instance.should_receive(:yes?).and_return(true)
        Socialcast::Gitx::CLI.any_instance.stub(:config).and_return( { 'base_branch' => 'special-master' })
        Socialcast::Gitx::CLI.any_instance.should_receive(:cleanup)
        Socialcast::Gitx::CLI.start ['release']
      end
      it 'should post message to socialcast' do end # see expectations
      it "treats the alternative base branch as reserved" do
        Socialcast::Gitx::CLI.new.send(:reserved_branches).should include 'special-master'
      end
      it 'should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git pull origin FOO",
          "git pull origin special-master",
          "git push origin HEAD",
          "git checkout special-master",
          "git pull origin special-master",
          "git pull . FOO",
          "git push origin HEAD",
          "git branch -D staging",
          "git fetch origin",
          "git checkout staging",
          "git pull . special-master",
          "git push origin HEAD",
          "git checkout special-master"
        ]
      end
    end

    context 'with alternative base branch via environment variable' do
      before do
        stub_message "#worklog releasing FOO to special-master #scgitx"

        Socialcast::Gitx::CLI.any_instance.should_receive(:yes?).and_return(true)
        Socialcast::Gitx::CLI.any_instance.stub(:config).and_return({})
        Socialcast::Gitx::CLI.any_instance.should_receive(:cleanup)
        ENV['BASE_BRANCH'] = 'special-master'
        Socialcast::Gitx::CLI.start ['release']
      end
      after do
        ENV.delete('BASE_BRANCH')
      end
      it "treats the alternative base branch as reserved" do
        Socialcast::Gitx::CLI.new.send(:reserved_branches).should include 'special-master'
      end
      it 'should post message to socialcast' do end # see expectations
      it 'should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git pull origin FOO",
          "git pull origin special-master",
          "git push origin HEAD",
          "git checkout special-master",
          "git pull origin special-master",
          "git pull . FOO",
          "git push origin HEAD",
          "git branch -D staging",
          "git fetch origin",
          "git checkout staging",
          "git pull . special-master",
          "git push origin HEAD",
          "git checkout special-master"
        ]
      end
    end

    context 'with alternative base branch via environment variable overriding base branch in config' do
      before do
        stub_message "#worklog releasing FOO to special-master #scgitx"

        Socialcast::Gitx::CLI.any_instance.should_receive(:yes?).and_return(true)
        Socialcast::Gitx::CLI.any_instance.stub(:config).and_return({ 'base_branch' => 'extra-special-master' })
        Socialcast::Gitx::CLI.any_instance.should_receive(:cleanup)
        ENV['BASE_BRANCH'] = 'special-master'
        Socialcast::Gitx::CLI.start ['release']
      end
      after do
        ENV.delete('BASE_BRANCH')
      end
      it "treats the alternative base branch as reserved" do
        Socialcast::Gitx::CLI.new.send(:reserved_branches).should include 'special-master'
        Socialcast::Gitx::CLI.new.send(:reserved_branches).should include 'extra-special-master'
      end
      it 'should post message to socialcast' do end # see expectations
      it 'should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git pull origin FOO",
          "git pull origin special-master",
          "git push origin HEAD",
          "git checkout special-master",
          "git pull origin special-master",
          "git pull . FOO",
          "git push origin HEAD",
          "git branch -D staging",
          "git fetch origin",
          "git checkout staging",
          "git pull . special-master",
          "git push origin HEAD",
          "git checkout special-master"
        ]
      end
    end
  end

  describe '#nuke' do
    context 'when target branch == prototype and --destination == master' do
      before do
        prototype_branches = %w( dev-foo dev-bar )
        master_branches = %w( dev-foo )
        Socialcast::Gitx::CLI.any_instance.should_receive(:branches).and_return(prototype_branches, master_branches, prototype_branches, master_branches)
        stub_message "#worklog resetting prototype branch to last_known_good_master #scgitx\n/cc @SocialcastDevelopers\n\nthe following branches were affected:\n* dev-bar"
        Socialcast::Gitx::CLI.start ['nuke', 'prototype', '--destination', 'master']
      end
      it 'should publish message into socialcast' do end # see expectations
      it 'should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git checkout master",
          "git branch -D last_known_good_master",
          "git fetch origin",
          "git checkout last_known_good_master",
          "git branch -D prototype",
          "git push origin --delete prototype",
          "git checkout -b prototype",
          "git push origin prototype",
          "git branch --set-upstream prototype origin/prototype",
          "git checkout master",
          "git checkout master",
          "git branch -D last_known_good_master",
          "git fetch origin",
          "git checkout last_known_good_master",
          "git branch -D last_known_good_prototype",
          "git push origin --delete last_known_good_prototype",
          "git checkout -b last_known_good_prototype",
          "git push origin last_known_good_prototype",
          "git branch --set-upstream last_known_good_prototype origin/last_known_good_prototype",
          "git checkout master"
        ]
      end
    end
    context 'when target branch == staging and --destination == last_known_good_staging' do
      before do
        stub_message "#worklog resetting staging branch to last_known_good_staging #scgitx\n/cc @SocialcastDevelopers"

        Socialcast::Gitx::CLI.start ['nuke', 'staging', '--destination', 'last_known_good_staging']
      end
      it 'should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git checkout master",
          "git branch -D last_known_good_staging",
          "git fetch origin",
          "git checkout last_known_good_staging",
          "git branch -D staging",
          "git push origin --delete staging",
          "git checkout -b staging",
          "git push origin staging",
          "git branch --set-upstream staging origin/staging",
          "git checkout master"
        ]
      end
    end
    context 'when target branch == prototype and destination prompt == nil' do
      before do
        stub_message "#worklog resetting prototype branch to last_known_good_prototype #scgitx\n/cc @SocialcastDevelopers"

        Socialcast::Gitx::CLI.any_instance.should_receive(:ask).and_return('')
        Socialcast::Gitx::CLI.start ['nuke', 'prototype']
      end
      it 'defaults to last_known_good_prototype and should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git checkout master",
          "git branch -D last_known_good_prototype",
          "git fetch origin",
          "git checkout last_known_good_prototype",
          "git branch -D prototype",
          "git push origin --delete prototype",
          "git checkout -b prototype",
          "git push origin prototype",
          "git branch --set-upstream prototype origin/prototype",
          "git checkout master"
        ]
      end
    end
    context 'when target branch == prototype and destination prompt = master' do
      before do
        stub_message "#worklog resetting prototype branch to last_known_good_master #scgitx\n/cc @SocialcastDevelopers"

        Socialcast::Gitx::CLI.any_instance.should_receive(:ask).and_return('master')
        Socialcast::Gitx::CLI.start ['nuke', 'prototype']
      end
      it 'should run expected commands' do
        Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
          "git checkout master",
          "git branch -D last_known_good_master",
          "git fetch origin",
          "git checkout last_known_good_master",
          "git branch -D prototype",
          "git push origin --delete prototype",
          "git checkout -b prototype",
          "git push origin prototype",
          "git branch --set-upstream prototype origin/prototype",
          "git checkout master",
          "git checkout master",
          "git branch -D last_known_good_master",
          "git fetch origin",
          "git checkout last_known_good_master",
          "git branch -D last_known_good_prototype",
          "git push origin --delete last_known_good_prototype",
          "git checkout -b last_known_good_prototype",
          "git push origin last_known_good_prototype",
          "git branch --set-upstream last_known_good_prototype origin/last_known_good_prototype",
          "git checkout master"
        ]
      end
    end
    context 'when target branch != staging || prototype' do
      it 'should raise error' do
        lambda {
          Socialcast::Gitx::CLI.any_instance.should_receive(:ask).and_return('master')
          Socialcast::Gitx::CLI.start ['nuke', 'asdfasdf']
        }.should raise_error(/Only aggregate branches are allowed to be reset/)
      end
    end
  end

  describe '#backportpr' do
    before do
      # https://developer.github.com/v3/search/#search-issues
      pr_response = {
        "url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/59",
        "id" => 13712197,
        "html_url" => "https://github.com/socialcast/socialcast-git-extensions/pull/59",
        "diff_url" => "https://github.com/socialcast/socialcast-git-extensions/pull/59.diff",
        "patch_url" => "https://github.com/socialcast/socialcast-git-extensions/pull/59.patch",
        "issue_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues/59",
        "number" => 59,
        "state" => "closed",
        "title" => "additional-notifications",
        "user" => {
          "login" => "MikeSilvis",
          "id" => 152323,
          "avatar_url" => "https://avatars.githubusercontent.com/u/152323?",
          "gravatar_id" => "1bb5f2e12dcbfb8c103689f4ae94f431",
          "url" => "https://api.github.com/users/MikeSilvis",
          "html_url" => "https://github.com/MikeSilvis",
          "followers_url" => "https://api.github.com/users/MikeSilvis/followers",
          "following_url" => "https://api.github.com/users/MikeSilvis/following{/other_user}",
          "gists_url" => "https://api.github.com/users/MikeSilvis/gists{/gist_id}",
          "starred_url" => "https://api.github.com/users/MikeSilvis/starred{/owner}{/repo}",
          "subscriptions_url" => "https://api.github.com/users/MikeSilvis/subscriptions",
          "organizations_url" => "https://api.github.com/users/MikeSilvis/orgs",
          "repos_url" => "https://api.github.com/users/MikeSilvis/repos",
          "events_url" => "https://api.github.com/users/MikeSilvis/events{/privacy}",
          "received_events_url" => "https://api.github.com/users/MikeSilvis/received_events",
          "type" => "User",
          "site_admin" => false
        },
        "body" => "simply testing this out",
        "created_at" => "2014-03-18T22:39:37Z",
        "updated_at" => "2014-03-18T22:40:18Z",
        "closed_at" => "2014-03-18T22:39:46Z",
        "merged_at" => nil,
        "merge_commit_sha" => "f73009f4eb245c84da90e8abf9be846c58bc1e3b",
        "assignee" => nil,
        "milestone" => nil,
        "commits_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/59/commits",
        "review_comments_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/59/comments",
        "review_comment_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/comments/{number}",
        "comments_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues/59/comments",
        "statuses_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/statuses/5e30d5af3f4d1bb3a34cc97568299be028b65f6f",
        "head" => {
          "label" => "socialcast:additional-notifications",
          "ref" => "additional-notifications",
          "sha" => "5e30d5af3f4d1bb3a34cc97568299be028b65f6f",
          "user" => {
            "login" => "socialcast",
            "id" => 57931,
            "avatar_url" => "https://avatars.githubusercontent.com/u/57931?",
            "gravatar_id" => "489ec347da22410e9770ea022e6e2038",
            "url" => "https://api.github.com/users/socialcast",
            "html_url" => "https://github.com/socialcast",
            "followers_url" => "https://api.github.com/users/socialcast/followers",
            "following_url" => "https://api.github.com/users/socialcast/following{/other_user}",
            "gists_url" => "https://api.github.com/users/socialcast/gists{/gist_id}",
            "starred_url" => "https://api.github.com/users/socialcast/starred{/owner}{/repo}",
            "subscriptions_url" => "https://api.github.com/users/socialcast/subscriptions",
            "organizations_url" => "https://api.github.com/users/socialcast/orgs",
            "repos_url" => "https://api.github.com/users/socialcast/repos",
            "events_url" => "https://api.github.com/users/socialcast/events{/privacy}",
            "received_events_url" => "https://api.github.com/users/socialcast/received_events",
            "type" => "Organization",
            "site_admin" => false
          },
          "repo" => {
            "id" => 1000634,
            "name" => "socialcast-git-extensions",
            "full_name" => "socialcast/socialcast-git-extensions",
            "owner" => {
              "login" => "socialcast",
              "id" => 57931,
              "avatar_url" => "https://avatars.githubusercontent.com/u/57931?",
              "gravatar_id" => "489ec347da22410e9770ea022e6e2038",
              "url" => "https://api.github.com/users/socialcast",
              "html_url" => "https://github.com/socialcast",
              "followers_url" => "https://api.github.com/users/socialcast/followers",
              "following_url" => "https://api.github.com/users/socialcast/following{/other_user}",
              "gists_url" => "https://api.github.com/users/socialcast/gists{/gist_id}",
              "starred_url" => "https://api.github.com/users/socialcast/starred{/owner}{/repo}",
              "subscriptions_url" => "https://api.github.com/users/socialcast/subscriptions",
              "organizations_url" => "https://api.github.com/users/socialcast/orgs",
              "repos_url" => "https://api.github.com/users/socialcast/repos",
              "events_url" => "https://api.github.com/users/socialcast/events{/privacy}",
              "received_events_url" => "https://api.github.com/users/socialcast/received_events",
              "type" => "Organization",
              "site_admin" => false
            },
            "private" => false,
            "html_url" => "https://github.com/socialcast/socialcast-git-extensions",
            "description" => "",
            "fork" => false,
            "url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions",
            "forks_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/forks",
            "keys_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/keys{/key_id}",
            "collaborators_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/collaborators{/collaborator}",
            "teams_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/teams",
            "hooks_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/hooks",
            "issue_events_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues/events{/number}",
            "events_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/events",
            "assignees_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/assignees{/user}",
            "branches_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/branches{/branch}",
            "tags_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/tags",
            "blobs_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/blobs{/sha}",
            "git_tags_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/tags{/sha}",
            "git_refs_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/refs{/sha}",
            "trees_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/trees{/sha}",
            "statuses_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/statuses/{sha}",
            "languages_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/languages",
            "stargazers_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/stargazers",
            "contributors_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/contributors",
            "subscribers_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/subscribers",
            "subscription_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/subscription",
            "commits_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/commits{/sha}",
            "git_commits_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/commits{/sha}",
            "comments_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/comments{/number}",
            "issue_comment_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues/comments/{number}",
            "contents_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/contents/{+path}",
            "compare_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/compare/{base}...{head}",
            "merges_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/merges",
            "archive_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/{archive_format}{/ref}",
            "downloads_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/downloads",
            "issues_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues{/number}",
            "pulls_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls{/number}",
            "milestones_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/milestones{/number}",
            "notifications_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/notifications{?since,all,participating}",
            "labels_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/labels{/name}",
            "releases_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/releases{/id}",
            "created_at" => "2010-10-18T21:23:25Z",
            "updated_at" => "2014-05-12T20:03:30Z",
            "pushed_at" => "2014-05-12T20:03:31Z",
            "git_url" => "git://github.com/socialcast/socialcast-git-extensions.git",
            "ssh_url" => "git@github.com:socialcast/socialcast-git-extensions.git",
            "clone_url" => "https://github.com/socialcast/socialcast-git-extensions.git",
            "svn_url" => "https://github.com/socialcast/socialcast-git-extensions",
            "homepage" => "",
            "size" => 1719,
            "stargazers_count" => 3,
            "watchers_count" => 3,
            "language" => "Ruby",
            "has_issues" => true,
            "has_downloads" => true,
            "has_wiki" => true,
            "forks_count" => 6,
            "mirror_url" => nil,
            "open_issues_count" => 13,
            "forks" => 6,
            "open_issues" => 13,
            "watchers" => 3,
            "default_branch" => "master"
          }
        },
        "base" => {
          "label" => "socialcast:master",
          "ref" => "master",
          "sha" => "1baae2de301c43d44297647f3f9c1e06697748ad",
          "user" => {
            "login" => "socialcast",
            "id" => 57931,
            "avatar_url" => "https://avatars.githubusercontent.com/u/57931?",
            "gravatar_id" => "489ec347da22410e9770ea022e6e2038",
            "url" => "https://api.github.com/users/socialcast",
            "html_url" => "https://github.com/socialcast",
            "followers_url" => "https://api.github.com/users/socialcast/followers",
            "following_url" => "https://api.github.com/users/socialcast/following{/other_user}",
            "gists_url" => "https://api.github.com/users/socialcast/gists{/gist_id}",
            "starred_url" => "https://api.github.com/users/socialcast/starred{/owner}{/repo}",
            "subscriptions_url" => "https://api.github.com/users/socialcast/subscriptions",
            "organizations_url" => "https://api.github.com/users/socialcast/orgs",
            "repos_url" => "https://api.github.com/users/socialcast/repos",
            "events_url" => "https://api.github.com/users/socialcast/events{/privacy}",
            "received_events_url" => "https://api.github.com/users/socialcast/received_events",
            "type" => "Organization",
            "site_admin" => false
          },
          "repo" => {
            "id" => 1000634,
            "name" => "socialcast-git-extensions",
            "full_name" => "socialcast/socialcast-git-extensions",
            "owner" => {
              "login" => "socialcast",
              "id" => 57931,
              "avatar_url" => "https://avatars.githubusercontent.com/u/57931?",
              "gravatar_id" => "489ec347da22410e9770ea022e6e2038",
              "url" => "https://api.github.com/users/socialcast",
              "html_url" => "https://github.com/socialcast",
              "followers_url" => "https://api.github.com/users/socialcast/followers",
              "following_url" => "https://api.github.com/users/socialcast/following{/other_user}",
              "gists_url" => "https://api.github.com/users/socialcast/gists{/gist_id}",
              "starred_url" => "https://api.github.com/users/socialcast/starred{/owner}{/repo}",
              "subscriptions_url" => "https://api.github.com/users/socialcast/subscriptions",
              "organizations_url" => "https://api.github.com/users/socialcast/orgs",
              "repos_url" => "https://api.github.com/users/socialcast/repos",
              "events_url" => "https://api.github.com/users/socialcast/events{/privacy}",
              "received_events_url" => "https://api.github.com/users/socialcast/received_events",
              "type" => "Organization",
              "site_admin" => false
            },
            "private" => false,
            "html_url" => "https://github.com/socialcast/socialcast-git-extensions",
            "description" => "",
            "fork" => false,
            "url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions",
            "forks_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/forks",
            "keys_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/keys{/key_id}",
            "collaborators_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/collaborators{/collaborator}",
            "teams_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/teams",
            "hooks_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/hooks",
            "issue_events_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues/events{/number}",
            "events_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/events",
            "assignees_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/assignees{/user}",
            "branches_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/branches{/branch}",
            "tags_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/tags",
            "blobs_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/blobs{/sha}",
            "git_tags_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/tags{/sha}",
            "git_refs_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/refs{/sha}",
            "trees_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/trees{/sha}",
            "statuses_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/statuses/{sha}",
            "languages_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/languages",
            "stargazers_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/stargazers",
            "contributors_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/contributors",
            "subscribers_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/subscribers",
            "subscription_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/subscription",
            "commits_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/commits{/sha}",
            "git_commits_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/commits{/sha}",
            "comments_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/comments{/number}",
            "issue_comment_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues/comments/{number}",
            "contents_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/contents/{+path}",
            "compare_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/compare/{base}...{head}",
            "merges_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/merges",
            "archive_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/{archive_format}{/ref}",
            "downloads_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/downloads",
            "issues_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues{/number}",
            "pulls_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls{/number}",
            "milestones_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/milestones{/number}",
            "notifications_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/notifications{?since,all,participating}",
            "labels_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/labels{/name}",
            "releases_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/releases{/id}",
            "created_at" => "2010-10-18T21:23:25Z",
            "updated_at" => "2014-05-12T20:03:30Z",
            "pushed_at" => "2014-05-12T20:03:31Z",
            "git_url" => "git://github.com/socialcast/socialcast-git-extensions.git",
            "ssh_url" => "git@github.com:socialcast/socialcast-git-extensions.git",
            "clone_url" => "https://github.com/socialcast/socialcast-git-extensions.git",
            "svn_url" => "https://github.com/socialcast/socialcast-git-extensions",
            "homepage" => "",
            "size" => 1719,
            "stargazers_count" => 3,
            "watchers_count" => 3,
            "language" => "Ruby",
            "has_issues" => true,
            "has_downloads" => true,
            "has_wiki" => true,
            "forks_count" => 6,
            "mirror_url" => nil,
            "open_issues_count" => 13,
            "forks" => 6,
            "open_issues" => 13,
            "watchers" => 3,
            "default_branch" => "master"
          }
        },
        "_links" => {
          "self" => {
            "href" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/59"
          },
          "html" => {
            "href" => "https://github.com/socialcast/socialcast-git-extensions/pull/59"
          },
          "issue" => {
            "href" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues/59"
          },
          "comments" => {
            "href" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/issues/59/comments"
          },
          "review_comments" => {
            "href" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/59/comments"
          },
          "review_comment" => {
            "href" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/comments/{number}"
          },
          "commits" => {
            "href" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/59/commits"
          },
          "statuses" => {
            "href" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/statuses/5e30d5af3f4d1bb3a34cc97568299be028b65f6f"
          }
        },
        "merged" => false,
        "mergeable" => true,
        "mergeable_state" => "unstable",
        "merged_by" => nil,
        "comments" => 0,
        "review_comments" => 0,
        "commits" => 1,
        "additions" => 14,
        "deletions" => 2,
        "changed_files" => 2
      }

      commits_response = [
        {
          "sha" => "5e30d5af3f4d1bb3a34cc97568299be028b65f6f",
          "commit" => {
            "author" => {
              "name" => "Mike Silvis",
              "email" => "mikesilvis@gmail.com",
              "date" => "2014-03-18T22:39:12Z"
            },
            "committer" => {
              "name" => "Mike Silvis",
              "email" => "mikesilvis@gmail.com",
              "date" => "2014-03-18T22:39:12Z"
            },
            "message" => "adding the ability to specify additional reviewers",
            "tree" => {
              "sha" => "dcf05deb22223997a5184cd3a1866249f3e73e3b",
              "url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/trees/dcf05deb22223997a5184cd3a1866249f3e73e3b"
            },
            "url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/git/commits/5e30d5af3f4d1bb3a34cc97568299be028b65f6f",
            "comment_count" => 0
          },
          "url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/commits/5e30d5af3f4d1bb3a34cc97568299be028b65f6f",
          "html_url" => "https://github.com/socialcast/socialcast-git-extensions/commit/5e30d5af3f4d1bb3a34cc97568299be028b65f6f",
          "comments_url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/commits/5e30d5af3f4d1bb3a34cc97568299be028b65f6f/comments",
          "author" => {
            "login" => "MikeSilvis",
            "id" => 152323,
            "avatar_url" => "https://avatars.githubusercontent.com/u/152323?",
            "gravatar_id" => "1bb5f2e12dcbfb8c103689f4ae94f431",
            "url" => "https://api.github.com/users/MikeSilvis",
            "html_url" => "https://github.com/MikeSilvis",
            "followers_url" => "https://api.github.com/users/MikeSilvis/followers",
            "following_url" => "https://api.github.com/users/MikeSilvis/following{/other_user}",
            "gists_url" => "https://api.github.com/users/MikeSilvis/gists{/gist_id}",
            "starred_url" => "https://api.github.com/users/MikeSilvis/starred{/owner}{/repo}",
            "subscriptions_url" => "https://api.github.com/users/MikeSilvis/subscriptions",
            "organizations_url" => "https://api.github.com/users/MikeSilvis/orgs",
            "repos_url" => "https://api.github.com/users/MikeSilvis/repos",
            "events_url" => "https://api.github.com/users/MikeSilvis/events{/privacy}",
            "received_events_url" => "https://api.github.com/users/MikeSilvis/received_events",
            "type" => "User",
            "site_admin" => false
          },
          "committer" => {
            "login" => "MikeSilvis",
            "id" => 152323,
            "avatar_url" => "https://avatars.githubusercontent.com/u/152323?",
            "gravatar_id" => "1bb5f2e12dcbfb8c103689f4ae94f431",
            "url" => "https://api.github.com/users/MikeSilvis",
            "html_url" => "https://github.com/MikeSilvis",
            "followers_url" => "https://api.github.com/users/MikeSilvis/followers",
            "following_url" => "https://api.github.com/users/MikeSilvis/following{/other_user}",
            "gists_url" => "https://api.github.com/users/MikeSilvis/gists{/gist_id}",
            "starred_url" => "https://api.github.com/users/MikeSilvis/starred{/owner}{/repo}",
            "subscriptions_url" => "https://api.github.com/users/MikeSilvis/subscriptions",
            "organizations_url" => "https://api.github.com/users/MikeSilvis/orgs",
            "repos_url" => "https://api.github.com/users/MikeSilvis/repos",
            "events_url" => "https://api.github.com/users/MikeSilvis/events{/privacy}",
            "received_events_url" => "https://api.github.com/users/MikeSilvis/received_events",
            "type" => "User",
            "site_admin" => false
          },
          "parents" => [
            {
              "sha" => "1baae2de301c43d44297647f3f9c1e06697748ad",
              "url" => "https://api.github.com/repos/socialcast/socialcast-git-extensions/commits/1baae2de301c43d44297647f3f9c1e06697748ad",
              "html_url" => "https://github.com/socialcast/socialcast-git-extensions/commit/1baae2de301c43d44297647f3f9c1e06697748ad"
            }
          ]
        }
      ]

      stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/59").
        with(:headers => { 'Accept' => 'application/json', 'Accept-Encoding' => 'gzip, deflate', 'Authorization' => /token\s\w+/, 'Content-Type' => 'application/json', 'User-Agent' => 'socialcast-git-extensions' }).
        to_return(:status => 200, :body => pr_response.to_json, :headers => {})
      stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls/59/commits").
        with(:headers => { 'Accept' => 'application/json', 'Accept-Encoding' => 'gzip, deflate', 'Authorization' => /token\s\w+/, 'Content-Type' => 'application/json', 'User-Agent' => 'socialcast-git-extensions' }).
        to_return(:status => 200, :body => commits_response.to_json, :headers => {})
      stub_request(:post, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls").
         with(:body => "{\"title\":\"backport_59_to_v1.x\",\"base\":\"v1.x\",\"head\":\"backport_59_to_v1.x\",\"body\":\"Backport #59 to https://github.com/socialcast/socialcast-git-extensions/tree/v1.x\\n***\\nsimply testing this out\"}",
              :headers => { 'Accept' => 'application/json', 'Accept-Encoding' => 'gzip, deflate', 'Authorization' => /token\s\w+/, 'Content-Type' => 'application/json', 'User-Agent'=>'socialcast-git-extensions' }).
         to_return(:status => 200, :body => '{"html_url": "https://github.com/socialcast/socialcast-git-extensions/pulls/60"}', :headers => { 'Content-Type' => 'application/json' })

      stub_message "#reviewrequest backport #59 to v1.x #scgitx\n\n/cc @SocialcastDevelopers", :url => 'https://github.com/socialcast/socialcast-git-extensions/pulls/60', :message_type => 'review_request'

      Socialcast::Gitx::CLI.any_instance.should_receive(:backportpr).and_call_original
      Socialcast::Gitx::CLI.any_instance.stub(:say).with do |message|
        @said_text = @said_text.to_s + message
      end
      Socialcast::Gitx::CLI.start ['backportpr', '59', 'v1.x']
    end
    it 'creates a branch based on v1.x and cherry-picks in PR 59' do
      @said_text.should include "Creating pull request for backport_59_to_v1.x against v1.x in socialcast/socialcast-git-extensions"
      @said_text.should include "Message has been posted: http://demo.socialcast.com/messages/123"
    end
  end

  describe '#findpr' do
    before do
      # https://developer.github.com/v3/search/#search-issues
      stub_response = {
        "total_count"=> 280,
        "items"=> [{
                     "url" => "https://api.github.com/repos/batterseapower/pinyin-toolkit/issues/132",
                     "labels_url" => "https://api.github.com/repos/batterseapower/pinyin-toolkit/issues/132/labels{/name}",
                     "comments_url" => "https://api.github.com/repos/batterseapower/pinyin-toolkit/issues/132/comments",
                     "events_url" => "https://api.github.com/repos/batterseapower/pinyin-toolkit/issues/132/events",
                     "html_url" => "https://github.com/batterseapower/pinyin-toolkit/issues/132",
                     "id" => 35802,
                     "number" => 132,
                     "title" => "Line Number Indexes Beyond 20 Not Displayed",
                     "user" => {
                       "login" => "Nick3C",
                       "id" => 90254,
                       "avatar_url" => "https://secure.gravatar.com/avatar/934442aadfe3b2f4630510de416c5718?d=https://a248.e.akamai.net/assets.github.com%2Fimages%2Fgravatars%2Fgravatar-user-420.png",
                       "gravatar_id" => "934442aadfe3b2f4630510de416c5718",
                       "url" => "https://api.github.com/users/Nick3C",
                       "html_url" => "https://github.com/Nick3C",
                       "followers_url" => "https://api.github.com/users/Nick3C/followers",
                       "following_url" => "https://api.github.com/users/Nick3C/following{/other_user}",
                       "gists_url" => "https://api.github.com/users/Nick3C/gists{/gist_id}",
                       "starred_url" => "https://api.github.com/users/Nick3C/starred{/owner}{/repo}",
                       "subscriptions_url" => "https://api.github.com/users/Nick3C/subscriptions",
                       "organizations_url" => "https://api.github.com/users/Nick3C/orgs",
                       "repos_url" => "https://api.github.com/users/Nick3C/repos",
                       "events_url" => "https://api.github.com/users/Nick3C/events{/privacy}",
                       "received_events_url" => "https://api.github.com/users/Nick3C/received_events",
                       "type" => "User"
                     },
                     "labels" => [{
                                    "url" => "https://api.github.com/repos/batterseapower/pinyin-toolkit/labels/bug",
                                    "name" => "bug",
                                    "color" => "ff0000"
                                  }],
                     "state" => "open",
                     "assignee" => nil,
                     "milestone" => nil,
                     "comments" => 15,
                     "created_at" => "2009-07-12T20:10:41Z",
                     "updated_at" => "2009-07-19T09:23:43Z",
                     "closed_at" => nil,
                     "pull_request" => {
                       "html_url" => nil,
                       "diff_url" => nil,
                       "patch_url" => nil
                     },
                     "body" => "...",
                     "score" => 1.3859273
                   }]
      }

      stub_request(:get, "https://api.github.com/search/issues?q=abc123%20type:pr%20repo:socialcast/socialcast-git-extensions").
        with(:headers => { 'Accept' => 'application/json', 'Accept-Encoding' => 'gzip, deflate', 'Authorization' => /token\s\w+/, 'Content-Type' => 'application/json', 'User-Agent' => 'socialcast-git-extensions'}).
        to_return(:status => 200, :body => stub_response.to_json, :headers => {})
      Socialcast::Gitx::CLI.any_instance.should_receive(:findpr).and_call_original
      Socialcast::Gitx::CLI.any_instance.stub(:say).with do |message|
        @said_text = @said_text.to_s + message
      end
      Socialcast::Gitx::CLI.start ['findpr', 'abc123']
    end
    it 'fetches the data from github and prints it out' do
      @said_text.should include "https://github.com/batterseapower/pinyin-toolkit/issues/132"
      @said_text.should include "Nick3C"
      @said_text.should include "Line Number Indexes Beyond 20 Not Displayed"
    end
  end

  describe '#reviewrequest' do
    context 'when there are no review_buddies specified' do
      before do
        Socialcast::Gitx::CLI.any_instance.stub(:config_file).and_return(Pathname(''))
      end
      context 'when description != nil' do
        before do
          stub_request(:post, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls").
            to_return(:status => 200, :body => %q({"html_url": "http://github.com/repo/project/pulls/1"}), :headers => {})

          stub_message "#reviewrequest for FOO #scgitx\n\n/cc @SocialcastDevelopers\n\ntesting\n\n1 file changed", :url => 'http://github.com/repo/project/pulls/1', :message_type => 'review_request'
          Socialcast::Gitx::CLI.any_instance.stub(:changelog_summary).and_return('1 file changed')
          Socialcast::Gitx::CLI.start ['reviewrequest', '--description', 'testing', '-s']
        end
        it 'should create github pull request' do end # see expectations
        it 'should post socialcast message' do end # see expectations
        it 'should run expected commands' do
          Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
            "git pull origin FOO",
            "git pull origin master",
            "git push origin HEAD"
          ]
        end
      end
    end

    context 'when review_buddies are specified via a /config YML file' do
      before do
        stub_request(:post, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls").
          to_return(:status => 200, :body => %q({"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://github.com/repos/repo/project/issues/1"}), :headers => {})
        stub_request(:patch, "http://github.com/repos/repo/project/issues/1").to_return(:status => 200)
      end
      context 'and additional reviewers are specified' do
        let(:message_body) { "#reviewrequest for FOO #scgitx\n\n/cc @SocialcastDevelopers\n\n\nAssigned additionally to @JohnSmith for API review\n\ntesting\n\n1 file changed" }
        before do
          Socialcast::Gitx::CLI.any_instance.stub(:changelog_summary).and_return('1 file changed')
          # The Review Buddy should be @mentioned in the message
          stub_message message_body, :url => 'http://github.com/repo/project/pulls/1', :message_type => 'review_request'
          Socialcast::Gitx::CLI.start ['reviewrequest', '--description', 'testing', '-a', 'a']
        end
        it 'should create github pull request' do end # see expectations
        it 'should post socialcast message' do end # see expectations
        it 'should run expected commands' do
          Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
            "git pull origin FOO",
            "git pull origin master",
            "git push origin HEAD"
          ]
        end
      end
      context 'and additional reviewers are not specified' do
        let(:message_body) { "#reviewrequest for FOO #scgitx\n\n/cc @SocialcastDevelopers\n\ntesting\n\n1 file changed" }
        before do
          Socialcast::Gitx::CLI.any_instance.stub(:changelog_summary).and_return('1 file changed')
          # The Review Buddy should be @mentioned in the message
          stub_message message_body, :url => 'http://github.com/repo/project/pulls/1', :message_type => 'review_request'
          Socialcast::Gitx::CLI.start ['reviewrequest', '--description', 'testing', '-s']
        end
        it 'should create github pull request' do end # see expectations
      end
    end
  end

  describe '#promote' do
    before do
      stub_message "#worklog integrating FOO into staging #scgitx"
      Socialcast::Gitx::CLI.start ['promote']
    end
    it 'should integrate into staging' do
      Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
        "git pull origin FOO",
        "git pull origin master",
        "git push origin HEAD",
        "git branch -D staging",
        "git fetch origin",
        "git checkout staging",
        "git pull . FOO",
        "git push origin HEAD",
        "git checkout FOO",
        "git branch -D prototype",
        "git fetch origin",
        "git checkout prototype",
        "git pull . staging",
        "git push origin HEAD",
        "git checkout staging",
        "git checkout FOO"
      ]
    end
  end

  describe '#cleanup' do
    before do
      Socialcast::Gitx::CLI.any_instance.should_receive(:branches).with(:merged => true, :remote => true).and_return(['master', 'foobar', 'last_known_good_master'])
      Socialcast::Gitx::CLI.any_instance.should_receive(:branches).with(:merged => true).and_return(['staging', 'bazquux', 'last_known_good_prototype'])
      Socialcast::Gitx::CLI.start ['cleanup']
    end
    it 'should only cleanup non-reserved branches' do
      Socialcast::Gitx::CLI.stubbed_executed_commands.should == [
        "git checkout master",
        "git pull",
        "git remote prune origin",
        "git push origin --delete foobar",
        "git branch -d bazquux"
      ]
    end
  end
end
