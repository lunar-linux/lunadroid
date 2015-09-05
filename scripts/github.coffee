# Description:
#
# Commands:
#
# Author:
#   Stefan Wold <ratler@lunar-linux.org>

qs = require 'querystring'
crypto = require 'crypto'
ic = require 'irc-colors'

events = ['push', 'issues', 'pull_request', 'status']
SHARED_SECRET = process.env.HUBOT_GITHUB_SHARED_SECRET
GOOGL_KEY = process.env.HUBOT_GOOGL_KEY


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
  state = {
    opened: "New pull request"
    closed: " has closed the pull request"
    merged: " has merged the pull request"
  }

  if data.action of state
    if data.action == 'opened'
      state_msg = state[data.action]
    else if data.action == 'closed' and data.pull_request.merged
      state_msg = data.pull_request.merged_by.login
      state_msg += state['merged']
    else
      state_msg = data.sender.login
      state_msg += state[data.action]

    callback "[#{data.repository.name}] #{state_msg} '#{data.pull_request.title}' by #{data.pull_request.user.login}: #{data.pull_request.html_url}"

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

  getCommits robot, data.pull_request.commits_url, (commits) ->
    for c in commits
      if data.action == 'opened' or data.action == 'synchronize'
        github.add "#{repo}:#{c}", pr
        github.add "#{repo}:#{c}:title", data.pull_request.title
      else if data.action == 'closed'
        github.del "#{repo}:#{c}"
        github.del "#{repo}:#{c}:title"

shortenUrl = (robot, url, callback) ->
  if GOOGL_KEY?
    data = JSON.stringify longUrl: url
    params = {}
    params.key = GOOGL_KEY
    robot.http('https://www.googleapis.com/urlshortener/v1/url')
      .query(params)
      .header("Content-Type", "application/json")
      .post(data) (err, res, body) ->
        callback if err then url else JSON.parse(body).id
  else
    console.log("To enable URL shortening set HUBOT_GOOGL_KEY.")
    callback url

notifyCiStatus = (robot, github, data, callback) ->
  repo = data.repository.name
  commit = data.commit.sha
  url = data.repository.html_url
  target = data.target_url.split "/"
  shortenUrl robot, data.target_url + 'consoleText', (shortTargetUrl) ->
    pr = github.get "#{repo}:#{commit}"
    title = github.get "#{repo}:#{commit}:title"
    msg = "#{repo} build ##{target[6]}"

    if data.state == 'success'
      msg += " [" + ic.green 'SUCCESS' + "]"
    else if data.state == 'failure'
      msg += " [" + ic.red 'FAILED' + "]"

    msg += " - #{title} - [ CI: #{shortTargetUrl} ]"

    if pr
      shortenUrl robot, "#{url}/pull/#{pr}", (shortGitUrl) ->
        msg += " [ PR ##{pr}: #{shortGitUrl} ]"
        callback msg
    else
      callback msg

module.exports = (robot) ->
  github = new Github robot

  robot.hear /gh add (.+) (.+)/, (msg) ->
    github.add msg.match[1], msg.match[2]
    msg.reply "OK, added #{msg.match[1]}"

  robot.hear /gh del (\w+)/, (msg) ->
    github.del msg.match[1]
    msg.reply "OK, removed #{msg.match[1]}"

  robot.hear /gh get (\w+)/, (msg) ->
    msg.reply github.get msg.match[1]

  robot.hear /gh list/, (msg) ->
    msg.reply "Available keys: " + github.list().join(", ")

  robot.hear /googl ((https?|ftp):\/\/[^\s\/$.?#].[^\s]*)/, (msg) ->
    shortenUrl robot, msg.match[1], (shortUrl) ->
      msg.reply shortUrl

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
                notifyCiStatus robot, github, data, (msg) ->
                  robot.messageRoom room, msg
        catch error
          robot.messageRoom room, "Crap something went wrong: #{error}"
    else
      console.log("Unknown event #{event}, ignoring.")
    res.end ""
