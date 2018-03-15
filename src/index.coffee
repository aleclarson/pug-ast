fs = require 'fs'
lex = require 'pug-lexer'
parse = require 'pug-parser'

# TODO: Use https://github.com/oxyc/luaparse to inspect the code.
lex.Lexer::assertExpression = -> true

exports.ast = (filePath) ->
  parse lex fs.readFileSync filePath, 'utf8'

exports.transpile = require './transpile'
exports.lua = require './generate'
