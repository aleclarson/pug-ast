const moonc = require('moonc')

// TODO: Warn on `return` within `if|do|for|while` statements.

// Pug prepends ! for `unless` and `until`.
const negatedRE = /^!/

// Root-level `local =` statements have `local` stripped.
const localsRE = /(^|\n)local (?=[^=]+\s*=)/g

// Root-level `return` statements have `return` stripped.
const returnRE = /(^|\n)return /g

async function transpile(code, node) {
  // Boolean literals may be passed for attribute values.
  if (typeof code == 'boolean') return code
  code = await moonc.promise(code.replace(negatedRE, 'not '))
  code = code.toString().trim().replace(returnRE, '$1')
  if (node.type == 'Code') {
    code = code.replace(localsRE, '$1')
  }
  return code
}

module.exports = transpile
