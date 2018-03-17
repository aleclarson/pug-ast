escape_html = require 'escape-html'

# TODO: Combine adjacent code blocks
# TODO: Combine adjacent text blocks

# Generate a render function and associated mixin functions.
# Returns a JSON string shaped like {render, mixins}
generate = (ast) ->
  tpl = new PugBlock
  tpl.lua = ['local render = function(_R, _E, _G)\n']
  tpl.mixins = {} # mixin name => mixin code

  generators.Block.call tpl, ast
  tpl.pushln 'end'

  # Declare the local `mixins` table.
  has_mixins = declare_mixins.call tpl

  # Export the `render` function and `mixins` table.
  tpl.push tpl.tab + 'return {render = render'
  tpl.push ', mixins = mixins' if has_mixins
  tpl.push '}'

  # All done!
  tpl.lua.join ''

module.exports = generate

rawAttrRE = /^(?:class|style)$/
newlineRE = /\n/g
dquoteRE = /"/g
stringRE = /^['"]/
falsyRE = /^(?:nil|false)$/
boolRE = /^(?:true|false)$/

generators =

  Block: ({ nodes }, has_scope) ->
    if nodes.length
      @indent()
      @pushln '_R:push_env()\n' if has_scope
      for node in nodes
        generators[node.type].call this, node
      @push '\n' + @tab + '_R:pop_env()\n' if has_scope
      @dedent()
      return

  Text: (node) ->
    if node.val
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
      @pushln "local __tag = tostring(#{node.expr})"
      @pushln '_R:push("<")'
      @pushln '_R:push(__tag)'

    if node.attrs[0] or node.attributeBlocks[0]
      generators.Attributes.call this, node, dynamic

    if dynamic or node.expr
      @push @tab + '_R:push("'

    if node.selfClosing
      @push '/>")\n'
      return

    {block} = node
    if block.nodes[0]
      dynamic = find_child(block.nodes, has_non_text)?

      if dynamic
        @push '>")\n'

        # Push a new scope if a child has unbuffered code.
        has_scope = find_child(block.nodes, has_unbuffered_code)?

        @pushln 'do'
        generators.Block.call this, block, has_scope
        @pushln 'end'

        @push @tab + '_R:push("'

      # Every child is a text node. Merge them into one string.
      else @push '>' + block.nodes.map(pluck_val).map(repr).join ''

    else @push '>'

    if node.name
      @push '</' + node.name + '>")\n'
    else
      @push '</")\n'
      @pushln '_R:push(__tag)'
      @pushln '_R:push(">")'
    return

  # This isn't a *real* AST node type.
  Attributes: (node, dynamic) ->

    if node.attrs[0]
      attrs = attr_map node.attrs
      classes = attrs.class

    if dynamic
      if attrs
        if classes then attrs.class =
          val: lua_list classes, @tab
        attrs = @indent_lines lua_attrs attrs
      else attrs = 'nil'
      @push @tab + '_R:attrs(' + attrs

      blocks = node.attributeBlocks
      if blocks[0]
        @push ', ' + blocks.map(
          (block) => @indent_lines block.val
        ).join ', '

      @push ')\n'
      return

    # Merge 'class' strings into one string.
    if classes then attrs.class =
      val: classes.join(' ').replace /["']/g, ''

    for name, {val, mustEscape} of attrs
      continue if falsyRE.test val

      if (val is true) or (val is 'true')
        @push ' ' + name
        continue

      if stringRE.test val
        val = val.slice 1, -1
        if mustEscape and !rawAttrRE.test name
          val = escape_html val
        val = val.replace dquoteRE, '\\"'

      @push " #{name}=#{repr quote val}"
    return

  Code: (node) ->
    if node.buffer
      tostring = if node.mustEscape then 'escape' else 'tostring'
      @pushln "_R:push(#{tostring}(#{node.val}))"
    else
      @pushln node.val.replace newlineRE, '\n' + @tab
    return

  Conditional: (node) ->
    i = -1
    loop
      @pushln "#{if ++i then 'elseif' else 'if'} #{node.test} then"
      generators.Block.call this, node.consequent

      break unless node = node.alternate
      unless node.test
        @pushln 'else'
        generators.Block.call this, node
        break

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

      if node.expr is 'default'
        @pushln 'else'
        generators.Block.call this, node.block
        break

      expr.push node.expr + ' == __expr'
      if node.block
        keyword = if ++i then 'elseif ' else 'if '
        if expr.length > 1
        then @pushln keyword + '(' + expr.join(') or (') + ') then'
        else @pushln keyword + expr[0] + ' then'
        expr.length = 0
        generators.Block.call this, node.block

    @pushln 'end'
    return

  Each: (node) ->
    {obj} = node
    unless obj.startsWith 'ipairs('
      iter = if node.key then '__each' else '__vals'
      obj = iter + "(#{obj})"

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
        'function(attributes'
        if node.args then ', ' + node.args
        ')\n'
      ]

      # Push a new scope if a child has unbuffered code.
      has_scope = find_child(node.block.nodes, has_unbuffered_code)?

      generators.Block.call mixin, node.block, has_scope
      mixin.push 'end,'

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
    @tab = @tab.slice 0, -2
    return

#
# Helpers
#

# Kind of like Python's `repr` function.
repr = (str) ->
  str.replace newlineRE, '\\n'
     .replace dquoteRE, '\\"'

has_unbuffered_code = (node) ->
  node.type is 'Code' and !node.buffer

has_non_text = (node) ->
  node.type isnt 'Text'

find_child = (nodes, test) ->
  for node in nodes
    return node if test node

pluck_val = (node) -> node.val

has_dynamic_attrs = (node) ->
  return true if node.attributeBlocks[0]
  for attr in node.attrs
    return true if !stringRE.test attr.val
  return false

attr_map = (attrs) ->
  map = {}
  for attr in attrs
    name = attr.name.toLowerCase()
    # Merge 'class' attributes into an array.
    if name is 'class'
      if map.class
      then map.class.push attr.val
      else map.class = [attr.val]
    else map[name] = attr
  return map

lua_attrs = (attrs) ->
  lines = ['{']
  for name, {val, mustEscape} of attrs

    # Boolean/nil values are left as-is.
    if !boolRE.test(val) and (val isnt 'nil')

      if stringRE.test val
        val = val.slice 1, -1
        if mustEscape and !rawAttrRE.test name
          val = escape_html val
        val = quote repr val

      else unless rawAttrRE.test name
        tostring = if mustEscape then 'escape' else 'tostring'
        val = tostring + "(#{val})"

    lines.push "  ['#{name}'] = #{val},"
  lines.push '}'
  lines.join '\n'

lua_list = (arr, tab) ->
  if arr.length > 1
  then "{\n  #{tab + arr.join ',\n  ' + tab}\n#{tab}}"
  else arr[0]

indent_lines = (node) ->
  node.val.replace newlineRE, '\n' + @tab

quote = (str) -> '"' + str + '"'

declare_mixins = ->
  mixins = Object.keys @mixins
  if mixins.length
    @pushln 'local mixins = {'
    @indent()
    for name in mixins
      @pushln "['#{name}'] = " + @indent_lines @mixins[name]
    @dedent()
    @pushln '}'
    return true
