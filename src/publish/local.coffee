# Haiku9 relies on the MD5 message digest algorithm to create a hash for each
# file. We can then reference that hash to determine if data stored in an S3
# object needs to be updated.

mime = require "mime"
{async, lsR, collect, flow, map, pull, read, md5} = require "fairmont"
{target} = require "../configuration"

module.exports =

  # Produce a table of filenames and their md5 hashes.
  scan: async ->
    console.log "Scanning local repo."
    table = {}
    paths = yield lsR target
    hashes = yield collect flow [
      paths
      map (pathname) ->
        if "text" in mime.lookup(pathname)
          read pathname
        else
          read pathname, "buffer"
      pull
      map (content) -> md5 content
    ]

    for i in [0...paths.length]
      path = paths[i].split(target + "/")[1]   # Remove "target" path prefix
      table[path] = hashes[i]
    table

  # Produce an array of tasks to make the S3 bucket sync with the local files.
  reconcile: (local, remote) ->
    # Files need to be uploaded or deleted from S3.
    dlist = []
    ulist = []

    # Ignore keys that signify a directory, instead of a flat data object.
    delete remote[k] for k, v of remote when k.match /.*\/$/

    dlist.push k for k, v of remote when !local[k] && !local[k + ".html"]

    for k, v of local
      obj = k.split(".html")[0]    # In S3, file is stripped of ".html" ext
      ulist.push {file: k, hash: v} if !remote[obj] || v != remote[obj].hash

    {dlist, ulist}
