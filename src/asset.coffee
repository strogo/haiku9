{include, read, read_buffer, write, readdir, async, keys,
  first, rest, collect, map, binary, curry} = require "fairmont"
{createReadStream} = require "fs"
{basename, extname, join} = require "path"
join = curry binary join
{attempt, promise} = require "when"
glob = require "panda-glob"
md2html = require "marked"
jade = require "jade"
stylus = require "stylus"
yaml = require "js-yaml"
CoffeeScript = require "coffee-script"


class Asset

  @create: (path) -> new Asset path

  @map: (paths) ->
    (Asset.create path) for path in paths

  @readDir: async (path) ->
    files = yield readdir path
    Asset.map (collect map (join path), files)

  @glob: (path, pattern) ->
    files = glob path, pattern
    Asset.map (collect map (join path), files)

  @registerFormatter: ({to, from}, formatter) ->
    @formatters ?= {}
    @formatters[from] ?= {}
    @formatters[from][to] = formatter
    @formatsFor ?= {}
    @formatsFor[to] ?= []
    @formatsFor[to].push from

  @formatterFor: (source, target) ->
    formatter = Asset.formatters[source]?[target]
    formatter ?= Asset.identityFormatter

  @registerExtension: ({extension, format}) ->
    Asset.extensions ?= {}
    Asset.extensions[extension] = format
    Asset.extensionFor ?= {}
    Asset.extensionFor[format] = extension

  @extensionsForFormat: (format) ->
    formats = @formatsFor[format]
    if formats?
      for format in [format, formats...]
        @extensionFor[format]
    else
      [format]

  @patternForFormat: (format, name="*") ->
    @patternForFormats [format], name

  @patternForFormats: (formats, name="*") ->
    extensions = map (format) => @extensionsForFormat format
    "#{name}.{#{collect extensions formats},}"

  @globNameForFormat: (path, name, formats...) ->
     Asset.glob path, Asset.patternForFormats formats, name

  constructor: (@path) ->
    extension = extname @path
    @extension = rest extension
    @key = basename @path, extension
    @format = Asset.extensions[@extension]
    @format ?= @extension
    @target = {}
    formatters = Asset.formatters[@format]
    @target.format = if formatters? then first keys formatters else @format
    @target.extension = Asset.extensionFor[@target.format]
    @target.extension ?= @target.format
    @context = {}

  targetPath: (path) ->
    if @target.extension?
      join path, "#{@key}.#{@target.extension}"
    else
      join path, @key

  write: async (path) ->
    write (@targetPath path), yield @render()

    # divider = content.indexOf("\n---\n")
    # if divider >= 0
    #   frontmatter = content[0...divider]
    #   try
    #     @data = yaml.safeLoad frontmatter
    #   catch error
    #     @data = {}
    #   @content = content[(divider+5)..]
    # else
    #   @content = content

  render: ->
    ((Asset.formatterFor @format, @target.format) @)

Asset.registerExtension extension: "md", format: "markdown"
Asset.registerExtension extension: "jade", format: "jade"
Asset.registerExtension extension: "styl", format: "stylus"
Asset.registerExtension extension: "coffee", format: "coffeescript"
Asset.registerExtension extension: "js", format: "javascript"

Asset.identityFormatter = async ({path}) -> yield read_buffer path

Asset.registerFormatter
  to: "html"
  from:  "markdown"
  async ({path}) -> md2html (yield read path)

Asset.registerFormatter
  to: "html"
  from:  "jade"
  ({path, context}) ->
    context.cache = false
    jade.renderFile path, context

Asset.registerFormatter
  to: "css"
  from:  "stylus"
  async ({path}) ->
    stylus (yield read path)
    .set "filename", path
    .render()

Asset.registerFormatter
  to: "javascript"
  from:  "coffeescript"
  async ({path}) ->
    CoffeeScript.compile (yield read path)

module.exports = Asset
