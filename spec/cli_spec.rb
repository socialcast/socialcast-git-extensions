require 'spec_helper'

describe Socialcast::Gitx::CLI do
  let(:stubbed_executed_commands) { [] }

  def stub_message(message_body, params = {})
    expect(Socialcast::CommandLine::Message).to receive(:create).with(params.merge(:body => message_body)).and_return(double(:permalink_url => 'https://community.socialcast.com/messages/1234'))
  end

  before do
    Socialcast::Gitx::CLI.instance_eval do # to supress warning from stubbing ldap_config
      @no_tasks = @no_commands = true
    end
    allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:run_cmd) do |_instance, cmd|
      stubbed_executed_commands << cmd
    end
    allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:'`') do |_instance, cmd|
      raise "Unstubbed backticks detected"
    end
    allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:current_repo).and_return('socialcast/socialcast-git-extensions')
    allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:say)
    allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:current_branch).and_return('FOO')
    allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:current_user).and_return('wireframe')
    allow(Socialcast::CommandLine).to receive(:credentials).and_return(:domain => 'testdomain', :user => 'testuser', :password => 'testpassword', :scgitx_token => 'faketoken')
  end

  describe '#update' do
    it do
      expect_any_instance_of(Socialcast::Gitx::CLI).not_to receive(:post)
      Socialcast::Gitx::CLI.start ['update']

      expect(stubbed_executed_commands).to eq([
        'git pull origin FOO',
        'git pull origin master',
        'git push origin HEAD'
      ])
    end
  end

  describe '#integrate' do
    context 'with no existing pull request' do
      before do
        stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls?head=socialcast:FOO")
          .with(:headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Authorization'=>'token faketoken', 'Content-Type'=>'application/json', 'User-Agent'=>'socialcast-git-extensions'})
          .to_return(:status => 200, :body => "[]", :headers => {})
      end
      context 'when target branch is omitted' do
        it 'defaults to prototype' do
          stub_message "#worklog integrating FOO into prototype in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers", :force_post => true

          Socialcast::Gitx::CLI.start ['integrate']

          expect(stubbed_executed_commands).to eq([
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
                                                  ])
        end
      end
      context 'when target branch is omitted with custom prototype branch' do
        it 'defaults to the custom prototype branch' do
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:prototype_branch).and_return('special-prototype')

          stub_message "#worklog integrating FOO into special-prototype in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers", :force_post => true

          Socialcast::Gitx::CLI.start ['integrate']

          expect(stubbed_executed_commands).to eq([
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
                                                  ])
        end
      end
      context 'when target branch == prototype' do
        it do
          stub_message "#worklog integrating FOO into prototype in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers", :force_post => true

          Socialcast::Gitx::CLI.start ['integrate', 'prototype']

          expect(stubbed_executed_commands).to eq([
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
                                                  ])
        end
      end
      context 'when target branch == staging' do
        it do
          stub_message "#worklog integrating FOO into staging in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers", :force_post => true

          Socialcast::Gitx::CLI.start ['integrate', 'staging']

          expect(stubbed_executed_commands).to eq([
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
                                                  ])
        end
      end
      context 'when target branch != staging || prototype' do
        it do
          expect {
            Socialcast::Gitx::CLI.start ['integrate', 'asdfasdfasdf']
          }.to raise_error(/Only aggregate branches are allowed for integration/)
        end
      end
    end
    context 'with an existing pull request' do
      before do
        stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls?head=socialcast:FOO")
          .to_return(:status => 200, :body => %q([{"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://api.github.com/repos/repo/project/issues/1", "body":"testing"}]))
      end
      it 'comments on the PR and does not force a post' do
        stub_message "#worklog integrating FOO into prototype in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers", :force_post => false

        stub_request(:post, "http://api.github.com/repos/repo/project/issues/1/comments")
          .with(
            :body => "{\"body\":\"Integrated into prototype /cc @SocialcastDevelopers #scgitx\"}",
          ).to_return(:status => 200, :body => "{}", :headers => {})

          Socialcast::Gitx::CLI.start ['integrate']

          expect(stubbed_executed_commands).to eq([
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
                                                  ])
      end
    end
  end

  describe '#release' do
    let(:branches_in_last_known_good_staging) { ['FOO'] }
    before do
      allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:enforce_staging_before_release?).and_return(true)
      allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:branches).with(:remote => true, :merged => true).and_return(branches_in_last_known_good_staging)
    end

    context 'when user rejects release' do
      before do
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:yes?).and_return(false)
        Socialcast::Gitx::CLI.start ['release']
      end
      it 'does not try and release the branch' do
        expect(stubbed_executed_commands).to eq(["git branch -D last_known_good_staging", "git fetch origin", "git checkout last_known_good_staging", "git checkout FOO"])
      end
    end
    context 'when user confirms release' do
      it do
        stub_message "#worklog releasing FOO to master in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"

        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:yes?).and_return(true)
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:cleanup)
        Socialcast::Gitx::CLI.start ['release']

        expect(stubbed_executed_commands).to eq([
          "git branch -D last_known_good_staging",
          "git fetch origin",
          "git checkout last_known_good_staging",
          "git checkout FOO",
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
        ])
      end
    end

    context 'when the branch is not in last_known_good_staging' do
      context 'and enforce_staging_before_release = true' do
        let(:branches_in_last_known_good_staging) { ['another-branch'] }
        before do
          expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:enforce_staging_before_release?).and_return(true)
          expect_any_instance_of(Socialcast::Gitx::CLI).not_to receive(:yes?)
        end
        it 'prevents the release of the branch' do
          expect { Socialcast::Gitx::CLI.start ['release'] }.to raise_error(RuntimeError, 'Cannot release FOO unless it has already been promoted separately to staging and the build has passed.')
        end
      end
      context 'and enforce_staging_before_release = false' do
        let(:branches_in_last_known_good_staging) { ['another-branch'] }
        before do
          stub_message "#worklog releasing FOO to master in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"
          expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:enforce_staging_before_release?).and_return(false)
          expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:yes?).and_return(true)
          expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:cleanup)
          Socialcast::Gitx::CLI.start ['release']
        end
        it 'should run expected commands' do
          expect(stubbed_executed_commands).to eq([
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
          ])
        end
      end
    end

    context 'with reserved_branches via config file' do
      before do
        stub_message "#worklog releasing FOO to master in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:yes?).and_return(true)
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config).and_return( { 'reserved_branches' => ['dont-del-me','dont-del-me-2'] })
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:cleanup)
        Socialcast::Gitx::CLI.start ['release']
      end
      it "treats the alternative base branch as reserved" do
        expect(Socialcast::Gitx::CLI.new.send(:reserved_branches)).to include 'dont-del-me'
        expect(Socialcast::Gitx::CLI.new.send(:reserved_branches)).to include 'dont-del-me-2'
      end
    end

    context 'with alternative base branch via config file' do
      it do
        stub_message "#worklog releasing FOO to special-master in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"

        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:yes?).and_return(true)
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config).and_return( { 'base_branch' => 'special-master' })
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:cleanup)
        Socialcast::Gitx::CLI.start ['release']

        expect(Socialcast::Gitx::CLI.new.send(:reserved_branches)).to include 'special-master'

        expect(stubbed_executed_commands).to eq([
          "git branch -D last_known_good_staging",
          "git fetch origin",
          "git checkout last_known_good_staging",
          "git checkout FOO",
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
        ])
      end
    end

    context 'with alternative base branch via environment variable' do
      before do
        stub_message "#worklog releasing FOO to special-master in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"

        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:yes?).and_return(true)
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config).and_return({})
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:cleanup)
        ENV['BASE_BRANCH'] = 'special-master'
        Socialcast::Gitx::CLI.start ['release']
      end
      after do
        ENV.delete('BASE_BRANCH')
      end
      it do
        expect(Socialcast::Gitx::CLI.new.send(:reserved_branches)).to include 'special-master'

        expect(stubbed_executed_commands).to eq([
          "git branch -D last_known_good_staging",
          "git fetch origin",
          "git checkout last_known_good_staging",
          "git checkout FOO",
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
        ])
      end
    end

    context 'with alternative base branch via environment variable overriding base branch in config' do
      before do
        stub_message "#worklog releasing FOO to special-master in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"

        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:yes?).and_return(true)
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config).and_return({ 'base_branch' => 'extra-special-master' })
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:cleanup)
        ENV['BASE_BRANCH'] = 'special-master'
        Socialcast::Gitx::CLI.start ['release']
      end
      after do
        ENV.delete('BASE_BRANCH')
      end
      it "treats the alternative base branch as reserved" do
        expect(Socialcast::Gitx::CLI.new.send(:reserved_branches)).to include 'special-master'
        expect(Socialcast::Gitx::CLI.new.send(:reserved_branches)).to include 'extra-special-master'

        expect(stubbed_executed_commands).to eq([
          "git branch -D last_known_good_staging",
          "git fetch origin",
          "git checkout last_known_good_staging",
          "git checkout FOO",
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
        ])
      end
    end
  end

  describe '#branchdiff' do
    subject(:branchdiff) { Socialcast::Gitx::CLI.start(['branchdiff'] + args) }
    let(:said_messages) { [] }
    before do
      expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:run_cmd).with('git fetch origin')
      allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:say) do |_instance, msg|
        said_messages << msg
      end
    end
    context 'with one branch-name argument' do
      let(:args) { ['my-branch'] }
      before do
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:branch_difference).with('my-branch', 'master').and_return(['dummy_branch'])
        branchdiff
      end
      it do
        expect(said_messages).to eq ["\nBranches in origin/my-branch and not in origin/master:\n\ndummy_branch\n\n"]
      end
    end
    context 'with two branch-name arguments' do
      let(:args) { ['my-branch', 'other-branch'] }
      before do
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:branch_difference).with('my-branch', 'other-branch').and_return(['dummy_branch'])
        branchdiff
      end
      it do
        expect(said_messages).to eq ["\nBranches in origin/my-branch and not in origin/other-branch:\n\ndummy_branch\n\n"]
      end
    end
    context 'when no results are found' do
      let(:args) { ['my-branch'] }
      before do
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:branch_difference).with('my-branch', 'master').and_return([])
        branchdiff
      end
      it do
        expect(said_messages).to eq ["\nNo branches found in origin/my-branch that are not also in origin/master\n\n"]
      end
    end
  end

  describe '#nuke' do
    before { allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:branches).and_return([]) }
    context 'when target branch == staging and --destination == last_known_good_staging' do
      before do
        stub_message "#worklog resetting staging branch to last_known_good_staging in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"
        Socialcast::Gitx::CLI.start ['nuke', 'staging', '--destination', 'last_known_good_staging']
      end
      it 'should run expected commands' do
        expect(stubbed_executed_commands).to eq([
          "git checkout master",
          "git branch -D last_known_good_staging",
          "git fetch origin",
          "git checkout last_known_good_staging",
          "git branch -D staging",
          "git push origin --delete staging",
          "git checkout -b staging",
          "git push origin staging",
          "git branch --set-upstream-to=origin/staging staging",
          "git checkout master"
        ])
      end
    end
    context 'when target branch == qa and destination prompt == nil and using custom aggregate_branches config' do
      before do
        stub_message "#worklog resetting qa branch to last_known_good_qa in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config).and_return( { 'aggregate_branches' => ['staging', 'qa'] })
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:ask).and_return('')
        Socialcast::Gitx::CLI.start ['nuke', 'qa']
      end
      it 'defaults to last_known_good_qa and should run expected commands' do
        expect(stubbed_executed_commands).to eq([
          "git checkout master",
          "git branch -D last_known_good_qa",
          "git fetch origin",
          "git checkout last_known_good_qa",
          "git branch -D qa",
          "git push origin --delete qa",
          "git checkout -b qa",
          "git push origin qa",
          "git branch --set-upstream-to=origin/qa qa",
          "git checkout master"
        ])
      end
    end
    context 'when target branch == qa and destination prompt = master and using custom aggregate_branches config' do
      before do
        stub_message "#worklog resetting qa branch to last_known_good_master in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers"
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config).and_return( { 'aggregate_branches' => ['staging', 'qa'] })
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:ask).and_return('master')
        Socialcast::Gitx::CLI.start ['nuke', 'qa']
      end
      it 'should run expected commands' do
        expect(stubbed_executed_commands).to eq([
          "git checkout master",
          "git branch -D last_known_good_master",
          "git fetch origin",
          "git checkout last_known_good_master",
          "git branch -D qa",
          "git push origin --delete qa",
          "git checkout -b qa",
          "git push origin qa",
          "git branch --set-upstream-to=origin/qa qa",
          "git checkout master",
          "git checkout master",
          "git branch -D last_known_good_master",
          "git fetch origin",
          "git checkout last_known_good_master",
          "git branch -D last_known_good_qa",
          "git push origin --delete last_known_good_qa",
          "git checkout -b last_known_good_qa",
          "git push origin last_known_good_qa",
          "git branch --set-upstream-to=origin/last_known_good_qa last_known_good_qa",
          "git checkout master"
        ])
      end
    end
    it 'raises an error when target branch is not an aggregate branch' do
      expect {
        expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:ask).and_return('master')
        Socialcast::Gitx::CLI.start ['nuke', 'asdfasdf']
      }.to raise_error(/Only aggregate branches are allowed to be reset/)
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
         to_return(:status => 200, :body => '{"html_url": "https://github.com/socialcast/socialcast-git-extensions/pulls/60", "issue_url": "https://api.github.com/repos/repo/project/issues/60"}', :headers => { 'Content-Type' => 'application/json' })

      stub_request(:post, "https://api.github.com/repos/repo/project/issues/60/comments")
        .with(
          :body => "{\"body\":\"#reviewrequest backport /cc @SocialcastDevelopers #scgitx\"}",
          :headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Authorization'=>'token faketoken', 'Content-Length'=>'68', 'Content-Type'=>'application/json', 'User-Agent'=>'socialcast-git-extensions'}
        ).to_return(:status => 200, :body => "{}", :headers => {})

      stub_request(:post, "https://testuser:testpassword@testdomain/api/messages.json")
        .with(
          :body => "{\"message\":{\"url\":\"https://github.com/socialcast/socialcast-git-extensions/pulls/60\",\"message_type\":\"review_request\",\"body\":\"#reviewrequest backport #59 to v1.x in socialcast/socialcast-git-extensions #scgitx\\n\\n/cc @SocialcastDevelopers\"}}",
          :headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}
        ).to_return(:status => 200, :body => "", :headers => {})

      expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:backportpr).and_call_original
      Socialcast::Gitx::CLI.start ['backportpr', '59', 'v1.x']
    end
    it 'creates a branch based on v1.x and cherry-picks in PR 59' do end
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
      expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:findpr).and_call_original
      allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:say).with("Searching github pull requests for abc123")
      allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:say).with("\nhttps://github.com/batterseapower/pinyin-toolkit/issues/132\n\tLine Number Indexes Beyond 20 Not Displayed\n\tNick3C 2009-07-12T20:10:41Z")
      Socialcast::Gitx::CLI.start ['findpr', 'abc123']
    end
    it 'fetches the data from github and prints it out' do end
  end

  describe '#reviewrequest' do
    context 'when there are no review_buddies specified' do
      before do
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config_file).and_return(Pathname(''))
      end
      context 'when description != nil' do
        it do
          stub_request(:post, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls").
            to_return(:status => 200, :body => %q({"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://api.github.com/repos/repo/project/issues/1"}), :headers => {})

          stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls?head=socialcast:FOO").
            to_return(:status => 200, :body => %q([{"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://api.github.com/repos/repo/project/issues/1", "body":"testing"}]), :headers => {})

          stub_request(:post, "http://api.github.com/repos/repo/project/issues/1/comments")
            .with(
              :body => "{\"body\":\"#reviewrequest \\n/cc @SocialcastDevelopers #scgitx\"}",
              :headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Authorization'=>'token faketoken', 'Content-Length'=>'61', 'Content-Type'=>'application/json', 'User-Agent'=>'socialcast-git-extensions'}
            ).to_return(:status => 200, :body => "{}", :headers => {})

          stub_message "#reviewrequest for FOO in socialcast/socialcast-git-extensions\nPR http://github.com/repo/project/pulls/1 \n\ntesting\n\n/cc @SocialcastDevelopers #scgitx\n\n1 file changed", :message_type => 'review_request'
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:changelog_summary).and_return('1 file changed')
          Socialcast::Gitx::CLI.start ['reviewrequest', '--description', 'testing', '-s']

          expect(stubbed_executed_commands).to eq([
            "git pull origin FOO",
            "git pull origin master",
            "git push origin HEAD"
          ])
        end
      end
    end

    context 'when review_buddies are specified via a /config YML file' do
      before do
        stub_request(:post, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls").
          to_return(:status => 200, :body => %q({"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://api.github.com/repos/repo/project/issues/1"}), :headers => {})
        stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls?head=socialcast:FOO").
          to_return(:status => 200, :body => %q([{"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://api.github.com/repos/repo/project/issues/1", "body":"testing"}]), :headers => {})
        stub_request(:post, "http://api.github.com/repos/repo/project/issues/1/comments")
          .with(
            :body => pr_comment_body,
            :headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Authorization'=>'token faketoken', 'Content-Length'=> pr_comment_body.length, 'Content-Type'=>'application/json', 'User-Agent'=>'socialcast-git-extensions'}
          ).to_return(:status => 200, :body => "{}", :headers => {})

        stub_request(:patch, "http://github.com/repos/repo/project/issues/1").to_return(:status => 200)
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:socialcast_review_buddy).and_return('JaneDoe')
      end
      context 'and additional reviewers are specified' do
        let(:message_body) { "#reviewrequest for FOO in socialcast/socialcast-git-extensions\nPR http://github.com/repo/project/pulls/1 assigned to @JaneDoe\n\ntesting\n\nAssigned additionally to @JohnSmith for API review\n/cc @SocialcastDevelopers #scgitx\n\n1 file changed" }
        let(:pr_comment_body) { "{\"body\":\"#reviewrequest assigned to @JaneDoe \\nAssigned additionally to @JohnSmith for API review \\n/cc @SocialcastDevelopers #scgitx\"}" }
        it do
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:changelog_summary).and_return('1 file changed')
          stub_message message_body, :message_type => 'review_request'
          Socialcast::Gitx::CLI.start ['reviewrequest', '--description', 'testing', '-a', 'a']

          expect(stubbed_executed_commands).to eq([
            "git pull origin FOO",
            "git pull origin master",
            "git push origin HEAD"
          ])
        end
      end
      context 'and a developer group is specified' do
        let(:message_body) { "#reviewrequest for FOO in socialcast/socialcast-git-extensions\nPR http://github.com/repo/project/pulls/1 assigned to @JaneDoe\n\ntesting\n\n/cc @#{another_group} #scgitx\n\n1 file changed" }
        let(:pr_comment_body) { "{\"body\":\"#reviewrequest assigned to @JaneDoe \\n/cc @#{another_group} #scgitx\"}" }
        let(:another_group) { 'AnotherDeveloperGroup' }
        it do
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:changelog_summary).and_return('1 file changed')
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config).and_return({'developer_group' => another_group})
          stub_message message_body, :message_type => 'review_request'
          Socialcast::Gitx::CLI.start ['reviewrequest', '--description', 'testing', '-s']
        end
      end
      context 'and additional reviewers are not specified' do
        let(:message_body) { "#reviewrequest for FOO in socialcast/socialcast-git-extensions\nPR http://github.com/repo/project/pulls/1 assigned to @JaneDoe\n\ntesting\n\n/cc @SocialcastDevelopers #scgitx\n\n1 file changed" }
        let(:pr_comment_body) { "{\"body\":\"#reviewrequest assigned to @JaneDoe \\n/cc @SocialcastDevelopers #scgitx\"}" }
        it do
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:changelog_summary).and_return('1 file changed')
          stub_message message_body, :message_type => 'review_request'
          Socialcast::Gitx::CLI.start ['reviewrequest', '--description', 'testing', '-s']
        end
      end
    end
  end

  describe '#createpr' do
    before do
      allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config_file).and_return(Pathname(''))
    end
    context 'when description != nil' do
      it do
        stub_request(:post, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls").
          to_return(:status => 200, :body => %q({"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://api.github.com/repos/repo/project/issues/1"}), :headers => {})

        Socialcast::Gitx::CLI.start ['createpr', '--description', 'testing']

        expect(stubbed_executed_commands).to eq([
          "git pull origin FOO",
          "git pull origin master",
          "git push origin HEAD"
        ])
      end
    end
  end

  describe '#assignpr' do
    context 'when there are no review_buddies specified' do
      before do
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config_file).and_return(Pathname(''))
      end
      it do
        stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls?head=socialcast:FOO").
          to_return(:status => 200, :body => %q([{"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://api.github.com/repos/repo/project/issues/1", "body":"testing"}]), :headers => {})

        stub_request(:post, "http://api.github.com/repos/repo/project/issues/1/comments")
          .with(
            :body => "{\"body\":\"#reviewrequest \\n/cc @SocialcastDevelopers #scgitx\"}",
            :headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Authorization'=>'token faketoken', 'Content-Length'=>'61', 'Content-Type'=>'application/json', 'User-Agent'=>'socialcast-git-extensions'}
          ).to_return(:status => 200, :body => "{}", :headers => {})

        stub_message "#reviewrequest for FOO in socialcast/socialcast-git-extensions\nPR http://github.com/repo/project/pulls/1 \n\ntesting\n\n/cc @SocialcastDevelopers #scgitx\n\n1 file changed", :message_type => 'review_request'
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:changelog_summary).and_return('1 file changed')
        Socialcast::Gitx::CLI.start ['assignpr', '-s']

        expect(stubbed_executed_commands).to eq([
          "git pull origin FOO",
          "git pull origin master",
          "git push origin HEAD"
        ])
      end
    end

    context 'when review_buddies are specified via a /config YML file' do
      before do
        stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls?head=socialcast:FOO").
          to_return(:status => 200, :body => %q([{"html_url": "http://github.com/repo/project/pulls/1", "issue_url": "http://api.github.com/repos/repo/project/issues/1", "body":"testing"}]), :headers => {})
        stub_request(:post, "http://api.github.com/repos/repo/project/issues/1/comments")
          .with(
            :body => pr_comment_body,
            :headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Authorization'=>'token faketoken', 'Content-Length'=> pr_comment_body.length, 'Content-Type'=>'application/json', 'User-Agent'=>'socialcast-git-extensions'}
          ).to_return(:status => 200, :body => "{}", :headers => {})

        stub_request(:patch, "http://github.com/repos/repo/project/issues/1").to_return(:status => 200)
        allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:socialcast_review_buddy).and_return('JaneDoe')
      end
      context 'and additional reviewers are specified' do
        let(:message_body) { "#reviewrequest for FOO in socialcast/socialcast-git-extensions\nPR http://github.com/repo/project/pulls/1 assigned to @JaneDoe\n\ntesting\n\nAssigned additionally to @JohnSmith for API review\n/cc @SocialcastDevelopers #scgitx\n\n1 file changed" }
        let(:pr_comment_body) { "{\"body\":\"#reviewrequest assigned to @JaneDoe \\nAssigned additionally to @JohnSmith for API review \\n/cc @SocialcastDevelopers #scgitx\"}" }
        it do
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:changelog_summary).and_return('1 file changed')
          stub_message message_body, :message_type => 'review_request'
          Socialcast::Gitx::CLI.start ['assignpr', '-a', 'a']

          expect(stubbed_executed_commands).to eq([
            "git pull origin FOO",
            "git pull origin master",
            "git push origin HEAD"
          ])
        end
      end
      context 'and a developer group is specified' do
        let(:message_body) { "#reviewrequest for FOO in socialcast/socialcast-git-extensions\nPR http://github.com/repo/project/pulls/1 assigned to @JaneDoe\n\ntesting\n\n/cc @#{another_group} #scgitx\n\n1 file changed" }
        let(:pr_comment_body) { "{\"body\":\"#reviewrequest assigned to @JaneDoe \\n/cc @#{another_group} #scgitx\"}" }
        let(:another_group) { 'AnotherDeveloperGroup' }
        it do
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:changelog_summary).and_return('1 file changed')
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:config).and_return({'developer_group' => another_group})
          stub_message message_body, :message_type => 'review_request'
          Socialcast::Gitx::CLI.start ['assignpr', '-s']
        end
      end
      context 'and additional reviewers are not specified' do
        let(:message_body) { "#reviewrequest for FOO in socialcast/socialcast-git-extensions\nPR http://github.com/repo/project/pulls/1 assigned to @JaneDoe\n\ntesting\n\n/cc @SocialcastDevelopers #scgitx\n\n1 file changed" }
        let(:pr_comment_body) { "{\"body\":\"#reviewrequest assigned to @JaneDoe \\n/cc @SocialcastDevelopers #scgitx\"}" }
        it do
          allow_any_instance_of(Socialcast::Gitx::CLI).to receive(:changelog_summary).and_return('1 file changed')
          stub_message message_body, :message_type => 'review_request'
          Socialcast::Gitx::CLI.start ['assignpr', '-s']
        end
      end
    end
  end

  describe '#promote' do
    before do
      stub_request(:get, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls?head=socialcast:FOO")
        .with(:headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Authorization'=>'token faketoken', 'Content-Type'=>'application/json', 'User-Agent'=>'socialcast-git-extensions'})
        .to_return(:status => 200, :body => "[]", :headers => {})

      stub_message "#worklog integrating FOO into staging in socialcast/socialcast-git-extensions #scgitx\n/cc @SocialcastDevelopers", :force_post => true
      Socialcast::Gitx::CLI.start ['promote']
    end
    it 'should integrate into staging' do
      expect(stubbed_executed_commands).to eq([
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
      ])
    end
  end

  describe '#cleanup' do
    before do
      expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:branches).with(:merged => true, :remote => true).and_return(['master', 'foobar', 'last_known_good_master'])
      expect_any_instance_of(Socialcast::Gitx::CLI).to receive(:branches).with(:merged => true).and_return(['staging', 'bazquux', 'last_known_good_prototype'])
      Socialcast::Gitx::CLI.start ['cleanup']
    end
    it 'should only cleanup non-reserved branches' do
      expect(stubbed_executed_commands).to eq([
        "git checkout master",
        "git pull",
        "git remote prune origin",
        "git push origin --delete foobar",
        "git branch -d bazquux"
      ])
    end
  end
end
