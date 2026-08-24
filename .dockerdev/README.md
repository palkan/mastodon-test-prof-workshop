# Docker for Development

Source: [Ruby on Whales: Dockerizing Ruby and Rails development](https://evilmartians.com/chronicles/ruby-on-whales-docker-for-ruby-rails-development).

This environment is meant for one thing: running the Mastodon test suite (RSpec) in containers.

## Installation

- Docker installed.

For MacOS just use the [official app](https://docs.docker.com/engine/installation/mac/).

- [`dip`](https://github.com/bibendi/dip) installed.

You can install `dip` as Ruby gem:

```sh
gem install dip
```

## Provisioning

When using Dip it could be done with a single command:

```sh
dip provision
```

This builds the Docker image, installs Ruby and JS dependencies, prepares the development
and test databases, and precompiles assets for the test environment.

## Running tests

```sh
# run the whole suite
dip rspec

# run a particular spec file
dip rspec spec/models/account_spec.rb

# run tests without a TTY (useful for benchmarking, e.g., with hyperfine)
dip rspec:notty spec/models/account_spec.rb
```

## Developing with Dip

### Useful commands

```sh
# run rails console
dip rails c

# run migrations
dip rails db:migrate

# pass env variables into application
dip VERSION=20100905201547 rails db:migrate:down

# simply launch bash within app directory (with dependencies up)
dip runner

# execute an arbitrary command via Bash
dip bash -c 'ls -al tmp/cache'

# Additional commands

# update gems or packages
dip bundle install
dip yarn install

# run psql console
dip psql

# run Redis console
dip redis-cli

# shutdown all containers
dip down
```

### Development flow

Another way is to run `dip <smth>` for every interaction. If you prefer this way and use ZSH, you can reduce the typing
by integrating `dip` into your session:

```sh
$ dip console | source /dev/stdin
# no `dip` prefix is required anymore!
$ rspec spec/models/account_spec.rb
```
