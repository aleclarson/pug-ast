
module.exports = function transpile(ast, opts) {
  let transpile
  if (typeof opts == 'function') {
    transpile = opts
  } else if (opts.moon) {
    transpile = require('./moon')
  }

  // Begin transpiling.
  return walk(ast)

  async function walk(node) {
    switch(node.type) {

      case 'Block':
        return each(node.nodes, walk)

      case 'Code':
        node.val = await transpile(node.val, node)
        break

      case 'Conditional':
        node.test = await transpile(node.test, node)
        await walk(node.consequent)
        if (node.alternate) {
          return walk(node.alternate)
        } else break

      case 'Tag':
        for (let attr of node.attrs)
          attr.val = await transpile(attr.val, attr)
        for (let block of node.attributeBlocks)
          block.val = await transpile(block.val, block)
        return walk(node.block)

      case 'Mixin':
        if (node.call) {
          node.args = await transpile(node.args, node)
          for (let attr of node.attrs)
            attr.val = await transpile(attr.val, attr)
          return each(node.attributeBlocks, async (node) => {
            node.val = await transpile(node.val, node)
          })
        }
        return walk(node.block)

      case 'While':
        node.test = await transpile(node.test, node)
        return walk(node.block)

      case 'Each':
        node.obj = await transpile(node.obj, node)
        return walk(node.block)

      case 'Case':
        node.expr = await transpile(node.expr, node)
        return each(node.block.nodes, async (node) => {
          if (node.expr != 'default')
            node.expr = await transpile(node.expr, node)
          return walk(node.block)
        })
    }
  }
}

async function each(arr, fn) {
  let i = -1, len = arr.length
  while (++i < len) {
    await fn(arr[i], i)
  }
}
