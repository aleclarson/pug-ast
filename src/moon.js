const moonc = require('moonc')

const negatedRE = /^!/

module.exports = transpile

async function transpile(code, node) {
  try {
    let lua = await moonc.promise(code.replace(negatedRE, 'not '))
    if (node.type == 'Code') {
      return stripLocals(lua)
    }
    // Remove the leading `return `
    return lua.slice(7)
  } catch(err) {
    global.node = node
    console.error(err)
    return code
  }
}

// Strip `local` keyword from root-level variables,
// but only if matching `local ... =` pattern.
function stripLocals(str) {
  let i = 0, res = []
  let re = /(?:^|\n)local [^=]+ =/g
  let match
  while (match = re.exec(str)) {
    let j = match.index + match[0].length
    if (i < j) {
      res.push(str.slice(i, j))
      i = j
    }
    match = match[0]
    if (match[0] == '\n') res.push('\n')
    res.push(match.slice(match.indexOf(' ') + 1))
  }
  if (i < str.length) {
    res.push(str.slice(i))
  }
  return res.join('')
}
