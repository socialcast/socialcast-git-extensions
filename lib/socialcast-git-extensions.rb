require 'rubygems'
require 'socialcast-git-extensions/version'
require 'socialcast-git-extensions/string_ext'
require 'socialcast-git-extensions/git'
require 'socialcast-git-extensions/github'

module Socialcast
  module Gitx
    DEFAULT_BASE_BRANCH = 'master'
    DEFAULT_STAGING_BRANCH = 'staging'
    DEFAULT_LAST_KNOWN_GOOD_STAGING_BRANCH = 'last_known_good_staging'
    DEFAULT_PROTOTYPE_BRANCH = 'prototype'

    private

    # execute a shell command and raise an error if non-zero exit code is returned
    def run_cmd(cmd)
      say "\n$ "
      say cmd.gsub("'", ''), :red
      raise "#{cmd} failed" unless system cmd
    end

  end
end
