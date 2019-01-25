require 'roda'
require 'json'
require 'cinch'

class GithubHookProcessor < Roda
  SECRET = ENV.delete('GITHUB_HOOKS_SECRET').freeze

  CHANNELS = {
    'sequel' => '#sequel',
    'sequel_pg' => '#sequel',
    'forme' => '#forme',
    'autoforme' => '#forme',
    'roda' => '#roda',
    'rodauth' => '#rodauth',
  }.freeze

  BOT = Cinch::Bot.new do
    configure do |c|
      c.sasl.username = "jeremye-gitbot"
      c.sasl.password = ENV.delete("GITHUB_HOOKS_IRC_PASSWORD")
      c.realname = "Jeremy Evans GitHubBot"
      c.nick = "jeremye-gitbot"
      c.server = "irc.freenode.org"
      c.channels = CHANNELS.values.uniq
      c.ssl.use = true
      c.port = 6697
    end
  end

  Thread.new{BOT.start}

  TYPES = %w'ping create push issues issue_comment pull_request commit_comment page_build'.freeze

  ROUTE = ENV.delete('GITHUB_HOOKS_ROUTE').freeze

  route do |r|
    r.post ROUTE do
      r.body.rewind
      payload_body = r.body.read
      unless valid_signature?(payload_body)
        response.status = 400
        next "Signatures didn't match!"
      end

      data = JSON.parse(payload_body)
      repo = data["repository"]["name"]

      type = env['HTTP_X_GITHUB_EVENT']
      if TYPES.include?(type)
        send(:"handle_#{type}", data, repo)
        response.status = 204
        ''
      else
        response.status = 400
        next "Event type not recognized"
      end
    end

    response.status = 404
    "Page Not Found"
  end

  def handle_ping(data, repo)
    # nothing
  end

  def handle_create(data, repo)
    ref = data['ref']
    ref_type = data['ref_type']
    say(repo, "#{repo}: #{ref_type} #{ref} created")
  end

  def handle_push(data, repo)
    branch = data["ref"].gsub(/^refs\/heads\//,"")
    commits = data["commits"]

    commits.slice!(0..5).each do |c|
      say(repo, "#{repo}/#{branch}: #{c["author"]["name"]} committed: #{format(c["message"])} #{c['url']}")
    end
    unless commits.empty?
      say(repo, "#{repo}/#{branch}: ... and #{commits.length} more commits added #{data['compare']}")
    end
  end

  def handle_issues(data, repo)
    issue = data['issue']
    action = data['action']
    n = issue['number']
    title = issue['title']
    user = data['sender']['login']
    url = issue['html_url']

    say(repo, "#{repo}: issue ##{n} #{action} by #{user}: #{format(title)} #{url}")
  end

  def handle_issue_comment(data, repo)
    issue = data['issue']
    comment = data['comment']
    action = data['action']
    n = issue['number']
    user = data['sender']['login']
    body = comment['body']
    url = comment['html_url']

    say(repo, "#{repo}: comment on issue ##{n} #{action} by #{user}: #{format(body)} #{url}")
  end

  def handle_pull_request(data, repo)
    pr = data['pull_request']
    action = data['action']
    n = pr['number']
    title = pr['title']
    user = data['sender']['login']
    url = pr['html_url']

    say(repo, "#{repo}: pull request ##{n} #{action} by #{user}: #{format(title)} #{url}")
  end

  def handle_commit_comment(data, repo)
    action = data['action']
    comment = data['comment']
    body = comment['body']
    user = data['sender']['login']
    url = comment['html_url']

    say(repo, "#{repo}: comment on commit #{action} by #{user}: #{format(body)} #{url}")
  end

  def handle_page_build(data, repo)
    status = data['build']['status']
    if error = data['build']['error']['message']
      error = format(error)
    end
    say(repo, "#{repo}: pages #{status} #{error}")
  end

  def format(msg)
    msg.split(/(\r?\n)(\r?\n)/, 2).
      first.
      to_s.
      gsub(/\s+/, ' ')[0..150]
  end

  def say(repo, msg)
    return unless channel = CHANNELS[repo]
    BOT.Channel(channel).send(msg)
  end

  def valid_signature?(payload_body)
    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), SECRET, payload_body)
    Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
  end
end
