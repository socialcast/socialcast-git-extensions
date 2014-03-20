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
    json_body = { :message => { :body => message_body }.merge!(params) }

    stub_request(:post, "https://testuser:testpassword@testdomain/api/messages.json")
      .with(:body => json_body)
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
        with(:headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Authorization'=>/token\s\w+/, 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}).
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
      context 'when description != null' do
        before do
          stub_request(:post, "https://api.github.com/repos/socialcast/socialcast-git-extensions/pulls").
            to_return(:status => 200, :body => %q({"html_url": "http://github.com/repo/project/pulls/1"}), :headers => {})

          stub_message "#reviewrequest for FOO #scgitx\n\n/cc @SocialcastDevelopers\n\ntesting\n\n", :url => 'http://github.com/repo/project/pulls/1', :message_type => 'review_request'
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
        let(:message_body) { "#reviewrequest for FOO #scgitx\n\n/cc @SocialcastDevelopers\n\n\nAssigned additionally to @JohnSmith for API review\n\ntesting\n\n" }
        before do
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
        let(:message_body) { "#reviewrequest for FOO #scgitx\n\n/cc @SocialcastDevelopers\n\ntesting\n\n" }
        before do
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
