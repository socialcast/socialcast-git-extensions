require 'rubygems'
require 'ostruct'
require 'bundler/setup'
require 'rspec/mocks'
require 'webmock/rspec'
require 'pry'
require 'byebug'
require 'socialcast-git-extensions/cli'

ENV['SCGITX_TEST'] = 'true'

RSpec.configure do |config|
  config.mock_with :rspec

  config.before do
    ## Needed because object does not have permalink url until after it has been posted
    allow_any_instance_of(Socialcast::CommandLine::Message).to receive(:permalink_url).and_return('http://demo.socialcast.com/messages/123')
  end

  def capture_with_status(stream)
    exit_status = 0
    begin
      stream = stream.to_s
      eval "$#{stream} = StringIO.new"
      begin
        yield
      rescue SystemExit => system_exit # catch any exit calls
        exit_status = system_exit.status
      end
      result = eval("$#{stream}").string
    ensure
      eval("$#{stream} = #{stream.upcase}")
    end
    return result, exit_status
  end

  def remove_directories(*names)
    project_dir = Pathname.new(Dir.pwd)
    names.each do |name|
      FileUtils.rm_rf(project_dir.join(name)) if FileTest.exists?(project_dir.join(name))
    end
  end
end
