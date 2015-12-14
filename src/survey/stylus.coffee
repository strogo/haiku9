{go, map, tee, reject,
include, Type, isType, isMatch,
Method,
glob} = require "fairmont"
{define} = Method
{task, context, stylus} = require "panda-9000"
{save, render} = Asset = require "../asset"
{pathWithUnderscore} = require "../utils"
{source} = require "../configuration"

type = Type.define Asset

task "survey/stylus", ->
  go [
    glob "**/*.styl", source
    reject pathWithUnderscore
    map context source
    tee ({target}) -> target.extension = ".css"
    map (context) -> include (Type.create type), context
    tee save
  ]

define render, (isType type), stylus
