# vim-ast-explorer

[WIP] AST Explorer plugin for vim; inspired by https://astexplorer.net/

Highly experimental so far, so don't install this plugin. Only works with @babel/parser.

## TODO

- [ ] Jump to AST node from file
- [ ] Actually highlight nodes instead of using visual mode
- [ ] Prettier AST output: folds, highlighting
- [ ] Support for more parsers
- [ ] Automatically detect available supported parsers for filetype
- [ ] Invoke parser with async job

## Development

Set up linting:

```
pyenv virtualenv 3.6.3 $(cat .python-version)
pip install -r requirements-lock.txt
```
