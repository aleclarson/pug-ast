escape_html = require 'escape-html'

# Generate a render function and associated mixin functions.
# Returns a JSON string shaped like {render, mixins}
generate = (ast) ->
  tpl = new PugBlock
  tpl.lua = ['return function(_R, _E, _G)\n']
  tpl.mixins = {} # mixin name => mixin code

  generators.Block.call tpl, ast

  render: tpl.lua.join ''
  mixins: tpl.mixins

module.exports = generate

# `class` and `style` are never escaped.
noEscapeRE = /^(?:class|style)$/
newlineRE = /\n/g
dquoteRE = /"/g

generators =

  Block: ({ nodes }) ->
    if nodes.length
      @indent()
      for node in nodes
        generators[node.type].call this, node
      @dedent()
      return

  Text: (node) ->
    @pushln '_R:push("' + repr(node.val) + '")'
    return

  # TODO: Check if all attributes are static.
  # TODO: Check if all child nodes are static.
  # TODO: Only call `push_env` if variables are declared by children
  Tag: (node) ->
    # Track if the tag has dynamic attributes/content.
    dynamic = has_dynamic_attrs node

    if node.name
      @push @tab + '_R:push("<' + node.name
      @push '")\n' if dynamic
    else
      @pushln '_R:push("<")'
      @pushln "_R:push(#{node.expr})"

    if node.attrs[0] or node.attributeBlocks[0]
      blocks.Attributes.call this, node, dynamic

    if dynamic or node.expr
      @push @tab + '_R:push("'

    if node.selfClosing
      @push '/>")\n'
      return

    {block} = node
    if block.nodes[0]
      @push '>")\n'

      # Push a new scope if a child has code.
      has_scope = find_child(block.nodes, has_code)?

      @pushln 'do'
      @pushln '  _R:push_env()' if has_scope
      generators.Block.call this, block
      @pushln '  _R:pop_env()' if has_scope
      @pushln 'end'

      @push @tab + '_R:push("'

    else @push '>'

    if node.name
      @push '</' + node.name + '>")\n'
    else
      @push '</")\n'
      @pushln "_R:push(tostring(#{node.expr}))"
      @pushln '_R:push(">")'
    return

  Attributes: (node, dynamic) ->

    if dynamic
      @pushln '_R:attrs({'
      @indent()

      for attr in node.attrs
        {name, val} = attr
        name = name.toLowerCase()
        if attr.mustEscape and not noEscapeRE.test name
          val = "escape(#{val})"
        @pushln "['#{name}'] = #{val},"

      blocks = node.attributeBlocks
      if blocks[0]
        blocks = blocks.map (block) =>
          block.val.replace newlineRE, '\n' + @tab
        @dedent()
        @pushln "}, #{blocks.join ', '})"
      else
        @dedent()
        @pushln '})'
      return

    for attr in node.attrs
      {name, val} = attr
      name = name.toLowerCase()
      if attr.mustEscape and not noEscapeRE.test name
        val = "\"#{escape_html val.slice 1, -1}\""
      @push " #{name}=#{val}"
    return

    # for attr in node.attrs
    #   attr.name
    #   repr(attr.val)
    #   attr.mustEscape

    # for block in node.attributeBlocks
    #

    return

  Code: (node) ->
    if node.buffer
      tostring = if node.mustEscape then 'escape' else 'tostring'
      @pushln "_R:push(#{tostring}(#{node.val}))"
    else
      @push @tab + node.val.replace newlineRE, '\n' + @tab
    return

  Conditional: (node) ->
    i = -1
    loop
      @pushln "#{if ++i then 'elseif' else 'if'} #{node.test} then\n"
      generators.Block.call this, node.consequent

      break unless node = node.alternate
      unless node.test
        @pushln 'else'
        generators.Block.call this, node

    @pushln 'end'
    return

    # TODO: Check if test:sub(1, 1) == '!'
    # test, consequent, alternate

  Case: (node) ->
    {nodes} = node.block

    # Evaluate the expression once.
    @pushln 'local __expr = ' + node.expr

    i = -1
    expr = []
    for node in nodes

      if case_node.expr is 'default'
        @pushln 'else'
        generators.Block.call this, case_node.block
        break

      expr.push case_node.expr + ' == __expr'
      if case_node.block
        keyword = if ++i then 'elseif ' else 'if '
        if expr.length > 1
        then @pushln keyword + '(' + expr.join(') or (') + ') then'
        else @pushln keyword + expr[0] + ' then'
        expr.length = 0
        generators.Block.call this, case_node.block

    @pushln 'end'
    return

  Each: (node) ->
    {obj} = node
    unless obj.startsWith 'ipairs('
      obj = "__each(#{obj})"

    args = node.key
    if args then args += ', ' + node.val
    else args = node.val

    @pushln "for #{args} in #{obj} do"
    generators.Block.call this, node.block
    @pushln 'end'
    return

  While: (node) ->
    @pushln "while #{node.test} do"
    generators.Block.call this, node.block
    @pushln 'end'
    return

  Mixin: (node) ->

    if node.call
      unless @mixins[node.name]
        # TODO: Include code snippet and location.
        throw Error "Cannot call undeclared mixin: '#{node.name}'"
      # TODO: args, attrs, attributeBlocks
      attrs = node.attributeBlocks.map(pluck_val).join ', '
      @pushln "_R:mixin('#{node.name}', {#{node.args}}, #{attrs or 'nil'})"

    else
      mixin = new PugBlock
      mixin.mixins = @mixins
      mixin.lua = [
        'return function(attributes'
        if node.args then ', ' + node.args
        ')\n'
      ]
      generators.Block.call mixin, node.block
      mixin.push 'end'

      @mixins[node.name] = mixin.lua.join ''
      return

  RawInclude: (node) ->
    @pushln '_R:include("' + node.file.path + '")'

  InterpolatedTag: (node) ->
    generators.Tag.call this, node

  Extends: (node) ->
    throw Error "`extends` is not supported yet"

  Doctype: (node) ->
    throw Error "`doctype` is not supported yet"

