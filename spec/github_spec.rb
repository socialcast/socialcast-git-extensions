require 'spec_helper'

describe Socialcast::Gitx::Github do
  let(:test_class) do
    Class.new do |k|
      include Socialcast::Gitx::Github

      def say(message); end
    end
  end
  let(:said_messages) { [] }
  before do
    stub_const('TestClass', test_class)
    allow_any_instance_of(TestClass).to receive(:'`') do |_instance, _cmd|
      raise 'Unstubbed backticks detected'
    end
    allow_any_instance_of(TestClass).to receive(:say) do |_instance, message|
      said_messages << message
    end
  end
  let(:test_instance) { TestClass.new }
  let(:branch) { 'my-branch' }
  let(:base_branch) { 'master' }
  let(:repo) { 'ownername/projectname' }

  describe '#create_pull_request' do
    subject { test_instance.send(:create_pull_request, branch, repo, body) }
    let(:create_pr_payload) do
      {
        :title => branch,
        :base => base_branch,
        :head => branch,
        :body => body
      }
    end
    let(:dummy_pr_created_response) { { 'dummy' => 'response' } }
    let(:body) { 'This is my pull request.' }
    before do
      allow(test_instance).to receive(:base_branch).and_return(base_branch)
      expect(test_instance).to receive(:github_api_request).with('POST', 'repos/ownername/projectname/pulls', create_pr_payload.to_json).and_return(dummy_pr_created_response)
    end
    it { is_expected.to eq dummy_pr_created_response }
  end

  describe '#pull_requests_for_branch' do
    subject { test_instance.send(:pull_requests_for_branch, repo, branch) }
    let(:branch) { 'my-http-and-https-branch' }
    let(:dummy_pr_list_response) { [{ 'dummy' => 'response' }] }
    before do
      allow(test_instance).to receive(:authorization_token).and_return('abc123')
      expect_any_instance_of(RestClient::Request).to receive(:execute) do |instance|
        expect(instance.url).to eq 'https://api.github.com/repos/ownername/projectname/pulls?head=ownername:my-http-and-https-branch'
        '[{ "dummy": "response" }]'
      end
    end
    it { is_expected.to eq dummy_pr_list_response }
  end

  describe '#current_pr_for_branch' do
    subject(:current_pr) { test_instance.send(:current_pr_for_branch, repo, branch) }
    let(:dummy_pr_one) { { :dummy => :pr1 } }
    let(:dummy_pr_two) { { :dummy => :pr2 } }
    before do
      expect(test_instance).to receive(:pull_requests_for_branch).with(repo, branch).and_return(dummy_pr_list_response)
    end
    context 'when an empty pr list is returned' do
      let(:dummy_pr_list_response) { [] }
      it { is_expected.to be_nil }
    end
    context 'when a single pr is returned' do
      let(:dummy_pr_list_response) { [dummy_pr_one] }
      it { is_expected.to eq dummy_pr_one }
    end
    context 'when multiple prs are returned' do
      let(:dummy_pr_list_response) { [dummy_pr_one, dummy_pr_two] }
      it { expect { current_pr }.to raise_error 'Multiple (2) open PRs for my-branch found in ownername/projectname, unable to proceed' }
    end
  end

  describe '#assign_pull_request' do
    subject { test_instance.send(:assign_pull_request, assignee, issue_url) }
    let(:assignee) { 'janedoe' }
    let(:issue_url) { 'repos/ownername/projectname/issues/1' }
    let(:dummy_assignment_response) { [{ :dummy => :response }] }
    let(:assign_payload) { { :assignee => assignee } }
    before do
      expect(test_instance).to receive(:github_api_request).with('PATCH', 'repos/ownername/projectname/issues/1', assign_payload.to_json).and_return(dummy_assignment_response)
    end
    it { is_expected.to eq dummy_assignment_response }
  end

  describe '#comment_on_issue' do
    subject { test_instance.send(:comment_on_issue, issue_url, comment_body) }
    let(:issue_url) { 'repos/ownername/projectname/issues/1' }
    let(:dummy_comment_response) { { :dummy => :response } }
    let(:comment_payload) { { :body => comment_body } }
    let(:comment_body) { 'Integrating into staging' }
    before do
      expect(test_instance).to receive(:github_api_request).with('POST', 'repos/ownername/projectname/issues/1/comments', comment_payload.to_json).and_return(dummy_comment_response)
    end
    it { is_expected.to eq dummy_comment_response }
  end
end
