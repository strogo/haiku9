{sep} = require "path"
{curry, go, map, tee, async, include, read, glob} = require "fairmont"
{define, context} = require "panda-9000"
yaml = require "js-yaml"
loadYAML = async (path) -> yaml.safeLoad yield read path

Data =

  root: {}

  set: curry (path, value) ->
    head = Data.root
    [keys..., name] = path.split sep
    for key in keys when key != "."
      head[key] ?= {}
      head = head[key]
    head[name] = value

  get: (path) ->
    head = Data.root
    keys = path.split sep
    for key in keys when key != "."
      head = head[key]
      break unless head?
    head

  augment: (asset) ->
    asset.data.name = asset.name
    asset.data.path = asset.path
    include asset.data, Data.root, Data.get asset.path

define "data", async ->
  {source} = require "./configuration"
  yield go [
    glob "**/*.yaml", source
    map context source
    tee async (context) ->
      context.path = context.path.replace /(^|\/)_/, "$1"
      Data.set context.path, yield loadYAML context.source.path
  ]

module.exports = Data
