jade    = require 'jade'
sysPath = require 'path'
mkdirp  = require 'mkdirp'
fs      = require 'fs'

# for the notification of errors
color   = require("ansi-color").set
growl   = require 'growl'

i18n = require "i18n"

fromJade2Html = (jadeFilePath, config, locale, callback) ->
  try
    fs.readFile jadeFilePath, (err,data) ->
      i18n.setLocale locale
      #TODO: Add filters that work
      #jade.filters["translate"] = (str) ->
      #  i18n.__(str)
      content = jade.compile data,
        compileDebug: no,
        filename: jadeFilePath,
        pretty: !!config.plugins?.jade?.pretty
      locals = "__": i18n.__
      res = content(locals)
      callback err, res
  catch err
    callback err

logError = (err, title) ->
  title = 'Brunch jade error' if not title?
  if err?
    console.log color err, "red"
    growl err , title: title

fileWriter = (newFilePath) -> (err, content) ->
  throw err if err?
  return if not content?
  dirname = sysPath.dirname newFilePath
  mkdirp dirname, '0775', (err) ->
    throw err if err?
    fs.writeFile newFilePath, content, (err) -> throw err if err?


isArray = (obj) ->
 !!(obj and obj.concat and obj.unshift and not obj.callee)

# -------------------- from brunch/lib/helpers --------------------------------
extend = (object, properties) ->
  Object.keys(properties).forEach (key) ->
    object[key] = properties[key]
  object

loadPackages = (rootPath, callback) ->
  rootPath = sysPath.resolve rootPath
  nodeModules = "#{rootPath}/node_modules"
  fs.readFile sysPath.join(rootPath, 'package.json'), (error, data) ->
    return callback error if error?
    json = JSON.parse(data)
    deps = Object.keys(extend(json.devDependencies ? {}, json.dependencies))
    try
      plugins = deps.map (dependency) -> require "#{nodeModules}/#{dependency}"
    catch err
      error = err
    callback error, plugins
#------------------------------------------------------------------------------


module.exports = class StaticJadeCompiler
  brunchPlugin: yes
  type: 'template'
  extension: ".jade"

  constructor: (@config) ->
    @extension    = @config.plugins?.static_jade?.extension ? ".jade"
    @relAssetPath = @config.plugins?.static_jade?.asset ? "app/assets"
    @locales      = @config.plugins?.i18n?.locales ? ['en', 'de']
    mkdirp.sync @relAssetPath
    StaticJadeCompiler::extension = @extension
    StaticJadeCompiler::config = @config
    StaticJadeCompiler::locales = @locales

    # static-jade-brunch must co-exist with jade-brunch plugin
    loadPackages process.cwd(), (error, packages) ->
      throw error if error?
      if "JadeCompiler" not in (p.name for p in packages)
        error = """
          `jade-brunch` plugin needed by `static-jade-brunch` \
          doesn't seems to be present.
          """
        logError error, 'Brunch plugin error'
        errmsg = """
          * Check that package.json contain the `jade-brunch` plugin
          * Check that it is correctly installed by using `npm list`"""
        console.log color errmsg, "red"
        throw error

    # Since this is running on the server, at compile time, we want to generate
    # the json files with untranslated strings.
    i18n.configure 
      locales: @locales
      updateFiles: true

  getDependencies: (data, path, callback) ->
    logError path
    return path.startsWith "locales"

  isFileToCompile: (filePath) ->
    if (@config.plugins?.static_jade?.path?)
      if isArray @config.plugins.static_jade.path
        fileDir = sysPath.dirname filePath
        positivePaths = (p for p in @config.plugins.static_jade.path when p.test fileDir)
        return no if positivePaths.length == 0

    fileName = sysPath.basename filePath
    fileName[-@extension.length..] == @extension

  getHtmlFilePath: (jadeFilePath, relAssetPath, locale) ->
    util = require 'util'
    # placing the generated files in 'asset' dir,
    # brunch would trigger the auto-reload-brunch only for them
    # without require to trigger the plugin from here
    relativeFilePathParts = jadeFilePath.split sysPath.sep
    # Add a locale specific extension unless it's the index
    ext = ".html"
    unless relativeFilePathParts[relativeFilePathParts.length - 1] == "index.jade"
      ext = ".#{locale}" + ext
    relativeFilePathParts.push(
      relativeFilePathParts.pop()[...-@extension.length] + ext )
    relativeFilePath = sysPath.join.apply this, relativeFilePathParts[1...]
    newpath = sysPath.join relAssetPath, relativeFilePath
    return newpath

  onCompile: (changedFiles) ->
    changedFiles.every (file) =>
      filesToCompile =
        f.path for f in file.sourceFiles when StaticJadeCompiler::isFileToCompile f.path
      for jadeFileName in filesToCompile
        # For each locale, create a different html
        for locale in @locales
          newFilePath = StaticJadeCompiler::getHtmlFilePath jadeFileName, @relAssetPath, locale
          try
            fromJade2Html jadeFileName, @config, locale, fileWriter newFilePath
          catch err
            logError err
            null
