# Brow

A generic background thread worker for shipping events via https to some API backend. It'll get events to your API by the sweat of its brow.

I've been wanting to build something like this for a while. This might be a terrible start. But its a start.

I noticed a lot of companies copied segment's [analytics-ruby](https://github.com/segmentio/analytics-ruby) project and are using it successfully.

So that's where I began. Seems safe to assume that project has been around long enough and is production hardened enough. I guess I'll find out. :)

Things around here are pretty basic for now. But I'm looking to spruce it up and production test it over the coming months &mdash; likely with [Flipper](https://github.com/jnunemaker/flipper) and [Flipper Cloud](https://www.flippercloud.io/?utm_source=brow&utm_medium=web&utm_campaign=readme).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'brow'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install brow

## Usage

```ruby
require "brow"

client = Brow::Client.new({
  url: "https://requestbin.net/r/rna67for",
})

50.times do |n|
  client.push({
    number: n,
    now: Time.now.utc,
  })
end

# batch of 50 events sent to api url above as json
client.flush
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jnunemaker/brow.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
