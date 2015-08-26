require 'spec_helper'

describe Socialcast::Gitx::Git do
  before do
    stub_const 'TestClass', Class.new { |k| include Socialcast::Gitx::Git }
    allow_any_instance_of(TestClass).to receive(:'`') do |_instance, _cmd|
      raise 'Unstubbed backticks detected'
    end
  end
  let(:test_instance) { TestClass.new }
  subject { test_instance }

  describe '#changelog_summary' do
    subject { test_instance.send(:changelog_summary, branch) }
    let(:base_branch) { 'master' }
    let(:branch) { 'my-branch' }
    let(:numstat_command) { 'git diff --numstat origin/master...my-branch' }
    let(:shortstat_command) { 'git diff --shortstat origin/master...my-branch' }
    before do
      allow(test_instance).to receive(:base_branch).and_return(base_branch)
      expect(test_instance).to receive(:'`').with(numstat_command).and_return(numstat_output)
      expect(test_instance).to receive(:'`').with(shortstat_command).and_return(shortstat_output)
    end
    context 'when fewer than 6 files are changed' do
      let(:shortstat_output) do
        <<-EOS.strip_heredoc
          5 files changed, 34 insertions(+), 129 deletions(-)
        EOS
      end
      let(:numstat_output) do
        <<-EOS.strip_heredoc
          11      4       engines/shoelaces/app/models/hightop.rb
          21      4       engines/shoelaces/spec/models/hightop_spec.rb
          2       2       engines/shoelaces/spec/models/bowling_spec.rb
          0       58      lib/tasks/images.rake
          0       61      script/img_dev.rb
        EOS
      end
      it 'shows file level detail and overall stats' do
        is_expected.to eq <<-EOS.strip_heredoc
          engines/shoelaces/app/models/hightop.rb | 11+ 4-
          engines/shoelaces/spec/models/hightop_spec.rb | 21+ 4-
          engines/shoelaces/spec/models/bowling_spec.rb | 2+ 2-
          lib/tasks/images.rake | 0+ 58-
          script/img_dev.rb | 0+ 61-
          5 files changed, 34 insertions(+), 129 deletions(-)
        EOS
      end
    end

    context 'when 6 or more files are changed' do
      let(:shortstat_output) do
        <<-EOS.strip_heredoc
          6 files changed, 35 insertions(+), 129 deletions(-)
        EOS
      end
      let(:numstat_output) do
        <<-EOS.strip_heredoc
          11      4       engines/shoelaces/app/models/hightop.rb
          21      4       engines/shoelaces/spec/models/hightop_spec.rb
          2       2       engines/shoelaces/spec/models/bowling_spec.rb
          0       58      lib/tasks/images.rake
          0       61      script/img_dev.rb
          1       0       doc/images.md
        EOS
      end
      it 'summarizes the changes by directory' do
        is_expected.to eq <<-EOS.strip_heredoc
          engines/shoelaces/spec/models (2 files)
          lib/tasks (1 file)
          script (1 file)
          doc (1 file)
          engines/shoelaces/app/models (1 file)
          6 files changed, 35 insertions(+), 129 deletions(-)
        EOS
      end
    end
  end
end
