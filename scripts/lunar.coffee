# Description:
#   Allows Hubot to get information from Lunar Linux package manager.
#   It also integrates with lunar linux paste service.
#
# Dependencies:
#   "querystring":""
#   "child_process":""
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

api_key = process.env.HUBOT_PASTE_API_KEY
channel = process.env.HUBOT_PASTE_CHANNEL

lvu_pattern = 'what|where|website|sources|maintainer|version'

module.exports = (robot) ->
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
