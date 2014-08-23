// Generated by CoffeeScript 1.7.1
(function() {
  var Asset, C50N, Evie, FileSystem, basename, extname, glob, join, md2html, _ref;

  FileSystem = require("fs");

  _ref = require("path"), basename = _ref.basename, extname = _ref.extname, join = _ref.join;

  glob = require("panda-glob");

  Evie = require("evie");

  md2html = require("marked");

  C50N = require("c50n");

  Asset = (function() {
    Asset.events = new Evie;

    Asset.read = function(path) {
      return this.events.source(function(events) {
        return FileSystem.readFile(path, {
          encoding: "utf8"
        }, function(error, content) {
          if (error == null) {
            return events.emit("success", new Asset(path, content));
          } else {
            return events.emit("error", error);
          }
        });
      });
    };

    Asset.readFiles = function(files) {
      return this.events.source(function(events) {
        return Asset.events.serially(function(go) {
          go(function() {
            return Asset.events.concurrently(function(go) {
              var file, _i, _len, _results;
              _results = [];
              for (_i = 0, _len = files.length; _i < _len; _i++) {
                file = files[_i];
                _results.push(go(file, function() {
                  return Asset.read(file);
                }));
              }
              return _results;
            })();
          });
          return go(function(assets) {
            return events.emit("success", assets);
          });
        })();
      });
    };

    Asset.readDir = function(path) {
      return this.events.source(function(events) {
        return FileSystem.readdir(path, function(error, files) {
          var file;
          if (error == null) {
            return Asset.readFiles((function() {
              var _i, _len, _results;
              _results = [];
              for (_i = 0, _len = files.length; _i < _len; _i++) {
                file = files[_i];
                _results.push(join(path, file));
              }
              return _results;
            })()).forward(events);
          } else {
            return events.emit("error", error);
          }
        });
      });
    };

    Asset.glob = function(path, pattern) {
      return this.events.source(function(events) {
        return events.safely(function() {
          var file;
          return Asset.readFiles((function() {
            var _i, _len, _ref1, _results;
            _ref1 = glob(path, pattern);
            _results = [];
            for (_i = 0, _len = _ref1.length; _i < _len; _i++) {
              file = _ref1[_i];
              _results.push(join(path, file));
            }
            return _results;
          })()).forward(events);
        });
      });
    };

    Asset.registerFormatter = function(_arg, formatter) {
      var from, to, _base;
      to = _arg.to, from = _arg.from;
      if (this.formatters == null) {
        this.formatters = {};
      }
      if ((_base = this.formatters)[from] == null) {
        _base[from] = {};
      }
      return this.formatters[from][to] = formatter;
    };

    function Asset(path, content) {
      var divider, error, extension, frontmatter;
      this.path = path;
      extension = extname(this.path);
      this.key = basename(this.path, extension);
      this.format = Asset.extensions[extension.slice(1)];
      divider = content.indexOf("\n---\n");
      if (divider >= 0) {
        frontmatter = content.slice(0, +(divider - 1) + 1 || 9e9);
        try {
          this.data = C50N.parse(frontmatter);
        } catch (_error) {
          error = _error;
          Asset.events.emit("error", error);
        }
        this.content = content.slice(divider + 5);
      }
    }

    Asset.prototype.render = function(format, context) {
      var _ref1;
      if (context == null) {
        context = this.context;
      }
      return (_ref1 = Asset.formatters[this.format]) != null ? typeof _ref1[format] === "function" ? _ref1[format](this.content, this.context) : void 0 : void 0;
    };

    return Asset;

  })();

  Asset.extensions = {
    md: "markdown"
  };

  Asset.registerFormatter({
    to: "html",
    from: "markdown"
  }, function(markdown) {
    return Asset.events.source(function(events) {
      return events.emit("success", md2html(markdown));
    });
  });

  module.exports = Asset;

}).call(this);