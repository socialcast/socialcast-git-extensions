[![Build Status](https://secure.travis-ci.org/socialcast/socialcast-git-extensions.png?branch=master)](http://travis-ci.org/socialcast/socialcast-git-extensions)
# socialcast-git-extensions

# Core Git Extensions

### Install
  `gem install socialcast-git-extensions`

  Test the installation by running

  `socialcast authenticate --domain (your domain)`

Where "(your domain)" would be the fully qualified domain name of the Socialcast community you will use for work e.g. [er.staging.socialcast.com](https://er.staging.socialcast.com)
#### GitHub Token Installation
Some of the extentions provided make use of the GitHub Application Token. When using commands such as [`git findpr`](https://github.com/socialcast/socialcast-git-extensions#git-findpr-) or [`git reviewrequest`](https://github.com/socialcast/socialcast-git-extensions#git-reviewrequest) the extensions will accept the credentials of the GitHub account and then install the GitHub token for you. If the GitHub account has two-factor authentication enabled then a manual installation of the GitHub Token is required.

#### Manual GitHub Token Installation
Access the [Application settings](https://github.com/settings/tokens) of your github.com account and select "*Generate new token*" or use an existing Github Application token. Store the token in  `~/.socialcast/credentials.yml`. Example:
```yaml
---
:domain: er.staging.socialcast.com
:proxy:
:user: person@example.com
:password: supersecret
:scgitx_token: 030000e600000000000000aaaaaaaaabbbbbbbbb
```

Test the token with the [`git findpr`](https://github.com/socialcast/socialcast-git-extensions#git-findpr-) command.

### Options
* ```--quiet```: suppress posting message in Socialcast
* config/scgitx.yml option `share_via_pr_comments`: Set to `true` to post reviewrequest and integration messages
as pull request comments instead of Socialcast posts.

## git start <new_branch_name (optional)>

update local repository with latest upstream changes and create a new feature branch

## git update

update the local feature branch with latest remote changes plus upstream released changes.

## git integrate <aggregate_branch_name (optional, default: prototype)>

integrate the current feature branch into an aggregate branch (ex: prototype, staging)

## git findpr <commit_hash>

Find pull requests on github including a given commit

## git branchdiff <branch> <base_branch (optional, default: master)>

List branches merged into remote origin/`branch` and not also merged into origin/`base_branch`

## git createpr

create a pull request on github for the current branch, without assigning it for review.

## git reviewrequest

create and assign a pull request on github for peer review of the current branch.  See `assignpr` for additional options.

## git assignpr

assign the pull request on github for the current branch for peer review.

### Optional:
Specify a Review Buddy mapping that will reference the local Github username and @mention a pre-assigned review buddy in the Socialcast Review Request message.  Specify the mapping by creating a .scgitx YML file relative to the Repo Root: config/scgitx.yml with the following format:

```yaml
review_buddies:
    emilyjames: # Github Username "emilyjames"
      socialcast_username: "EmilyJames" # Socialcast UserName
      buddy: bobdavis # Buddy's Github username
    bobdavis:
      socialcast_username: "BobDavis"
      buddy: emilyjames
```

In this example, when Emily runs `git reviewrequest` from her local machine, @BobDavis will receive an @mention in Socialcast notifying him to review her branch.  If Bob runs the command, Emily will receive a notice in Socialcast.

Additionally you can specify a specialty reviewer, such that you can
notify individuals in your organization with a specific skill set. Like Security, or API's

``` yaml
specialty_reviewers:
  a:
    label: API
    command: (a)pi
    socialcast_username: JohnSmith
  s:
    label: Security
    command: (s)ecurity
    socialcast_username: KellyWilliams
```

## git release

release the current feature branch to master

# Extra Git Extensions

## git cleanup

delete released branches after they have been merged into master.

## git nuke <aggregate_branch_name>

reset an aggregate branch (ex: prototype, staging) back to a known good state.


## Note on Patches/Pull Requests

* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so I don't break it in a
  future version unintentionally.
* Commit, do not mess with rakefile, version, or history.
  (if you want to have your own version, that is fine but bump version in a commit by itself I can ignore when I pull)
* Send me a pull request. Bonus points for topic branches.

## Copyright

Copyright (c) 2014 Socialcast, Inc. See LICENSE for details.

