# Description:
#   Allows Hubot to get information from Lunar Linux package manager.
#   It also integrates with lunar linux paste service.
#
# Dependencies:
#   "querystring":""
#   "child_process":""
#   "amqp":""
#
# Configuration:
#   HUBOT_PASTE_API_KEY
#   HUBOT_PASTE_CHANNEL
#
# Commands:
#   !help [lvu]
#   !lvu <what|where|website|sources|maintainer|verion> <module>
#
# Author:
#   Stefan Wold <ratler@lunar-linux.org>

{spawn} = require 'child_process'
qs = require 'querystring'
amqplib = require 'amqp'

api_key = process.env.HUBOT_PASTE_API_KEY
channel = process.env.HUBOT_PASTE_CHANNEL
lvu_pattern = 'what|where|website|sources|maintainer|version'
amqp_url = "amqp://" + process.env.HUBOT_RMQ_USER
amqp_url += ":" + process.env.HUBOT_RMQ_PASS
amqp_url += "@" + process.env.HUBOT_RMQ_HOST
amqp_url += "/" + process.env.HUBOT_RMQ_VHOST

responses = [
  "Your wish is my command master!",
  "Sure sure, want me to do your laundry while I'm at it as well?!",
  "Never any time for resting, I'm on it.",
  "Again?! Oh well I'll do it, but just for you!",
  "HA beat you to it, already working on that."
  ]


class Rmq
  constructor: (amqpURL) ->
    @exchange = 0
    @conn = amqplib.createConnection({url: amqpURL,
    reconnect: true,
    reconnectBackoffStrategy: 'linear',
    reconnectBacoffTime: 1000})

    @conn.on 'ready', () =>
      console.log("Connected to " + process.env.HUBOT_RMQ_HOST)
      @conn.exchange 'hubottopic', type: 'topic', (ex) =>
        console.log("Exchange ready")
        @exchange = ex
        @conn.queue 'hubot', autoDelete: false, (q) =>
          console.log("Queue ready")
          q.bind ex, '#'

  send: (message) ->
    if @exchange
      @exchange.publish '', message, {}, (err) ->
        console.log('Published message.')

module.exports = (robot) ->
  rmq = new Rmq amqp_url

  robot.hear /!help($|\s+\w+)/, (msg) ->
    what = msg.match[1].replace /^\s+|\s+$/g, ""
    if what == 'lvu'
      msg.reply "!lvu <#{lvu_pattern}> <module>"
    else
      msg.reply "Available commands: !help, !lvu"

  robot.hear new RegExp('^!lvu (' + lvu_pattern + ')($|\\s+[-\\w]+)', 'i'), (msg) ->
    cmd = msg.match[1]

    if cmd == 'help'
      msg.reply "!lvu <#{lvu_pattern}> <module>"
      return

    module = msg.match[2].replace /^\s+|\s+$/g, ""
    output = spawn "/bin/lvu", [cmd, module]

    output.stderr.on 'data', (data) ->
      if data.toString().match /Unable to find/i
        msg.reply "Module #{module} not found."
        return
    output.stdout.on 'data', (data) ->
      msg.reply data.toString().replace(/\n/g, " ")

  robot.hear /^!paste$/, (msg) ->
    msg.reply "http://devnull.lunar-linux.org"

  robot.respond /.*update.* moonbase.*/i, (msg) ->
    rmq.send 'update-moonbase'
    msg.reply msg.random responses

  robot.respond /update your self/i, (msg) ->
    console.log(process.cwd())
    output = spawn "/usr/bin/git", ['pull', '-q', 'origin', 'master']
    output.stderr.on 'data', (data) ->
      msg.reply "Update failed: " + data.toString().replace(/\n/g, " ")
      return
    output.on 'close', (code) ->
      if code == 0
        msg.emote "obeys his master (update OK)"

  # Paste related functions
  robot.router.get "/paste/notify", (req, res) ->
    if api_key? and channel?
      query = qs.parse(req._parsedUrl.query)

      if api_key == query.apikey and query.url?
        name = 'Anonymous'
        if query.name?
          name = query.name

        envelope = {}
        envelope.room = channel
        robot.send envelope, "#{name} has pasted something at #{query.url}"
    else
      console.log "Paste API key or channel not set."
    res.end "OK"
