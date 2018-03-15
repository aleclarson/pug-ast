# pug2lua v0.0.1

Generate Lua functions from Pug templates.

Combine this library with [**lua-pug**](https://github.com/aleclarson/lua-pug) to render dynamic HTML.

```js
let pug = require('pug2lua')

// Lex and parse the Pug string into an AST.
let ast = pug.ast(string)

// Do something with every string of non-Pug code.
pug.transpile(ast, (code, node) => {
  // Return the transpiled code.
})

// Generate Lua code and return a JSON string.
let json = pug.lua(ast)

JSON.parse(json) // => { render: String, mixins: {String => String} }
```

### Built-in transpilers

```js
// https://github.com/leafo/moonscript
await pug.transpile(ast, {moon: true})
```

### CLI

```sh
# Convert a Pug file into a Lua JSON string. And transpile with MoonScript.
pug2lua <src> -o <dest> --moon

# Use stdin and stdout. And transpile with MoonScript.
pug2lua -s --moon
```

### Code generation

The `pug.lua` function generates a JSON string shaped like `{render, mixins}`.

The `_G` variable is *not* the actual global environment.

The `_E` variable is the template function's environment.
You are not required to do `_E.foo = 1` to mutate a property,
since `foo = 1` does the same thing (unless locally shadowed).

The `_R` variable is the template result builder.

#### Quirks

- CSS strings are *not* escaped
- Conditionals abort on nil and false
- Mixins cannot be used before their declaration
- Mixins only have access to their scope and any globals
- Mixins are always globally accessible, so nesting has no effect

#### Variable scoping

- A variable scope exists for every **tag** and **mixin**.
- Descendants have access to their ancestors' variables.
- Mutating an ancestor's variable is only temporary (except for tables).

#### `for..in`

- You cannot do `for a, b, c in iterator`
- `pairs` and `ipairs` are nil-tolerant
- `pairs` is the default iterator
- Custom iterators are supported

#### Missing features

- `extends`
- `block/append/prepend`
- `doctype`
- `...` rest arguments for mixins
- `//` buffered comments
- `--[[` multi-line comments in code blocks
