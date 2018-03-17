
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
        return transpileProp(node, 'val')

      case 'Conditional':
        return Promise.all([
          transpileProp(node, 'test'),
          walk(node.consequent),
          node.alternate && walk(node.alternate),
        ])

      case 'Tag':
      case 'InterpolatedTag':
        return Promise.all([
          node.expr && transpileProp(node, 'expr'),
          transpileProp(node.attrs, 'val'),
          transpileProp(node.attributeBlocks, 'val'),
          walk(node.block),
        ])

      case 'Mixin':
        if (node.call) {
          return Promise.all([
            node.args && transpileProp(node, 'args'),
            transpileProp(node.attrs, 'val'),
            transpileProp(node.attributeBlocks, 'val'),
          ])
        }
        return walk(node.block)

      case 'While':
        return Promise.all([
          transpileProp(node, 'test'),
          walk(node.block),
        ])

      case 'Each':
        return Promise.all([
          transpileProp(node, 'obj'),
          walk(node.block),
        ])

      case 'Case':
        return Promise.all([
          transpileProp(node, 'expr'),
          each(node.block.nodes, async (node) => {
            return Promise.all([
              node.expr == 'default' || transpileProp(node, 'expr'),
              node.block && walk(node.block),
            ])
          })
        ])
    }
  }

  // Transpile the given property of every given node.
  async function transpileProp(node, prop) {
    if (Array.isArray(node)) {
      await Promise.all(node.map(node => transpileProp(node, prop)))
    } else {
      node[prop] = await transpile(node[prop], node)
    }
  }
}

// Parallel enumeration
function each(arr, fn) {
  let promises = []
  for (let i = 0; i < arr.length; i++) {
    promises.push(fn(arr[i], i))
  }
  return Promise.all(promises)
}
