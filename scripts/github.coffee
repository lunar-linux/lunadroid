# Description:
#
# Commands:
#
# Author:
#   Stefan Wold <ratler@lunar-linux.org>

qs = require 'querystring'
crypto = require 'crypto'

events = ['push', 'issues', 'pull_request', 'status']
SHARED_SECRET = process.env.HUBOT_GITHUB_SHARED_SECRET


class Github
  constructor: (@robot) ->
    @robot.brain.on 'loaded', =>
      @cache = @robot.brain.data.ghdata ||= {}

  add: (key, val) ->
    unless @cache[key]?
      @cache[key] = val
      @robot.brain.data.ghdata = @cache

  del: (key) ->
    if @cache[key]?
      delete @cache[key]
      @robot.brain.data.ghdata = @cache

  get: (key) ->
    @cache[key]

  list: ->
    Object.keys(@cache)


zip = () ->
  lengthArray = (arr.length for arr in arguments)
  length = Math.min(lengthArray...)
  for i in [0...length]
    arr[i] for arr in arguments

compareTimeEqual = (a, b) ->
  if a.length != b.length
    return false
  result = 0
  for [x, y] in zip(a, b)
    result |= x ^ y
  return result == 0

notifyPullRequest = (data, callback) ->
  if data.action == 'opened'
    callback "[#{data.repository.name}] New pull request '#{data.pull_request.title}' by #{data.pull_request.user.login}: #{data.pull_request.html_url}"

getCommits = (robot, url, callback) ->
  robot.http(url).get() (err, res, body) ->
    commits = []
    unless err
      for commit in JSON.parse body
        commits.push commit.sha
    callback commits

pullRequestState = (robot, github, data) ->
  repo = data.repository.name
  pr = data.number

  switch data.action
    # fetch and keep state of commits
    when 'opened'
      getCommits robot, data.pull_request.commits_url, (commits) ->
        for c in commits
          github.add "#{repo}:#{c}", pr
    when 'synchronize'
      getCommits robot, data.pull_request.commits_url, (commits) ->
        for c in commits
          github.add "#{repo}:#{c}", pr
    when 'closed'
      getCommits robot, data.pull_request.commits_url, (commits) ->
        for c in commits
          github.del "#{repo}:#{c}"

notifyCiStatus = (github, data, callback) ->
  repo = data.repository.name
  commit = data.commit.sha
  url = data.repository.html_url
  target = data.target_url.split "/"
  target_url = data.target_url + 'consoleText'
  pr = github.get "#{repo}:#{commit}"
  msg = "#{repo} build ##{target[6]}:"

  if data.state == 'success'
    msg += " SUCCESS: #{target_url}"
    if pr
      pull_url = "#{url}/pull/#{pr}"
      msg += " [ PR: #{pull_url} ]"
  else if data.state == 'failure'
    msg += " FAILED: #{target_url}"
    if pr
      pull_url = "#{url}/pull/#{pr}"
      msg += " [ PR: #{pull_url} ]"
  callback msg

module.exports = (robot) ->
  github = new Github robot

  robot.hear /gh add (\w+) (.*)/, (msg) ->
    github.add msg.match[1], msg.match[2]
    msg.reply "OK, added #{msg.match[1]}"

  robot.hear /gh del (\w+)/, (msg) ->
    github.del msg.match[1]
    msg.reply "OK, removed #{msg.match[1]}"

  robot.hear /gh get (\w+)/, (msg) ->
    msg.reply github.get msg.match[1]

  robot.hear /gh list/, (msg) ->
    msg.reply "Available keys: " + github.list().join(", ")

  # Event listener for github
  robot.router.post '/github/api/:room', (req, res) ->
    if not SHARED_SECRET?
      console.log("Please set env HUBOT_GITHUB_SHARED_SECRET")
      res.end ""
      return
    if not req.headers['x-github-event']?
      res.end ""
      return

    event = req.headers['x-github-event']

    if event in events
      data = req.body
      room = req.params.room
      ghSig = req.headers['x-hub-signature']
      hmac = crypto.createHmac 'sha1', SHARED_SECRET
      sig = 'sha1=' + hmac.update(JSON.stringify req.body).digest('hex')

      # Validate HMAC before doing anything else using a "somewhat" safe compare method
      # to avoid timing attacks
      if compareTimeEqual ghSig, sig
        try
          switch event
            when 'pull_request'
              pullRequestState robot, github, data
              notifyPullRequest data, (msg) ->
                robot.messageRoom room, msg
            when 'status'
              if data.state == 'success' or data.state == 'failure'
                notifyCiStatus github, data, (msg) ->
                  robot.messageRoom room, msg
        catch error
          robot.messageRoom room, "Crap something went wrong: #{error}"
    else
      console.log("Unknown event #{event}, ignoring.")
    res.end ""