#
# Helpers
#

# Kind of like Python's `repr` function.
repr = (str) ->
  str.replace newlineRE, '\\n'
     .replace dquoteRE, '\\"'

has_code = (node) ->
  node.type is "Code"

find_child = (nodes, test) ->
  for node in nodes
    return node if test node

pluck_val = (node) -> node.val

stringRE = /^['"]/

has_dynamic_attrs = (node) ->
  return true if node.attributeBlocks[0]
  for attr in node.attrs
    return true if !stringRE.test attr.val
  return false

class PugBlock
  constructor: ->
    @tab = ''
    return

  push: (code) ->
    @lua.push code
    return

  pushln: (code) ->
    @lua.push @tab + code + '\n'
    return

  indent: ->
    @tab += '  '
    return

  dedent: ->
    @tab = @tab.slice 0, -.2
    return

# -- TODO: Dont create a new scope unless new variables are declared
# -- TODO: Try to inline code blocks safely
# -- TODO: Combine adjacent code blocks
# -- TODO: Combine adjacent text blocks
# -- TODO: Check if tag has all static descendants
#
#   -- Compile an AST into a render function.
#   compile: (ast) =>
#     @len = 1
#     @lua = {'return function(res, env, _G)\n'}
#     @funcs = {} -- func id => func
#     @mixins = {} -- mixin name => func
#
#     -- Process the AST.
#     for node in *ast.nodes
#       compile_node self, node
#
#     -- End the render function.
#     @push 'end'
#
#     -- Allocate the render function.
#     render = loadstring(concat @lua, '')!
#     setfenv render, runtime
#
#     -- Cache any render options.
#     {:funcs, :mixins, :globals, :resolve} = self
#
#     -- Release heavy data structures.
#     @mixins = nil
#     @funcs = nil
#     @lua = nil
#
#     return (opts = {}) ->
#
#       -- Include compiler globals in each render.
#       if type(globals) == 'table'
#         if type(opts.globals) ~= 'table'
#           opts.globals = globals
#         else
#           mt = getmetatable opts.globals
#           if mt == nil
#             setmetatable opts.globals, __index: globals
#           elseif mt.__index == nil
#             mt.__index = globals
#           else
#             get = mt.__index
#             mt.__index = (k) =>
#               v = get k
#               v = globals[k] if v == nil
#               v
#
#       -- Use the compiler's resolver if none exists.
#       if resolve and not opts.resolve
#         opts.resolve = resolve
#
#       res = PugResult opts
#       res.funcs = funcs
#       res.mixins = mixins
#
#       render res, res.env, res.globals
#       concat res.html, ''
#
# ----------------------------------------
#
# -- Returns all text nodes combined, if only text nodes exist.
# just_text = (nodes) ->
#   i = 0
#   text = {}
#   for node in *nodes
#     if node.type == 'Text'
#       i += 1
#       text[i] = node.val
#     else return
#   return concat text, ''

# return PugCompiler
